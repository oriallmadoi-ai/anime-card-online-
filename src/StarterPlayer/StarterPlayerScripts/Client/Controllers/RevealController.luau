--!strict
-- Card reveal.
--
-- WHAT CHANGED AND WHY.
-- Every "light" in the old reveal was a plain Frame: twelve white rectangles
-- for rays, a rounded rectangle for the glow, a UIStroke circle for the ring.
-- A Frame has a hard edge and no falloff, so none of it read as light - it read
-- as cardboard. All of that is gone. Light is now drawn with authored sprites
-- (VfxAssets) that have real alpha ramps, tinted per rarity with ImageColor3.
--
-- FIVE TIERS, and the fifth is the point.
--   quick      commons - a puff and out, under half a second
--   normal     rare/epic - bloom, one shockwave, a few sparks
--   major      mythic/forbidden - shafts, rays, banner, shake
--   cinematic  divine / Secret variant - all of the above, longer wind-up
--   legend     THE PULL IS RARER THAN ANYTHING THE PLAYER OWNS
--
-- `legend` is the only tier with an anticipation phase and the only one that
-- takes over the whole screen: focus lines converge, the screen slams white,
-- and the card lands out of the flash. It also ignores quick-roll, because a
-- personal record is exactly the moment the player wants to be interrupted.
--
-- The whole thing is still fast. Even legend is ~3.2s end to end; ordinary
-- pulls are 0.45-1.6s. Nothing here should ever be the reason a player stops
-- rolling.
--
-- THE BORDER IS NOT DRAWN HERE. CardRenderer already draws the tier's own
-- border and runs its Shine, and that is the border the deck screen shows too.
-- The reveal's only obligation is to not clip it, which is why cardWrapper and
-- cardGroup both have ClipsDescendants = false. The CARD ROOT is a different
-- matter and stays clipped - see the note where it is set.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local RarityBands = require(ReplicatedStorage.Shared.Config.RarityBands)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local RarityFormat = require(ReplicatedStorage.Shared.Util.RarityFormat)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local Vfx = require(ReplicatedStorage.Shared.Config.VfxAssets)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local player = Players.LocalPlayer

local RevealController = {}
RevealController.Name = "RevealController"

-- Where the card sits vertically. Everything centred on the card reads this.
local CARD_Y = 0.45

-- A record has to clear this printed rarity before it earns the full-screen
-- treatment. Without a floor a brand new account would get the grand sequence
-- on its first half-dozen rolls, because every early pull beats the last one.
-- 2500 is the Rare band's minimum, so the escalation starts where the game
-- itself starts calling a pull notable.
local LEGEND_FLOOR = 2500

local TIERS = {
	quick = {
		hold = 0.45,
		bloom = 0.55,
	},

	normal = {
		hold = 1.05,
		dim = 0.22,
		bloom = 0.74,
		shocks = 1,
		sparks = 5,
		streak = true,
	},

	major = {
		build = 0.30,
		hold = 1.55,
		dim = 0.52,
		bloom = 0.86,
		shocks = 2,
		sparks = 12,
		motes = 10,
		rays = 0.70,
		shafts = 6,
		streak = true,
		banner = true,
		shake = 8,
	},

	cinematic = {
		build = 0.50,
		hold = 1.95,
		dim = 0.66,
		bloom = 0.95,
		shocks = 2,
		sparks = 18,
		motes = 16,
		rays = 0.66,
		shafts = 8,
		rune = true,
		streak = true,
		banner = true,
		shake = 12,
	},

	legend = {
		anticipate = 0.62,
		hold = 2.15,
		dim = 0.84,
		bloom = 1.00,
		shocks = 3,
		sparks = 26,
		motes = 22,
		rays = 0.60,
		shafts = 8,
		rune = true,
		streak = true,
		banner = true,
		shake = 20,
		speedLines = true,
		flash = true,
	},
}

local SHAFT_COUNT = 10
local SHOCK_COUNT = 3
local SPARK_POOL = 22
local MOTE_POOL = 26

local gui, dim, vignette, flash, stage
local speedLines, rays, rune, shaftHub, bloom, cardGlow, streak
local shocks, shafts = {}, {}
local particles
local sparkPool, motePool = {}, {}
local cardWrapper, cardGroup, cardFrame, cardScale, cardStroke, cardHandle
local banner, subBanner

local generation = 0
local activeTweens = {}
local spinTweens = {}
local shakeAmp, shakeConn = 0, nil

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------

local function new(class, props, children)
	local inst = Instance.new(class)

	for k, v in pairs(props) do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end

	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end

	if props.Parent then
		inst.Parent = props.Parent
	end

	return inst
end

local function tween(obj, time, goal, style, dir)
	local t = TweenService:Create(
		obj,
		TweenInfo.new(
			time,
			style or Enum.EasingStyle.Quad,
			dir or Enum.EasingDirection.Out
		),
		goal
	)

	table.insert(activeTweens, t)
	t:Play()

	return t
end

-- Square big enough to cover the screen whatever the aspect ratio. Fixed pixel
-- sizes cannot do this: 900x900 leaves bars on an ultrawide and swallows a
-- phone, and a scale-based size on a square sprite stretches it.
local function cover(mult: number): UDim2
	local v = gui.AbsoluteSize

	if v.X < 2 or v.Y < 2 then
		v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
			or Vector2.new(1280, 720)
	end

	local d = math.max(v.X, v.Y) * mult

	return UDim2.fromOffset(d, d)
end

-- `seconds` is one full turn; negative spins the other way. The rune and the
-- shafts deliberately turn in OPPOSITE directions - two layers rotating the
-- same way read as one flat texture, two against each other read as depth.
local function spin(obj, seconds: number)
	obj.Rotation = 0

	local t = TweenService:Create(
		obj,
		TweenInfo.new(math.abs(seconds), Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Rotation = seconds < 0 and -360 or 360 }
	)

	table.insert(spinTweens, t)
	t:Play()

	return t
end

-- One decaying screen shake, applied to `stage` so the dim and the white flash
-- stay nailed to the screen edges while everything inside them moves.
local function shake(amp: number)
	shakeAmp = math.max(shakeAmp, amp)

	if shakeConn then
		return
	end

	shakeConn = RunService.RenderStepped:Connect(function(dt)
		shakeAmp *= math.exp(-dt * 7.0)

		if shakeAmp < 0.4 then
			shakeAmp = 0
			stage.Position = UDim2.fromOffset(0, 0)
			shakeConn:Disconnect()
			shakeConn = nil
			return
		end

		stage.Position = UDim2.fromOffset(
			math.random(-100, 100) / 100 * shakeAmp,
			math.random(-100, 100) / 100 * shakeAmp
		)
	end)
end

----------------------------------------------------------------
-- PARTICLES
----------------------------------------------------------------

local function claim(pool)
	for _, rec in ipairs(pool) do
		if not rec.busy then
			rec.busy = true
			rec.token += 1
			return rec
		end
	end

	return nil
end

-- Sparks burst outward and shrink; motes drift up slowly and hold their size.
-- Both release themselves on a token so a reveal that gets cut short can never
-- hand a live particle back to the pool underneath the next one.
local function emitSpark(tint: Color3)
	local rec = claim(sparkPool)

	if not rec then
		return
	end

	local i = rec.inst
	local token = rec.token
	local x = math.random(-150, 150)
	local y = math.random(-170, 170)
	local size = math.random(30, 74)
	local life = 0.55 + math.random() * 0.45

	i.ImageColor3 = tint
	i.Size = UDim2.fromOffset(size, size)
	i.Position = UDim2.new(0.5, x, CARD_Y, y)
	i.Rotation = math.random(0, 360)
	i.ImageTransparency = 1
	i.Visible = true

	TweenService:Create(i, TweenInfo.new(life * 0.22), { ImageTransparency = 0.02 }):Play()

	TweenService:Create(
		i,
		TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.new(0.5, x * 1.55, CARD_Y, y - math.random(70, 170)),
			Rotation = i.Rotation + math.random(-110, 110),
			Size = UDim2.fromOffset(size * 0.25, size * 0.25),
		}
	):Play()

	task.delay(life * 0.30, function()
		if rec.token == token then
			TweenService:Create(i, TweenInfo.new(life * 0.70), { ImageTransparency = 1 }):Play()
		end
	end)

	task.delay(life + 0.08, function()
		if rec.token == token then
			i.Visible = false
			rec.busy = false
		end
	end)
end

local function emitMote(tint: Color3)
	local rec = claim(motePool)

	if not rec then
		return
	end

	local i = rec.inst
	local token = rec.token
	local x = math.random(-210, 210)
	local y = math.random(-40, 220)
	local size = math.random(8, 22)
	local life = 1.1 + math.random() * 0.9

	i.ImageColor3 = tint
	i.Size = UDim2.fromOffset(size, size)
	i.Position = UDim2.new(0.5, x, CARD_Y, y)
	i.ImageTransparency = 1
	i.Visible = true

	TweenService:Create(i, TweenInfo.new(life * 0.25), { ImageTransparency = 0.25 }):Play()

	TweenService:Create(
		i,
		TweenInfo.new(life, Enum.EasingStyle.Linear),
		{
			Position = UDim2.new(0.5, x + math.random(-40, 40), CARD_Y, y - math.random(120, 260)),
		}
	):Play()

	task.delay(life * 0.45, function()
		if rec.token == token then
			TweenService:Create(i, TweenInfo.new(life * 0.55), { ImageTransparency = 1 }):Play()
		end
	end)

	task.delay(life + 0.08, function()
		if rec.token == token then
			i.Visible = false
			rec.busy = false
		end
	end)
end

local function clearParticles()
	for _, pool in ipairs({ sparkPool, motePool }) do
		for _, rec in ipairs(pool) do
			rec.token += 1
			rec.busy = false
			rec.inst.Visible = false
		end
	end
end

----------------------------------------------------------------
-- BUILD
----------------------------------------------------------------

function RevealController:Build()
	gui = new("ScreenGui", {
		Name = "CardReveal",
		Parent = player:WaitForChild("PlayerGui"),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	dim = new("Frame", {
		Name = "Dim",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
	})

	-- Black-with-alpha sprite, not a second flat Frame: the corners of the
	-- screen go darker than the middle, which is what makes the card feel lit
	-- rather than pasted onto a grey sheet.
	vignette = new("ImageLabel", {
		Name = "Vignette",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = Vfx.Vignette,
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 2,
	})

	stage = new("Frame", {
		Name = "Stage",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = 10,
	})

	speedLines = new("ImageLabel", {
		Name = "SpeedLines",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, CARD_Y, 0),
		Size = UDim2.fromOffset(1200, 1200),
		BackgroundTransparency = 1,
		Image = Vfx.SpeedLines,
		ImageTransparency = 1,
		Visible = false,
		ZIndex = 1,
	})

	rays = new("ImageLabel", {
		Name = "Rays",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, CARD_Y, 0),
		Size = UDim2.fromOffset(1200, 1200),
		BackgroundTransparency = 1,
		Image = Vfx.Burst,
		ImageTransparency = 1,
		Visible = false,
		ZIndex = 2,
	})

	rune = new("ImageLabel", {
		Name = "Rune",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, CARD_Y, 0),
		Size = UDim2.fromOffset(700, 700),
		BackgroundTransparency = 1,
		Image = Vfx.Rune,
		ImageTransparency = 1,
		Visible = false,
		ZIndex = 3,
	})

	-- Zero-size hub so the shafts all pivot about the card's centre: each shaft
	-- is anchored at its own base and rotated, so rotating the hub sweeps the
	-- whole fan without moving any of them off the card.
	shaftHub = new("Frame", {
		Name = "ShaftHub",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, CARD_Y, 0),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = false,
		Visible = false,
		ZIndex = 4,
	})

	for i = 1, SHAFT_COUNT do
		shafts[i] = new("ImageLabel", {
			Name = "Shaft" .. i,
			Parent = shaftHub,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(150, 420),
			BackgroundTransparency = 1,
			Image = Vfx.Shaft,
			ImageTransparency = 1,
			Visible = false,
			ZIndex = 4,
		})
	end

	for i = 1, SHOCK_COUNT do
		shocks[i] = new("ImageLabel", {
			Name = "Shock" .. i,
			Parent = stage,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, CARD_Y, 0),
			Size = UDim2.fromOffset(200, 200),
			BackgroundTransparency = 1,
			Image = Vfx.Shock,
			ImageTransparency = 1,
			Visible = false,
			ZIndex = 5,
		})
	end

	bloom = new("ImageLabel", {
		Name = "Bloom",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, CARD_Y, 0),
		Size = UDim2.fromOffset(700, 700),
		BackgroundTransparency = 1,
		Image = Vfx.Glow,
		ImageTransparency = 1,
		ZIndex = 6,
	})

	cardGlow = new("ImageLabel", {
		Name = "CardGlow",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, CARD_Y, 0),
		Size = UDim2.fromOffset(470, 606),
		BackgroundTransparency = 1,
		Image = Vfx.CardGlow,
		ImageTransparency = 1,
		ZIndex = 7,
	})

	cardWrapper = new("Frame", {
		Name = "CardWrapper",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, CARD_Y, 0),
		Size = UDim2.fromOffset(360, 470),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ClipsDescendants = false,
		ZIndex = 10,
	})

	cardGroup = new("CanvasGroup", {
		Name = "CardGroup",
		Parent = cardWrapper,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		ClipsDescendants = false,
		ZIndex = 10,
	})

	local card = CardRenderer.create(cardGroup, 250, 10)

	card.root.AnchorPoint = Vector2.new(0.5, 0.5)
	card.root.Position = UDim2.fromScale(0.5, 0.5)
	card.root.Visible = true
	-- The card root MUST keep clipping. CardRenderer.create runs Sweep.attach,
	-- which sets ClipsDescendants = true precisely so the three highlight bars
	-- stay inside the face; between passes they park at x = 1.4, i.e. entirely
	-- off the right edge. Turning clipping off here left them visible as a pale
	-- slab hanging off the side of the revealed card.
	--
	-- It was never needed for the border either: a UIStroke renders OUTSIDE its
	-- element and ignores clipping, so the tier border is unaffected. Only
	-- cardWrapper and cardGroup have to stay unclipped, and they do.
	card.root.ClipsDescendants = true

	cardHandle = card
	cardFrame = card.root
	cardStroke = card.stroke

	cardScale = new("UIScale", { Parent = cardWrapper, Scale = 1 })

	streak = new("ImageLabel", {
		Name = "Streak",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, CARD_Y, 0),
		Size = UDim2.fromOffset(900, 220),
		BackgroundTransparency = 1,
		Image = Vfx.Streak,
		ImageTransparency = 1,
		ZIndex = 12,
	})

	particles = new("Frame", {
		Name = "Particles",
		Parent = stage,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = false,
		ZIndex = 14,
	})

	for i = 1, SPARK_POOL do
		sparkPool[i] = {
			busy = false,
			token = 0,
			inst = new("ImageLabel", {
				Name = "Spark" .. i,
				Parent = particles,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(48, 48),
				BackgroundTransparency = 1,
				Image = Vfx.Spark,
				ImageTransparency = 1,
				Visible = false,
				ZIndex = 14,
			}),
		}
	end

	for i = 1, MOTE_POOL do
		motePool[i] = {
			busy = false,
			token = 0,
			inst = new("ImageLabel", {
				Name = "Mote" .. i,
				Parent = particles,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 1,
				Image = Vfx.Mote,
				ImageTransparency = 1,
				Visible = false,
				ZIndex = 14,
			}),
		}
	end

	banner = new("TextLabel", {
		Name = "Banner",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.135, 0),
		Size = UDim2.fromOffset(820, 56),
		BackgroundTransparency = 1,
		FontFace = Theme.font(),
		Text = "",
		TextSize = 44,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 20,
	}, {
		new("UIStroke", {
			Color = Color3.new(0, 0, 0),
			Thickness = 3,
			Transparency = 0.25,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}),
		new("UIScale", { Scale = 1 }),
	})

	subBanner = new("TextLabel", {
		Name = "SubBanner",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.135, 40),
		Size = UDim2.fromOffset(820, 30),
		BackgroundTransparency = 1,
		FontFace = Theme.font(),
		Text = "",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(236, 238, 246),
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 20,
	}, {
		new("UIStroke", {
			Color = Color3.new(0, 0, 0),
			Thickness = 2,
			Transparency = 0.3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}),
	})

	-- Outside `stage` on purpose: the impact flash must not shake, or the
	-- screen edges tear away from the viewport for a few frames.
	flash = new("Frame", {
		Name = "Flash",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 30,
	})
end

----------------------------------------------------------------
-- RESET
----------------------------------------------------------------

function RevealController:Reset()
	for _, t in ipairs(activeTweens) do
		pcall(function()
			t:Cancel()
		end)
	end

	table.clear(activeTweens)

	for _, t in ipairs(spinTweens) do
		pcall(function()
			t:Cancel()
		end)
	end

	table.clear(spinTweens)

	if shakeConn then
		shakeConn:Disconnect()
		shakeConn = nil
	end

	shakeAmp = 0
	stage.Position = UDim2.fromOffset(0, 0)

	clearParticles()

	dim.BackgroundTransparency = 1
	vignette.ImageTransparency = 1
	flash.BackgroundTransparency = 1

	speedLines.Visible = false
	speedLines.ImageTransparency = 1
	speedLines.Rotation = 0

	rays.Visible = false
	rays.ImageTransparency = 1
	rays.Rotation = 0

	rune.Visible = false
	rune.ImageTransparency = 1
	rune.Rotation = 0

	shaftHub.Visible = false
	shaftHub.Rotation = 0

	for _, s in ipairs(shafts) do
		s.Visible = false
		s.ImageTransparency = 1
	end

	for _, s in ipairs(shocks) do
		s.Visible = false
		s.ImageTransparency = 1
	end

	bloom.ImageTransparency = 1
	cardGlow.ImageTransparency = 1
	streak.ImageTransparency = 1

	cardWrapper.Visible = false
	cardWrapper.Position = UDim2.new(0.5, 0, CARD_Y, 0)
	cardWrapper.Rotation = 0

	cardGroup.Visible = true
	cardGroup.GroupTransparency = 1

	cardFrame.Visible = true
	cardFrame.Rotation = 0
	cardFrame.Position = UDim2.fromScale(0.5, 0.5)
	cardScale.Scale = 1

	-- Shine parks this stroke itself on the tiers that carry a spec, so the
	-- reveal must not second-guess it the way it used to.
	cardStroke.Transparency = 0

	banner.Visible = false
	banner.TextTransparency = 1
	subBanner.Visible = false
	subBanner.TextTransparency = 1

	local bs = banner:FindFirstChildOfClass("UIScale")

	if bs then
		bs.Scale = 1
	end
end

----------------------------------------------------------------
-- SEQUENCE PIECES
----------------------------------------------------------------

local function shockwave(index: number, tint: Color3, from: number, to: number, dur: number, alpha: number)
	local s = shocks[index]

	if not s then
		return
	end

	s.ImageColor3 = tint
	s.Size = UDim2.fromOffset(from, from)
	s.ImageTransparency = alpha
	s.Visible = true

	tween(
		s,
		dur,
		{
			Size = UDim2.fromOffset(to, to),
			ImageTransparency = 1,
		},
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)
end

local function raiseShafts(count: number, tint: Color3, length: number, alpha: number)
	shaftHub.Visible = true

	for i = 1, SHAFT_COUNT do
		local s = shafts[i]

		if i <= count then
			-- Uneven lengths and a jittered angle: an evenly spaced fan of
			-- identical shafts reads as a graphic, not as light.
			local jitter = (math.random() - 0.5) * (300 / count)
			local scale = 0.7 + math.random() * 0.55

			s.Rotation = (i - 1) * (360 / count) + jitter
			s.Size = UDim2.fromOffset(length * 0.34, length * 0.30)
			s.ImageColor3 = tint
			s.ImageTransparency = 1
			s.Visible = true

			tween(
				s,
				0.42 + math.random() * 0.22,
				{
					Size = UDim2.fromOffset(length * 0.34, length * scale),
					ImageTransparency = alpha,
				},
				Enum.EasingStyle.Quint,
				Enum.EasingDirection.Out
			)
		else
			s.Visible = false
		end
	end

	spin(shaftHub, -26)
end

-- Sparks front-load into the impact; motes are spread over `window` so the hold
-- keeps moving instead of going still two thirds of the way through.
local function burstParticles(sparks: number, motes: number, window: number, tint: Color3, gen: number, isCurrent)
	for i = 1, sparks do
		task.delay(0.02 + i * 0.030, function()
			if isCurrent(gen) then
				emitSpark(tint)
			end
		end)
	end

	local step = motes > 0 and (window / motes) or 0

	for i = 1, motes do
		task.delay(0.10 + (i - 1) * step, function()
			if isCurrent(gen) then
				emitMote(tint)
			end
		end)
	end
end

----------------------------------------------------------------
-- PLAY
----------------------------------------------------------------

function RevealController:Play(result, quickMode: boolean)
	-- BOTH tables. Supports live in SupportDefinitions, so a CardDefinitions-only
	-- lookup returned nil for every one of them and this function bailed on its
	-- third line - the pull was granted and banked server-side, but no reveal
	-- ever played, so a rolled support looked like it had never dropped at all.
	-- CardRenderer has always resolved from both; this is the same fallback.
	local def = CardDefinitions.get(result.cardId)
		or SupportDefinitions.get(result.cardId)

	if not def then
		return
	end

	generation += 1

	local myGen = generation

	local function stale()
		return generation ~= myGen
	end

	local function isCurrent(g: number)
		return generation == g
	end

	local variant = VariantConfig.get(result.variant)
	local effective = VariantConfig.effectiveRarity(def.baseRarity, result.variant)

	-- Reveal intensity is based on the SAME effective denominator printed on the
	-- card, not only the base card. This matters for variants: a Gilded 1/100
	-- card is a 1/10,000 pull and must not be treated like a plain 1/100 Basic.
	local band = RarityBands.forDenominator(effective)
	local tierName = band.reveal

	-- Variant floors. Gilded always gets at least a normal reveal, Divine at
	-- least major, and Secret always gets cinematic.
	if variant.rank >= 4 then
		tierName = "cinematic"
	elseif variant.rank >= 3 and tierName ~= "cinematic" then
		tierName = "major"
	elseif variant.rank >= 2 and tierName == "quick" then
		tierName = "normal"
	end

	-- QUICK ROLL must only silence Basic/Standard pulls. The old logic turned a
	-- Gilded normal reveal back into quick and then immediately discarded it,
	-- which made Gilded pulls look as if they never happened.
	if quickMode and variant.rank == 1 and tierName == "normal" then
		tierName = "quick"
	end

	local isLegend = result.best == true and effective >= LEGEND_FLOOR

	if isLegend then
		-- Deliberately after the quick-roll downgrade above. A personal record
		-- overrules quick roll: it is the one moment the player wants the game
		-- to stop and make a noise about it.
		tierName = "legend"
	elseif quickMode and tierName == "quick" and variant.rank == 1 then
		self:Reset()
		return
	end

	local tier = TIERS[tierName] or TIERS.normal
	local tint = variant.rank > 1 and variant.color or band.color

	self:Reset()

	local entry =
		self.profile
		and self.profile.cards[CardStats.key(result.cardId, result.variant)]

	local level = entry and entry.level or 0

	CardRenderer.update(cardHandle, {
		cardId = result.cardId,
		variant = variant.id,
		level = level,
	})

	----------------------------------------------------------------
	-- 1. ANTICIPATION - legend only
	----------------------------------------------------------------

	if tier.anticipate then
		dim.BackgroundTransparency = 1
		tween(dim, tier.anticipate * 0.55, { BackgroundTransparency = 1 - tier.dim })

		vignette.ImageTransparency = 1
		tween(vignette, tier.anticipate * 0.7, { ImageTransparency = 0.22 })

		speedLines.ImageColor3 = tint:Lerp(Color3.new(1, 1, 1), 0.45)
		speedLines.Size = cover(3.1)
		speedLines.Rotation = -6
		speedLines.ImageTransparency = 0.98
		speedLines.Visible = true

		tween(
			speedLines,
			tier.anticipate,
			{
				Size = cover(1.30),
				ImageTransparency = 0.26,
				Rotation = 6,
			},
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.In
		)

		rune.ImageColor3 = tint
		rune.Size = cover(0.20)
		rune.ImageTransparency = 1
		rune.Visible = true

		tween(
			rune,
			tier.anticipate,
			{
				Size = cover(0.52),
				ImageTransparency = 0.72,
			},
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		)

		spin(rune, 22)

		shake(3)

		task.wait(tier.anticipate)

		if stale() then
			return
		end
	end

	----------------------------------------------------------------
	-- 2. BUILD - the softer wind-up the middle tiers get
	----------------------------------------------------------------

	if tier.dim and tier.dim > 0 and not tier.anticipate then
		tween(dim, (tier.build or 0.24) * 0.9, { BackgroundTransparency = 1 - tier.dim })
		tween(vignette, (tier.build or 0.30), { ImageTransparency = 0.45 })
	end

	if tier.build then
		cardWrapper.Visible = true
		cardWrapper.Rotation = -1.4
		cardGroup.GroupTransparency = 0.92
		cardScale.Scale = 0.72

		tween(cardGroup, tier.build, { GroupTransparency = 0.74 }, Enum.EasingStyle.Sine)
		tween(cardWrapper, tier.build, { Rotation = -0.6 }, Enum.EasingStyle.Sine)
		tween(cardScale, tier.build, { Scale = 0.78 }, Enum.EasingStyle.Sine)

		task.wait(tier.build)

		if stale() then
			return
		end
	end

	----------------------------------------------------------------
	-- 3. IMPACT
	----------------------------------------------------------------

	if tier.flash then
		flash.BackgroundTransparency = 0.04
		tween(flash, 0.34, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quart)

		tween(
			speedLines,
			0.22,
			{
				ImageTransparency = 1,
				Size = cover(0.75),
			},
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
	end

	if tier.shake then
		shake(tier.shake)
	end

	if tier.rays then
		rays.ImageColor3 = tint:Lerp(Color3.new(1, 1, 1), 0.22)
		rays.Size = cover(0.55)
		rays.ImageTransparency = 1
		rays.Visible = true

		tween(
			rays,
			0.45,
			{
				Size = cover(tier.speedLines and 1.45 or 1.15),
				ImageTransparency = tier.rays,
			},
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.Out
		)

		spin(rays, tier.speedLines and 14 or 20)
	end

	if tier.rune and not tier.anticipate then
		rune.ImageColor3 = tint
		rune.Size = cover(0.22)
		rune.ImageTransparency = 1
		rune.Visible = true

		tween(
			rune,
			0.55,
			{
				Size = cover(0.50),
				ImageTransparency = 0.78,
			},
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.Out
		)

		spin(rune, 22)
	elseif tier.rune then
		tween(rune, 0.5, { Size = cover(0.60), ImageTransparency = 0.74 }, Enum.EasingStyle.Quint)
	end

	if tier.shafts then
		local v = gui.AbsoluteSize

		-- Pulled toward white and held well back in opacity. Fully saturated
		-- shafts at a low transparency turn the whole screen into one colour
		-- and the card - the thing the player actually wants to look at -
		-- disappears into it.
		raiseShafts(
			tier.shafts,
			tint:Lerp(Color3.new(1, 1, 1), 0.30),
			math.max(v.X, v.Y) * (tier.speedLines and 0.85 or 0.72),
			0.78
		)
	end

	-- Card lands. On legend it comes DOWN out of the flash rather than growing
	-- in, which is what makes it feel dropped onto the screen instead of
	-- inflated onto it.
	local entryScale = tier.flash and 1.55 or (tier.build and 0.78 or 0.80)

	cardWrapper.Visible = true
	cardScale.Scale = entryScale
	cardGroup.GroupTransparency = tier.build and cardGroup.GroupTransparency or 1

	tween(cardGroup, tier.flash and 0.14 or 0.20, { GroupTransparency = 0 }, Enum.EasingStyle.Quint)
	tween(cardWrapper, 0.26, { Rotation = 0 }, Enum.EasingStyle.Quad)

	tween(
		cardScale,
		tier.flash and 0.40 or 0.30,
		{ Scale = 1 },
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)

	bloom.ImageColor3 = tint
	bloom.Size = cover(0.30)
	bloom.ImageTransparency = 1 - (tier.bloom or 0.6)

	tween(
		bloom,
		0.55,
		{
			Size = cover(0.92),
			ImageTransparency = 1,
		},
		Enum.EasingStyle.Quad
	)

	cardGlow.ImageColor3 = tint
	cardGlow.ImageTransparency = 0.35

	tween(cardGlow, 0.5, { ImageTransparency = 0.72 }, Enum.EasingStyle.Quad)

	if tier.streak then
		streak.ImageColor3 = tint:Lerp(Color3.new(1, 1, 1), 0.55)
		streak.Size = UDim2.fromOffset(340, 200)
		streak.ImageTransparency = 0.15

		tween(
			streak,
			0.55,
			{
				Size = UDim2.fromOffset(1500, 120),
				ImageTransparency = 1,
			},
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.Out
		)
	end

	local shockCount = tier.shocks or 0

	if shockCount >= 1 then
		local v = gui.AbsoluteSize
		local far = math.max(v.X, v.Y)

		shockwave(1, tint, 160, far * 1.45, 0.62, 0.05)

		if shockCount >= 2 then
			task.delay(0.16, function()
				if isCurrent(myGen) then
					shockwave(2, tint, 120, far * 1.0, 0.78, 0.45)
				end
			end)
		end

		if shockCount >= 3 then
			task.delay(0.55, function()
				if isCurrent(myGen) then
					shockwave(3, tint, 200, far * 1.9, 1.05, 0.55)
				end
			end)
		end
	end

	burstParticles(tier.sparks or 0, tier.motes or 0, tier.hold * 0.8, tint, myGen, isCurrent)

	if tier.banner then
		local headline

		if tierName == "legend" then
			headline = "NEW BEST PULL"
		elseif variant.rank > 1 then
			headline = variant.display:upper() .. " PULL"
		else
			headline = band.name:upper() .. " PULL"
		end

		banner.Text = headline
		banner.TextColor3 = tierName == "legend" and Color3.fromRGB(255, 255, 255) or tint
		banner.TextTransparency = 1
		banner.Visible = true

		-- The band of the EFFECTIVE denominator, not the printed one. A Secret
		-- copy of a 1/7,000 card is a 1/7,000,000,000 pull, and labelling that
		-- "RARE" because the base card is rare made the headline argue with the
		-- number printed directly underneath it.
		local shownBand = RarityBands.forDenominator(effective)

		subBanner.Text = shownBand.name:upper() .. "   ·   " .. RarityFormat.denominator(effective)
		subBanner.TextColor3 = tint
		subBanner.TextTransparency = 1
		subBanner.Visible = true

		local bs = banner:FindFirstChildOfClass("UIScale")

		if bs then
			bs.Scale = 1.35
			tween(bs, 0.42, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end

		tween(banner, 0.26, { TextTransparency = 0 })
		tween(subBanner, 0.34, { TextTransparency = 0.12 })
	end

	if stale() then
		return
	end

	----------------------------------------------------------------
	-- 4. HOLD
	----------------------------------------------------------------

	-- The card breathes rather than sitting frozen: a slow glow swell is the
	-- cheapest way to stop a two second hold reading as a paused frame.
	tween(
		cardGlow,
		tier.hold * 0.55,
		{ ImageTransparency = 0.52 },
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut
	)

	task.wait(tier.hold)

	if stale() then
		return
	end

	----------------------------------------------------------------
	-- 5. EXIT
	----------------------------------------------------------------

	local out = 0.24

	tween(cardScale, out, { Scale = 0.93 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(cardGroup, out, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(cardWrapper, out, { Rotation = 1.0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	tween(dim, out + 0.06, { BackgroundTransparency = 1 })
	tween(vignette, out + 0.06, { ImageTransparency = 1 })
	tween(cardGlow, out, { ImageTransparency = 1 })
	tween(rays, out, { ImageTransparency = 1 })
	tween(rune, out, { ImageTransparency = 1 })

	for _, s in ipairs(shafts) do
		if s.Visible then
			tween(s, out, { ImageTransparency = 1 })
		end
	end

	if banner.Visible then
		tween(banner, out * 0.8, { TextTransparency = 1 })
		tween(subBanner, out * 0.8, { TextTransparency = 1 })
	end

	task.wait(out + 0.04)

	if stale() then
		return
	end

	self:Reset()
end

----------------------------------------------------------------
-- INIT
----------------------------------------------------------------

function RevealController:Init()
	self:Build()
	self.profile = nil

	Remotes.ProfileSync.OnClientEvent:Connect(function(data)
		self.profile = data
	end)

	Remotes.RollResult.OnClientEvent:Connect(function(result)
		local quick = false

		local ui =
			self.Controllers
			and self.Controllers.UIController

		if ui and ui.IsQuickRoll then
			quick = ui:IsQuickRoll()
		end

		-- A preview asked for this reveal by name, so it always plays in full.
		-- Quick roll silences the quick tier outright, which for a debug command
		-- is indistinguishable from the command being broken.
		if result.preview then
			quick = false
		end

		task.spawn(function()
			self:Play(result, quick)
		end)
	end)
end

return RevealController
