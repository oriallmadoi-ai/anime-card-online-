--!strict
-- Signature ability VFX: the beam the two "Son" cards fire, and Number One's
-- burst of rounds.
--
-- WHY A SECOND VFX MODULE.
-- StatusVfx decorates ONE card - a border, a badge, a puff that stays inside
-- the card's own footprint. These effects travel BETWEEN two cards, so they
-- need the distance and angle from one seat to the other, and they need to be
-- drawn over the whole board rather than over a card. Folding that into
-- StatusVfx would have meant two unrelated coordinate systems in one file.
--
-- HOW A BEAM IS AIMED.
-- A GuiObject rotates about its own CENTRE. AnchorPoint decides where the
-- object SITS, not where it spins - so anchoring a shaft at its left edge and
-- rotating it does not pivot it about the muzzle. The whole bar swings around
-- its middle and the origin slides off the firing card, which is exactly what
-- the first build did: the beam left from a point below the card and landed
-- below the target.
--
-- So the shaft is centred on the midpoint between the two cards, and "firing
-- out" is animated as length AND centre together: at any moment the bar is
-- dist*t long with its centre t*dist/2 out from the muzzle, which pins the
-- near end to the card while the far end races away.
--
-- The shaft sprite is uniform along its length on purpose, so stretching it to
-- an arbitrary distance is free. Muzzle and impact are separate sprites; bake
-- them into the shaft and they stretch with it.
--
-- Everything here is a tweened ImageLabel. ParticleEmitter does not render in
-- a ScreenGui at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)

local AbilityVfx = {}

-- ── Palette ────────────────────────────────────────────────────────
-- Both Son cards fire the SAME beam - they are the same technique, and making
-- them different colours would imply otherwise. Number One reuses the identical
-- sprites in deep blue with a completely different motion.
local BLUE_WHITE = Color3.fromRGB(158, 210, 255)
local BLUE_HOT   = Color3.fromRGB(226, 244, 255)
-- Deep, but not dark. The first pass used a genuinely dark blue and the
-- rounds vanished against the board - a tracer is a light source, so its
-- colour has to stay bright and take its "deep" from the hue instead.
local DEEP_BLUE  = Color3.fromRGB( 92, 152, 255)
local DEEP_HOT   = Color3.fromRGB(196, 224, 255)

local Z_BASE = 124        -- over the board, under StatusVfx bursts and modals

local RECIPES: { [string]: any } = {
	-- Son Prodigy. Two beats a turn apart, because that is what his card says he
	-- does: he charges, and THEN he blasts.
	--
	-- `triggers` is the important field. A passive fires one Passive event per
	-- CLAUSE and every one of them carries the same passive id, so hanging the
	-- beam off the id alone fired it on the wind-up clause as well as the blast:
	-- the beam went off the moment he walked on, a whole turn before he shot
	-- anything, and then again when he actually did. Each clause now gets the
	-- beat that belongs to it, and a clause not named here plays nothing at all.
	FinalBlast = {
		kind = "beam", colour = BLUE_WHITE, hot = BLUE_HOT,
		triggers = { OnEntry = "charge", OnTurnStart = "beam" },
		thickness = 0.62, hold = 0.46, impact = 1.25,
	},
	-- Son Warrior. Same technique, smaller: no wind-up, thinner shaft.
	--
	-- Gated for the same reason: his other clause is an on-DEATH damage
	-- reduction for the party, and it was firing a beam out of his corpse.
	TheFirstOfMany = {
		kind = "beam", colour = BLUE_WHITE, hot = BLUE_HOT,
		triggers = { OnAttack = "beam" },
		thickness = 0.40, hold = 0.26, impact = 0.90,
	},
	-- Number One. Same sprites, deep blue, fired as a burst of rounds.
	-- Number One. Same sprites, deep blue, fired as a burst of rounds.
	--
	-- firesOn = "attack" is the important field. Run & Gun is an attackPattern,
	-- not a clause, so it NEVER pushes a Passive event - the volley is his basic
	-- attack. Hanging this recipe off the Passive event, the way the two beams
	-- are, meant it could not fire at all.
	RunAndGun = {
		kind = "shots", colour = DEEP_BLUE, hot = DEEP_HOT,
		firesOn = "attack",
		count = 10, spread = 0.26, gap = 0.048,
		length = 1.70, calibre = 0.40,
	},
}

AbilityVfx.Recipes = RECIPES

-- ── Layer ──────────────────────────────────────────────────────────
local layer: Frame? = nil

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

function AbilityVfx.mount(screenGui: ScreenGui)
	if layer and layer.Parent then layer:Destroy() end
	layer = new("Frame", {
		Name = "AbilityVfxLayer",
		Parent = screenGui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = Z_BASE,
		Active = false,
	})
end

function AbilityVfx.reset()
	if layer and layer.Parent then
		for _, c in ipairs(layer:GetChildren()) do c:Destroy() end
	end
end

-- Centre of a card in the layer's own pixel space.
local function centreOf(root: GuiObject?): Vector2?
	if not root or not root.Parent or not layer or not layer.Parent then return nil end
	local size = root.AbsoluteSize
	if size.X < 4 then return nil end
	return root.AbsolutePosition - layer.AbsolutePosition + size * 0.5
end

local function img(texture: string, colour: Color3, at: Vector2, w: number, h: number,
	anchor: Vector2, rot: number, transparency: number, z: number): ImageLabel
	local o = new("ImageLabel", {
		Parent = layer,
		BackgroundTransparency = 1,
		Image = texture,
		ImageColor3 = colour,
		ImageTransparency = transparency,
		AnchorPoint = anchor,
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(w, h),
		Rotation = rot,
		ZIndex = z,
	})
	Debris:AddItem(o, 6)
	return o
end

local function tw(o: Instance, seconds: number, goal: { [string]: any },
	style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(o, TweenInfo.new(seconds,
		style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function fadeKill(o: ImageLabel, seconds: number, grow: number?)
	local goal: { [string]: any } = { ImageTransparency = 1 }
	if grow then
		goal.Size = UDim2.fromOffset(o.Size.X.Offset * grow, o.Size.Y.Offset * grow)
	end
	local t = tw(o, seconds, goal)
	t.Completed:Once(function()
		if o.Parent then o:Destroy() end
	end)
end

-- Sparks thrown off an impact point. Small, short, and NOT on the card, so the
-- card's ClipsDescendants cannot eat them.
local function scatter(at: Vector2, colour: Color3, n: number, reach: number, z: number)
	for i = 1, n do
		local a = math.random() * math.pi * 2
		local d = math.random(14, 26)
		local o = img(VfxAssets.Spark, colour, at, d, d, Vector2.new(0.5, 0.5),
			math.random(0, 359), 0.1, z)
		local to = at + Vector2.new(math.cos(a), math.sin(a) * 1.1) * reach * (0.5 + math.random() * 0.7)
		task.delay(i * 0.012, function()
			if o.Parent then
				tw(o, 0.34 + math.random() * 0.2, {
					Position = UDim2.fromOffset(to.X, to.Y),
					Size = UDim2.fromOffset(d * 0.35, d * 0.35),
					ImageTransparency = 1,
				})
				Debris:AddItem(o, 0.8)
			end
		end)
	end
end

-- ── The beam ───────────────────────────────────────────────────────
local function playBeam(r: any, from: Vector2, to: Vector2, cardW: number, mode: string?)
	if mode == "charge" then
		-- Wind-up ONLY, and handled before anything else in this function: it is
		-- energy being gathered ON the caster's own card, so it has no target and
		-- no distance. Leaving it below the travel maths meant a card that wound
		-- up while the opposing seat was empty drew nothing at all.
		local orb = img(VfxAssets.BeamCharge, r.colour, from, cardW * 0.18, cardW * 0.18,
			Vector2.new(0.5, 0.5), 0, 0.55, Z_BASE + 5)
		tw(orb, 0.40, { Size = UDim2.fromOffset(cardW * 1.02, cardW * 1.02),
			ImageTransparency = 0.08 }, Enum.EasingStyle.Quad)
		-- Rotation is tweened separately so the fade below can take size and
		-- transparency back without stopping the spin.
		tw(orb, 1.6, { Rotation = 240 }, Enum.EasingStyle.Linear)
		task.delay(0.66, function()
			if orb.Parent then
				tw(orb, 0.60, { Size = UDim2.fromOffset(cardW * 0.80, cardW * 0.80),
					ImageTransparency = 1 }, Enum.EasingStyle.Quad)
			end
		end)
		Debris:AddItem(orb, 2)
		return
	end

	local delta = to - from
	local dist = delta.Magnitude
	if dist < 8 then return end
	local dir = delta.Unit
	local angle = math.deg(math.atan2(delta.Y, delta.X))
	local thick = math.max(12, cardW * r.thickness)
	local z = Z_BASE + 2

	local function fire()
		-- Muzzle first, so the beam looks like it comes OUT of something.
		local flare = img(VfxAssets.BeamFlare, r.hot, from, thick * 3.4, thick * 3.4,
			Vector2.new(0.5, 0.5), angle, 0.05, z + 2)
		flare.Size = UDim2.fromOffset(thick * 1.2, thick * 1.2)
		tw(flare, 0.10, { Size = UDim2.fromOffset(thick * 3.6, thick * 3.6) },
			Enum.EasingStyle.Back)
		task.delay(0.10, function()
			if flare.Parent then fadeKill(flare, r.hold * 0.9 + 0.2, 0.75) end
		end)

		-- The shaft starts as a zero-length bar sitting on the muzzle and grows
		-- outward. Both the size and the centre are tweened; size alone would
		-- extend the beam backwards out of the firing card as fast as forwards.
		local shaft = img(VfxAssets.BeamCore, r.colour, from, 0, thick,
			Vector2.new(0.5, 0.5), angle, 0.04, z)
		-- A hotter, thinner shaft riding inside the first. One sprite at one
		-- width reads as a painted stripe; two widths read as a core inside a
		-- sheath, which is what light actually looks like.
		local core = img(VfxAssets.BeamCore, r.hot, from, 0, thick * 0.34,
			Vector2.new(0.5, 0.5), angle, 0.12, z + 1)
		local mid = from + dir * (dist * 0.5)

		tw(shaft, 0.085, { Size = UDim2.fromOffset(dist, thick),
			Position = UDim2.fromOffset(mid.X, mid.Y) }, Enum.EasingStyle.Quint)
		tw(core, 0.075, { Size = UDim2.fromOffset(dist, thick * 0.34),
			Position = UDim2.fromOffset(mid.X, mid.Y) }, Enum.EasingStyle.Quint)

		-- Impact once the front actually arrives, not on the same frame it fired.
		task.delay(0.085, function()
			local hit = img(VfxAssets.BeamImpact, r.hot, to,
				thick * 1.5, thick * 1.5, Vector2.new(0.5, 0.5), math.random(0, 359), 0.02, z + 3)
			tw(hit, 0.30, { Size = UDim2.fromOffset(thick * 7 * r.impact, thick * 7 * r.impact),
				ImageTransparency = 1 }, Enum.EasingStyle.Quint)
			Debris:AddItem(hit, 1)
			scatter(to, r.colour, 10, cardW * 1.1, z + 4)
		end)

		-- Hold at full width, then snap shut from the muzzle end: the beam is
		-- cut off at the source, which is why the width collapses rather than
		-- the whole thing fading in place.
		task.delay(0.085 + r.hold, function()
			for _, o in ipairs({ shaft, core }) do
				if o.Parent then
					local t = tw(o, 0.16, {
						Size = UDim2.fromOffset(0, o.Size.Y.Offset * 0.4),
						Position = UDim2.fromOffset(from.X, from.Y),
						ImageTransparency = 1,
					}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					t.Completed:Once(function()
						if o.Parent then o:Destroy() end
					end)
				end
			end
		end)
	end

	fire()
end

-- ── The burst ──────────────────────────────────────────────────────
local function playShots(r: any, from: Vector2, to: Vector2, cardW: number, shots: number?)
	local base = to - from
	if base.Magnitude < 8 then return end
	local z = Z_BASE + 2
	local len = math.max(56, cardW * (r.length or 1.55))
	local thick = math.max(10, cardW * (r.calibre or 0.26))

	-- The server rolls the real shot count (5-12 for Run & Gun) and puts it on
	-- the Attack event. Drawing the recipe's fixed count instead would show ten
	-- tracers for a five-bullet volley.
	local count = math.clamp(shots or r.count, 1, 16)
	for i = 1, count do
		task.delay((i - 1) * r.gap, function()
			if not layer or not layer.Parent then return end
			-- Each round takes its own line. A burst fired down one perfect
			-- track reads as a single dashed beam, not as separate shots.
			local jitter = Vector2.new(
				(math.random() - 0.5) * cardW * r.spread,
				(math.random() - 0.5) * cardW * r.spread)
			local muzzle = from + Vector2.new((math.random() - 0.5) * cardW * 0.18,
				(math.random() - 0.5) * cardW * 0.18)
			local target = to + jitter
			local delta = target - muzzle
			local angle = math.deg(math.atan2(delta.Y, delta.X))

			local flash = img(VfxAssets.BeamFlare, r.hot, muzzle, thick * 4.2, thick * 4.2,
				Vector2.new(0.5, 0.5), angle, 0.02, z + 2)
			fadeKill(flash, 0.16, 1.6)

			-- The sprite's nose is its RIGHT edge and rotation pivots about the
			-- centre, so the centre has to ride half a body-length behind the
			-- nose along the line of fire. Tweening the nose position directly
			-- lands the round half a body early and starts it half a body inside
			-- the shooter.
			local dir = delta.Unit
			local back = dir * (len * 0.5)
			-- Two layers, same as the beam: a wide coloured round with a hot thin
			-- one inside it. A single tracer at a single width is a coloured
			-- dash; the pair reads as something burning.
			-- Three layers. The sprite is mostly a long low-alpha tail, so one copy at
			-- one width reads as a faint scratch against a dark board - which is
			-- exactly how the first build failed: firing correctly, invisible.
			-- Wide dim bloom, solid coloured body, near-white spine.
			local bloom = img(VfxAssets.ShotTracer, r.colour, muzzle - back, len * 1.05, thick * 2.3,
				Vector2.new(0.5, 0.5), angle, 0.62, z - 1)
			local shot = img(VfxAssets.ShotTracer, r.colour, muzzle - back, len, thick,
				Vector2.new(0.5, 0.5), angle, 0.02, z)
			local spine = img(VfxAssets.ShotTracer, r.hot, muzzle - back, len, thick * 0.40,
				Vector2.new(0.5, 0.5), angle, 0.04, z + 1)
			local flight = 0.13 + math.random() * 0.04
			local land = target - back
			for _, o in ipairs({ bloom, shot, spine }) do
				tw(o, flight, { Position = UDim2.fromOffset(land.X, land.Y) },
					Enum.EasingStyle.Linear)
			end

			task.delay(flight, function()
				for _, o in ipairs({ bloom, shot, spine }) do
					if o.Parent then
						tw(o, 0.10, { ImageTransparency = 1 })
						Debris:AddItem(o, 0.3)
					end
				end
				local hit = img(VfxAssets.BeamImpact, r.hot, target,
					thick * 1.6, thick * 1.6, Vector2.new(0.5, 0.5),
					math.random(0, 359), 0.0, z + 3)
				tw(hit, 0.26, { Size = UDim2.fromOffset(thick * 7.0, thick * 7.0),
					ImageTransparency = 1 }, Enum.EasingStyle.Quint)
				Debris:AddItem(hit, 0.6)
				scatter(target, r.colour, 3, cardW * 0.45, z + 4)
			end)
		end)
	end
end

-- ── Public ─────────────────────────────────────────────────────────
-- Returns true when the passive had a recipe, so the caller can tell the
-- difference between "played" and "nothing defined for this ability".
-- `opts.firesOn` says which event the caller is reacting to. A recipe only
-- plays for its own source, so the Attack branch cannot double-fire a beam
-- that the Passive branch already played, and vice versa.
-- `opts.shots` is the server's rolled hit count for this volley.
function AbilityVfx.play(passiveId: string?, fromRoot: GuiObject?, toRoot: GuiObject?,
	opts: { firesOn: string?, shots: number?, trigger: string? }?): boolean
	if not passiveId then return false end
	local r = RECIPES[passiveId]
	if not r then return false end
	if (r.firesOn or "passive") ~= ((opts and opts.firesOn) or "passive") then return false end

	-- Which clause of the passive fired decides which beat plays, and whether
	-- anything plays at all. A recipe with a `triggers` table is opt-IN: a
	-- clause it does not name draws nothing, which is what stops a passive's
	-- bookkeeping clauses from replaying its headline effect.
	local mode = "beam"
	if r.triggers then
		mode = r.triggers[(opts and opts.trigger) or ""]
		if not mode then return false end
	end
	if not layer or not layer.Parent then return false end

	local from = centreOf(fromRoot)
	if not from then return false end
	-- Only a beat that TRAVELS needs somewhere to travel to.
	local to = (mode == "charge") and from or centreOf(toRoot)
	if not to then return false end

	local cardW = (fromRoot :: GuiObject).AbsoluteSize.X
	if cardW < 8 then return false end

	if r.kind == "shots" then
		playShots(r, from, to, cardW, opts and opts.shots)
	else
		playBeam(r, from, to, cardW, mode)
	end
	return true
end

return AbilityVfx
