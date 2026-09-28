--!strict
-- Battle status VFX: the part of a status effect the player actually sees.
--
-- WHY THIS EXISTS.
-- Statuses used to be text only. A card could be bleeding for ten stacks, frozen
-- solid and shielded at the same time and the board looked identical to a card
-- with nothing on it at all - the only evidence was a line in the log rail, which
-- is where the player is NOT looking while a round resolves. This layer puts the
-- state back on the card itself: a coloured border that breathes, a stack badge
-- in the corner, and a one-shot burst when the status lands or ticks.
--
-- TWO SURFACES, AND THEY CANNOT BE THE SAME ONE.
--   * The aura and the badges live ON the card (root frame). They stay inside
--     the card's bounds, so the card's ClipsDescendants does not hurt them, and
--     they travel with it for free when the board re-fits.
--   * The bursts live on a SEPARATE full-screen layer. They have to: a card root
--     clips its children, and a burst that cannot leave the card is not a burst.
--     They are positioned each time from the card's AbsolutePosition, so they
--     land correctly no matter where the layout put the seat.
--
-- EVERYTHING IS AN ImageLabel, NEVER A ParticleEmitter. ParticleEmitter does not
-- render in a ScreenGui at all - it is a 3D-space object. Tweened sprites on the
-- eleven authored VfxAssets textures are the only way to get soft-edged light
-- into 2D UI, which is exactly what RevealController already does.
--
-- Colours, badges, motion and priority all come out of StatusEffects.visual(id).
-- Adding a new status needs no change in this file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local StatusEffects = require(ReplicatedStorage.Shared.Config.StatusEffects)
local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)

local StatusVfx = {}

-- ── Tuning ─────────────────────────────────────────────────────────
local CARD_RADIUS = 10          -- matches CardRenderer's root corner
local BADGE_MIN_W = 30
local BADGE_MAX_W = 54
local FLASH_DECAY = 0.055       -- per frame at 60fps; a landing flash lasts ~0.15s
local RATE_HOSTILE = 7.2        -- border pulses per 2pi seconds
local RATE_FRIENDLY = 4.1

-- ── State ──────────────────────────────────────────────────────────
local overlay: Frame? = nil
local cards: { [Instance]: any } = {}
local pulseConn: RBXScriptConnection? = nil
local liveCards = 0

-- ── Tiny helpers ───────────────────────────────────────────────────
local function new(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	if children then
		for _, c in ipairs(children) do c.Parent = inst end
	end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end

local function clamp01(n: number): number
	return math.clamp(n, 0, 1)
end

local function dim(colour: Color3, amount: number): Color3
	return colour:Lerp(Color3.fromRGB(10, 10, 16), amount)
end

-- ── The burst layer ────────────────────────────────────────────────
-- Mounted once from BattleController:Init. Without it the aura and badges still
-- work; only the bursts are skipped, so a caller that forgets to mount gets a
-- quieter board rather than a stack of errors.
function StatusVfx.mount(screenGui: ScreenGui)
	if overlay and overlay.Parent then overlay:Destroy() end
	overlay = new("Frame", {
		Name = "StatusVfxLayer",
		Parent = screenGui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		-- Above the board, below any modal. A burst must never cover a dialog.
		ZIndex = 120,
		-- Light on top of the board, not a click target in front of it.
		Active = false,
	})
end

-- Card rect translated into the overlay's own space. Returns nil while the card
-- has not been laid out yet (AbsoluteSize is 0 on the frame it is created).
local function rectOf(cardRoot: GuiObject): (Vector2?, Vector2?)
	local layer = overlay
	if not layer or not layer.Parent then return nil, nil end
	local size = cardRoot.AbsoluteSize
	if size.X < 4 or size.Y < 4 then return nil, nil end
	return cardRoot.AbsolutePosition - layer.AbsolutePosition, size
end

local function sprite(texture: string, colour: Color3, at: Vector2, diameter: number,
	rotation: number?, transparency: number?): ImageLabel
	local img = new("ImageLabel", {
		Parent = overlay,
		BackgroundTransparency = 1,
		Image = texture,
		ImageColor3 = colour,
		ImageTransparency = transparency or 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(diameter, diameter),
		Rotation = rotation or 0,
		ZIndex = 121,
	})
	-- Belt and braces: if a tween is cancelled by a board rebuild the sprite
	-- still goes away instead of hanging on screen for the rest of the battle.
	Debris:AddItem(img, 3)
	return img
end

local function sail(img: ImageLabel, to: Vector2, diameter: number, seconds: number,
	style: Enum.EasingStyle?)
	local goal = {
		Position = UDim2.fromOffset(to.X, to.Y),
		Size = UDim2.fromOffset(diameter, diameter),
		ImageTransparency = 1,
	}
	local t = TweenService:Create(
		img,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goal)
	t:Play()
	t.Completed:Once(function()
		if img.Parent then img:Destroy() end
	end)
end

-- Motion decides where the small sprites start and which way they travel. This
-- is the whole reason a DoT feels different from a buff even when both are just
-- "some dots near a card".
local function particles(v: any, origin: Vector2, size: Vector2, strength: number)
	local count = math.max(3, math.floor((v.motion == "crackle" and 11 or 9) * strength))
	local texture = VfxAssets[v.sprite] or VfxAssets.Mote
	local cx = origin.X + size.X * 0.5
	local cy = origin.Y + size.Y * 0.5

	for i = 1, count do
		local d = math.random(19, 34) * (0.7 + strength * 0.5)
		local startAt: Vector2, endAt: Vector2, seconds: number

		if v.motion == "fall" then
			local x = origin.X + size.X * (0.12 + math.random() * 0.76)
			startAt = Vector2.new(x, origin.Y + size.Y * (0.10 + math.random() * 0.25))
			endAt = startAt + Vector2.new(math.random(-10, 10), size.Y * (0.35 + math.random() * 0.4))
			seconds = 0.5 + math.random() * 0.3

		elseif v.motion == "rise" then
			local x = origin.X + size.X * (0.12 + math.random() * 0.76)
			startAt = Vector2.new(x, origin.Y + size.Y * (0.72 + math.random() * 0.2))
			endAt = startAt - Vector2.new(math.random(-10, 10), size.Y * (0.4 + math.random() * 0.35))
			seconds = 0.55 + math.random() * 0.3

		else
			-- ring / shell / crackle all throw outward from the middle; the
			-- difference between them is carried by the headline sprite below.
			local a = math.random() * math.pi * 2
			local r0 = v.motion == "shell" and size.X * 0.55 or size.X * 0.12
			local r1 = size.X * (v.motion == "shell" and 0.30 or 0.78)
			startAt = Vector2.new(cx + math.cos(a) * r0, cy + math.sin(a) * r0 * 1.2)
			endAt = Vector2.new(cx + math.cos(a) * r1, cy + math.sin(a) * r1 * 1.2)
			seconds = 0.38 + math.random() * 0.22
		end

		local img = sprite(texture, v.colour, startAt, d, math.random(0, 359), 0.1)
		task.delay(i * 0.022, function()
			if img.Parent then sail(img, endAt, d * 0.45, seconds) end
		end)
	end
end

-- The one big sprite that says WHICH kind of thing just happened.
local function headline(v: any, origin: Vector2, size: Vector2, strength: number)
	local cx = origin.X + size.X * 0.5
	local cy = origin.Y + size.Y * 0.5
	local centre = Vector2.new(cx, cy)
	local texture = VfxAssets[v.burst] or VfxAssets.Glow

	if v.motion == "ring" then
		-- A summoning circle snapping open under the card: control landing.
		local img = sprite(texture, v.colour, centre, size.X * 0.5 * strength, 0, 0.18)
		TweenService:Create(img, TweenInfo.new(0.6, Enum.EasingStyle.Linear), { Rotation = 110 }):Play()
		sail(img, centre, size.X * 2.05 * strength, 0.6)

	elseif v.motion == "shell" then
		-- Runs BACKWARDS compared to every other burst: a shield closes onto the
		-- card rather than blowing away from it, which is what makes it read as
		-- protection instead of another hit.
		local img = sprite(texture, v.colour, centre, size.X * 2.5 * strength, 0, 0.18)
		sail(img, centre, size.X * 1.12, 0.52, Enum.EasingStyle.Back)

	elseif v.motion == "rise" then
		-- Three streaks climbing the card: a buff is lift.
		for i = 1, 3 do
			local x = cx + (i - 2) * size.X * 0.27
			local at = Vector2.new(x, cy + size.Y * 0.30)
			local img = sprite(VfxAssets.Streak, v.colour, at, size.X * 1.05 * strength, 90, 0.25)
			task.delay((i - 1) * 0.06, function()
				if img.Parent then
					sail(img, at - Vector2.new(0, size.Y * 0.62), size.X * 0.5, 0.5)
				end
			end)
		end
		local glow = sprite(VfxAssets.Glow, v.colour, centre, size.X * 0.7, 0, 0.45)
		sail(glow, centre, size.X * 1.5, 0.45)

	elseif v.motion == "crackle" then
		local img = sprite(texture, v.colour, centre, size.X * 0.7 * strength, math.random(0, 359), 0.2)
		sail(img, centre, size.X * 1.75 * strength, 0.35)

	else
		-- fall / anything new: a soft bloom sitting on the card.
		local img = sprite(texture, v.colour, centre, size.X * 1.5 * strength, 0, 0.38)
		sail(img, centre, size.X * 1.05, 0.44)
	end
end

local function playBurst(cardRoot: GuiObject, v: any, strength: number)
	if not overlay or not overlay.Parent then return end
	local origin, size = rectOf(cardRoot)
	if not origin or not size then return end
	headline(v, origin, size, strength)
	particles(v, origin, size, strength)
end

-- ── Per-card furniture ─────────────────────────────────────────────
local function badgeWidth(cardRoot: GuiObject): number
	local w = cardRoot.AbsoluteSize.X
	if w < 4 then w = cardRoot.Size.X.Offset end
	return math.clamp(math.floor(w * 0.31), BADGE_MIN_W, BADGE_MAX_W)
end

local function makeBadge(state: any, v: any): any
	local w = badgeWidth(state.root)
	local h = math.floor(w * 0.44)
	local holder = new("Frame", {
		Name = "Badge_" .. v.id,
		Parent = state.badges,
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = dim(v.colour, 0.72),
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		-- Highest priority sits at the top of the column.
		LayoutOrder = 100 - v.priority,
		ZIndex = state.z + 2,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, math.floor(h * 0.34)) }),
		new("UIStroke", { Color = v.colour, Thickness = 1, Transparency = 0.25 }),
	})
	local text = new("TextLabel", {
		Parent = holder,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = math.max(8, math.floor(h * 0.62)),
		TextColor3 = v.colour:Lerp(Color3.new(1, 1, 1), 0.55),
		Text = v.badge,
		ZIndex = state.z + 3,
	})
	return { frame = holder, text = text, v = v }
end

local function paintBadge(entry: any)
	local v = entry.v
	if entry.stacks and entry.stacks > 1 then
		entry.text.Text = ("%s %d"):format(v.badge, entry.stacks)
	else
		entry.text.Text = v.badge
	end
end

local function ensure(cardRoot: GuiObject): any
	local existing = cards[cardRoot]
	if existing then return existing end

	local z = cardRoot.ZIndex + 22
	local state: any = {
		root = cardRoot,
		z = z,
		entries = {},
		dominant = nil,
		flash = 0,
		rate = RATE_FRIENDLY,
	}

	-- The aura is its own frame rather than a second UIStroke on the card,
	-- because the card's own stroke is already owned by CardRenderer (rarity
	-- colour) and by BattleTheme.glow (seat accent). Fighting either of those
	-- for the same property is how a border ends up flickering between three
	-- colours a frame apart.
	state.aura = new("Frame", {
		Name = "StatusAura",
		Parent = cardRoot,
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, CARD_RADIUS) }),
	})
	state.stroke = new("UIStroke", {
		Parent = state.aura,
		Color = Color3.new(1, 1, 1),
		Thickness = 2,
		Transparency = 1,
		LineJoinMode = Enum.LineJoinMode.Round,
	})

	-- The outer bloom. It has to hang OUTSIDE the card, so it is parented to the
	-- card's parent holder and sits one layer behind the card itself.
	local host = cardRoot.Parent
	if host and host:IsA("GuiObject") then
		state.glow = new("ImageLabel", {
			Name = "StatusGlow",
			Parent = host,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1.42, 0, 1.36, 0),
			BackgroundTransparency = 1,
			Image = VfxAssets.CardGlow,
			ImageColor3 = Color3.new(1, 1, 1),
			ImageTransparency = 1,
			ZIndex = math.max(1, cardRoot.ZIndex - 1),
		})
	end

	state.badges = new("Frame", {
		Name = "StatusBadges",
		Parent = cardRoot,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -7, 0, 7),
		Size = UDim2.new(0, BADGE_MAX_W, 1, -14),
		BackgroundTransparency = 1,
		ZIndex = z + 1,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 3),
		}),
	})

	cards[cardRoot] = state
	liveCards += 1
	return state
end

local function teardown(state: any)
	if state.aura then state.aura:Destroy() end
	if state.glow then state.glow:Destroy() end
	if state.badges then state.badges:Destroy() end
	cards[state.root] = nil
	liveCards -= 1
end

-- Loudest live status owns the border. Ties break on whichever landed last,
-- which is the one the player is most likely asking "what just happened" about.
local function refreshDominant(state: any)
	local best: any, bestKey: number = nil, -1
	for _, e in pairs(state.entries) do
		local key = e.v.priority * 1000 + e.seq
		if key > bestKey then best, bestKey = e, key end
	end
	state.dominant = best
	if best then
		state.stroke.Color = best.v.colour
		state.rate = best.v.hostile and RATE_HOSTILE or RATE_FRIENDLY
		if state.glow then state.glow.ImageColor3 = best.v.colour end
	else
		state.stroke.Transparency = 1
		if state.glow then state.glow.ImageTransparency = 1 end
	end
end

-- ── The pulse ──────────────────────────────────────────────────────
-- One connection for every card on the board, not one per card. Sixteen
-- statuses on two cards is still exactly one RenderStepped handler.
local function pulse()
	local now = os.clock()
	for root, state in pairs(cards) do
		if not root.Parent then
			teardown(state)
		elseif state.dominant then
			local beat = 0.5 + 0.5 * math.sin(now * state.rate)
			local lift = state.flash
			state.stroke.Transparency = clamp01(0.60 - 0.34 * beat - lift)
			state.stroke.Thickness = 2 + 1.5 * beat + lift * 2
			if state.glow then
				state.glow.ImageTransparency = clamp01(0.72 - 0.26 * beat - lift * 0.7)
			end
			if lift > 0 then
				state.flash = math.max(0, lift - FLASH_DECAY)
			end
		end
	end
	if liveCards <= 0 and pulseConn then
		pulseConn:Disconnect()
		pulseConn = nil
	end
end

local function wake()
	if pulseConn then return end
	pulseConn = RunService.RenderStepped:Connect(pulse)
end

-- ── Public API ─────────────────────────────────────────────────────
local applySeq = 0

-- A status landed (or was refreshed, or gained stacks).
function StatusVfx.apply(cardRoot: GuiObject?, statusId: string?, stacks: number?)
	if not cardRoot or not cardRoot.Parent or not statusId then return end
	local v = StatusEffects.visual(statusId)
	if not v then return end

	local state = ensure(cardRoot)
	local entry = state.entries[statusId]
	if not entry then
		entry = makeBadge(state, v)
		entry.id = statusId
		state.entries[statusId] = entry
	end
	applySeq += 1
	entry.seq = applySeq
	entry.stacks = math.max(1, stacks or 1)
	paintBadge(entry)

	refreshDominant(state)
	state.flash = 0.42
	wake()
	playBurst(cardRoot, v, 1)
end

-- A damage-over-time status fired this round: re-flash, small burst.
function StatusVfx.tick(cardRoot: GuiObject?, statusId: string?)
	if not cardRoot or not cardRoot.Parent or not statusId then return end
	local v = StatusEffects.visual(statusId)
	if not v then return end
	local state = cards[cardRoot]
	if state then
		state.flash = 0.36
		wake()
	end
	playBurst(cardRoot, v, 0.55)
end

-- A status expired. The badge goes; the aura falls back to whatever else is
-- still on the card, or off entirely.
function StatusVfx.clear(cardRoot: GuiObject?, statusId: string?)
	if not cardRoot or not statusId then return end
	local state = cards[cardRoot]
	if not state then return end
	local entry = state.entries[statusId]
	if not entry then return end
	state.entries[statusId] = nil
	if entry.frame then entry.frame:Destroy() end
	refreshDominant(state)
	if not state.dominant then teardown(state) end
end

-- Card left the field, or the battle ended.
function StatusVfx.clearAll(cardRoot: GuiObject?)
	if not cardRoot then return end
	local state = cards[cardRoot]
	if state then teardown(state) end
end

-- Whole board reset. Cheap enough to call on every battle open.
function StatusVfx.reset()
	for _, state in pairs(cards) do
		teardown(state)
	end
	cards = {}
	liveCards = 0
	if overlay and overlay.Parent then
		for _, c in ipairs(overlay:GetChildren()) do c:Destroy() end
	end
end

return StatusVfx
