--!nonstrict
-- Anime Card Online - battle victory reward presentation.
--
-- ReplicatedStorage > Shared > UI > RewardPopup
--
-- The battle itself closes before this opens. This module intentionally has NO
-- filled modal background: it lives at the top of the screen, replacing the old
-- "YOU BEAT <ENEMY>" message instead of stacking another window over battle UI.
--
-- THE LOOK (drawn first in Figma: "Anime Card Online - UI Kit" > Battle Victory)
--   * a gold light behind the header: a soft bloom and a slowly turning ray burst
--   * the BATTLE WON header: dark glass, the animated rainbow Shine border, a gold
--     title with a shimmer sweeping through it, and a twinkling star either side
--   * a chip under the title saying what was cleared ("FIRST CLEAR - HARD")
--   * one tile per reward, each in its exact rarity border from VariantConfig
--     (Elder Coins keep their Cosmic border), dealt in one after another
--   * "REWARDS ADDED TO YOUR BACKPACK" underneath
--
-- Everything that moves is driven by ONE Heartbeat connection that exists only
-- while the banner is up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local TextShine = require(ReplicatedStorage.Shared.UI.TextShine)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)
local ElderCoin = require(ReplicatedStorage.Shared.UI.ElderCoin)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local ArtLoader = require(ReplicatedStorage.Shared.UI.ArtLoader)
local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)

local RewardPopup = {}

local ROOT_W = 900
local HEADER_W, HEADER_H = 640, 124
local TILE_W, TILE_H = 132, 150
local TILE_GAP = 18
local TILES_Y = HEADER_H + 30
local SHOW_SECONDS = 5.5

local INK = Color3.fromRGB(10, 10, 16)
local WHITE = Color3.new(1, 1, 1)
local TEXT = Color3.fromRGB(248, 248, 255)
local MUTED = Color3.fromRGB(205, 207, 226)
local GOLD = Color3.fromRGB(255, 214, 110)
local GOLD_DEEP = Color3.fromRGB(255, 196, 92)
local NEW_GREEN = Color3.fromRGB(110, 232, 160)
local PANEL_TOP = Color3.fromRGB(24, 26, 41)
local PANEL_BOTTOM = Color3.fromRGB(9, 10, 17)

-- The header's animated border, built by the SAME Shine system used throughout
-- the game. The rotating gradient is what makes colour travel around the outline.
local RAINBOW_BORDER = {
	baseColour = Color3.fromRGB(255, 255, 255),
	baseThickness = 1.6,
	baseTransparency = 0.6,
	corner = 20,
	glowScale = 1.25,
	glowColours = {
		Color3.fromRGB(255, 75, 90),
		Color3.fromRGB(255, 166, 65),
		Color3.fromRGB(255, 235, 80),
		Color3.fromRGB(89, 255, 150),
		Color3.fromRGB(75, 225, 255),
		Color3.fromRGB(92, 125, 255),
		Color3.fromRGB(190, 90, 255),
		Color3.fromRGB(255, 75, 190),
		Color3.fromRGB(255, 75, 90),
	},
}

local DIFFICULTY_LABEL = {
	Easy = "EASY", Medium = "MEDIUM", Hard = "HARD", Impossible = "IMPOSSIBLE", Cosmic = "COSMIC",
}

local gui: ScreenGui? = nil
local ui = {}
local hideToken = 0
local loop: RBXScriptConnection? = nil

-- Hard deadline for the banner, in os.clock() seconds. The timed slide-up is
-- the NICE way out; this is the one that cannot be skipped. Anything that
-- re-enables the ScreenGui behind this module's back (BattleController's
-- suppressOtherGuis used to do exactly that) would otherwise leave the banner
-- up forever, because the hide timer for that showing has already run. The
-- watchdog re-checks every frame, so a banner past its deadline is switched off
-- no matter who switched it on.
local visibleUntil = 0
local watchdog: RBXScriptConnection? = nil

local function new(class: string, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function ink(thickness: number, transparency: number?)
	return new("UIStroke", { Color = INK, Thickness = thickness, Transparency = transparency or 0,
		LineJoinMode = Enum.LineJoinMode.Round })
end

local function tween(object, props, duration, style, direction, delay)
	local t = TweenService:Create(object, TweenInfo.new(duration, style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out, 0, false, delay or 0), props)
	t:Play()
	return t
end

----------------------------------------------------------------------
-- BUILD (once)
----------------------------------------------------------------------

local function build()
	if gui then
		return
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = new("ScreenGui", {
		Name = "BattleRewards",
		Parent = playerGui,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 110,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})

	if not watchdog then
		watchdog = RunService.Heartbeat:Connect(function()
			local g = gui
			if g and g.Enabled and os.clock() > visibleUntil then
				g.Enabled = false
			end
		end)
	end

	-- Layout container only. There is deliberately NO modal rectangle behind it.
	local root = new("Frame", {
		Parent = gui,
		Name = "RewardPresentation",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.022),
		Size = UDim2.fromOffset(ROOT_W, TILES_Y + TILE_H + 60),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	ui.root = root
	ui.scale = new("UIScale", { Parent = root, Name = "PopScale", Scale = 1 })

	-- THE LIGHT behind the header: a warm bloom and a ray burst that turns.
	ui.bloom = new("ImageLabel", {
		Parent = root, Name = "Bloom", BackgroundTransparency = 1, Image = VfxAssets.Glow,
		ImageColor3 = GOLD, ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, HEADER_H / 2 + 8), Size = UDim2.fromOffset(820, 460), ZIndex = 1,
	})
	ui.rays = new("ImageLabel", {
		Parent = root, Name = "Rays", BackgroundTransparency = 1, Image = VfxAssets.Burst,
		ImageColor3 = Color3.fromRGB(255, 232, 170), ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, HEADER_H / 2 + 8), Size = UDim2.fromOffset(620, 620), ZIndex = 1,
	})

	-- THE HEADER
	local header = new("Frame", {
		Parent = root, Name = "BattleWonHeader", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(HEADER_W, HEADER_H),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.02, ZIndex = 3,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 20) }),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(PANEL_TOP, PANEL_BOTTOM) }),
	})
	ui.header = header
	Shine.applySpec(header, RAINBOW_BORDER, HEADER_W, "BattleWonRainbow")
	ui.headerScale = new("UIScale", { Parent = header, Scale = 1 })

	-- a faint sheen across the top of the glass
	new("Frame", {
		Parent = header, Name = "Sheen", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 56), ZIndex = 3,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 20) }),
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.94, 1) }),
	})

	ui.flash = new("Frame", {
		Parent = header, Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 9,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 20) }) })

	-- Title. The gradient is gold with a bright band in the middle; sliding its
	-- Offset across the word is the shimmer.
	ui.title = new("TextLabel", {
		Parent = header, Name = "Title", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.new(1, -140, 0, 60),
		Text = "BATTLE WON", FontFace = Theme.font(), TextSize = 54, TextColor3 = WHITE, ZIndex = 6,
	}, { ink(3.5) })
	ui.titleShine = new("UIGradient", {
		Parent = ui.title, Rotation = 18,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, GOLD_DEEP),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 236, 170)),
			ColorSequenceKeypoint.new(0.5, WHITE),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 236, 170)),
			ColorSequenceKeypoint.new(1, GOLD_DEEP),
		}),
		Offset = Vector2.new(-1, 0),
	})

	-- A star either side of the title, placed from the title's real text width.
	ui.stars = {}
	for i, side in ipairs({ -1, 1 }) do
		local star = new("ImageLabel", {
			Parent = header, Name = "Star" .. i, BackgroundTransparency = 1, Image = VfxAssets.Spark,
			ImageColor3 = GOLD, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, side * 190, 0, 42), Size = UDim2.fromOffset(46, 46), ZIndex = 7,
		})
		table.insert(ui.stars, { image = star, side = side, phase = i * 1.7 })
	end

	-- What was cleared.
	ui.chip = new("Frame", {
		Parent = header, Name = "Chip", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = INK, BackgroundTransparency = 0.2, ZIndex = 6,
	}, {
		new("UICorner", { CornerRadius = UDim.new(1, 0) }),
		new("UIStroke", { Color = GOLD, Transparency = 0.3, Thickness = 1 }),
		new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
	})
	ui.chipText = new("TextLabel", {
		Parent = ui.chip, BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X, Text = "", FontFace = Theme.font(), TextSize = 14,
		TextColor3 = GOLD, ZIndex = 7,
	})

	-- THE TILES
	ui.tileRow = new("Frame", {
		Parent = root, Name = "Tiles", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TILES_Y), Size = UDim2.new(1, -28, 0, TILE_H + 16),
		BackgroundTransparency = 1, ZIndex = 3,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, TILE_GAP),
			HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	ui.footer = new("TextLabel", {
		Parent = root, Name = "Footer", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TILES_Y + TILE_H + 24), Size = UDim2.new(1, 0, 0, 20),
		Text = "REWARDS ADDED TO YOUR BACKPACK", FontFace = Theme.font(), TextSize = 15,
		TextColor3 = MUTED, ZIndex = 3,
	}, { ink(2, 0.2) })
end

----------------------------------------------------------------------
-- TILES
----------------------------------------------------------------------

local function makeTile(reward, order: number)
	local variant = VariantConfig.get(reward.variant or "Standard")
	local accent = variant.color
	local isUnlock = reward.unlockLabel ~= nil

	-- The holder is what the layout places and what pops in; the tile inside
	-- carries the art, so the rarity Shine is never scaled out of step with it.
	local holder = new("Frame", {
		Parent = ui.tileRow, Name = reward.kind or "Reward", LayoutOrder = order,
		Size = UDim2.fromOffset(TILE_W, TILE_H), BackgroundTransparency = 1, ZIndex = 4,
	})
	local pop = new("UIScale", { Parent = holder, Scale = 0 })

	-- the tile's own light, spilling out behind it
	local glow = new("ImageLabel", {
		Parent = holder, Name = "Glow", BackgroundTransparency = 1, Image = VfxAssets.Glow,
		ImageColor3 = accent, ImageTransparency = 0.72, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.9, 1.7), ZIndex = 3,
	})

	local tile = new("Frame", {
		Parent = holder, Name = "Tile", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE, ClipsDescendants = false, ZIndex = 4,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 18) }),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(
			accent:Lerp(Color3.fromRGB(15, 15, 24), 0.72), Color3.fromRGB(10, 10, 18)) }),
		new("UIStroke", { Name = "TileEdge", Color = accent, Thickness = 2, Transparency = 0.1 }),
	})
	-- Same renderer and same rarity data as actual cards.
	Shine.apply(tile, variant.id, TILE_W)

	local flash = new("Frame", {
		Parent = tile, Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 10,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 18) }) })

	-- ICON
	local glyph = new("TextLabel", {
		Parent = tile, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.fromScale(0.56, 0.44),
		Text = reward.glyph or "\u{25C9}", FontFace = Theme.font(), TextScaled = true,
		TextColor3 = accent, ZIndex = 6,
	})

	-- Elder Coins get the modelled coin. The kind decides it, not the glyph
	-- string, so the server can keep sending its fallback character.
	if reward.kind == "ElderCoins" then
		glyph.Visible = false
		ElderCoin.attach(tile, { Position = UDim2.fromScale(0.5, 0.43), Size = UDim2.fromOffset(84, 84), ZIndex = 6 })
	end

	if reward.icon and reward.icon ~= "" then
		glyph.Visible = false
		local art = new("ImageLabel", {
			Parent = tile, Name = "Art", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			-- An unlock announces a CARD, so it gets the card's proportions and
			-- fills the tile rather than the small pictogram a currency uses.
			Position = UDim2.fromScale(0.5, isUnlock and 0.5 or 0.43),
			Size = isUnlock and UDim2.fromScale(1, 1) or UDim2.fromScale(0.72, 0.56),
			ScaleType = isUnlock and Enum.ScaleType.Crop or Enum.ScaleType.Fit, ZIndex = 6,
		}, { new("UICorner", { CornerRadius = UDim.new(0, 18) }) })
		-- Through ArtLoader: a cold-cache failure must not leave a blank face.
		ArtLoader.set(art, reward.icon)
	end

	-- A Summon Core's art is shared by every level of its family, so the level
	-- is drawn on top, the same way the Backpack does.
	local stage = if reward.kind == "SummonCore" then SummonCoreConfig.get(reward.id) else nil
	if stage then
		new("TextLabel", {
			Parent = tile, Name = "CoreLevel", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(0.86, 0, 0.74, 0), Size = UDim2.fromOffset(56, 30),
			Text = stage.numeral, FontFace = Theme.font(), TextSize = 28, TextColor3 = stage.colour,
			TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 8,
		}, { ink(3) })
	end

	if isUnlock then
		-- The band sits ON the artwork: "this is now yours to roll", not one more
		-- payout. Scrimmed, because card art is busy.
		local band = new("Frame", {
			Parent = tile, Name = "UnlockBand", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = INK, BackgroundTransparency = 0.14, ZIndex = 8,
		}, {
			new("UIGradient", { Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.14, 0),
				NumberSequenceKeypoint.new(0.86, 0), NumberSequenceKeypoint.new(1, 1) }) }),
		})
		local unlockText = new("TextLabel", {
			Parent = band, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
			Text = reward.unlockLabel, FontFace = Theme.font(), TextSize = 17, TextColor3 = WHITE, ZIndex = 9,
		}, { ink(2.5) })
		TextShine.apply(unlockText, "Transcendent")
	end

	-- rarity badge
	local badge = new("TextLabel", {
		Parent = tile, BackgroundColor3 = Color3.fromRGB(12, 12, 20), BackgroundTransparency = 0.12,
		Position = UDim2.fromOffset(7, 7), Size = UDim2.fromOffset(22, 22), Text = variant.label,
		FontFace = Theme.font(), TextSize = 12, TextColor3 = accent, ZIndex = 7,
	}, {
		new("UICorner", { CornerRadius = UDim.new(1, 0) }),
		new("UIStroke", { Color = accent, Thickness = 1, Transparency = 0.28 }),
	})
	TextShine.apply(badge, variant.id)

	-- An unlock is not a quantity: it says NEW instead of "x1".
	new("TextLabel", {
		Parent = tile, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -9, 0, 7), Size = UDim2.fromOffset(90, 22),
		Text = isUnlock and "NEW" or ("x" .. Format.comma(reward.amount or 1)),
		FontFace = Theme.font(), TextSize = 17, TextColor3 = isUnlock and NEW_GREEN or WHITE,
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 8,
	}, { ink(2.5) })

	new("TextLabel", {
		Parent = tile, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -9), Size = UDim2.new(1, -12, 0, 18),
		Text = reward.name or "Reward", FontFace = Theme.font(), TextSize = 15, TextScaled = true,
		TextColor3 = Color3.fromRGB(232, 234, 248), ZIndex = 8,
	}, {
		new("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 15 }),
		ink(2),
	})

	return { holder = holder, pop = pop, flash = flash, glow = glow }
end

----------------------------------------------------------------------
-- MOTION
----------------------------------------------------------------------

local function stopLoop()
	if loop then
		loop:Disconnect()
		loop = nil
	end
end

-- Everything that keeps moving while the banner is up: the rays turn, the
-- bloom breathes, the stars twinkle and a shimmer runs through the title.
local function startLoop()
	stopLoop()
	local started = os.clock()
	loop = RunService.Heartbeat:Connect(function()
		if not (gui and gui.Enabled) then
			stopLoop()
			return
		end
		local t = os.clock() - started
		ui.rays.Rotation = (t * 10) % 360
		if t > 0.6 then
			ui.bloom.ImageTransparency = 0.3 + 0.08 * math.sin(t * 2.2)
		end
		for _, star in ipairs(ui.stars) do
			local s = 0.5 + 0.5 * math.sin(t * 3.2 + star.phase)
			star.image.Rotation = star.side * t * 40
			star.image.Size = UDim2.fromOffset(34 + 18 * s, 34 + 18 * s)
			star.image.ImageTransparency = 0.25 * (1 - s)
		end
		-- a sweep every 2.4s, crossing the word in the first 0.9s of it
		local cycle = (t % 2.4) / 0.9
		ui.titleShine.Offset = Vector2.new(math.clamp(cycle, 0, 1) * 2 - 1, 0)
	end)
end

local function chipText(event, coinsTotal: number): string
	local difficulty = event.difficulty and (DIFFICULTY_LABEL[event.difficulty] or string.upper(tostring(event.difficulty)))
	if difficulty and event.firstClear then
		return "FIRST CLEAR  \u{2022}  " .. difficulty
	elseif difficulty then
		return difficulty .. " CLEARED"
	elseif coinsTotal > 0 then
		return ("+%s ELDER COINS"):format(Format.comma(coinsTotal))
	end
	return "VICTORY"
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function RewardPopup.Show(event)
	if not event or event.won ~= true then
		return
	end

	local rewards = event.rewards
	if type(rewards) ~= "table" or #rewards == 0 then
		return
	end

	build()

	for _, child in ipairs(ui.tileRow:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local coinsTotal = 0
	local tiles = {}
	for index, reward in ipairs(rewards) do
		if reward.kind == "ElderCoins" then
			coinsTotal += reward.amount or 0
		end
		table.insert(tiles, makeTile(reward, index))
	end

	-- More tiles than the row is wide: shrink the row rather than letting it run
	-- off both edges. Recreated every showing, because the loop above clears it.
	local needed = #rewards * TILE_W + math.max(0, #rewards - 1) * TILE_GAP
	new("UIScale", {
		Parent = ui.tileRow, Name = "RowScale",
		Scale = math.min(1, (ROOT_W - 28) / math.max(needed, 1)),
	})

	ui.chipText.Text = chipText(event, coinsTotal)

	-- Narrow screens: the whole banner shrinks to fit rather than clipping.
	local screenW = gui.AbsoluteSize.X > 0 and gui.AbsoluteSize.X or 1280
	local fitScale = math.clamp((screenW - 24) / ROOT_W, 0.45, 1)

	-- Set BEFORE the ScreenGui goes up, so the watchdog never sees an enabled
	-- banner with a stale deadline. The extra covers the slide-out tween.
	visibleUntil = os.clock() + SHOW_SECONDS + 0.5
	gui.Enabled = true

	-- ENTRANCE
	local root = ui.root
	ui.scale.Scale = fitScale * 0.86
	tween(ui.scale, { Scale = fitScale }, 0.42, Enum.EasingStyle.Back)
	root.Position = UDim2.fromScale(0.5, -0.04)
	tween(root, { Position = UDim2.fromScale(0.5, 0.022) }, 0.36, Enum.EasingStyle.Quint)

	ui.flash.BackgroundTransparency = 0.35
	tween(ui.flash, { BackgroundTransparency = 1 }, 0.5)
	ui.headerScale.Scale = 1.06
	tween(ui.headerScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Elastic)

	ui.bloom.ImageTransparency = 1
	tween(ui.bloom, { ImageTransparency = 0.3 }, 0.6)
	ui.rays.ImageTransparency = 1
	tween(ui.rays, { ImageTransparency = 0.62 }, 0.8)

	ui.chip.Size = UDim2.fromOffset(0, 26)
	ui.footer.TextTransparency = 1
	tween(ui.footer, { TextTransparency = 0 }, 0.4, nil, nil, 0.35 + #tiles * 0.09)

	-- Tiles are dealt in one after another, each landing with a flash.
	for i, t in ipairs(tiles) do
		local delay = 0.28 + (i - 1) * 0.09
		t.pop.Scale = 0
		tween(t.pop, { Scale = 1 }, 0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delay)
		t.flash.BackgroundTransparency = 0.25
		tween(t.flash, { BackgroundTransparency = 1 }, 0.45, nil, nil, delay + 0.12)
		t.glow.ImageTransparency = 1
		tween(t.glow, { ImageTransparency = 0.72 }, 0.5, nil, nil, delay)
	end

	startLoop()

	hideToken += 1
	local token = hideToken
	task.delay(SHOW_SECONDS, function()
		if hideToken ~= token or not gui then
			return
		end
		tween(ui.bloom, { ImageTransparency = 1 }, 0.25, nil, Enum.EasingDirection.In)
		tween(ui.rays, { ImageTransparency = 1 }, 0.25, nil, Enum.EasingDirection.In)
		local out = tween(root, { Position = UDim2.fromScale(0.5, -0.08) }, 0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		out.Completed:Once(function()
			if hideToken == token and gui then
				gui.Enabled = false
				stopLoop()
			end
		end)
	end)
end

function RewardPopup.Hide()
	hideToken += 1
	visibleUntil = 0
	stopLoop()
	if gui then
		gui.Enabled = false
	end
end

return RewardPopup
