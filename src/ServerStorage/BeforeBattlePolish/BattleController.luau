--!strict
-- Battle presentation. Marvel-Snap-shaped: one board, one location, two cards
-- facing each other, a hand along the bottom.
--
-- THIS FILE IS PRESENTATION ONLY. It owns no combat rules. Every fact it draws
-- arrives from the server through Shared.Net.BattleRemotes, and every action a
-- player takes goes back through the same RemoteFunction for the server to
-- validate. Damage, HP, abilities, rarity, decks, rewards and win/loss all
-- still live where they lived before.
--
--   Action (RemoteFunction) : "StartTest" | "PlayCard" {slot} | "Forfeit"
--   State  (RemoteEvent)    : full snapshot, authoritative
--   Event  (RemoteEvent)    : one chronological beat to animate
--
-- Furniture is built by Shared.UI.BattleLayout; the look lives in
-- Shared.UI.BattleTheme. Card faces are drawn by the EXISTING Shared.UI.
-- CardRenderer, so rarity borders, shine and ability text are untouched.
--
-- Location: StarterPlayer > StarterPlayerScripts > Client > Controllers

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LeaderboardVisibility = require(ReplicatedStorage.Shared.UI.LeaderboardVisibility)
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local BattleRemotes = require(ReplicatedStorage.Shared.Net.BattleRemotes)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local Sweep = require(ReplicatedStorage.Shared.UI.Sweep)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local BattleTheme = require(ReplicatedStorage.Shared.UI.BattleTheme)
local BattleLayout = require(ReplicatedStorage.Shared.UI.BattleLayout)
local LocationDefinitions = require(ReplicatedStorage.Shared.Config.LocationDefinitions)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local PassiveDefinitions = require(ReplicatedStorage.Shared.Config.PassiveDefinitions)
local StatusEffects = require(ReplicatedStorage.Shared.Config.StatusEffects)
local StatusVfx = require(ReplicatedStorage.Shared.UI.StatusVfx)
local AbilityVfx = require(ReplicatedStorage.Shared.UI.AbilityVfx)
local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)
local EncounterDefinitions = require(ReplicatedStorage.Shared.Config.EncounterDefinitions)
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local RewardPopup = require(ReplicatedStorage.Shared.UI.RewardPopup)
local RestrictionTip = require(ReplicatedStorage.Shared.UI.RestrictionTip)
local ArtLoader = require(ReplicatedStorage.Shared.UI.ArtLoader)
local GamePassConfig = require(ReplicatedStorage.Shared.Config.GamePassConfig)
local MarketplaceService = game:GetService("MarketplaceService")

local C = BattleTheme.Colors
local E = BattleTheme.Ease
local new = BattleTheme.new
local tween = BattleTheme.tween
local Z = BattleLayout.Z

local BattleController = {}
BattleController.Name = "BattleController"

local player = Players.LocalPlayer

-- ── State ───────────────────────────────────────────────────────────
local gui: ScreenGui
local R                       -- layout references
local testButton: TextButton?

local snapshot = nil          -- last authoritative snapshot
local handRefs: { any } = {}  -- one entry per card in hand
local fieldRefs = { player = nil :: any, enemy = nil :: any }
local defeatedCards = { player = {}, enemy = {} }
local dragging = nil :: any
local inspectCard = nil :: any
local busy = false            -- true while the server is resolving a round
local ending = false          -- guards the short result transition from duplicate events

-- Gesture state, declared up here because clearHand() below has to be able to
-- cancel an in-flight press. Declared any lower and those assignments would
-- silently create globals instead of clearing these.
local pressRef = nil :: any
local pressAt = nil :: Vector2?
local pressMoved = false
local dragOverSeat = false    -- pointer is over the drop zone right now

-- Defined further down, but called from handleEvent above it.
local setStageVisible

-- ── Sound (reuses the game's existing UI sounds; adds no new ids) ────────
local function uiSound(name: string)
	local template = SoundService:FindFirstChild(name, true)
	if not template or not template:IsA("Sound") then return end
	local s = template:Clone()
	s.Name = "Battle_" .. name
	s.Parent = SoundService
	s.TimePosition = 0
	s:Play()
	Debris:AddItem(s, math.max(s.TimeLength + 1, 3))
end
local function hoverSound() uiSound("UIHover") end
local function clickSound() uiSound("UIClick") end

-- ── Battle Power ──────────────────────────────────────────────────
-- Unchanged from the previous controller, deliberately: supports are excluded
-- and the figure is effective rarity, which is how LeaderboardService computes
-- it. The battle screen and the leaderboard must never disagree.
local function entryBattlePower(entry): number
	if not entry or not entry.cardId then return 0 end
	local def = CardStats.definition(entry.cardId)
	if not (def and def.baseRarity) then return 0 end
	local variant = VariantConfig.get(entry.variant or "Standard")
	return VariantConfig.effectiveRarity(def.baseRarity, variant.id)
end

local function sideBattlePower(side): number
	if not side then return 0 end
	local total = 0
	for _, card in ipairs(side.hand or {}) do
		total += entryBattlePower(card)
	end
	if side.active then total += entryBattlePower(side.active) end
	return total
end

-- ── Small helpers ─────────────────────────────────────────────────
local noticeToken = 0
local function notice(message: string, color: Color3?)
	if not R then return end
	noticeToken += 1
	local mine = noticeToken
	R.notice.Text = string.upper(message)
	R.notice.TextColor3 = color or C.Gold
	R.notice.TextTransparency = 0
	task.delay(2.2, function()
		if noticeToken == mine and R then
			tween(R.notice, E.Fade, { TextTransparency = 1 })
		end
	end)
end

local function cardData(entry)
	-- CardRenderer computes printed stats from cardId/variant/level, but accepts
	-- dmg/maxHP overrides. Passing the snapshot's LIVE figures is what keeps a
	-- buffed or drained card honest on its own face.
	return {
		cardId = entry.cardId,
		variant = entry.variant,
		level = entry.level,
		dmg = entry.dmg,
		maxHP = entry.maxHP,
	}
end

local function buildCard(parent: Instance, width: number, z: number, entry)
	local card = CardRenderer.create(parent, width, z)
	CardRenderer.update(card, cardData(entry))
	-- Named so StatusVfx can find them and put effect icons beside the name.
	if card.name then card.name.Name = "CardName" end
	if card.denom then card.denom.Name = "CardDenom" end
	-- No travelling highlight on a battle card.
	--
	-- It earns its place in the deck screen and the collection, where cards sit
	-- apart and a slow gleam reads as gloss. In here they overlap constantly -
	-- the hand is a pile with 4px of each card showing, cards get dragged over
	-- one another, and a seat card sits under a health bar - so the highlights
	-- pile up and composite into stripes across the whole board instead of
	-- lighting one card. Stripped at the source, so every battle card is
	-- covered: hand, both seats, and the inspect modal.
	Sweep.remove(card.root)
	return card
end

-- ── Reactive HP bar for a card standing on the field ────────────────────
local function attachHealth(host: GuiObject, card, accent: Color3, z: number)
	local cardHeight = card.root.Size.Y.Offset
	local bar = new("Frame", {
		Name = "HealthBar",
		-- CardRenderer clips its card root to preserve rounded artwork. Parenting
		-- here would cut off any bar positioned below the card, so the bar belongs
		-- to the transparent, unclipped active-card holder instead.
		Parent = host,
		AnchorPoint = Vector2.new(0.5, 0),
		-- The logical holder is taller than the rendered card. Position from the
		-- card's real bottom edge so short viewports do not crop the player bar.
		Position = UDim2.new(0.5, 0, 0.5, cardHeight / 2 + 2),
		Size = UDim2.new(1, -6, 0, 18),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z + 12,
	}, { new("UIScale", { Name = "ReactionScale", Scale = 1 }) })

	local track = new("Frame", {
		Name = "Track",
		Parent = bar,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(17, 12, 28),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = z + 12,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 7) }),
		new("UIStroke", {
			Name = "HealthStroke",
			Color = accent,
			Thickness = 1.4,
			Transparency = 0.38,
		}),
	})

	-- The delayed trail makes lost HP readable instead of instantly disappearing.
	local trail = new("Frame", {
		Name = "DamageTrail",
		Parent = track,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 174, 74),
		BorderSizePixel = 0,
		ZIndex = z + 13,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 7) }) })

	local fill = new("Frame", {
		Name = "Fill",
		Parent = track,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Good,
		BorderSizePixel = 0,
		ZIndex = z + 14,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 7) }),
		new("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(175, 175, 175)),
			Rotation = 90,
		}),
	})

	local sheen = new("Frame", {
		Name = "Sheen",
		Parent = fill,
		Size = UDim2.new(1, 0, 0.36, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		ZIndex = z + 15,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 7) }) })
	local _ = sheen

	local label = BattleLayout.text(track, {
		Name = "Value",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextColor3 = C.Text,
		TextScaled = true,
		ZIndex = z + 17,
	})
	new("UITextSizeConstraint", { Parent = label, MaxTextSize = 12 })
	new("UIStroke", { Parent = label, Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.3 })

	local flash = new("Frame", {
		Name = "ReactionFlash",
		Parent = bar,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Bad,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z + 18,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 7) }),
		new("UIStroke", {
			Name = "ReactionStroke",
			Color = C.Bad,
			Thickness = 2,
			Transparency = 1,
		}),
	})

	return {
		bar = bar, track = track, trail = trail, fill = fill, label = label,
		flash = flash, reactionScale = bar:FindFirstChild("ReactionScale"),
		current = nil, max = nil, reactionToken = 0,
	}
end

local function setHealth(ref, current: number, max: number, animate: boolean?)
	if not ref or not ref.health then return end
	local health = ref.health
	max = math.max(1, max)
	current = math.clamp(current, 0, max)
	local oldCurrent, oldMax = health.current, health.max
	-- Keep inspect/stat refreshes in step with the number actually replayed.
	if ref.entry then ref.entry.currentHP = current; ref.entry.maxHP = max end
	health.current, health.max = current, max
	health.label.Text = "HP " .. Format.short(current) .. " / " .. Format.short(max)
	-- A Stat event or snapshot often repeats the preceding Damage value.
	-- Leave its running tween and delayed trail alone instead of restarting them.
	if animate and oldCurrent == current and oldMax == max then return end
	health.reactionToken += 1
	local token = health.reactionToken
	if health.fillTween then health.fillTween:Cancel() end
	if health.trailTween then health.trailTween:Cancel() end
	local pct = math.clamp(current / max, 0, 1)
	local color = pct > 0.6 and C.Good or (pct > 0.3 and C.Gold or C.Bad)
	local healthStroke = health.track:FindFirstChild("HealthStroke")
	local tookDamage = oldCurrent ~= nil and current < oldCurrent
	local healed = oldCurrent ~= nil and current > oldCurrent
	if animate and oldCurrent ~= nil then
		-- Tween from the displayed position. Never snap back to an old target
		-- when another hit arrives before the previous animation finishes.
		health.fillTween = tween(health.fill, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(pct, 1), BackgroundColor3 = color,
		})
		if tookDamage then
			health.trail.BackgroundColor3 = Color3.fromRGB(255, 174, 74)
			task.delay(0.16, function()
				if ref.health == health and health.reactionToken == token and health.trail.Parent then
					health.trailTween = tween(health.trail, E.Drift, { Size = UDim2.fromScale(pct, 1) })
				end
			end)
		else
			health.trailTween = tween(health.trail, E.Return, { Size = UDim2.fromScale(pct, 1) })
		end
		if tookDamage or healed then
			local reactionColor = healed and C.Good or C.Bad
			health.flash.BackgroundColor3 = reactionColor
			health.flash.BackgroundTransparency = 0.72
			local reactionStroke = health.flash:FindFirstChild("ReactionStroke")
			if reactionStroke and reactionStroke:IsA("UIStroke") then
				reactionStroke.Color = reactionColor
				reactionStroke.Transparency = 0.08
				tween(reactionStroke, TweenInfo.new(0.32), { Transparency = 1 })
			end
			tween(health.flash, TweenInfo.new(0.32), { BackgroundTransparency = 1 })
		end
	else
		health.fill.Size = UDim2.fromScale(pct, 1)
		health.fill.BackgroundColor3 = color
		health.trail.Size = UDim2.fromScale(pct, 1)
	end
	if healthStroke and healthStroke:IsA("UIStroke") then
		healthStroke.Color = pct <= 0.3 and C.Bad or color
		healthStroke.Transparency = pct <= 0.3 and 0.14 or 0.42
	end
end

local function pulseDamageStat(ref, oldDmg: number?, newDmg: number?)
	if not ref or not ref.card or not ref.card.dmg or oldDmg == nil or newDmg == nil or oldDmg == newDmg then
		return
	end
	local label = ref.card.dmg
	local pulse = label:FindFirstChild("LiveStatPulse")
	if not pulse then
		pulse = new("UIScale", { Name = "LiveStatPulse", Parent = label, Scale = 1 })
	end
	local pulseScale = pulse :: UIScale
	label.TextColor3 = newDmg > oldDmg and C.Good or C.Bad
	pulseScale.Scale = 0.88
	tween(pulseScale, E.Pop, { Scale = 1.16 })
	task.delay(0.14, function()
		if label.Parent and pulse.Parent then
			tween(pulse, E.Return, { Scale = 1 })
			tween(label, E.Drift, { TextColor3 = Color3.fromRGB(255, 82, 82) })
		end
	end)
end

local function updateFieldCard(ref, entry, animateStats: boolean?)
	if not ref or not entry then return end
	local oldDmg = ref.entry and ref.entry.dmg
	CardRenderer.update(ref.card, cardData(entry))
	ref.entry = entry
	setHealth(ref, entry.currentHP or entry.hp or 0, entry.maxHP or 1, true)
	if animateStats then
		pulseDamageStat(ref, oldDmg, entry.dmg)
	end
end

-- ── Hand ──────────────────────────────────────────────────────────
-- These MUST be read live, not captured. BattleLayout rescales them to the
-- window, and a captured copy silently kept the hand at its authored size while
-- the rest of the board resized around it - which is what pushed the hand off
-- the bottom of the screen.
local function handW(): number return BattleLayout.HandCardWidth end
local function handH(): number return BattleLayout.HandCardWidth * 1.45 end
local function fieldW(): number return BattleLayout.FieldCardWidth end

-- ── The tray ──────────────────────────────────────────────────────
-- The hand is a pile in the bottom-right corner that fans out to the LEFT on
-- hover. Every card is anchored to the tray frame's bottom-right corner, so
-- "further left" is just a more negative X offset and the tray frame itself
-- never has to change size.
local trayExpanded = false
local trayToken = 0        -- cancels a pending collapse
local hoveredCard = nil :: any

-- Assigned below; setTrayExpanded has to be able to re-raise a card that was
-- already hovered when the fan opened underneath it.
local raiseCard

local TRAY_COLLAPSE_DELAY = 0.34
local TRAY_STAGGER        = 0.028
-- A hovered card rises and grows toward the enemy effects rail above the tray.
-- 18 and 1.12 leave about 20px of clearance at the tightest point; larger
-- values put the top of the card behind the rail.
local CARD_LIFT           = 18
local CARD_HOVER_SCALE    = 1.12

local function trayHome(index: number, count: number): (UDim2, number)
	-- `back` counts from the RIGHT: 0 is the card sitting at the tray corner.
	local back = count - index

	if not trayExpanded then
		-- Collapsed: a neat pile, each card peeking a few pixels out from under
		-- the one in front with a slight tilt so it reads as physical cards
		-- rather than one thick rectangle.
		local step = math.min(4, 26 / math.max(count, 1))
		return UDim2.new(1, -back * step, 1, -back * step * 1.2), -back * 1.1
	end

	-- Expanded: fanned left across TraySpan, which BattleLayout bounds so the
	-- leftmost card can never reach the player's own card.
	local w = handW()
	local span = BattleLayout.TraySpan or 520
	local spacing = count > 1
		and math.min(w * 0.80, (span - w) / (count - 1))
		or 0

	-- t: 0 at the leftmost card, 1 at the rightmost.
	local t = count > 1 and (index - 1) / (count - 1) or 0.5
	-- A shallow arc - the middle of the fan rides highest, the ends drop away.
	local lift = math.sin(t * math.pi) * 16
	local rot = (t - 0.5) * 11
	return UDim2.new(1, -back * spacing, 1, -lift), rot
end

local function layoutHand(animate: boolean?)
	local count = #handRefs
	for i, ref in ipairs(handRefs) do
		local pos, rot = trayHome(i, count)
		ref.home = pos
		ref.homeRotation = rot
		-- Later cards sit in front, so the pile has a clear top card and the fan
		-- overlaps rightward-on-top like a real hand.
		ref.holder.ZIndex = Z.Hand + i
		if ref == dragging or ref == hoveredCard then continue end
		if animate then
			-- Staggered, and dealt from the outside in when expanding so the fan
			-- appears to shuffle open rather than snapping.
			local order = trayExpanded and (count - i) or (i - 1)
			local holder = ref.holder
			task.delay(order * TRAY_STAGGER, function()
				if not holder.Parent then return end
				if ref == dragging or ref == hoveredCard then return end
				tween(holder, E.Drift, { Position = pos, Rotation = rot })
			end)
		else
			ref.holder.Position = pos
			ref.holder.Rotation = rot
		end
	end

	if R and R.trayCount then
		R.trayCount.Text = count > 0
			and (("%d CARD%s"):format(count, count == 1 and "" or "S"))
			or ""
	end
	if R and R.trayPad then
		tween(R.trayPad, E.Fade, { BackgroundTransparency = trayExpanded and 0.92 or 0.72 })
	end
end

-- Is the pointer over the tray, counting the cards themselves once fanned out?
-- Checking real geometry rather than keeping an enter/leave counter, because
-- those counters drift the moment a card is destroyed while hovered - which
-- happens on every snapshot.
local function pointerInTray(): boolean
	if not R or not R.hand then return false end
	local m = UserInputService:GetMouseLocation()
	local PAD = 26

	local function inside(o: GuiObject): boolean
		local p, s = o.AbsolutePosition, o.AbsoluteSize
		return m.X >= p.X - PAD and m.X <= p.X + s.X + PAD
		   and m.Y >= p.Y - PAD and m.Y <= p.Y + s.Y + PAD
	end

	if R.trayHit and inside(R.trayHit) then return true end
	for _, ref in ipairs(handRefs) do
		if ref.holder and ref.holder.Parent and inside(ref.holder) then return true end
	end
	return false
end

local function setTrayExpanded(on: boolean)
	if trayExpanded == on then return end
	trayExpanded = on
	layoutHand(true)
	-- The pointer may already be sitting on the top card of the pile when the
	-- fan opens. layoutHand deliberately skips the hovered card, so its raise
	-- has to be recomputed against its NEW home or it stays parked at the old one.
	if hoveredCard and raiseCard then raiseCard(hoveredCard, true) end
end

local function expandTray()
	trayToken += 1            -- cancels any collapse already scheduled
	if not trayExpanded then
		hoverSound()
		setTrayExpanded(true)
	end
end

local function scheduleCollapse()
	trayToken += 1
	local tok = trayToken
	task.delay(TRAY_COLLAPSE_DELAY, function()
		if tok ~= trayToken then return end     -- re-entered in the meantime
		if dragging then return end             -- never collapse mid-drag
		if hoveredCard then return end          -- still reading a card
		if pointerInTray() then return end
		setTrayExpanded(false)
	end)
end

function raiseCard(ref, up: boolean)
	if dragging == ref or not ref.holder or not ref.holder.Parent then return end
	local scale = ref.holder:FindFirstChildOfClass("UIScale")
	if up then
		hoveredCard = ref
		-- Raised, enlarged, straightened, and lifted above its neighbours.
		tween(ref.holder, E.Hover, {
			Position = ref.home + UDim2.fromOffset(0, -CARD_LIFT),
			Rotation = 0,
		})
		if scale then tween(scale, E.Hover, { Scale = CARD_HOVER_SCALE }) end
		BattleTheme.setGlow(ref.holder, 1)
		ref.holder.ZIndex = Z.Hand + 40
	else
		if hoveredCard == ref then hoveredCard = nil end
		tween(ref.holder, E.Hover, { Position = ref.home, Rotation = ref.homeRotation })
		if scale then tween(scale, E.Hover, { Scale = 1 }) end
		BattleTheme.setGlow(ref.holder, 0)
		ref.holder.ZIndex = Z.Hand + (ref.index or 1)
	end
end

local function clearHand()
	for _, ref in ipairs(handRefs) do
		if ref.holder then ref.holder:Destroy() end
	end
	table.clear(handRefs)
	dragging = nil
	-- The hovered card is one of the ones just destroyed. Left set, it would
	-- block every future collapse forever.
	hoveredCard = nil
	-- drop any in-flight gesture; its card no longer exists
	pressRef, pressAt, pressMoved = nil, nil, false
	-- A snapshot can land while the tray is open and the pointer is nowhere near
	-- it. This re-checks and closes it if so.
	scheduleCollapse()
end

-- forward declarations, because drag-drop and inspect refer to each other
local openInspect
local playSlot

local function pointerInside(frame: GuiObject, pos: Vector2): boolean
	local p, s = frame.AbsolutePosition, frame.AbsoluteSize
	return pos.X >= p.X and pos.X <= p.X + s.X
	   and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

local function endDrag(commit: boolean)
	local ref = dragging
	if not ref then return end
	dragging = nil

	local seat = R.playerSeat
	dragOverSeat = false
	if seat.setEmpty then seat.setEmpty(true, false) end

	ref.holder.Parent = R.hand
	local scale = ref.holder:FindFirstChildOfClass("UIScale")

	local mouse = UserInputService:GetMouseLocation()
	local dropped = commit and pointerInside(seat.holder, mouse)

	if dropped then
		-- Snap to the seat first so the card visibly lands, then ask the server.
		-- If the server refuses, the next snapshot puts it back in hand anyway.
		-- Hand cards anchor at their BOTTOM-RIGHT now that the hand is a tray, so
		-- landing the card's CENTRE on the seat's centre means aiming its corner
		-- half a card down and to the right of that point. Without this the card
		-- snaps in visibly offset by half its own size.
		local seatPos = seat.holder.AbsolutePosition + seat.holder.AbsoluteSize / 2
		local handPos = R.hand.AbsolutePosition
		local half = ref.holder.AbsoluteSize / 2
		tween(ref.holder, E.Snap, {
			Position = UDim2.fromOffset(
				seatPos.X - handPos.X + half.X,
				seatPos.Y - handPos.Y + half.Y),
			Rotation = 0,
		})
		if scale then tween(scale, E.Snap, { Scale = 1 }) end
		clickSound()
		playSlot(ref.slot)
	else
		tween(ref.holder, E.Return, { Position = ref.home, Rotation = ref.homeRotation })
		if scale then tween(scale, E.Return, { Scale = 1 }) end
		BattleTheme.setGlow(ref.holder, 0)
	end
end

local function beginDrag(ref)
	dragging = ref
	ref.holder.Parent = R.dragLayer
	ref.holder.ZIndex = Z.Drag + 5
	local scale = ref.holder:FindFirstChildOfClass("UIScale")
	if scale then tween(scale, E.Hover, { Scale = 1.06 }) end
	tween(ref.holder, E.Hover, { Rotation = 0 })

	-- The tray stays open for the whole drag - scheduleCollapse checks
	-- `dragging` before it fires.
	expandTray()

	local seat = R.playerSeat
	dragOverSeat = false
	if seat.setEmpty then seat.setEmpty(true, false) end
end

-- ONE set of global handlers is installed in Init and reads the gesture state
-- declared at the top of the file. The previous version connected
-- InputChanged/InputEnded per card, and since the hand is rebuilt on every
-- snapshot those connections accumulated forever, each still holding a
-- reference to a destroyed card.
-- ── Off-field health ──────────────────────────────────────────────
-- A card waiting in hand can still be hurt: splash, "next enemy in line"
-- abilities and the location all reach past the front line. Until now the only
-- way to find out was to play the card and read its bar on the field.
--
-- The bar lives INSIDE the card, along the bottom. A hand card no longer
-- renders its ability paragraph - the whole card is one click away in the
-- inspector - so that band is free, and anything drawn OUTSIDE the card would
-- be covered by the next card in the pile anyway.

-- Last DISPLAYED health per off-field card, keyed "side:slot".
--
-- The hand is rebuilt from scratch on every snapshot, so the bar that shows a
-- card's new health is a different Frame from the one that showed its old
-- health - which is why the first build had no animation at all: there was
-- nothing left to animate FROM. Remembering the previous figure lets the new
-- bar open at the old value and run down to the new one, so a hand card loses
-- health the same way a card on the field does.
local offFieldHp: { [string]: { cur: number, max: number } } = {}

local function forgetOffFieldHp()
	table.clear(offFieldHp)
end

local function attachOffFieldHealth(root: GuiObject, accent: Color3, z: number,
	clearsRow: boolean?)
	-- `clearsRow` is set for a real card face, which still prints its DMG / HP
	-- figures along the very bottom edge. CardRenderer lays that row out against
	-- a scale derived from the card's height, so the bar computes the same scale
	-- and parks itself just above the row instead of on top of it.
	local inset = 7
	if clearsRow then
		local sc = math.clamp(root.Size.Y.Offset / math.floor(240 * 1.34), 0.55, 1)
		inset = math.floor(6 * sc + 0.5) + math.floor(22 * sc + 0.5) + 3
	end

	local track = new("Frame", {
		Name = "OffFieldHP",
		Parent = root,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -inset),
		Size = UDim2.new(1, -16, 0, 11),
		BackgroundColor3 = Color3.fromRGB(17, 12, 28),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = z + 18,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 6) }),
		new("UIStroke", { Color = accent, Thickness = 1, Transparency = 0.58 }),
	})

	-- The lagging amber remainder, same idea as the field bar: it holds the old
	-- length for a beat after the green has dropped, so the SIZE of the hit is
	-- readable rather than just the result.
	local trail = new("Frame", {
		Name = "Trail",
		Parent = track,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 174, 74),
		BorderSizePixel = 0,
		ZIndex = z + 19,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 6) }) })

	local fill = new("Frame", {
		Name = "Fill",
		Parent = track,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Good,
		BorderSizePixel = 0,
		ZIndex = z + 20,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 6) }),
		new("UIGradient", {
			Color = ColorSequence.new(Color3.fromRGB(236, 236, 236), Color3.fromRGB(142, 142, 142)),
			Rotation = 90,
		}),
	})

	-- Left aligned, not centred. In the fanned tray every card is overlapped on
	-- its RIGHT by the next one, so a centred figure gets its second half
	-- covered; the left edge of a card is the part that is always on show.
	local label = BattleLayout.text(track, {
		Name = "Value",
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -10, 1, 0),
		Text = "",
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		ZIndex = z + 21,
	})
	new("UITextSizeConstraint", { Parent = label, MaxTextSize = 10 })
	new("UIStroke", { Parent = label, Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.25 })

	local function shade(frac: number): Color3
		-- Green down to half, amber to a quarter, red below: the same three-step
		-- read the field bar uses, so one glance means the same thing anywhere.
		return frac > 0.5 and C.Good or (frac > 0.25 and C.Gold or C.Bad)
	end

	return function(current: number?, maximum: number?, key: string?)
		local max = math.max(1, maximum or 1)
		local cur = math.clamp(current or max, 0, max)
		local frac = cur / max
		label.Text = ("%s / %s"):format(Format.short(cur), Format.short(max))

		local prev = key and offFieldHp[key] or nil
		if key then offFieldHp[key] = { cur = cur, max = max } end

		-- Nothing remembered, or nothing changed: take the final state straight
		-- away. Animating a card that has simply been rebuilt would make the
		-- whole hand twitch on every snapshot.
		if not prev or prev.cur == cur then
			fill.Size = UDim2.fromScale(frac, 1)
			fill.BackgroundColor3 = shade(frac)
			trail.Size = UDim2.fromScale(frac, 1)
			return
		end

		local from = math.clamp(prev.cur / math.max(1, prev.max), 0, 1)
		fill.Size = UDim2.fromScale(from, 1)
		fill.BackgroundColor3 = shade(from)
		trail.Size = UDim2.fromScale(from, 1)

		tween(fill, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(frac, 1),
			BackgroundColor3 = shade(frac),
		})
		if cur < prev.cur then
			task.delay(0.16, function()
				if trail.Parent then tween(trail, E.Drift, { Size = UDim2.fromScale(frac, 1) }) end
			end)
		else
			tween(trail, E.Return, { Size = UDim2.fromScale(frac, 1) })
		end
	end
end

-- ── The enemy tray ────────────────────────────────────────────────
-- Their bench, face down, at the top of the same edge the player's tray sits on.
--
-- The client cannot draw these cards even if it wanted to: the server redacts
-- the enemy hand to a slot and a health figure before sending it, so there is
-- no id, name or art here to leak. What is drawn is a back, a count, and how
-- badly each one has been hurt.
local enemyRefs: { any } = {}
local enemyTrayOpen = false

local function enemyTrayHome(index: number, count: number): (UDim2, number)
	local back = count - index
	if not enemyTrayOpen then
		-- Mirror of the player's pile: theirs peels up-and-left out of a
		-- bottom-right corner, this one peels DOWN-and-left out of a top-right one.
		local step = math.min(4, 26 / math.max(count, 1))
		return UDim2.new(1, -back * step, 0, back * step * 1.2), -back * 1.1
	end
	local w = handW()
	local span = BattleLayout.EnemyTraySpan or BattleLayout.TraySpan or 420
	local spacing = count > 1
		and math.min(w * 0.80, (span - w) / (count - 1))
		or 0
	local tt = count > 1 and (index - 1) / (count - 1) or 0.5
	local drop = math.sin(tt * math.pi) * 16
	return UDim2.new(1, -back * spacing, 0, drop), (tt - 0.5) * 11
end

local function layoutEnemyHand(animate: boolean?)
	local count = #enemyRefs
	for i, ref in ipairs(enemyRefs) do
		local pos, rot = enemyTrayHome(i, count)
		ref.holder.ZIndex = Z.Hand + i
		if animate then
			local order = enemyTrayOpen and (count - i) or (i - 1)
			local holder = ref.holder
			task.delay(order * 0.028, function()
				if holder.Parent then tween(holder, E.Drift, { Position = pos, Rotation = rot }) end
			end)
		else
			ref.holder.Position = pos
			ref.holder.Rotation = rot
		end
	end
	if R and R.enemyTrayCount then
		R.enemyTrayCount.Text = count > 0
			and (("%d CARD%s"):format(count, count == 1 and "" or "S"))
			or ""
	end
	if R and R.enemyToggle then
		R.enemyToggle.Visible = count > 0
	end
	if R and R.enemyTrayPad then
		tween(R.enemyTrayPad, E.Fade, { BackgroundTransparency = enemyTrayOpen and 0.92 or 0.72 })
	end
end

-- The back. Deliberately NOT a CardRenderer card with its face blanked: that
-- would mean building the real card and covering it, which is one bug away from
-- showing it.
-- The back. Deliberately NOT a CardRenderer card with its face blanked: that
-- would mean building the real card and covering it, which is one bug away from
-- showing it.
--
-- The art is the game's OWN card back - the same texture the physical cards in
-- the encounter world and the lobby monument are printed with - rather than
-- something invented for this one screen. A second back design would be a
-- second thing to keep in step every time the first one changes.
local function buildCardBack(parent: Instance, width: number, z: number)
	local height = math.floor(width * 1.34)
	local root = new("Frame", {
		Name = "Back",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Color3.fromRGB(12, 10, 18),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = z,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 10) }),
		-- A quiet grey hairline. At 3px in their crimson the backs read as hazard
		-- tape: the brightest, hardest edge on the board, on the one element that
		-- carries the least information. The tray is background - which side it
		-- belongs to is already obvious from where it sits.
		new("UIStroke", {
			Color = Color3.fromRGB(118, 122, 138), Thickness = 1, Transparency = 0.38,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			LineJoinMode = Enum.LineJoinMode.Round,
		}),
	})
	new("ImageLabel", {
		Parent = root,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 10, 18),
		BorderSizePixel = 0,
		Image = EncounterDefinitions.Assets.CardBack,
		-- Tinted to a cool slate and dropped a little. The texture is printed
		-- for a card standing in a lit 3D scene, where those red streaks are a
		-- highlight; flat on a dark HUD at thumbnail size they are the loudest
		-- thing on the board. A tint with less red than blue mutes them without
		-- touching the crest, so it is still recognisably the game's own back.
		ImageColor3 = Color3.fromRGB(132, 138, 156),
		ImageTransparency = 0.06,
		-- Crop, matching EncounterCard and the monument: the texture is not the
		-- same aspect as a battle card and stretching it warps the crest.
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = z + 1,
	})
	return root
end

local function addEnemyCard(entry, index: number)
	local holder = new("Frame", {
		Name = "EnemyHand_" .. tostring(entry.slot or index),
		Parent = R.enemyHand,
		-- Anchored top-RIGHT: this tray grows leftward out of the TOP corner.
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(handW(), handH()),
		ZIndex = Z.Hand + index,
	})
	local back = buildCardBack(holder, handW(), Z.Hand + index)
	-- Grey rim on the bar too, for the same reason: the figure is the signal,
	-- the housing around it is not.
	local setHp = attachOffFieldHealth(back, Color3.fromRGB(118, 122, 138), Z.Hand + index)
	setHp(entry.currentHP, entry.maxHP, "enemy:" .. tostring(entry.slot))
	enemyRefs[index] = { slot = entry.slot, holder = holder, back = back, setHp = setHp,
		maxHP = entry.maxHP, currentHP = entry.currentHP }
end

local function clearEnemyHand()
	for _, ref in ipairs(enemyRefs) do
		if ref.holder then ref.holder:Destroy() end
	end
	table.clear(enemyRefs)
end

local function renderEnemyHand(list)
	clearEnemyHand()
	for i, entry in ipairs(list or {}) do
		addEnemyCard(entry, i)
	end
	layoutEnemyHand(false)
end

local function setEnemyTrayOpen(on: boolean)
	if enemyTrayOpen == on then return end
	enemyTrayOpen = on
	layoutEnemyHand(true)
	if R and R.enemyToggleGlyph then
		-- The mark points the way the fan will travel: left to open, right to shut.
		tween(R.enemyToggleGlyph, E.Snap, { Rotation = on and 0 or 180 })
	end
end

local function wireCard(ref)
	-- An explicit button rather than the holder Frame: a fully transparent Frame
	-- is unreliable as a click target, which is why the first build's
	-- click-to-inspect never fired.
	local hit = new("TextButton", {
		Name = "Hit",
		Parent = ref.holder,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = (ref.holder.ZIndex or 1) + 30,
	}) :: TextButton
	ref.hit = hit

	hit.MouseEnter:Connect(function()
		if dragging then return end
		-- Cancels any pending collapse, whether or not the fan is already open.
		expandTray()
		hoverSound()
		raiseCard(ref, true)
		-- Mid-fight is exactly when "how many times can this still fire" matters,
		-- so shift works on the hand as well as in the deck screen.
		RestrictionTip.setTarget(ref.entry and ref.entry.cardId, ref.holder)
	end)
	hit.MouseLeave:Connect(function()
		RestrictionTip.clear(ref.holder)
		if dragging == ref then return end
		raiseCard(ref, false)
		-- Leaving a card is not the same as leaving the tray - the pointer is
		-- usually just crossing onto the next card. scheduleCollapse re-checks
		-- the real pointer position when its timer fires.
		scheduleCollapse()
	end)
	hit.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if dragging or inspectCard then return end
		pressRef = ref
		pressAt = UserInputService:GetMouseLocation()
		pressMoved = false
	end)
end

-- Installed once, from Init.
local function installGestureHandlers()
	UserInputService.InputChanged:Connect(function(input)
		if not pressRef or not pressAt then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if not pressRef.holder or not pressRef.holder.Parent then
			pressRef, pressAt = nil, nil
			return
		end

		local now = UserInputService:GetMouseLocation()
		if not pressMoved and (now - pressAt).Magnitude > 6 then
			pressMoved = true
			beginDrag(pressRef)
		end
		if dragging == pressRef then
			local origin = R.dragLayer.AbsolutePosition
			pressRef.holder.Position = UDim2.fromOffset(now.X - origin.X, now.Y - origin.Y)

			-- Live drop-zone feedback: the seat only lights up fully while the
			-- pointer is actually over it, so "this will play" and "this will go
			-- back" look different before the player lets go.
			local seat = R.playerSeat
			local over = pointerInside(seat.holder, now)
			if over ~= dragOverSeat then
				dragOverSeat = over
				-- The invisible socket only reveals a soft temporary glow while a
				-- valid dragged card is actually over it.
				if seat.setEmpty then seat.setEmpty(true, over) end
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not pressRef then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local ref = pressRef
		local travelled = pressMoved
		pressRef, pressAt, pressMoved = nil, nil, false

		if dragging == ref then
			endDrag(true)
		elseif not travelled then
			-- a press that never travelled is a click: inspect
			clickSound()
			openInspect(ref.entry)
		end
	end)
end

local function addHandCard(entry, index: number)
	local holder = new("Frame", {
		Name = "Hand_" .. tostring(entry.slot),
		Parent = R.hand,
		-- Anchored bottom-RIGHT: the tray grows leftward out of its corner.
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(handW(), handH()),
		ZIndex = Z.Hand + index,
	}, {
		new("UIScale", { Scale = 1 }),
	})
	BattleTheme.glow(holder, C.Player, 0)

	local card = buildCard(holder, handW(), Z.Hand + index, entry)
	card.root.AnchorPoint = Vector2.new(0.5, 0.5)
	card.root.Position = UDim2.fromScale(0.5, 0.5)

	-- The ability paragraph comes off a hand card. At 128px it was four lines
	-- of 8px text that nobody reads mid-round, and clicking the card already
	-- opens it full size in the inspector where the text is actually legible.
	-- Losing it frees the bottom band for the health bar.
	if card.abilityDesc then card.abilityDesc.Visible = false end
	local setHp = attachOffFieldHealth(card.root, C.Player, Z.Hand + index, true)
	setHp(entry.currentHP, entry.maxHP, "player:" .. tostring(entry.slot))

	local ref = {
		slot = entry.slot, entry = entry, holder = holder, card = card, index = index,
		setHp = setHp,
	}
	handRefs[index] = ref
	wireCard(ref)
	return ref
end

-- ── Battlefield seats ──────────────────────────────────────────────
local function clearSeat(side: string)
	local ref = fieldRefs[side]
	if ref and ref.health then
		ref.health.reactionToken += 1
		if ref.health.fillTween then ref.health.fillTween:Cancel() end
		if ref.health.trailTween then ref.health.trailTween:Cancel() end
	end
	if ref and ref.card then StatusVfx.clearAll(ref.card.root) end
	if ref and ref.holder then ref.holder:Destroy() end
	fieldRefs[side] = nil
	local seat = side == "player" and R.playerSeat or R.enemySeat
	if seat.setEmpty then seat.setEmpty(true) else seat.hint.Visible = true end
end

local function setSeat(side: string, entry, animate: boolean?)
	local seat = side == "player" and R.playerSeat or R.enemySeat
	local existing = fieldRefs[side]

	if existing and not existing.defeated and existing.slot == entry.slot and existing.cardId == entry.cardId then
		updateFieldCard(existing, entry, true)
		if existing.card then StatusVfx.sync(existing.card.root, entry.statuses) end
		return existing
	end

	clearSeat(side)
	if seat.setEmpty then seat.setEmpty(false) else seat.hint.Visible = false end

	local holder = new("Frame", {
		Name = "Active",
		Parent = seat.holder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(fieldW(), fieldW() * 1.45),
		BackgroundTransparency = 1,
		ZIndex = Z.Card + 4,
	}, { new("UIScale", { Scale = animate and 0.6 or 1 }) })
	local card = buildCard(holder, fieldW(), Z.Card + 4, entry)
	card.root.AnchorPoint = Vector2.new(0.5, 0.5)
	card.root.Position = UDim2.fromScale(0.5, 0.5)
	-- Glow the actual card edge, never the transparent seat-sized holder.
	BattleTheme.glow(card.root, seat.accent, 0.28)

	local ref = {
		side = side, slot = entry.slot, cardId = entry.cardId, entry = entry,
		holder = holder, card = card,
	}
	ref.health = attachHealth(holder, card, seat.accent, Z.Card + 4)
	fieldRefs[side] = ref
	setHealth(ref, entry.currentHP, entry.maxHP, false)
	-- Effect icons for whatever is already on the card as it takes its seat.
	StatusVfx.sync(card.root, entry.statuses)

	if animate then
		local scale = holder:FindFirstChildOfClass("UIScale")
		if scale then tween(scale, E.Snap, { Scale = 1 }) end
	end

	-- clicking a card on the field inspects it too
	local hit = new("TextButton", {
		Parent = holder, BackgroundTransparency = 1, Text = "",
		Size = UDim2.fromScale(1, 1), ZIndex = Z.Card + 20, AutoButtonColor = false,
	}) :: TextButton
	hit.Activated:Connect(function()
		clickSound()
		openInspect(ref.entry)
	end)

	return ref
end

-- ── Battle log ──────────────────────────────────────────────────────
-- The rails are a LOG, not a live status list.
--
-- They used to mirror the snapshot's card.effects, which meant an effect
-- vanished from the rail the moment it expired - so a heal or a proc that
-- resolved inside one round was on screen for well under a second and the
-- player never saw what their card actually did. Every entry now stays for the
-- whole battle. Entries that were a lasting status dim when the status falls
-- off, rather than disappearing.
--
-- Nothing here is invented: every entry is appended from a real BattleEvent the
-- server fired, and every number quoted is the number the server sent.
local LOG_STYLE = {
	ability = { glyph = "\u{25C6}", color = C.Gold },
	heal    = { glyph = "+",        color = C.Good },
	buff    = { glyph = "\u{25B2}", color = C.Good },
	debuff  = { glyph = "\u{25BC}", color = C.Bad },
	damage  = { glyph = "\u{2739}", color = C.Bad },
	shield  = { glyph = "\u{25C8}", color = C.Player },
	blocked = { glyph = "\u{2716}", color = C.TextDim },
	death   = { glyph = "\u{2716}", color = C.Bad },
	revive  = { glyph = "\u{271A}", color = C.Good },
	place   = { glyph = "\u{25CF}", color = C.Gold },
}

local battleLog = { player = {}, enemy = {} }
local logRound = 1
-- The most recent Passive on each side. Damage/Heal/Status that the server
-- fires immediately after a passive carry no ability name of their own, so they
-- are folded into that passive's entry as its RESULT instead of becoming a
-- second, unexplained marker.
local pendingPassive = { player = nil :: any, enemy = nil :: any }

local tooltip, tooltipTitle, tooltipBody

local function hideTooltip()
	if tooltip then tooltip.Visible = false end
end

-- The text a marker will show. Kept separate from the hover handler so it can
-- also be published onto the marker itself (below), which makes the log
-- readable without a mouse - useful for testing and for anything that wants to
-- read the battle back.
local function composeLogBody(entry): string
	local lines = { ("Round %d"):format(entry.round or 1) }
	if entry.source then table.insert(lines, "From: " .. entry.source) end
	for _, line in ipairs(entry.detail) do table.insert(lines, line) end
	if entry.endedRound then
		table.insert(lines, ("Wore off in round %d"):format(entry.endedRound))
	end
	return table.concat(lines, "\n")
end

local function publishLogText(entry)
	if not entry or not entry.marker or not entry.marker.Parent then return end
	entry.marker:SetAttribute("LogText", entry.title .. "\n" .. composeLogBody(entry))

	-- Keep the useful part visible in the rail itself. The most recent result
	-- replaces the long ability description as soon as the server resolves it.
	local summary = entry.resultLine or "Triggered"
	if not entry.resultLine and entry.kind ~= "ability" then
		for i = 1, #(entry.detail or {}) do
			local line = entry.detail[i]
			if line and line ~= "" then summary = line; break end
		end
	end
	if entry.endedRound then
		summary = ("Ended R%d  •  %s"):format(entry.endedRound, summary)
	end
	if entry.titleLabel then entry.titleLabel.Text = string.upper(entry.title) end
	if entry.detailLabel then entry.detailLabel.Text = summary end
	if entry.roundLabel then
		entry.roundLabel.Text = (entry.activationCount or 1) > 1
			and ("×" .. tostring(entry.activationCount))
			or ("R" .. tostring(entry.round or 1))
	end
end

local function showLogTooltip(entry, anchor: GuiObject, isPlayer: boolean)
	if not tooltip then return end

	tooltipTitle.Text = string.upper(entry.title)
	tooltipBody.Text = composeLogBody(entry)
	tooltip.Visible = true

	-- park it beside the marker, on the inboard side so it never leaves the screen
	local a = anchor.AbsolutePosition
	local root = R.root.AbsolutePosition
	tooltip.AnchorPoint = Vector2.new(isPlayer and 0 or 1, 0.5)
	tooltip.Position = UDim2.fromOffset(
		(isPlayer and (a.X + anchor.AbsoluteSize.X + 10) or (a.X - 10)) - root.X,
		a.Y + anchor.AbsoluteSize.Y / 2 - root.Y)
end

local function railFor(side: string)
	-- ONE battle log for both sides; the round tag's colour says whose it was.
	return R.playerEffects
end

-- Draws one marker for a log entry. The log is append-only, so this only ever
-- ADDS: redrawing the whole rail on every event would also reset the scroll
-- position while the player is reading back through it.
local logSeq = 0
local function drawLogEntry(side: string, entry, index: number)
	local rail = railFor(side)
	if not rail then return end
	rail.empty.Visible = false
	logSeq += 1

	-- Plain text, no panel, no pill: a round tag in the side's colour (yours
	-- violet, theirs red), what happened, and its result underneath in the
	-- colour of the kind of thing it was. Newest at the top.
	local style = LOG_STYLE[entry.kind] or LOG_STYLE.ability
	local sideColor = side == "player" and C.Player or C.Enemy
	local marker = new("TextButton", {
		Name = "Log_" .. logSeq,
		Parent = rail.list,
		LayoutOrder = -logSeq,
		Size = UDim2.new(1, -6, 0, 36),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = Z.Chrome + 2,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 6) }),
	}) :: TextButton

	local roundLabel = BattleLayout.text(marker, {
		Name = "Round", Position = UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(30, 16),
		Text = "R" .. tostring(entry.round or 1), TextColor3 = sideColor, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z.Chrome + 3,
	})
	local titleLabel = BattleLayout.text(marker, {
		Name = "EffectName", Position = UDim2.fromOffset(34, 1),
		Size = UDim2.new(1, -36, 0, 17), Text = string.upper(entry.title),
		TextColor3 = C.Text, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z.Chrome + 3,
	})
	new("UIStroke", { Parent = titleLabel, Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.55 })
	local detailLabel = BattleLayout.text(marker, {
		Name = "EffectResult", Position = UDim2.fromOffset(34, 18),
		Size = UDim2.new(1, -36, 0, 15), Text = "Triggered", TextSize = 12,
		TextColor3 = style.color, TextTransparency = 0.1,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = Z.Chrome + 3,
	})

	entry.marker = marker
	entry.glyphLabel = nil
	entry.titleLabel = titleLabel
	entry.detailLabel = detailLabel
	entry.roundLabel = roundLabel

	marker.MouseEnter:Connect(function()
		tween(marker, E.Fade, { BackgroundTransparency = 0.82 })
		showLogTooltip(entry, marker, true)
	end)
	marker.MouseLeave:Connect(function()
		tween(marker, E.Fade, { BackgroundTransparency = 1 })
		hideTooltip()
	end)
	marker.Activated:Connect(function() showLogTooltip(entry, marker, true) end)
end

local function logAppend(side: string, kind: string, title: string, source: string?, detail)
	if not battleLog[side] then return nil end
	local entry = {
		side = side, kind = kind, title = title, source = source,
		detail = detail or {}, round = logRound,
	}
	table.insert(battleLog[side], entry)
	drawLogEntry(side, entry, #battleLog[side])
	publishLogText(entry)
	return entry
end

-- Folds a resolved number into the passive that caused it. Damage and Heal
-- events carry no ability name of their own, so without this the player would
-- get a second, unexplained marker instead of "Cola Overload - healed 15 HP".
local function attachToPassive(side: string, line: string): boolean
	local p = pendingPassive[side]
	if not p or not p.entry then return false end
	-- 2s, not 1s. The server paces a replay out over EVENT_DELAY per event, so a
	-- passive and the damage it caused can be most of a second apart.
	if os.clock() - p.at > 2.0 then return false end
	local stored = (p.entry.activationCount or 1) > 1
		and (("Round %d: %s"):format(logRound, line))
		or line
	table.insert(p.entry.detail, stored)
	p.entry.resultLine = line
	publishLogText(p.entry)
	return true
end

local function markStatusEnded(side: string, statusId: string)
	local list = battleLog[side]
	if not list then return end
	for i = #list, 1, -1 do
		local e = list[i]
		if e.statusId == statusId and not e.endedRound then
			e.endedRound = logRound
			publishLogText(e)
			-- Dimmed, never removed: the player asked to still see what happened
			-- after it stopped happening.
			if e.titleLabel then e.titleLabel.TextTransparency = 0.45 end
			if e.detailLabel then e.detailLabel.TextTransparency = 0.5 end
			return
		end
	end
end

local function clearLog()
	battleLog.player = {}
	battleLog.enemy = {}
	pendingPassive.player = nil
	pendingPassive.enemy = nil
	logRound = 1
	hideTooltip()
	for _, side in ipairs({ "player", "enemy" }) do
		local rail = railFor(side)
		if rail then
			for _, c in ipairs(rail.list:GetChildren()) do
				if c:IsA("GuiObject") then c:Destroy() end
			end
			rail.empty.Visible = true
		end
	end
end

-- ── Inspect ───────────────────────────────────────────────────────
local function closeInspect()
	if not inspectCard then return end
	local card = inspectCard
	inspectCard = nil
	local scale = R.inspectHolder:FindFirstChildOfClass("UIScale")
	if scale then tween(scale, E.Fade, { Scale = 0.82 }) end
	tween(R.inspectDim, E.Fade, { BackgroundTransparency = 1 })
	R.inspectClose.Visible = false
	task.delay(0.2, function()
		if inspectCard then return end   -- reopened during the fade
		if card.root then card.root:Destroy() end
		R.inspectDim.Visible = false
	end)
end

function openInspect(entry)
	if not entry or not R then return end
	if inspectCard then
		inspectCard.root:Destroy()
		inspectCard = nil
	end

	local w = BattleLayout.InspectWidth
	local card = buildCard(R.inspectHolder, w, Z.Modal + 4, entry)
	card.root.AnchorPoint = Vector2.new(0.5, 0.5)
	card.root.Position = UDim2.fromScale(0.5, 0.5)
	inspectCard = card

	-- Live HP is not part of a printed card face, so it is stated underneath
	-- where it cannot be mistaken for the card's base stat.
	if entry.currentHP and entry.maxHP then
		local live = BattleLayout.text(card.root, {
			Name = "LiveHP",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 10),
			Size = UDim2.fromOffset(w, 24),
			Text = ("HP %s / %s"):format(Format.short(entry.currentHP), Format.short(entry.maxHP)),
			TextColor3 = C.Good,
			TextScaled = true,
			ZIndex = Z.Modal + 8,
		})
		new("UITextSizeConstraint", { Parent = live, MaxTextSize = 20 })
	end

	R.inspectDim.Visible = true
	R.inspectDim.BackgroundTransparency = 1
	R.inspectClose.Visible = true
	local scale = R.inspectHolder:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.82
		tween(scale, E.Snap, { Scale = 1 })
	end
	-- The board behind is busy - two cards, a lit location, a fanned hand - and
	-- at 0.4 it read straight through the inspected card. 0.22 leaves the board
	-- legible as context without competing with the thing being inspected.
	tween(R.inspectDim, E.Fade, { BackgroundTransparency = 0.22 })
end

-- ── Leave ───────────────────────────────────────────────────────
local closeBattle

local function showConfirm(show: boolean)
	local scale = R.confirmPanel:FindFirstChildOfClass("UIScale")
	if show then
		R.confirmDim.Visible = true
		R.confirmDim.BackgroundTransparency = 1
		if scale then scale.Scale = 0.85; tween(scale, E.Snap, { Scale = 1 }) end
		tween(R.confirmDim, E.Fade, { BackgroundTransparency = 0.45 })
	else
		if scale then tween(scale, E.Fade, { Scale = 0.85 }) end
		tween(R.confirmDim, E.Fade, { BackgroundTransparency = 1 })
		task.delay(0.2, function() R.confirmDim.Visible = false end)
	end
end

-- ── Rendering a snapshot ───────────────────────────────────────────
local function applyLocation(loc)
	if not loc then return end
	R.locationName.Text = string.upper(loc.name or "LOCATION")
	R.locationDesc.Text = loc.description or ""

	-- The snapshot carries only name/description/borderTheme. Artwork and the
	-- palette live in LocationDefinitions, which is in ReplicatedStorage - so the
	-- client reads them directly and the server needs no change.
	local def = loc.id and LocationDefinitions.get(loc.id)
	if def then
		if def.Artwork then ArtLoader.set(R.locationArt, def.Artwork) end
		local colors = def.Colors
		if colors then
			local edge = R.location:FindFirstChild("Edge")
			if edge and edge:IsA("UIStroke") then
				edge.Color = colors.Highlight or C.Gold
			end
			R.locationName.TextColor3 = colors.Text or C.Text
		end
	end
end

-- Initiative is supplied by the server; the client only presents its order.
local function renderRoundLabel(round, firstTeam, reason)
	-- Just the round. Who goes first shows in the attack itself.
	R.round.Text = ("ROUND %d"):format(round or 1)
end

local function renderSnapshot(snap)
	if not snap then return end
	snapshot = snap

	R.root.Visible = snap.active ~= false
	renderRoundLabel(snap.round, snap.firstTeam, snap.initiativeReason)
	applyLocation(snap.location)

	R.enemy.name.Text = string.upper(snap.enemyName or "ENEMY")
	R.player.name.Text = string.upper(player.DisplayName or player.Name)

	-- Battle power, stated quietly beside each portrait
	local pp = sideBattlePower(snap.player)
	-- A redacted side reports its own total, because the client no longer holds
	-- the cards to add up. Falls back to the local sum for any snapshot that
	-- still arrives in full.
	local ep = (snap.enemy and snap.enemy.power) or sideBattlePower(snap.enemy)
	R.player.power.Text = Format.comma(pp) .. " BP"
	R.enemy.power.Text = Format.comma(ep) .. " BP"

	local combined = pp + ep
	local chance = combined > 0 and math.clamp(math.floor(pp / combined * 100 + 0.5), 0, 100) or 50
	R.victory.Text = "WIN CHANCE " .. chance .. "%"
	R.victory.TextColor3 = chance >= 60 and C.Good or (chance <= 40 and C.Enemy or C.Gold)

	-- Enemy portrait: their strongest card's artwork, per the brief.
	-- The strongest card is now named by the SERVER, since the hand it used to
	-- be picked from arrives redacted. No information is lost: the portrait has
	-- always shown their best card on purpose.
	local best = snap.enemy and snap.enemy.portrait or nil
	if not best then
		local bestPower = -1
		for _, entry in ipairs(snap.enemy and snap.enemy.hand or {}) do
			local p = entryBattlePower(entry)
			if p > bestPower then best, bestPower = entry, p end
		end
		if snap.enemy and snap.enemy.active then
			local p = entryBattlePower(snap.enemy.active)
			if p > bestPower then best, bestPower = snap.enemy.active, p end
		end
	end
	if best then
		local def = CardStats.definition(best.cardId)
		if def and def.art then ArtLoader.set(R.enemy.art, def.art) end
		-- Real rarity border, from the SAME systems the deck and leaderboard use:
		-- the variant's colour on the frame stroke, and Shine for the animated
		-- tiers. No hand-drawn imitation of a rarity frame.
		local variant = VariantConfig.get(best.variant or "Standard")
		if variant then
			R.enemy.portraitStroke.Color = variant.color
			R.enemy.portraitStroke.Thickness = variant.rank > 1 and 4 or 3
			pcall(function() Shine.apply(R.enemy.portrait, variant.id, 86) end)
		end
	end

	-- The rails are NOT redrawn from the snapshot any more. They are an
	-- append-only log of the events the server fired, and rebuilding them from
	-- the current statuses is exactly the behaviour that made effects vanish the
	-- moment they expired. renderSnapshot only keeps the round counter honest,
	-- since a snapshot can arrive without a RoundStart before it.
	logRound = snap.round or logRound

	-- Seats
	if snap.player and snap.player.active then
		setSeat("player", snap.player.active, fieldRefs.player == nil)
	else
		clearSeat("player")
	end
	if snap.enemy and snap.enemy.active then
		setSeat("enemy", snap.enemy.active, fieldRefs.enemy == nil)
	else
		clearSeat("enemy")
	end

	-- Hand. Rebuilt wholesale: the hand is small and a diff would be more code
	-- than it saves, but the DRAGGED card is left alone so a rebuild landing
	-- mid-gesture cannot yank it out of the player's hand.
	if not dragging then
		clearHand()
		for i, entry in ipairs(snap.player and snap.player.hand or {}) do
			addHandCard(entry, i)
		end
		layoutHand(false)
	end

	-- Their bench. Rebuilt wholesale like the player's: it is at most a handful
	-- of backs and a diff would cost more code than it saves.
	renderEnemyHand(snap.enemy and snap.enemy.hand or {})
end

function playSlot(slot: number)
	if busy then
		notice("wait for the round to finish")
		return
	end
	busy = true
	task.spawn(function()
		local ok, reason, snap = pcall(function()
			return BattleRemotes.Action:InvokeServer("PlayCard", { slot = slot })
		end)
		-- pcall wraps the invoke because a server-side error would otherwise throw
		-- on the client and leave `busy` stuck true, soft-locking the hand.
		busy = false
		if not ok then
			notice("could not play that card", C.Bad)
			return
		end
		local accepted, why, snapshotOut = reason, snap, nil
		if typeof(accepted) == "boolean" and not accepted then
			notice(tostring(why or "invalid move"), C.Bad)
		end
	end)
end

-- ── Animated events ───────────────────────────────────────────────
-- A side can contain several living cards. A queued card's damage/death
-- must never animate the active fighter just because they share that side.
local function refFor(side: string, slot: number?)
	local ref = fieldRefs[side]
	if ref and (slot == nil or ref.slot == slot) then return ref end
	return nil
end

-- The bench.
--
-- refFor only ever knew about the two cards on the FIELD, so every event aimed
-- at a card still waiting in hand fell straight through it and did nothing. The
-- bar caught up only when the end-of-replay snapshot rebuilt the whole tray -
-- which is why an ability that hits the entire line read as every card dying at
-- once instead of a chain running down it.
--
-- Returns one shape for both trays so a Damage, Heal or Death event does not
-- have to care whose bench it landed on.
-- Ability VFX travel between the two SEATS, and a card's seat is created from
-- the snapshot - which the server sends AFTER it has replayed the events. So a
-- passive that fires the instant a card is played (Final Blast's wind-up, for
-- one) arrives while the seat it belongs to does not exist yet, and the effect
-- was simply dropped. Wait a few frames for the seat rather than giving up on
-- the first try; if it never appears, nothing is drawn, as before.
local function playAbilityVfx(side: string, passiveId: string?, trigger: string?)
	if not passiveId then return end
	local other = side == "player" and "enemy" or "player"
	local function attempt(): boolean
		local mine = fieldRefs[side]
		if not (mine and mine.card) then return false end
		-- A wind-up plays on the caster alone, so an empty opposing seat must not
		-- block it. The recipe decides whether the target matters; handing it the
		-- caster twice makes a travelling beat fail its own distance check and
		-- fall through to the retry below, which is what we want.
		local foe = fieldRefs[other]
		local target = (foe and foe.card and foe.card.root) or mine.card.root
		return AbilityVfx.play(passiveId, mine.card.root, target,
			{ firesOn = "passive", trigger = trigger })
	end
	if attempt() then return end
	task.spawn(function()
		local deadline = os.clock() + 1.2
		while os.clock() < deadline do
			task.wait(0.06)
			if attempt() then return end
		end
	end)
end

local function benchRefFor(side: string, slot: number?)
	if slot == nil then return nil end
	if side == "player" then
		for _, ref in ipairs(handRefs) do
			if ref.slot == slot then
				return {
					holder = ref.holder, root = ref.card.root, setHp = ref.setHp,
					key = "player:" .. tostring(slot),
					maxHP = ref.entry and ref.entry.maxHP,
					list = handRefs, relayout = layoutHand,
				}
			end
		end
		return nil
	end
	for _, ref in ipairs(enemyRefs) do
		if ref.slot == slot then
			return {
				holder = ref.holder, root = ref.back, setHp = ref.setHp,
				key = "enemy:" .. tostring(slot),
				maxHP = ref.maxHP,
				list = enemyRefs, relayout = layoutEnemyHand,
			}
		end
	end
	return nil
end

local function updateEventVitals(event)
	local side = event.side or "enemy"
	local function update(entry)
		if not entry or (event.slot ~= nil and entry.slot ~= event.slot) then return end
		if event.maxHP ~= nil then entry.maxHP = math.max(1, event.maxHP) end
		if event.hp ~= nil then entry.currentHP = math.clamp(event.hp, 0, entry.maxHP or math.max(1, event.hp)) end
		if event.dmg ~= nil then entry.dmg = event.dmg end
	end
	local state = snapshot and snapshot[side]
	if state then
		update(state.active)
		-- Slotless legacy events belong only to the active fighter.
		if event.slot ~= nil then for _, entry in ipairs(state.hand or {}) do update(entry) end end
	end
	local ref = refFor(side, event.slot)
	if ref then update(ref.entry) end
	if side == "player" and event.slot ~= nil then
		for _, hand in ipairs(handRefs) do update(hand.entry) end
	end
	return ref
end

-- A card whose passive REPLACES the basic attack never swings, so it must not
-- play the swing animation. Run & Gun is the case that forced this: the volley
-- arrives as one Attack event followed by 5-12 Hit events, and the client was
-- lunging on every one of them - the card bounced up and down a dozen times for
-- what is meant to be one burst of fire from a standing card.
local function attackPatternOf(side: string, slot: number?)
	local ref = refFor(side, slot)
	if not ref or not ref.cardId then return nil, nil end
	local def = CardStats.definition(ref.cardId)
	local passiveId = def and def.passive
	if not passiveId then return nil, nil end
	local passive = PassiveDefinitions.get(passiveId)
	return passiveId, passive and passive.attackPattern or nil
end

local function lunge(side: string, slot: number?)
	local ref = refFor(side, slot)
	if not ref or ref.defeated then return end
	-- Both a normal Attack and a redirected Attack can arrive for one swing.
	-- A stable anchor and token prevent stacked lunges from drifting the card.
	ref.lungeToken = (ref.lungeToken or 0) + 1
	local token = ref.lungeToken
	local home = UDim2.fromScale(0.5, 0.5)
	-- The board is horizontal: you strike to the RIGHT, the enemy to the LEFT.
	local toward = side == "player" and 70 or -70
	tween(ref.holder, E.Lunge, { Position = home + UDim2.fromOffset(toward, 0) })
	task.delay(0.14, function()
		if ref.holder.Parent and ref.lungeToken == token and not ref.defeated then
			tween(ref.holder, E.Recover, { Position = home })
		end
	end)
end

local function flashLocation()
	local stroke = R.locationFlash:FindFirstChild("FlashStroke")
	R.locationFlash.TextTransparency = 0
	if stroke and stroke:IsA("UIStroke") then stroke.Transparency = 0.2 end
	BattleTheme.setGlow(R.location, 1)

	local fade = TweenInfo.new(0.9, Enum.EasingStyle.Quad)
	tween(R.locationFlash, fade, { TextTransparency = 1 })
	-- The stroke has to be faded SEPARATELY; it does not inherit the label's
	-- TextTransparency and would otherwise sit there as a permanent outline.
	if stroke and stroke:IsA("UIStroke") then
		tween(stroke, fade, { Transparency = 1 })
	end
	task.delay(0.9, function() BattleTheme.setGlow(R.location, 0.35) end)
end

local function handleEvent(event)
	if not R or not event then return end
	local t = event.type

	if t == "RoundStart" then
		busy = true
		logRound = event.round or (logRound + 1)
		renderRoundLabel(event.round, event.firstTeam, event.initiativeReason)
		R.round.TextTransparency = 1
		local s = R.round:FindFirstChildOfClass("UIScale") or new("UIScale", { Parent = R.round })
		s.Scale = 1.4
		tween(s, E.Snap, { Scale = 1 })
		tween(R.round, E.Fade, { TextTransparency = 0 })

	elseif t == "TurnOrder" then
		renderRoundLabel(event.round, event.firstTeam, event.reason)
		if snapshot then
			snapshot.firstTeam = event.firstTeam
			snapshot.initiativeReason = event.reason
		end

	elseif t == "LocationActivate" then
		flashLocation()
		-- One battle log for both sides now, so the location is logged once.
		logAppend("player", "ability", event.locationName or "Location",
			"Location", { event.description or "" })

	elseif t == "EnemyPlay" then
		if event.card then setSeat("enemy", event.card, true) end

	elseif t == "Attack" then
		local side = event.side or "player"
		local passiveId, pattern = attackPatternOf(side, event.slot)
		local replaced = pattern ~= nil and pattern.replacesBasic == true
		if not replaced and (event.hitCount or 1) == 1 then
			lunge(side, event.slot)
		end
		-- An attackPattern passive fires no Passive event at all, so its VFX has
		-- to hang off the Attack event instead. hitCount is the volley the server
		-- actually rolled, so the tracers match the damage.
		if replaced then
			local me = fieldRefs[side]
			local foe = fieldRefs[side == "player" and "enemy" or "player"]
			if me and me.card and foe and foe.card then
				AbilityVfx.play(passiveId, me.card.root, foe.card.root,
					{ firesOn = "attack", shots = event.hitCount })
			end
		end

	elseif t == "Hit" then
		local side = event.side or "player"
		local _, pattern = attackPatternOf(side, event.slot)
		if not (pattern and pattern.replacesBasic) then
			lunge(side, event.slot)
		end

	elseif t == "Damage" then
		-- The victim is event.side; sourceSide/sourceName identify who dealt it.
		local side = event.side or "enemy"
		local ref = refFor(side, event.slot)
		local amount = event.amount or 0
		updateEventVitals(event)
		if ref then
			-- Shake the artwork, not the holder being moved by the attack lunge.
			BattleTheme.shake(ref.card.root, 7, 0.24)
			BattleTheme.floatNumber(ref.holder, "-" .. Format.short(amount), C.Bad, Z.Card)
			-- The server sends `hp` and `maxHP`. This read `event.currentHP`, which
			-- does not exist on a Damage event, so the health bar never moved from
			-- a hit - it only caught up on the next full snapshot.
			if event.hp then
				setHealth(ref, event.hp, event.maxHP or (ref.entry and ref.entry.maxHP) or 1, true)
			end
		else
			-- Not the card on the field, so it is one on the bench. It gets the same
			-- three beats the field card gets: a flinch, the number floating off it,
			-- and the bar running down - at the moment the hit lands rather than at
			-- the end of the replay.
			local bench = benchRefFor(side, event.slot)
			if bench then
				BattleTheme.shake(bench.root, 5, 0.2)
				if amount > 0 then
					BattleTheme.floatNumber(bench.holder, "-" .. Format.short(amount), C.Bad, Z.Hand + 70)
				end
				if event.hp and bench.setHp then
					bench.setHp(event.hp, event.maxHP or bench.maxHP, bench.key)
				end
			end
		end

		-- Basic swings are the battle itself, not an "effect" - logging every one
		-- would bury the abilities the player actually wants to read back.
		local tag = event.tag
		local left = event.hp
			and ("%s left on %s"):format(Format.comma(event.hp), event.targetName or "the card")
			or nil

		if tag == "passive" then
			-- Only ability damage belongs to the passive that fired just before it.
			-- A crit is a basic attack that rolled well, and folding it into whatever
			-- passive happened to fire first credited the wrong card entirely.
			local dealt = ("Dealt %s damage to %s"):format(
				Format.comma(amount), event.targetName or "the enemy")
			if not attachToPassive(event.sourceSide or side, dealt) then
				logAppend(event.sourceSide or side, "damage", "Ability damage",
					event.sourceName, { dealt, left })
			end

		elseif tag == "dot" or tag == "crit" or tag == "location" then
			-- These land on the VICTIM's rail: it is their card that is bleeding,
			-- being critted or standing in the wrong place.
			local title = tag == "dot" and (event.status or "Damage over time")
				or tag == "crit" and "Critical hit"
				or "Location damage"
			logAppend(side, "damage", title, event.sourceName, {
				("Took %s damage"):format(Format.comma(amount)),
				left,
			})

			-- Re-flash the aura on the tick, not just when the status landed.
			-- A burn that only sparked once reads as a one-off hit.
			if tag == "dot" and event.status then
				local burning = fieldRefs[side]
				if burning and burning.card then
					StatusVfx.tick(burning.card.root, event.status)
				end
			end
		end

	elseif t == "Heal" then
		local side = event.side or "player"
		local ref = refFor(side, event.slot)
		local amount = event.amount or 0
		updateEventVitals(event)
		if ref then
			if amount > 0 then
				BattleTheme.floatNumber(ref.holder, "+" .. Format.short(amount), C.Good, Z.Card)
			end
			if event.hp then
				setHealth(ref, event.hp, event.maxHP or (ref.entry and ref.entry.maxHP) or 1, true)
			end
		else
			local bench = benchRefFor(side, event.slot)
			if bench then
				if amount > 0 then
					BattleTheme.floatNumber(bench.holder, "+" .. Format.short(amount), C.Good, Z.Hand + 70)
				end
				if event.hp and bench.setHp then
					bench.setHp(event.hp, event.maxHP or bench.maxHP, bench.key)
				end
			end
		end
		-- The concrete number, which is the whole point: the card says "heals 50%",
		-- the log says how many HP that actually was.
		--
		-- A zero heal is not worth a line - several passives fire every round and
		-- heal nothing, and "Healed 0 HP" under each one is just noise.
		if amount > 0 then
			local what = ("Healed %s HP"):format(Format.comma(amount))
			if event.hp and event.maxHP and event.hp >= 0 and event.hp <= event.maxHP then
				what = what .. (" (now %s / %s)"):format(
					Format.comma(event.hp), Format.comma(event.maxHP))
			end
			if not attachToPassive(side, what) then
				logAppend(side, "heal", "Heal", event.cardName, { what })
			end
		else
			local what = event.hp and event.maxHP and event.hp >= event.maxHP
				and "No healing — already at full HP"
				or "No HP restored"
			if not attachToPassive(side, what) then
				logAppend(side, "heal", "Heal", event.cardName, { what })
			end
		end

	elseif t == "Shield" then
		local side = event.side or "player"
		local what = ("Absorbed %s damage"):format(Format.comma(event.amount or 0))
		if not attachToPassive(side, what) then
			logAppend(side, "shield", "Shield", nil, { what })
		end

	elseif t == "Stat" then
		-- BattleRuntime emits this immediately when DMG changes from a status,
		-- permanent modifier, or expiry. Keep the authoritative number on the card
		-- face and give it one restrained green/red pop.
		local side = event.side or "player"
		local ref = refFor(side, event.slot)
		if ref and (event.slot == nil or ref.slot == event.slot) then
			local updated = table.clone(ref.entry)
			if event.dmg ~= nil then updated.dmg = event.dmg end
			if event.hp ~= nil then updated.currentHP = event.hp end
			if event.maxHP ~= nil then updated.maxHP = event.maxHP end
			updateFieldCard(ref, updated, true)
		end
		updateEventVitals(event)

	elseif t == "Status" then
		local side = event.side or "player"
		local eff = event.effect or {}
		local detail = {}
		if eff.description and eff.description ~= "" then
			table.insert(detail, eff.description)
		end
		if (eff.stacks or 1) > 1 then
			table.insert(detail, ("%d stacks"):format(eff.stacks))
		end
		if (eff.duration or 0) > 0 then
			table.insert(detail, ("Lasts %d round%s"):format(
				eff.duration, eff.duration == 1 and "" or "s"))
		else
			table.insert(detail, "Lasts the whole battle")
		end
		local label = event.statusName or event.status or "Status"
		local entry = logAppend(side,
			eff.isDebuff and "debuff" or "buff",
			label,
			eff.sourceAbility and ("%s (%s)"):format(eff.sourceCard or "?", eff.sourceAbility)
				or eff.sourceCard,
			detail)
		if entry then entry.statusId = event.status end

		-- The visual half of the same event. The log says what happened; this
		-- says it on the card, which is where the player is actually looking
		-- while a round resolves.
		local hit = fieldRefs[side]
		if hit and hit.card then
			StatusVfx.apply(hit.card.root, event.status, eff.stacks)
		end

		-- A status lands on the card that RECEIVES it, but the ability that applied
		-- it usually belongs to the other side. Without this the applier's entry
		-- reads as though the ability fired and did nothing at all.
		if eff.sourceSide then
			attachToPassive(eff.sourceSide, ("Applied %s to %s"):format(
				label, eff.sourceSide == side and "itself" or "the opposing card"))
		end

	elseif t == "StatusEnd" then
		local side = event.side or "player"
		markStatusEnded(side, event.status)
		local gone = fieldRefs[side]
		if gone and gone.card then
			StatusVfx.clear(gone.card.root, event.status)
		end

	elseif t == "Cancel" then
		local side = event.side or "player"
		local what = event.dodged and "Dodged the incoming attack" or "Blocked the incoming attack"
		if not attachToPassive(side, what) then
			logAppend(side, "blocked",
				event.dodged and "Dodged" or "Attack blocked",
				event.cardName, { what })
		end

	elseif t == "Skip" then
		logAppend(event.side or "player", "blocked", "Turn skipped",
			event.cardName, { "The card could not act this round" })

	elseif t == "Revive" then
		local side = event.side or "player"
		local saved = event.slot and defeatedCards[side][event.slot]
		if saved then
			local entry = table.clone(saved.entry)
			entry.currentHP = event.hp or 0
			entry.maxHP = event.maxHP or entry.maxHP
			entry.state = saved.active and "active" or "hand"
			local state = snapshot and snapshot[side]
			if state then
				if saved.active then state.active = entry else table.insert(state.hand, entry) end
			end
			if saved.active then
				-- Rebuild a genuinely revived card, invalidating any old death tween.
				clearSeat(side)
				setSeat(side, entry, true)
			elseif side == "player" then
				addHandCard(entry, #handRefs + 1)
				layoutHand(true)
			end
			defeatedCards[side][event.slot] = nil
		end
		updateEventVitals(event)
		logAppend(event.side or "player", "revive", "Revived", event.cardName, {
			("Came back with %s HP"):format(Format.comma(event.hp or 0)),
		})

	elseif t == "Passive" then
		local side = event.side or "player"
		local ref = refFor(side, event.slot)
		if ref then
			BattleTheme.setGlow(ref.card.root, 0.75)
			task.delay(0.5, function() BattleTheme.setGlow(ref.card.root, 0.28) end)
		end

		-- Signature abilities that fire something across the board. The recipe
		-- is keyed on the passive id, so a card without one costs nothing here
		-- and adding another is a table entry rather than a branch.
		playAbilityVfx(side, event.passive, event.trigger)
		-- The gold "<ability>!" flash that used to fire here is gone. It appeared
		-- on every single attack, it was ambiguous about whether the ability had
		-- actually done anything, and it vanished before it could be read. The
		-- ability is recorded in the rail instead, where it stays.
		local detail = {}
		if event.passiveDescription and event.passiveDescription ~= "" then
			table.insert(detail, event.passiveDescription)
		end
		-- sourceCardName differs from cardName only when the passive came from the
		-- equipped SUPPORT card, which is worth saying out loud.
		local source = event.cardName
		if event.sourceCardName and event.sourceCardName ~= event.cardName then
			source = ("%s (via %s)"):format(event.cardName or "?", event.sourceCardName)
		end
		-- Repeated activations share one readable row. The badge becomes ×2, ×3,
		-- and the tooltip keeps the round-by-round results instead of filling the
		-- rail with identical circles/rows.
		local entry
		for i = #battleLog[side], 1, -1 do
			local prior = battleLog[side][i]
			if prior.passiveId == event.passive and prior.sourceSlot == event.slot then
				entry = prior
				break
			end
		end
		if entry then
			entry.activationCount = (entry.activationCount or 1) + 1
			entry.resultLine = ("Triggered %d times"):format(entry.activationCount)
			table.insert(entry.detail, ("Round %d: triggered"):format(logRound))
			publishLogText(entry)
		else
			entry = logAppend(side, "ability",
				event.passiveName or event.passive or "Ability", source, detail)
			if entry then
				entry.passiveId = event.passive
				entry.sourceSlot = event.slot
				entry.activationCount = 1
				publishLogText(entry)
			end
		end
		-- Whatever the server fires next - the damage, heal, status, or modifier -
		-- gets folded into this ability row as its latest visible result.
		pendingPassive[side] = entry and { entry = entry, at = os.clock() } or nil

	elseif t == "Modifier" then
		local side = event.side or "player"
		local value = event.value or 0
		local valueText = event.valueType == "Chance"
			and ("+%d%% chance"):format(math.floor(value * 100 + 0.5))
			or ("+%s DMG"):format(Format.comma(value))
		local what = (event.displayName or "Modifier") .. ": " .. valueText
		if not attachToPassive(side, what) then
			logAppend(side, "buff", event.displayName or "Modifier", event.sourceCardName, { what })
		end

	elseif t == "Summon" then
		local side = event.side or "player"
		local what = ("Summoned %s with %s DMG and %s HP"):format(
			event.cardName or "a clone",
			Format.comma(event.card and event.card.dmg or 0),
			Format.comma(event.card and event.card.maxHP or 0))
		if not attachToPassive(side, what) then
			logAppend(side, "buff", "Summoned", event.cardName, { what })
		end

	elseif t == "Death" then
		local side = event.side or "enemy"
		local ref = refFor(side, event.slot)
		local state = snapshot and snapshot[side]
		local active = ref ~= nil
		local entry = ref and ref.entry
		if state then
			if state.active and (event.slot == nil or state.active.slot == event.slot) then
				entry = entry or state.active
				active = true
				state.active = nil
			elseif event.slot ~= nil then
				for i, waiting in ipairs(state.hand or {}) do
					if waiting.slot == event.slot then entry = waiting; table.remove(state.hand, i); break end
				end
			end
		end
		if entry then defeatedCards[side][entry.slot] = { entry = table.clone(entry), active = active } end
		if not active and event.slot ~= nil then
			-- A bench card now gets the same short exit the field card gets, on BOTH
			-- sides. Destroying it on the frame the Death event landed is what made a
			-- run of kills read as the whole line blinking out together; the enemy's
			-- bench was not handled here at all and only vanished on the next snapshot.
			local bench = benchRefFor(side, event.slot)
			if bench then
				local holder, list, relayout = bench.holder, bench.list, bench.relayout
				if bench.setHp then bench.setHp(0, bench.maxHP, bench.key) end
				BattleTheme.shake(bench.root, 7, 0.22)
				local scale = holder:FindFirstChildOfClass("UIScale")
					or new("UIScale", { Parent = holder, Scale = 1 })
				tween(scale, E.Return, { Scale = 0.12 })
				tween(bench.root, E.Return, { BackgroundTransparency = 1 })
				task.delay(0.42, function()
					if not holder.Parent then return end
					for i, r in ipairs(list) do
						if r.holder == holder then table.remove(list, i) break end
					end
					holder:Destroy()
					relayout(true)
				end)
			end
		end
		if ref then
			ref.defeated = true
			ref.lungeToken = (ref.lungeToken or 0) + 1
			local scale = ref.holder:FindFirstChildOfClass("UIScale")
			if scale then tween(scale, E.Return, { Scale = 0.1 }) end
			tween(ref.card.root, E.Return, { BackgroundTransparency = 1 })
			local captured = ref
			task.delay(0.45, function()
				if fieldRefs[captured.side] == captured and captured.defeated then
					clearSeat(captured.side)
				end
			end)
		end

	elseif t == "BattleEnd" then
		if ending then return end
		ending = true
		busy = false

		local won = event.won == true
		local isDraw = event.reason == "draw"
		local resultText = won and "VICTORY" or (isDraw and "DRAW" or "DEFEAT")
		local resultColor = won and C.Good or (isDraw and C.Gold or C.Bad)

		-- Replace the whole board with one concise result beat. The old flow hid
		-- the cards but left the arena background hanging for 2.6 seconds.
		setStageVisible(false)
		closeInspect()
		showConfirm(false)
		R.endOverlay.Visible = true
		R.endOverlay.GroupTransparency = 1
		R.endTitle.Text = resultText
		R.endTitle.TextColor3 = resultColor
		R.endTitle.Position = UDim2.fromScale(0.5, 0.43)
		R.endSubtitle.Text = won and "BATTLE COMPLETE"
			or (isDraw and "NO WINNER" or "REGROUP AND TRY AGAIN")
		for _, child in ipairs(R.endOverlay:GetChildren()) do
			if child.Name == "ResultRule" and child:IsA("Frame") then
				child.BackgroundColor3 = resultColor
			end
		end

		TweenService:Create(
			R.endOverlay,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ GroupTransparency = 0 }
		):Play()
		TweenService:Create(
			R.endTitle,
			TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(0.5, 0.46) }
		):Play()

		-- Hold just long enough to read, then dissolve the arena and restore the
		-- normal HUD. Rewards appear after the board is already gone.
		task.delay(0.46, function()
			if not ending or not R then return end
			local fade = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(R.endOverlay, fade, { GroupTransparency = 1 }):Play()
			TweenService:Create(R.root, fade, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(R.arena, fade, { ImageTransparency = 1 }):Play()
			TweenService:Create(R.arenaScrim, fade, { BackgroundTransparency = 1 }):Play()
		end)

		task.delay(0.70, function()
			if not ending then return end
			closeBattle()
			pcall(function() RewardPopup.Show(event) end)
		end)
	end

	-- Any event that carries a fresh stat refreshes the face it belongs to.
	if event.card and event.side then
		local ref = refFor(event.side, event.card.slot)
		if ref and ref.slot == event.card.slot then
			updateFieldCard(ref, event.card, true)
		end
	end
end

-- ── Open / close ───────────────────────────────────────────────────
-- ── Taking over the screen ──────────────────────────────────────────
-- A battle is a MODE, not a window. The roll buttons, menu rail and leaderboard
-- all stayed visible behind the first build and the result read as panels
-- stacked on gameplay. Their enabled state is remembered so nothing is left
-- switched off if a battle ends unexpectedly.
local hiddenGuis: { [ScreenGui]: boolean } = {}

-- Everything on the board except the backdrop and the notice line. Hidden as a
-- group when the battle is over so the reward presentation is not fighting a
-- board that is no longer being played.
function setStageVisible(on: boolean)
	if not R then return end
	-- luau: this assigns the forward-declared local above, not a global.
	for _, part in ipairs({
		R.field, R.hand, R.round, R.victory, R.leave,
		R.player.holder, R.enemy.holder,
		R.playerEffects.holder,
	}) do
		if part then part.Visible = on end
	end
	if R.enemyEffects then R.enemyEffects.holder.Visible = false end
end

local function suppressOtherGuis(hide: boolean)
	-- The leaderboard is not switched by the loop below: it answers to
	-- LeaderboardVisibility, shared by every screen that hides it.
	if hide then
		LeaderboardVisibility.hide("Battle")
	else
		LeaderboardVisibility.show("Battle")
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	if hide then
		table.clear(hiddenGuis)
		for _, g in ipairs(pg:GetChildren()) do
			-- The reward banner is NOT one of the guis this function owns. It used
			-- to be: a banner still up when the next battle opened was recorded
			-- here, switched off, and then switched back on by suppressOtherGuis
			-- (false) when that battle ended - by which time its own five-second
			-- hide timer had long since run, so nothing was left to take it down
			-- and the "BATTLE WON" header sat on screen for the rest of the
			-- session. RewardPopup manages its own visibility; leave it alone.
			if g:IsA("ScreenGui") and g ~= gui and g.Enabled
				and g.Name ~= "BattleRewards" and g.Name ~= "BattlePowerLeaderboard" then
				hiddenGuis[g] = true
				g.Enabled = false
			end
		end
	else
		for g in pairs(hiddenGuis) do
			if g and g.Parent then g.Enabled = true end
		end
		table.clear(hiddenGuis)
	end
end

function closeBattle()
	if not R then return end
	ending = false
	if R.endOverlay then
		R.endOverlay.Visible = false
		R.endOverlay.GroupTransparency = 1
	end
	if R.entryCurtain then
		R.entryCurtain.Visible = false
		R.entryCurtain.BackgroundTransparency = 1
	end
	R.root.BackgroundTransparency = 0.02
	R.arena.ImageTransparency = 0.90
	R.arenaScrim.BackgroundTransparency = 0.25
	clearHand()
	clearSeat("player")
	clearSeat("enemy")
	closeInspect()
	showConfirm(false)
	R.root.Visible = false
	suppressOtherGuis(false)
	snapshot = nil
	table.clear(defeatedCards.player)
	table.clear(defeatedCards.enemy)
	busy = false
	if testButton then testButton.Visible = RunService:IsStudio() end
end

local function openBattle(snap)
	ending = false
	table.clear(defeatedCards.player)
	table.clear(defeatedCards.enemy)
	-- A win whose banner is still counting down when the next fight starts: take
	-- it down now rather than letting it hang over the new board.
	pcall(function() RewardPopup.Hide() end)
	R.root.BackgroundTransparency = 0.02
	R.arena.ImageTransparency = 0.90
	R.arenaScrim.BackgroundTransparency = 0.25
	R.root.Visible = true
	if R.endOverlay then
		R.endOverlay.Visible = false
		R.endOverlay.GroupTransparency = 1
	end
	if R.entryCurtain then
		R.entryCurtain.Visible = true
		R.entryCurtain.BackgroundTransparency = 0
	end
	setStageVisible(true)
	setTrayExpanded(false)     -- every battle starts with the hand stacked
	-- Their bench starts stacked too, and the chevron starts pointing left.
	enemyTrayOpen = false
	-- Slots are reused between battles, so last fight's health would otherwise
	-- be the starting point for this fight's first bar.
	forgetOffFieldHp()
	if R.enemyToggleGlyph then R.enemyToggleGlyph.Rotation = 180 end
	-- A fresh battle starts with an empty log. Without this the previous fight's
	-- markers would still be sitting in the rails.
	clearLog()
	suppressOtherGuis(true)
	if testButton then testButton.Visible = false end
	renderSnapshot(snap)

	if R.entryCurtain then
		local curtain = R.entryCurtain
		local intro = TweenService:Create(
			curtain,
			TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		)
		intro:Play()
		intro.Completed:Once(function()
			if curtain and curtain.Parent then curtain.Visible = false end
		end)
	end
end

-- ── Lifecycle ─────────────────────────────────────────────────────
function BattleController:Init()
	gui = new("ScreenGui", {
		Name = "BattleScreen",
		Parent = player:WaitForChild("PlayerGui"),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	R = BattleLayout.build(gui)

	-- VIP 2x battle speed toggle, stacked above LEAVE. A non-VIP sees it too,
	-- labelled as a VIP perk, and clicking it opens the VIP purchase.
	do
		local speedButton = new("TextButton", {
			Name = "SpeedButton",
			Parent = R.root,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 30, 1, -94),
			Size = UDim2.fromOffset(168, 40),
			BackgroundColor3 = C.Panel,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = Z.Chrome,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, 10) }),
		}) :: TextButton
		local fill = new("UIGradient", { Parent = speedButton, Rotation = 90 })
		local rim = new("UIStroke", { Parent = speedButton, Thickness = 2, Transparency = 0.1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		local speedLabel = BattleLayout.text(speedButton, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.56),
			Text = "SPEED 1x",
			TextScaled = true,
			ZIndex = Z.Chrome + 4,
		})
		new("UITextSizeConstraint", { Parent = speedLabel, MaxTextSize = 18 })
		local speedScale = new("UIScale", { Parent = speedButton, Scale = 1 })

		local function currentSpeed(): number
			if GamePassConfig.owns(player, "VIP") and player:GetAttribute("BattleSpeed") == GamePassConfig.VipBattleSpeed then
				return GamePassConfig.VipBattleSpeed
			end
			return 1
		end
		local function paintSpeed()
			local vip = GamePassConfig.owns(player, "VIP")
			local speed = currentSpeed()
			BattleTheme.Speed = speed
			if not vip then
				speedLabel.Text = "2x SPEED \u{00B7} VIP"
				speedLabel.TextColor3 = C.TextDim
				fill.Color = ColorSequence.new(Color3.fromRGB(38, 30, 60), Color3.fromRGB(20, 16, 34))
				rim.Color = C.PlayerDim
			elseif speed > 1 then
				speedLabel.Text = "SPEED 2x"
				speedLabel.TextColor3 = Color3.fromRGB(40, 22, 0)
				fill.Color = ColorSequence.new(Color3.fromRGB(255, 226, 120), Color3.fromRGB(240, 160, 30))
				rim.Color = Color3.fromRGB(255, 240, 180)
			else
				speedLabel.Text = "SPEED 1x"
				speedLabel.TextColor3 = C.Text
				fill.Color = ColorSequence.new(Color3.fromRGB(70, 50, 130), Color3.fromRGB(34, 24, 66))
				rim.Color = C.Player
			end
		end
		paintSpeed()
		player:GetAttributeChangedSignal(GamePassConfig.attribute("VIP")):Connect(paintSpeed)
		player:GetAttributeChangedSignal("BattleSpeed"):Connect(paintSpeed)

		speedButton.MouseEnter:Connect(function()
			hoverSound()
			tween(speedScale, E.Hover, { Scale = 1.05 })
		end)
		speedButton.MouseLeave:Connect(function() tween(speedScale, E.Hover, { Scale = 1 }) end)
		local speedBusy = false
		speedButton.Activated:Connect(function()
			clickSound()
			if not GamePassConfig.owns(player, "VIP") then
				pcall(function()
					MarketplaceService:PromptGamePassPurchase(player, GamePassConfig.Passes.VIP.id)
				end)
				return
			end
			if speedBusy then return end
			speedBusy = true
			local want = if currentSpeed() > 1 then 1 else GamePassConfig.VipBattleSpeed
			-- Shown at once; the server's attribute confirms (or reverts) it.
			BattleTheme.Speed = want
			speedLabel.Text = want > 1 and "SPEED 2x" or "SPEED 1x"
			task.spawn(function()
				pcall(function() BattleRemotes.Action:InvokeServer("SetSpeed", want) end)
				speedBusy = false
				paintSpeed()
			end)
		end)
	end

	-- Bursts cannot live inside a card (the root clips its children), so they
	-- get their own full-screen layer above the board and below any modal.
	StatusVfx.mount(gui)
	-- Signature ability effects travel BETWEEN the two seats, so they get a
	-- layer of their own above the board.
	AbilityVfx.mount(gui)

	-- Size the board to the window, and keep it sized. Without this the stack is
	-- authored for one window height and either overlaps itself in a short one or
	-- floats as a small island in a tall one.
	-- Measured from the ScreenGui, NOT from Camera.ViewportSize. CurrentCamera
	-- can be a camera that is not the one being rendered (it reports 1x1 during
	-- startup and whenever another camera is swapped in), and a single refit at
	-- that moment pins the whole board at its minimum scale for the rest of the
	-- session. AbsoluteSize is the space the GUI actually has.
	local lastFitHeight = 0
	local function refit()
		local h = gui.AbsoluteSize.Y
		if h < 240 then return end          -- not laid out yet
		if math.abs(h - lastFitHeight) < 2 then return end
		lastFitHeight = h
		BattleLayout.fit(R, h, gui.AbsoluteSize.X)
		-- The cards on screen were built at the old scale, so a resize has to lay
		-- them out again - but only when a battle is actually up, and never in the
		-- middle of a drag, which would tear the card out of the player's hand.
		if snapshot and R.root.Visible and not dragging then
			renderSnapshot(snapshot)
		end
	end

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()
	-- The GUI has no size on the frame it is created, so the first real fit
	-- happens here rather than relying on a change event that may never fire if
	-- the window is never resized.
	task.defer(refit)
	task.delay(0.5, refit)

	-- Effect tooltip, built once and reparked per hover.
	-- Taller and wider than the old status tooltip: it now has to hold the round,
	-- the source card, the ability text and the resolved numbers.
	tooltip = new("Frame", {
		Name = "EffectTooltip",
		Parent = R.root,
		Size = UDim2.fromOffset(300, 150),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Z.Modal - 4,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 8) }),
		new("UIStroke", { Color = C.Player, Thickness = 2, Transparency = 0.1 }),
	})
	tooltipTitle = BattleLayout.text(tooltip, {
		Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(276, 22),
		Text = "", TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true, ZIndex = Z.Modal - 2,
	})
	new("UITextSizeConstraint", { Parent = tooltipTitle, MaxTextSize = 16 })
	-- NOT TextScaled. The body is several short lines of different lengths, and
	-- TextScaled sizes to the longest one, which made a four-line tooltip
	-- unreadably small. A fixed size with wrapping keeps every line legible.
	tooltipBody = BattleLayout.text(tooltip, {
		Position = UDim2.fromOffset(12, 34), Size = UDim2.fromOffset(276, 108),
		Text = "", TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true, TextSize = 13, ZIndex = Z.Modal - 2,
	})

	-- The battle lane's energy flow. A single looping gradient scroll, so the
	-- column between the two cards reads as current running through the board
	-- rather than a static stripe. One tween, no per-frame work.
	if R.energyFlow then
		R.energyFlow.Offset = Vector2.new(0, -1)
		TweenService:Create(
			R.energyFlow,
			TweenInfo.new(3.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
			{ Offset = Vector2.new(0, 1) }
		):Play()
	end

	-- The tray: hovering the pile fans it open, leaving it closes it after a
	-- beat. Both sides are also driven by the individual cards' own hit buttons,
	-- because once the fan is open the pointer spends its time on cards rather
	-- than on this catcher.
	R.trayHit.MouseEnter:Connect(expandTray)
	R.trayHit.MouseLeave:Connect(scheduleCollapse)

	-- The enemy tray is CLICKED open and stays open. Hover would fan their hand
	-- out every time the pointer crossed the top of the board on its way
	-- somewhere else, and unlike the player's own hand there is nothing up
	-- there the pointer is actually travelling to.
	if R.enemyToggle then
		R.enemyToggle.Activated:Connect(function()
			clickSound()
			setEnemyTrayOpen(not enemyTrayOpen)
		end)
		R.enemyToggle.MouseEnter:Connect(function()
			hoverSound()
			tween(R.enemyToggle, E.Fade, { BackgroundTransparency = 0.1 })
		end)
		R.enemyToggle.MouseLeave:Connect(function()
			tween(R.enemyToggle, E.Fade, { BackgroundTransparency = 0.35 })
		end)
		R.enemyToggle.Visible = false
	end
	R.trayPad.MouseEnter:Connect(expandTray)

	-- Leave button polish: red glow and a small scale-up on hover.
	local leaveScale = new("UIScale", { Parent = R.leave, Scale = 1 })
	R.leave.MouseEnter:Connect(function()
		BattleTheme.setGlow(R.leave, 1.4)
		tween(leaveScale, E.Hover, { Scale = 1.05 })
	end)
	R.leave.MouseLeave:Connect(function()
		BattleTheme.setGlow(R.leave, 0.7)
		tween(leaveScale, E.Hover, { Scale = 1 })
	end)

	-- player portrait: real Roblox headshot
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
		end)
		if ok and url and R then R.player.art.Image = url end
	end)
	R.player.name.Text = string.upper(player.DisplayName or player.Name)

	-- leave flow
	R.leave.MouseEnter:Connect(hoverSound)
	R.leave.Activated:Connect(function()
		clickSound()
		showConfirm(true)
	end)
	R.confirmNo.Activated:Connect(function()
		clickSound()
		showConfirm(false)
	end)
	R.confirmYes.Activated:Connect(function()
		clickSound()
		showConfirm(false)
		pcall(function() BattleRemotes.Action:InvokeServer("Forfeit") end)
		closeBattle()
	end)
	R.confirmDim.Activated:Connect(function() showConfirm(false) end)

	-- inspect closes on the backdrop or the X
	R.inspectDim.Activated:Connect(closeInspect)
	R.inspectClose.Activated:Connect(function()
		clickSound()
		closeInspect()
	end)

	-- Studio-only entry point, same as before.
	testButton = new("TextButton", {
		Name = "TestBattleButton",
		Parent = gui,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -22, 1, -22),
		Size = UDim2.fromOffset(165, 48),
		BackgroundColor3 = Color3.fromRGB(60, 42, 105),
		BorderSizePixel = 0,
		Text = "TEST BATTLE",
		FontFace = Theme.font(),
		TextSize = 18,
		TextColor3 = C.Text,
		Visible = RunService:IsStudio(),
		ZIndex = 5,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 15) }),
		new("UIStroke", { Color = C.Player, Thickness = 2, Transparency = 0.15 }),
	}) :: TextButton

	testButton.MouseEnter:Connect(hoverSound)
	testButton.Activated:Connect(function()
		clickSound()
		testButton.Active = false
		testButton.Text = "LOADING..."
		local ok, result, reason, snap = pcall(function()
			return BattleRemotes.Action:InvokeServer("StartTest")
		end)
		testButton.Active = true
		testButton.Text = "TEST BATTLE"
		if ok and result and snap then
			openBattle(snap)
		else
			warn("[Battle] " .. tostring(reason or "could not start"))
			notice(tostring(reason or "could not start battle"), C.Bad)
		end
	end)

	installGestureHandlers()

	BattleRemotes.State.OnClientEvent:Connect(function(snap)
		if not snap then return end
		if snap.active == false then
			closeBattle()
			return
		end
		if not R.root.Visible then
			openBattle(snap)
		else
			renderSnapshot(snap)
		end
		busy = false
	end)

	BattleRemotes.Event.OnClientEvent:Connect(function(event)
		local ok, err = pcall(handleEvent, event)
		if not ok then
			-- One malformed beat must never stall the whole replay.
			warn("[Battle] event " .. tostring(event and event.type) .. ": " .. tostring(err))
		end
	end)
end

-- Is the battle board currently up? Read by the encounter panel so it cannot
-- open behind a fight in progress - the panel's prompt lives a couple of studs
-- from where the player is standing when a battle starts, so without this a
-- stray E during combat queues a panel that appears the moment the board closes.
function BattleController:IsBattleOpen(): boolean
	return R ~= nil and R.root ~= nil and R.root.Visible == true
end

-- Public entry point used by the physical Arlong Park NPC encounter panel.
-- Keeping the actual openBattle call here means only this controller owns battle
-- presentation state; the encounter controller merely asks it to start.
-- `difficulty` is an EncounterModes stage id. It defaults to Easy so any older
-- caller that passes only a card id still works unchanged; the server validates
-- the name either way and builds the real lineup itself.
function BattleController:StartEncounter(cardId: string, difficulty: string?): (boolean, string?)
	if busy or (R and R.root.Visible) then
		return false, "a battle is already active"
	end

	local ok, result, reason, snap = pcall(function()
		return BattleRemotes.Action:InvokeServer("StartEncounter", {
			cardId = cardId,
			difficulty = difficulty or "Easy",
		})
	end)
	if ok and result and snap then
		openBattle(snap)
		return true, nil
	end

	local message = tostring(reason or (ok and "could not start battle" or result))
	warn("[Battle] " .. message)
	return false, message
end

function BattleController:Start()
	print("[BattleController] Marvel-Snap battle UI online")
end

return BattleController





