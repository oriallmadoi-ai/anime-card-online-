--!strict
-- Card reveal with ONE clean border close to the card.
--
-- BORDER GOAL:
-- • NO outer halo
-- • NO stacked blue/white/gray layers
-- • ONE thick border tight to the card
-- • the border colour comes from the card variant
-- • one VERY BRIGHT coloured shine travels around that same border
--
-- SPECIAL VARIANTS:
-- • Astral       = deep blue border + neon cyan/blue travelling flash
-- • Transcendent = black/yellow border + electric yellow travelling flash
-- • Gilded       = bright gold/orange border + white-hot gold travelling flash
--
-- Everything else falls back to VariantConfig colour.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local RarityBands = require(ReplicatedStorage.Shared.Config.RarityBands)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local PassiveDefinitions = require(ReplicatedStorage.Shared.Config.PassiveDefinitions)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local RarityFormat = require(ReplicatedStorage.Shared.Util.RarityFormat)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local player = Players.LocalPlayer

local RevealController = {}
RevealController.Name = "RevealController"

local TEXT = Color3.fromRGB(238, 240, 250)

local TIERS = {
	quick     = { build = 0.00, hold = 0.65, dim = 0.00, rays = false, shake = false, ring = false },
	normal    = { build = 0.18, hold = 2.00, dim = 0.00, rays = false, shake = false, ring = true  },
	major     = { build = 0.75, hold = 2.60, dim = 0.45, rays = true,  shake = true,  ring = true  },
	cinematic = { build = 1.40, hold = 3.40, dim = 0.70, rays = true,  shake = true,  ring = true  },
}

local gui, dim, rayHolder, ring, cardWrapper, cardGroup, cardFrame, cardScale, cardStroke, glow
local cardHandle
local parts = {}
local generation = 0
local rayTween = nil
local activeTweens = {}


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

local function label(props)
	local d = {
		BackgroundTransparency = 1,
		FontFace = Theme.font(),
		TextColor3 = TEXT,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}

	for k, v in pairs(props) do
		d[k] = v
	end

	return new("TextLabel", d)
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

----------------------------------------------------------------
-- VARIANT BORDER PALETTES
----------------------------------------------------------------

----------------------------------------------------------------
-- BORDER
----------------------------------------------------------------
-- There is no separate reveal border any more.
--
-- The reveal used to hide CardRenderer's border and draw its own single neon
-- stroke instead, which meant a Secret card revealed as one thing and then sat
-- in your deck as another. The deck's border is the one that was right - the
-- flowing multi-colour falloff Shine draws from the tier's own spec - so the
-- reveal simply shows the card CardRenderer built, border and all.
--
-- The only thing the reveal has to do is not clip it: Shine's shells render
-- OUTSIDE the card, so cardFrame.ClipsDescendants is false in Build below.
-- That single line is what lets the same border look the same in both places.

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
		Parent = gui,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 1,
	})

	rayHolder = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 900, 0, 900),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 2,
	})

	for i = 1, 12 do
		new("Frame", {
			Parent = rayHolder,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 26, 0, 900),
			Rotation = (i - 1) * 15,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			ZIndex = 2,
		})
	end

	ring = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 120, 0, 120),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
	}, {
		new("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		new("UIStroke", {
			Color = Color3.new(1, 1, 1),
			Thickness = 4,
			Transparency = 0,
		}),
	})

	glow = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 300, 0, 390),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, {
		new("UICorner", {
			CornerRadius = UDim.new(0, 28),
		}),
	})

	-- Wrapper controls position/rotation/scale for BOTH card and border.
	cardWrapper = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.46, 0),
		Size = UDim2.new(0, 360, 0, 470),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ClipsDescendants = false,
		ZIndex = 4,
	})

	-- Only the CARD CONTENT fades. The neon border is outside this CanvasGroup.
	cardGroup = new("CanvasGroup", {
		Parent = cardWrapper,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = true,
		ClipsDescendants = false,
		ZIndex = 4,
	})

	local card = CardRenderer.create(cardGroup, 250, 4)

	card.root.AnchorPoint = Vector2.new(0.5, 0.5)
	card.root.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.root.Visible = true
	card.root.ClipsDescendants = false

	cardHandle = card
	cardFrame = card.root

	-- Scale the WRAPPER, not only the card.
	-- Border and card now stay perfectly attached during the pop animation.
	cardScale = Instance.new("UIScale")
	cardScale.Scale = 1
	cardScale.Parent = cardWrapper

	cardStroke = card.stroke

	parts.banner = label({
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.16, 0),
		Size = UDim2.new(0, 700, 0, 40),
		Text = "",
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Theme.font(),
		Visible = false,
		ZIndex = 20,
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

	if rayTween then
		rayTween:Cancel()
		rayTween = nil
	end

	cardWrapper.Visible = false
	cardWrapper.Position = UDim2.new(0.5, 0, 0.46, 0)
	cardWrapper.Rotation = 0

	cardGroup.Visible = true
	cardGroup.GroupTransparency = 1

	cardFrame.Visible = true
	cardFrame.Rotation = 0
	cardFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	cardScale.Scale = 1

	-- The card's own border is the card's own business now; Shine parks this
	-- stroke itself on the tiers that carry a spec, so the reveal must not
	-- second-guess it the way it used to.
	cardStroke.Transparency = 0

	rayHolder.Visible = false
	rayHolder.Rotation = 0

	ring.Visible = false
	parts.banner.Visible = false

	dim.BackgroundTransparency = 1
	glow.BackgroundTransparency = 1

	for _, ray in ipairs(rayHolder:GetChildren()) do
		if ray:IsA("Frame") then
			ray.BackgroundTransparency = 0.88
		end
	end
end

----------------------------------------------------------------
-- PLAY
----------------------------------------------------------------

function RevealController:Play(result, quickMode: boolean)
	local def = CardDefinitions.get(result.cardId)

	if not def then
		return
	end

	generation += 1

	local myGen = generation

	local function stale()
		return generation ~= myGen
	end

	local band = RarityBands.forDenominator(def.baseRarity)
	local variant = VariantConfig.get(result.variant)

	local tierName = band.reveal

	if variant.rank >= 4 then
		tierName = "cinematic"
	elseif variant.rank >= 3 and tierName ~= "cinematic" then
		tierName = "major"
	elseif variant.rank >= 2 and tierName == "quick" then
		tierName = "normal"
	end

	if quickMode and tierName == "normal" then
		tierName = "quick"
	end

	if quickMode and tierName == "quick" then
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

	-- No border call here. CardRenderer.update above already drew the tier's
	-- own border and started its Shine - the same one the deck screen shows.

	----------------------------------------------------------------
	-- 1. BUILD-UP
	----------------------------------------------------------------

	if tier.dim > 0 then
		tween(
			dim,
			tier.build * 0.6,
			{
				BackgroundTransparency = 1 - tier.dim,
			}
		)
	end

	if tier.rays then
		rayHolder.Visible = true

		rayTween = TweenService:Create(
			rayHolder,
			TweenInfo.new(
				9,
				Enum.EasingStyle.Linear,
				Enum.EasingDirection.InOut,
				-1
			),
			{
				Rotation = 360,
			}
		)

		rayTween:Play()
	end

	if tier.build > 0 then
		cardWrapper.Visible = true
		cardWrapper.Position = UDim2.new(0.5, 0, 0.465, 0)
		cardWrapper.Rotation = -1.4

		cardGroup.Visible = true
		cardGroup.GroupTransparency = 0.92

		cardScale.Scale = 0.72

		tween(
			cardGroup,
			tier.build,
			{
				GroupTransparency = 0.74,
			},
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		)

		tween(
			cardWrapper,
			tier.build,
			{
				Position = UDim2.new(0.5, 0, 0.458, 0),
				Rotation = -0.6,
			},
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		)

		tween(
			cardScale,
			tier.build,
			{
				Scale = 0.77,
			},
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out
		)


		task.wait(tier.build)
	end

	if stale() then
		return
	end

	----------------------------------------------------------------
	-- 2. REVEAL
	----------------------------------------------------------------

	cardWrapper.Visible = true
	cardGroup.Visible = true

	if tier.build <= 0 then
		cardGroup.GroupTransparency = 1
		cardWrapper.Position = UDim2.new(0.5, 0, 0.465, 0)
		cardWrapper.Rotation = -1.5
		cardScale.Scale = 0.78
	else
		cardScale.Scale = 0.77
	end

	tween(
		cardGroup,
		0.22,
		{
			GroupTransparency = 0,
		},
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)

	tween(
		cardWrapper,
		0.24,
		{
			Position = UDim2.new(0.5, 0, 0.45, 0),
			Rotation = 0,
		},
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	tween(
		cardScale,
		0.30,
		{
			Scale = 1,
		},
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)


	-- Keep the background flash subtle.
	-- The BORDER should be the main visual effect now.
	glow.BackgroundColor3 = tint
	glow.Size = UDim2.new(0, 275, 0, 355)
	glow.BackgroundTransparency = 0.72

	tween(
		glow,
		0.42,
		{
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 400, 0, 500),
		},
		Enum.EasingStyle.Quad
	)

	if tier.ring then
		ring.Visible = true
		ring.Size = UDim2.new(0, 140, 0, 140)

		local rs = ring:FindFirstChildOfClass("UIStroke")

		if rs then
			rs.Color = tint
			rs.Transparency = 0

			tween(
				ring,
				0.55,
				{
					Size = UDim2.new(0, 620, 0, 620),
				}
			)

			tween(
				rs,
				0.55,
				{
					Transparency = 1,
				}
			)
		end
	end

	if tier.shake then
		for _ = 1, 6 do
			if stale() then
				return
			end

			cardWrapper.Position = UDim2.new(
				0.5,
				math.random(-5, 5),
				0.45,
				math.random(-5, 5)
			)

			task.wait(0.03)
		end

		cardWrapper.Position = UDim2.new(0.5, 0, 0.45, 0)

		parts.banner.Text =
			(
				variant.rank > 1
				and (variant.display:upper() .. " PULL")
				or (band.name:upper() .. " PULL")
			)

		parts.banner.TextColor3 = tint
		parts.banner.Visible = true
		parts.banner.TextTransparency = 1

		tween(
			parts.banner,
			0.25,
			{
				TextTransparency = 0,
			}
		)
	end

	if stale() then
		return
	end

	----------------------------------------------------------------
	-- 3. HOLD
	----------------------------------------------------------------

	task.wait(tier.hold)

	if stale() then
		return
	end

	----------------------------------------------------------------
	-- 4. SMOOTH EXIT
	----------------------------------------------------------------

	tween(
		cardScale,
		0.20,
		{
			Scale = 0.94,
		},
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)


	tween(
		cardGroup,
		0.20,
		{
			GroupTransparency = 1,
		},
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)

	tween(
		cardWrapper,
		0.20,
		{
			Position = UDim2.new(0.5, 0, 0.462, 0),
			Rotation = 1.0,
		},
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)

	-- Nothing to fade separately any more: the border lives on the card, which
	-- lives inside the CanvasGroup, so GroupTransparency takes it out with
	-- everything else.

	if tier.dim > 0 then
		tween(
			dim,
			0.26,
			{
				BackgroundTransparency = 1,
			}
		)
	end

	if parts.banner.Visible then
		tween(
			parts.banner,
			0.18,
			{
				TextTransparency = 1,
			}
		)
	end

	if rayHolder.Visible then
		for _, ray in ipairs(rayHolder:GetChildren()) do
			if ray:IsA("Frame") then
				tween(
					ray,
					0.20,
					{
						BackgroundTransparency = 1,
					}
				)
			end
		end
	end

	task.wait(0.22)

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

		task.spawn(function()
			self:Play(result, quick)
		end)
	end)
end

return RevealController