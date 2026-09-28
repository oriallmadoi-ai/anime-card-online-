--!nonstrict
-- The Summon Core roulette: full screen, horizontal, cards travelling right to
-- left through a centre marker, slowing down onto the card the server already
-- chose, then a short reveal.
--
-- HONEST BY CONSTRUCTION
--   * The card is decided on the server (SummonCoreService:Open) before a
--     single frame of this plays. This module animates TOWARDS a card it has
--     been told; nothing here can change what was won.
--   * Every card on the strip comes from result.pool: the outcomes that had a
--     non-zero chance for THIS core and THIS player. A card that could not
--     have dropped is never drawn, not even as filler.
--   * The near miss - the card the strip creeps towards and stops just short
--     of - comes from the same pool, and only from outcomes that are rarer
--     than the win AND had at least NEAR_MISS_MIN_P chance. A real "almost",
--     never a one-in-a-billion tease.
--   * Filler is drawn with the odds flattened (p ^ FILLER_POWER), so a strip
--     for a low core is not forty copies of one common card. That changes how
--     often a POSSIBLE card passes by, never which cards can appear.
--
-- USE
--   SummonRoulette.open(stageId)  asks the server to open one core of that
--                                 stage, plays the result, and returns once
--                                 the player has collected it. Yields.
--   SummonRoulette.play(result)   plays an already-decided result. Yields.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local RarityBands = require(ReplicatedStorage.Shared.Config.RarityBands)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)
local RarityFormat = require(ReplicatedStorage.Shared.Util.RarityFormat)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local Sweep = require(ReplicatedStorage.Shared.UI.Sweep)
local TextShine = require(ReplicatedStorage.Shared.UI.TextShine)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

local SummonRoulette = {}

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- tuning
----------------------------------------------------------------------
local SPIN_TIME = 6.4          -- launch to stop, seconds
local SPIN_POWER = 3.1         -- ease-out exponent: higher = longer crawl at the end
local WIN_INDEX = 44           -- where the won card sits on the strip
local NEAR_MISS_MIN_P = 0.002  -- a near miss must have had at least this chance
local FILLER_POWER = 0.55      -- flattening for filler picks (1 = true odds)
local TICK_MIN_GAP = 0.034     -- seconds between tick sounds at full speed
local DISPLAY_ORDER = 120      -- above the HUD, menus and roll reveals

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TEXT = Color3.fromRGB(240, 242, 250)
local MUTED = Color3.fromRGB(156, 152, 182)
local DIM = Color3.fromRGB(110, 106, 138)
local ACCENT = Color3.fromRGB(150, 110, 255)
local ACCENT_HI = Color3.fromRGB(200, 176, 255)

-- Tick, Start and Fanfare are engine-shipped (rbxasset://), so they cannot
-- fail moderation. Reveal is the game's own upload (RouletteReveal): the sound
-- of the final card landing.
local SOUNDS = {
	Tick = { id = "rbxasset://sounds/clickfast.wav", volume = 0.3 },
	Start = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.32 },
	Reveal = { id = "rbxassetid://129055375267424", volume = 0.6 },
	Fanfare = { id = "rbxasset://sounds/victory.wav", volume = 0.42 },
}

local QUAD = Enum.EasingStyle.Quad
local QUART = Enum.EasingStyle.Quart
local BACK = Enum.EasingStyle.Back

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function new(className, props, children)
	local object = Instance.new(className)
	if object:IsA("GuiObject") then object.BorderSizePixel = 0 end
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then object[key] = value end
	end
	for _, child in ipairs(children or {}) do child.Parent = object end
	if props and props.Parent then object.Parent = props.Parent end
	return object
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function tween(object, properties, duration, style, direction)
	local motion = TweenService:Create(object, TweenInfo.new(duration or 0.2,
		style or QUAD, direction or Enum.EasingDirection.Out), properties)
	motion:Play()
	return motion
end

local function label(parent, name, value, size, color, z, font)
	return new("TextLabel", { Parent = parent, Name = name, BackgroundTransparency = 1, Text = value,
		Font = font or Enum.Font.GothamMedium, TextSize = size, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = z or 1 })
end

local soundPool = {}
local function pooled(name)
	local spec = SOUNDS[name]
	if not spec then return nil end
	local sound = soundPool[name]
	if not sound or not sound.Parent then
		sound = Instance.new("Sound")
		sound.Name = "Roulette_" .. name
		sound.SoundId = spec.id
		sound.Volume = spec.volume
		sound.Parent = SoundService
		soundPool[name] = sound
	end
	return sound
end

local function play(name, pitch)
	local sound = pooled(name)
	if not sound then return end
	sound.PlaybackSpeed = pitch or 1
	sound.TimePosition = 0
	sound:Play()
end

-- Fetches an uploaded sound ahead of its cue. The first play of an asset that
-- is not cached yet starts late, by however long the download takes, and a
-- reveal sound that trails its flash reads as a bug.
local function warm(name)
	local sound = pooled(name)
	if sound and not sound.IsLoaded then
		task.spawn(function()
			pcall(function() ContentProvider:PreloadAsync({ sound }) end)
		end)
	end
end

-- This module is required the moment a core is opened, a network round trip
-- and a full spin before the reveal, so warming here is plenty early.
-- (Only in a running client: Studio's Edit mode also reports IsClient, and a
-- Sound made there would be saved into the place.)
if RunService:IsClient() and RunService:IsRunning() then
	task.defer(warm, "Reveal")
end

local function defOf(cardId)
	return CardDefinitions.get(cardId) or SupportDefinitions.get(cardId)
end

-- The colour a pull is celebrated in: its tier colour for anything above
-- Basic, otherwise the rarity band's (same rule as the roll reveal).
local function tintFor(variantId, rarity)
	local variant = VariantConfig.get(variantId)
	if variant.rank > 1 then return variant.color end
	return RarityBands.forDenominator(rarity).color
end

local function sameOutcome(a, b)
	return a and b and a.id == b.id and a.variant == b.variant
end

-- A small, self-dismissing notice for a refused open ("You don't own that
-- core"). The roulette never opened, so there is no screen to put it on.
local function toast(text)
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	local gui = new("ScreenGui", { Name = "SummonRouletteToast", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = DISPLAY_ORDER + 1, Parent = playerGui })
	local plate = new("TextLabel", { Parent = gui, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromRGB(21, 20, 31),
		BackgroundTransparency = 0.06, Text = text, Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = TEXT },
		{ corner(10), new("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }),
			new("UIStroke", { Color = Color3.fromRGB(255, 112, 134), Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })
	task.delay(2.4, function()
		tween(plate, { TextTransparency = 1, BackgroundTransparency = 1 }, 0.25)
		task.delay(0.3, function() gui:Destroy() end)
	end)
end

----------------------------------------------------------------------
-- the strip
----------------------------------------------------------------------

local function weightedPick(rng, list, weights, total)
	local r = rng:NextNumber() * total
	for i, entry in ipairs(list) do
		r -= weights[i]
		if r <= 0 then return entry end
	end
	return list[#list]
end

-- Every card on the strip, in order. Only outcomes from result.pool appear.
local function buildStrip(result, count)
	local rng = Random.new()
	local pool = result.pool or {}
	local win = { id = result.cardId, variant = result.variant, rarity = result.effectiveRarity }
	if #pool == 0 then pool = { { id = win.id, variant = win.variant, rarity = win.rarity, p = 1 } } end

	local weights, total = {}, 0
	for i, entry in ipairs(pool) do
		local w = math.max(entry.p or 0, 1e-12) ^ FILLER_POWER
		weights[i] = w
		total += w
	end

	local cards = table.create(count)
	for i = 1, count do
		cards[i] = weightedPick(rng, pool, weights, total)
	end
	cards[WIN_INDEX] = win

	-- The near miss: a rarer card that genuinely had a real chance.
	local candidates, cw, ct = {}, {}, 0
	for _, entry in ipairs(pool) do
		if entry.rarity > win.rarity and (entry.p or 0) >= NEAR_MISS_MIN_P then
			table.insert(candidates, entry)
			local w = entry.p ^ 0.5
			table.insert(cw, w)
			ct += w
		end
	end
	local nearMiss = nil
	if #candidates > 0 then
		nearMiss = weightedPick(rng, candidates, cw, ct)
		cards[WIN_INDEX + 1] = nearMiss
	end

	-- Never an identical twin right beside the win: it would make the landing
	-- look ambiguous.
	for _, i in ipairs({ WIN_INDEX - 1, WIN_INDEX + 1, WIN_INDEX + 2 }) do
		if cards[i] and cards[i] ~= nearMiss and sameOutcome(cards[i], win) then
			for _ = 1, 8 do
				local alt = weightedPick(rng, pool, weights, total)
				if not sameOutcome(alt, win) then
					cards[i] = alt
					break
				end
			end
		end
	end
	return cards, nearMiss ~= nil
end

----------------------------------------------------------------------
-- play
----------------------------------------------------------------------

local busy = false

function SummonRoulette.isBusy()
	return busy
end

function SummonRoulette.play(result)
	warm("Reveal")
	local playerGui = player:WaitForChild("PlayerGui")
	local stage = SummonCoreConfig.get(result.stageId)
	local family = stage and SummonCoreConfig.Families[stage.family] or SummonCoreConfig.Families.Basic
	local variant = VariantConfig.get(result.variant)
	local tint = tintFor(result.variant, result.effectiveRarity)
	local def = defOf(result.cardId)

	local gui = new("ScreenGui", { Name = "SummonRoulette", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = DISPLAY_ORDER, Parent = playerGui })
	local W, H = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	if W < 10 or H < 10 then
		local cam = workspace.CurrentCamera
		W, H = cam.ViewportSize.X, cam.ViewportSize.Y
	end

	-- Sizes follow the screen's height; everything below is in real pixels.
	local ui = math.clamp(H / 900, 0.6, 1.25)
	local CARD_W = math.clamp(math.floor(H * 0.2), 112, 220)
	local CARD_H = math.floor(CARD_W * 1.34)
	local GAP = math.floor(CARD_W * 0.1)
	local STEP = CARD_W + GAP
	local BAND_H = CARD_H + math.floor(34 * ui)
	local CY = math.floor(H * 0.46)
	local MX = math.floor(W / 2)
	local REVEAL_SCALE = math.clamp((H * 0.5) / CARD_H, 1.08, 1.32)

	-- Enough cards to fill the right half of the screen at the landing.
	local count = WIN_INDEX + math.ceil(MX / STEP) + 3
	-- The first card starts just off the right edge, so the strip streams in
	-- rather than popping into place.
	local startX = W + GAP

	-- Input blocker + backdrop.
	local blocker = new("TextButton", { Parent = gui, Name = "Blocker", Text = "", AutoButtonColor = false,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1 })
	local backdrop = new("Frame", { Parent = gui, Name = "Backdrop", BackgroundColor3 = Color3.fromRGB(6, 5, 11),
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	local vignette = new("ImageLabel", { Parent = gui, Name = "Vignette", BackgroundTransparency = 1,
		Image = VfxAssets.Vignette, ImageTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	local wash = new("ImageLabel", { Parent = gui, Name = "FamilyGlow", BackgroundTransparency = 1, Image = VfxAssets.Glow,
		ImageColor3 = family.colour, ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(MX, CY), Size = UDim2.fromOffset(W * 1.1, BAND_H * 3.2), ZIndex = 3 })

	-- Header: which core is being opened.
	local header = new("Frame", { Parent = gui, Name = "Header", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(MX, CY - CARD_H * REVEAL_SCALE / 2 - 18 * ui), Size = UDim2.fromOffset(W, 76 * ui), ZIndex = 10 })
	local headerRow = new("Frame", { Parent = header, Name = "Row", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 10 },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 12 * ui), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local coreIcon = new("ImageLabel", { Parent = headerRow, Name = "Core", LayoutOrder = 1, BackgroundTransparency = 1,
		Image = family.image, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(62 * ui, 62 * ui), ImageTransparency = 1, ZIndex = 10 })
	local titles = new("Frame", { Parent = headerRow, Name = "Titles", LayoutOrder = 2, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 62 * ui), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 10 },
		{ new("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
	local caption = label(titles, "Caption", "OPENING", math.floor(13 * ui), DIM, 10)
	caption.LayoutOrder = 1
	caption.AutomaticSize = Enum.AutomaticSize.X
	caption.Size = UDim2.fromOffset(0, 16 * ui)
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextTransparency = 1
	local title = label(titles, "Title", stage and stage.name or "Summon Core", math.floor(28 * ui), TEXT, 10, Enum.Font.GothamBold)
	title.LayoutOrder = 2
	title.AutomaticSize = Enum.AutomaticSize.X
	title.Size = UDim2.fromOffset(0, 32 * ui)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTransparency = 1
	local titleStroke = new("UIStroke", { Parent = title, Color = BLACK, Thickness = 1.4, Transparency = 1 })
	local luckText = ("Luck \u{00D7}%s"):format(SummonCoreConfig.formatBoost(result.luck or 1))
	local sub = label(titles, "Luck", luckText, math.floor(13 * ui), family.colour:Lerp(WHITE, 0.25), 10)
	sub.LayoutOrder = 3
	sub.AutomaticSize = Enum.AutomaticSize.X
	sub.Size = UDim2.fromOffset(0, 16 * ui)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTransparency = 1

	-- The band the cards run through.
	local band = new("Frame", { Parent = gui, Name = "Band", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, CY), Size = UDim2.new(1, 0, 0, BAND_H), BackgroundColor3 = Color3.fromRGB(11, 10, 18),
		BackgroundTransparency = 1, ZIndex = 4 })
	local edges = {}
	for _, y in ipairs({ 0, 1 }) do
		local line = new("Frame", { Parent = band, Name = y == 0 and "TopLine" or "BottomLine", AnchorPoint = Vector2.new(0.5, y),
			Position = UDim2.fromScale(0.5, y), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = family.colour,
			BackgroundTransparency = 1, ZIndex = 6 },
			{ new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(1, 1) }) }) })
		table.insert(edges, line)
	end

	local strip = new("Frame", { Parent = band, Name = "Strip", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(startX, 0), Size = UDim2.new(0, count * STEP, 1, 0), ZIndex = 5 })
	local dim = new("Frame", { Parent = band, Name = "Dim", BackgroundColor3 = BLACK, BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 7 })
	-- Soft ends, so cards fade in at the right edge and out at the left.
	for _, side in ipairs({ 0, 1 }) do
		new("Frame", { Parent = band, Name = side == 0 and "FadeLeft" or "FadeRight", BackgroundColor3 = Color3.fromRGB(6, 5, 11),
			AnchorPoint = Vector2.new(side, 0), Position = UDim2.fromScale(side, 0), Size = UDim2.new(0.22, 0, 1, 0), ZIndex = 8 },
			{ new("UIGradient", { Rotation = side == 0 and 0 or 180, Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }) })
	end

	-- Cards.
	local outcomes, hasNearMiss = buildStrip(result, count)
	local cards = table.create(count)
	for i, outcome in ipairs(outcomes) do
		local card = CardRenderer.create(strip, CARD_W, 5)
		CardRenderer.update(card, { cardId = outcome.id, variant = outcome.variant, level = 0 })
		Sweep.remove(card.root)
		card.root.AnchorPoint = Vector2.new(0.5, 0.5)
		card.root.Position = UDim2.new(0, (i - 1) * STEP + CARD_W / 2, 0.5, 0)
		card.scale = new("UIScale", { Parent = card.root, Scale = 1 })
		cards[i] = card
	end

	-- The marker.
	local marker = new("Frame", { Parent = gui, Name = "Marker", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(MX, CY), Size = UDim2.fromOffset(40, BAND_H + 34 * ui), ZIndex = 9 })
	local markerGlow = new("ImageLabel", { Parent = marker, Name = "Glow", BackgroundTransparency = 1, Image = VfxAssets.Glow,
		ImageColor3 = family.colour, ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 70, 1, 40), ZIndex = 9 })
	local markerLine = new("Frame", { Parent = marker, Name = "Line", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 10 },
		{ new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(1, 0.1) }) }) })
	local pointers = {}
	for _, y in ipairs({ 0, 1 }) do
		local pointer = new("Frame", { Parent = marker, Name = y == 0 and "PointerTop" or "PointerBottom",
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, y), Size = UDim2.fromOffset(16 * ui, 16 * ui),
			Rotation = 45, BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 10 },
			{ new("UIStroke", { Color = family.colour, Thickness = 2, Transparency = 1 }) })
		table.insert(pointers, pointer)
	end

	-- Skip.
	local skip = new("TextButton", { Parent = gui, Name = "Skip", Text = "SKIP", AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24), Size = UDim2.fromOffset(92 * ui, 36 * ui),
		BackgroundColor3 = Color3.fromRGB(30, 28, 44), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = math.floor(14 * ui), TextColor3 = MUTED, TextTransparency = 1, ZIndex = 12 },
		{ corner(10), new("UIStroke", { Color = Color3.fromRGB(66, 62, 96), Transparency = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) })

	----------------------------------------------------------------
	-- entrance
	----------------------------------------------------------------
	tween(backdrop, { BackgroundTransparency = 0.06 }, 0.3)
	tween(vignette, { ImageTransparency = 0.25 }, 0.4)
	tween(wash, { ImageTransparency = 0.9 }, 0.5)
	tween(band, { BackgroundTransparency = 0.25 }, 0.3)
	for _, line in ipairs(edges) do tween(line, { BackgroundTransparency = 0.35 }, 0.4) end
	tween(coreIcon, { ImageTransparency = 0 }, 0.3)
	tween(caption, { TextTransparency = 0 }, 0.3)
	tween(title, { TextTransparency = 0 }, 0.3)
	tween(titleStroke, { Transparency = 0.45 }, 0.3)
	tween(sub, { TextTransparency = 0 }, 0.3)
	tween(markerGlow, { ImageTransparency = 0.55 }, 0.4)
	tween(markerLine, { BackgroundTransparency = 0 }, 0.3)
	for _, pointer in ipairs(pointers) do
		tween(pointer, { BackgroundTransparency = 0 }, 0.3)
		tween(pointer:FindFirstChildOfClass("UIStroke"), { Transparency = 0.2 }, 0.3)
	end
	tween(skip, { BackgroundTransparency = 0.15, TextTransparency = 0 }, 0.3)
	tween(skip:FindFirstChildOfClass("UIStroke"), { Transparency = 0.3 }, 0.3)
	play("Start", 1.1)

	----------------------------------------------------------------
	-- the spin
	----------------------------------------------------------------
	-- Where the marker lands inside the winning card, measured from its
	-- centre. With a near miss it stops near the winner's trailing edge, the
	-- rarer card creeping up behind; otherwise anywhere comfortably inside.
	local landRng = Random.new()
	local land
	if hasNearMiss then
		land = CARD_W * landRng:NextNumber(0.24, 0.41)
	else
		land = CARD_W * landRng:NextNumber(-0.32, 0.32)
	end
	local endX = MX - land - (WIN_INDEX - 1) * STEP - CARD_W / 2
	local centreX = endX + land

	local x = startX
	local function emphasise()
		local under = math.floor((MX - x) / STEP) + 1
		for i = math.max(1, under - 3), math.min(count, under + 3) do
			local card = cards[i]
			local centre = x + (i - 1) * STEP + CARD_W / 2
			local k = math.max(0, 1 - math.abs(centre - MX) / STEP)
			card.scale.Scale = 1 + 0.07 * k
		end
	end

	local spinStart = os.clock() + 0.25
	local lastSlot = math.floor((MX - x) / STEP)
	local lastTick = 0
	local finished = false
	local skipped = false
	skip.Activated:Connect(function()
		if finished or skipped then return end
		skipped = true
		-- Fast-forward: jump to the last moment of the same curve, so the
		-- landing is exactly the one that would have happened.
		spinStart = math.min(spinStart, os.clock() - SPIN_TIME * 0.992)
		tween(skip, { BackgroundTransparency = 1, TextTransparency = 1 }, 0.15)
	end)

	local spinConn
	spinConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - spinStart
		if t < 0 then return end
		local u = math.clamp(t / SPIN_TIME, 0, 1)
		local k = 1 - (1 - u) ^ SPIN_POWER
		x = startX + (endX - startX) * k
		strip.Position = UDim2.fromOffset(x, 0)
		emphasise()
		local slot = math.floor((MX - x) / STEP)
		-- Only real cards crossing the marker tick; nothing ticks while the
		-- strip is still streaming in from the right.
		if slot ~= lastSlot and slot >= 0 then
			lastSlot = slot
			local now = os.clock()
			if now - lastTick >= TICK_MIN_GAP and not (skipped and u < 1) then
				lastTick = now
				play("Tick", 0.95 + 0.18 * (1 - u) + math.random() * 0.06)
			end
		end
		if u >= 1 then
			finished = true
			spinConn:Disconnect()
		end
	end)
	while not finished and gui.Parent do task.wait() end
	if not gui.Parent then
		-- Torn down from outside (the player left mid-spin): nothing to finish.
		spinConn:Disconnect()
		return
	end
	tween(skip, { BackgroundTransparency = 1, TextTransparency = 1 }, 0.15)
	tween(skip:FindFirstChildOfClass("UIStroke"), { Transparency = 1 }, 0.15)

	-- Settle the winner onto the marker.
	task.wait(0.28)
	local settleStart, settleFrom = os.clock(), x
	while true do
		local u = math.clamp((os.clock() - settleStart) / 0.3, 0, 1)
		local k = TweenService:GetValue(u, QUAD, Enum.EasingDirection.InOut)
		x = settleFrom + (centreX - settleFrom) * k
		strip.Position = UDim2.fromOffset(x, 0)
		emphasise()
		if u >= 1 or not gui.Parent then break end
		RunService.RenderStepped:Wait()
	end

	if not gui.Parent then return end

	----------------------------------------------------------------
	-- reveal
	----------------------------------------------------------------
	local winner = cards[WIN_INDEX]
	local big = variant.rank >= 3 or (result.effectiveRarity or 0) >= 1000000
	-- Always at its own pitch: it is a designed sound, not a placeholder to
	-- bend. Big pulls still get the fanfare on top.
	play("Reveal")
	if big then task.delay(0.12, function() play("Fanfare", 1) end) end

	-- Everything but the winner steps back. The winner moves up out of the
	-- strip into the band itself, so it can sit above the dim layer.
	winner.root.Parent = band
	winner.root.Position = UDim2.new(0, x + (WIN_INDEX - 1) * STEP + CARD_W / 2, 0.5, 0)
	winner.root.ZIndex = 10
	tween(dim, { BackgroundTransparency = 0.38 }, 0.35)
	tween(winner.scale, { Scale = REVEAL_SCALE }, 0.5, BACK)
	for _, line in ipairs(edges) do
		line.BackgroundColor3 = tint
		tween(line, { BackgroundTransparency = 0.1 }, 0.3)
	end
	tween(wash, { ImageColor3 = tint, ImageTransparency = 0.82 }, 0.4)
	tween(markerLine, { BackgroundTransparency = 1 }, 0.25)
	tween(markerGlow, { ImageTransparency = 1 }, 0.25)
	for _, pointer in ipairs(pointers) do
		tween(pointer, { BackgroundTransparency = 1 }, 0.25)
		tween(pointer:FindFirstChildOfClass("UIStroke"), { Transparency = 1 }, 0.25)
	end

	-- Light behind the card: slow rays, a halo in the card's shape, a ring.
	local fx = new("Frame", { Parent = gui, Name = "RevealFx", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(MX, CY), Size = UDim2.fromOffset(CARD_H * 3, CARD_H * 3), ZIndex = 4 })
	local rays = new("ImageLabel", { Parent = fx, Name = "Rays", BackgroundTransparency = 1, Image = VfxAssets.Burst,
		ImageColor3 = tint, ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(big and 1.05 or 0.8, big and 1.05 or 0.8), ZIndex = 4 })
	local halo = new("ImageLabel", { Parent = band, Name = "Halo", BackgroundTransparency = 1, Image = VfxAssets.CardGlow,
		ImageColor3 = tint, ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, MX, 0.5, 0),
		Size = UDim2.fromOffset(CARD_W * REVEAL_SCALE * 1.7, CARD_H * REVEAL_SCALE * 1.55), ZIndex = 9 })
	local shock = new("ImageLabel", { Parent = band, Name = "Shock", BackgroundTransparency = 1, Image = VfxAssets.Shock,
		ImageColor3 = tint:Lerp(WHITE, 0.3), ImageTransparency = 0.15, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, MX, 0.5, 0), Size = UDim2.fromOffset(CARD_W * 0.8, CARD_W * 0.8), ZIndex = 9 })
	local flash = new("Frame", { Parent = gui, Name = "Flash", BackgroundColor3 = tint:Lerp(WHITE, 0.7),
		BackgroundTransparency = big and 0.35 or 0.6, Size = UDim2.fromScale(1, 1), ZIndex = 11 })
	tween(flash, { BackgroundTransparency = 1 }, 0.45)
	tween(rays, { ImageTransparency = big and 0.45 or 0.62 }, 0.5)
	tween(halo, { ImageTransparency = 0.25 }, 0.4)
	tween(shock, { Size = UDim2.fromOffset(CARD_H * 2.6, CARD_H * 2.6), ImageTransparency = 1 }, 0.7, QUART)

	local spinning = true
	task.spawn(function()
		while spinning and rays.Parent do
			rays.Rotation = (rays.Rotation + 0.12) % 360
			RunService.RenderStepped:Wait()
		end
	end)

	-- Sparks thrown outwards from the card.
	local sparkCount = big and 18 or 9
	for i = 1, sparkCount do
		local angle = (i / sparkCount) * math.pi * 2 + math.random() * 0.4
		local dist = CARD_H * (0.6 + math.random() * 0.55)
		local size = math.floor((10 + math.random() * 14) * ui)
		local spark = new("ImageLabel", { Parent = gui, Name = "Spark", BackgroundTransparency = 1,
			Image = i % 3 == 0 and VfxAssets.Spark or VfxAssets.Mote, ImageColor3 = tint:Lerp(WHITE, 0.4),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(MX, CY), Size = UDim2.fromOffset(size, size),
			ImageTransparency = 0.05, ZIndex = 10 })
		local goal = UDim2.fromOffset(MX + math.cos(angle) * dist, CY + math.sin(angle) * dist * 0.8)
		tween(spark, { Position = goal, ImageTransparency = 1, Size = UDim2.fromOffset(size * 0.4, size * 0.4) },
			0.7 + math.random() * 0.4, QUART)
		task.delay(1.2, function() spark:Destroy() end)
	end

	-- Text: tier, name, rarity, tags, and the way out.
	local info = new("Frame", { Parent = gui, Name = "Info", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(MX, CY + CARD_H * REVEAL_SCALE / 2 + 18 * ui), Size = UDim2.fromOffset(W, 170 * ui), ZIndex = 12 },
		{ new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 4 * ui),
			SortOrder = Enum.SortOrder.LayoutOrder }) })
	local infoScale = new("UIScale", { Parent = info, Scale = 0.92 })
	local tierText = label(info, "Tier", string.upper(variant.display), math.floor(18 * ui), variant.color, 12, Enum.Font.GothamBold)
	tierText.LayoutOrder = 1
	tierText.AutomaticSize = Enum.AutomaticSize.X
	tierText.Size = UDim2.fromOffset(0, 22 * ui)
	TextShine.apply(tierText, variant.id)
	local nameText = new("TextLabel", { Parent = info, Name = "CardName", LayoutOrder = 2, BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 44 * ui), Text = def and def.name or result.cardId,
		FontFace = Theme.font(), TextSize = math.floor(38 * ui), TextColor3 = WHITE, ZIndex = 12 })
	new("UIStroke", { Parent = nameText, Color = BLACK, Thickness = 2.4, LineJoinMode = Enum.LineJoinMode.Round })
	local rarityText = label(info, "Rarity", RarityFormat.denominator(result.effectiveRarity or 0), math.floor(17 * ui), tint, 12,
		Enum.Font.GothamBold)
	rarityText.LayoutOrder = 3
	rarityText.AutomaticSize = Enum.AutomaticSize.X
	rarityText.Size = UDim2.fromOffset(0, 22 * ui)
	new("UIStroke", { Parent = rarityText, Color = BLACK, Thickness = 1.2, Transparency = 0.4 })

	local tags = {}
	if result.isBonus then table.insert(tags, { "2x CORE BONUS", Color3.fromRGB(255, 197, 61) }) end
	if result.new then table.insert(tags, { "NEW", Color3.fromRGB(121, 255, 185) }) end
	if result.best and (result.effectiveRarity or 0) >= 2500 then table.insert(tags, { "BEST PULL", Color3.fromRGB(255, 216, 140) }) end
	if #tags > 0 then
		local row = new("Frame", { Parent = info, Name = "Tags", LayoutOrder = 4, BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24 * ui), ZIndex = 12 },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8 * ui),
				SortOrder = Enum.SortOrder.LayoutOrder }) })
		for i, tag in ipairs(tags) do
			local pill = label(row, "Tag", tag[1], math.floor(12 * ui), Color3.fromRGB(16, 18, 24), 12, Enum.Font.GothamBold)
			pill.LayoutOrder = i
			pill.BackgroundTransparency = 0
			pill.BackgroundColor3 = tag[2]
			pill.AutomaticSize = Enum.AutomaticSize.X
			pill.Size = UDim2.fromOffset(0, 22 * ui)
			new("UIPadding", { Parent = pill, PaddingLeft = UDim.new(0, 10 * ui), PaddingRight = UDim.new(0, 10 * ui) })
			corner(11).Parent = pill
		end
	end

	new("Frame", { Parent = info, Name = "Spacer", LayoutOrder = 5, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(1, 8 * ui) })
	local collect = new("TextButton", { Parent = info, Name = "Collect", LayoutOrder = 6, Text = "", AutoButtonColor = false,
		Size = UDim2.fromOffset(210 * ui, 46 * ui), BackgroundColor3 = WHITE, ZIndex = 12 }, { corner(11) })
	new("UIGradient", { Parent = collect, Rotation = 90,
		Color = ColorSequence.new(ACCENT:Lerp(WHITE, 0.1), ACCENT:Lerp(BLACK, 0.42)) })
	local collectStroke = new("UIStroke", { Parent = collect, Color = ACCENT_HI, Transparency = 0.3, Thickness = 1.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local collectScale = new("UIScale", { Parent = collect, Scale = 1 })
	local collectText = label(collect, "Caption", "COLLECT", math.floor(17 * ui), WHITE, 13, Enum.Font.GothamBold)
	collectText.Size = UDim2.fromScale(1, 1)
	new("UIStroke", { Parent = collectText, Color = BLACK, Thickness = 1.2, Transparency = 0.55 })
	Sweep.attach(collect, { tint = WHITE, transparency = 0.84, width = 0.34, zIndex = 13 })
	collect.MouseEnter:Connect(function()
		tween(collectScale, { Scale = 1.04 }, 0.12)
		tween(collectStroke, { Transparency = 0.05 }, 0.12)
	end)
	collect.MouseLeave:Connect(function()
		tween(collectScale, { Scale = 1 }, 0.14)
		tween(collectStroke, { Transparency = 0.3 }, 0.14)
	end)
	collect.MouseButton1Down:Connect(function() tween(collectScale, { Scale = 0.95 }, 0.06) end)

	-- Fade the info block in.
	local infoParts = {}
	for _, object in ipairs(info:GetDescendants()) do
		if object:IsA("TextLabel") or object:IsA("TextButton") then
			table.insert(infoParts, { object, "TextTransparency", object.TextTransparency })
			table.insert(infoParts, { object, "BackgroundTransparency", object.BackgroundTransparency })
			object.TextTransparency = 1
			object.BackgroundTransparency = 1
		elseif object:IsA("UIStroke") then
			table.insert(infoParts, { object, "Transparency", object.Transparency })
			object.Transparency = 1
		end
	end
	task.wait(0.18)
	tween(infoScale, { Scale = 1 }, 0.4, BACK)
	for _, entry in ipairs(infoParts) do
		tween(entry[1], { [entry[2]] = entry[3] }, 0.3)
	end

	----------------------------------------------------------------
	-- wait for COLLECT (or a click anywhere once it has settled)
	----------------------------------------------------------------
	local closed = false
	local readyAt = os.clock() + 0.7
	local function close()
		if closed or os.clock() < readyAt then return end
		closed = true
	end
	collect.Activated:Connect(close)
	blocker.Activated:Connect(close)
	while not closed and gui.Parent do task.wait() end

	-- Exit.
	spinning = false
	for _, object in ipairs(gui:GetDescendants()) do
		if object:IsA("GuiObject") then
			local props = { BackgroundTransparency = 1 }
			if object:IsA("TextLabel") or object:IsA("TextButton") then props.TextTransparency = 1 end
			if object:IsA("ImageLabel") then props.ImageTransparency = 1 end
			tween(object, props, 0.22)
		elseif object:IsA("UIStroke") then
			tween(object, { Transparency = 1 }, 0.22)
		end
	end
	tween(winner.scale, { Scale = REVEAL_SCALE * 0.94 }, 0.22)
	task.wait(0.24)
	gui:Destroy()
end

----------------------------------------------------------------------
-- open
----------------------------------------------------------------------

function SummonRoulette.open(stageId)
	if busy then return false, "busy" end
	busy = true

	local okCall, ok, payload = pcall(function()
		local CoreRemotes = require(ReplicatedStorage.Shared.Net.SummonCoreRemotes)
		return CoreRemotes.Action:InvokeServer("open", { stageId = stageId })
	end)
	if not okCall then
		busy = false
		toast("Couldn't reach the forge. Try again.")
		return false, tostring(ok)
	end
	if not ok then
		busy = false
		toast(tostring(payload or "That core can't be opened right now."))
		return false, payload
	end

	local function playSafely(result)
		local played, err = pcall(SummonRoulette.play, result)
		if not played then
			warn("[SummonRoulette] " .. tostring(err))
			-- The card is already in the inventory; make sure no half-built
			-- overlay is left covering the screen.
			local playerGui = player:FindFirstChildOfClass("PlayerGui")
			local leftover = playerGui and playerGui:FindFirstChild("SummonRoulette")
			if leftover then leftover:Destroy() end
		end
	end
	playSafely(payload)
	-- 2x Summon Core pass: the server already rolled a second card from the
	-- same core; play it straight after the first is collected.
	if type(payload) == "table" and type(payload.bonus) == "table" then
		playSafely(payload.bonus)
	end
	busy = false
	return true, payload
end

return SummonRoulette
