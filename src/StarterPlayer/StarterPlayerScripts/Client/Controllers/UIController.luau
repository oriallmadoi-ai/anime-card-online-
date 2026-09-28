--!strict
-- Lobby HUD. Overlays the 3D world and must never cover it.
--
-- Layout follows the genre convention: navigation down the left, roll controls
-- pinned bottom-centre where they are always reachable, stats along the top.
--
-- Nav buttons are an icon plus a caption, both INSIDE one square button face:
-- the icon fills the upper part, the label sits in a reserved band along the
-- bottom. The caption used to hang below the button in the gap between cells,
-- which read as a floating word rather than as part of the control. Every icon
-- is given the same square cell and scaled to fit, so mismatched source
-- resolutions still line up.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local Sfx = require(ReplicatedStorage.Shared.UI.Sfx)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local ArtLoader = require(ReplicatedStorage.Shared.UI.ArtLoader)
local UITheme = require(ReplicatedStorage.Shared.UI.UITheme)
local MenuConfig = require(ReplicatedStorage.Shared.Config.MenuConfig)

local player = Players.LocalPlayer

local UIController = {}
UIController.Name = "UIController"

-- Neutral, not navy. The HUD chrome had drifted blue - navy plates, a blue
-- accent, blue-tinted "white" text - which fought the game's own palette
-- (red/green/gold cards, a purple sky). Greys and blacks stay out of the way
-- and let the per-feature accent colours be the only colour on screen.
local PANEL  = Color3.fromRGB(18, 18, 21)
-- One text colour across every menu, from UITheme. See MenuController.
local TEXT   = UITheme.Text
local MUTED  = UITheme.TextMuted
local ACCENT = Color3.fromRGB(142, 142, 148)
local GOLD   = Color3.fromRGB(255, 216, 140)

-- Order here is the order on screen.
-- Highlight that slides across each button face.
local SWEEP_IMAGE = "rbxassetid://135060446578504"

-- Existing feature artwork and accent colours remain the navigation identity.
-- The HUD treatment below only changes presentation and interaction feedback.
local NAV = {
	{ id = "Deck",       label = "Deck",        image = "rbxassetid://107383168454655", glow = Color3.fromRGB(239, 53, 78) },
	-- Steel, not the blue this icon would otherwise suggest. The HUD is
	-- deliberately blue-free, so the two blue features take neutral accents.
	{ id = "Backpack",   label = "Backpack",    image = "rbxassetid://97534595040988",  glow = Color3.fromRGB(178, 182, 190) },
	{ id = "Quests",     label = "Quests",      image = "rbxassetid://77987610643269",  glow = Color3.fromRGB(93, 218, 70) },
	{ id = "BattlePass", label = "Battle Pass", image = "rbxassetid://107867939390433", glow = Color3.fromRGB(110, 218, 69) },
	{ id = "Teleport",   label = "Teleport",    image = "rbxassetid://116662081402516", glow = Color3.fromRGB(255, 177, 31) },
	{ id = "Store",      label = "Shop",        image = "rbxassetid://81589496518912",  glow = Color3.fromRGB(164, 87, 255) },

	-- Same button as every other one on this rail - same face, same text, same
	-- sweep - with a white border, because the cloud is white. The icon is read
	-- from MenuConfig so the rail and the window header can never show two
	-- different pictures for the same feature.
	{ id = "Mounts",     label = "Mounts",      image = MenuConfig.MountIcon,           glow = Color3.fromRGB(255, 255, 255) },

	-- Skill Tree keeps its existing image and its own specialised full-screen UI.
	{ id = "SkillTree",  label = "Skill Tree",  image = "rbxassetid://87024386633723", glow = Color3.fromRGB(140, 144, 152) },

	{ id = "Settings",   label = "Settings",    image = "rbxassetid://86261752940686",  glow = Color3.fromRGB(255, 139, 27) },
	{ id = "Codes",      label = "Codes",       image = "rbxassetid://123936473099980", glow = Color3.fromRGB(238, 67, 201) },
}
local profile = nil
local rollBusy = false
local autoRoll = false
local quickRoll = false

local gui, panelRoot, panelTitle, panelBody
local statRolls, statLuck, statName, announceBar, toastLabel
local rollButton, autoButton, quickButton, luckyLabel, luckyFill, luckyStroke
local toastVersion, announcementVersion = 0, 0
local toastTween, toastStrokeTween
local sweeps = {}

local function new(class: string, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end

local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function stroke(c, t) return new("UIStroke", { Color = c, Thickness = t or 2 }) end
local function pad(n)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, n), PaddingBottom = UDim.new(0, n),
		PaddingLeft = UDim.new(0, n), PaddingRight = UDim.new(0, n),
	})
end
local function label(props)
	local d = { BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = Theme.font(), TextColor3 = TEXT,
		TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in pairs(props) do d[k] = v end
	return new("TextLabel", d)
end

-- A local HUD treatment: this never changes the shared Deck or Skill Tree styles.
local function surface(object, tint: Color3, radius: number)
	object.BackgroundColor3 = Color3.new(1, 1, 1)
	object.BackgroundTransparency = 0.12
	object.BorderSizePixel = 0
	corner(radius).Parent = object
	local border = new("UIStroke", { Parent = object, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = tint, Thickness = 1, Transparency = 0.48 })
	-- A UIGradient on a TextLabel also tints its text, so notification text
	-- keeps a solid navy plate and its original readable foreground colour.
	if object:IsA("TextLabel") then
		object.BackgroundColor3 = PANEL
	else
		new("UIGradient", { Parent = object, Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(32, 32, 35), Color3.fromRGB(12, 12, 14)) })
	end
	return border
end

local function bindScaleFeedback(button, scale, baseScale: number)
	local hovering = false
	local activeTween
	local function to(value, duration)
		if activeTween then activeTween:Cancel() end
		activeTween = TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out), { Scale = baseScale * value })
		activeTween:Play()
	end
	button.AutoButtonColor = false
	button.MouseEnter:Connect(function() hovering = true; to(1.035, 0.14) end)
	button.MouseLeave:Connect(function() hovering = false; to(1, 0.16) end)
	button.SelectionGained:Connect(function() hovering = true; to(1.035, 0.14) end)
	button.SelectionLost:Connect(function() hovering = false; to(1, 0.16) end)
	button.MouseButton1Down:Connect(function() to(0.965, 0.07) end)
	button.MouseButton1Up:Connect(function() to(hovering and 1.035 or 1, 0.16) end)
end

function UIController:IsQuickRoll(): boolean
	return quickRoll
end

function UIController:Toast(text: string)
	if not toastLabel then return end
	toastVersion += 1
	local version = toastVersion
	if toastTween then toastTween:Cancel() end
	if toastStrokeTween then toastStrokeTween:Cancel() end
	toastLabel.Text = text
	toastLabel.Visible = true
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.12
	toastLabel.Position = UDim2.new(0.5, 0, 0, 108)
	local border = toastLabel:FindFirstChildOfClass("UIStroke")
	if border then border.Transparency = 0.48 end
	toastTween = TweenService:Create(toastLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 98) })
	toastTween:Play()
	task.delay(2.8, function()
		if version ~= toastVersion or not toastLabel.Parent then return end
		toastTween = TweenService:Create(toastLabel, TweenInfo.new(0.3),
			{ TextTransparency = 1, BackgroundTransparency = 1 })
		toastTween:Play()
		if border then
			toastStrokeTween = TweenService:Create(border, TweenInfo.new(0.3), { Transparency = 1 })
			toastStrokeTween:Play()
		end
		task.delay(0.3, function()
			if version == toastVersion then toastLabel.Visible = false end
		end)
	end)
end

-- ── panels ─────────────────────────────────────────────────

function UIController:ClosePanel()
	panelRoot.Visible = false
end

function UIController:OpenPanel(title: string)
	for _, c in ipairs(panelBody:GetChildren()) do
		if not (c:IsA("UIGridLayout") or c:IsA("UIListLayout")) then c:Destroy() end
	end
	panelTitle.Text = title:upper()
	panelRoot.Visible = true
	return panelBody
end

-- The Deck is where owned cards live.
function UIController:OpenScreen(id: string)
	if id == "Deck" then
		local menus = self.Controllers and self.Controllers.MenuController
		if menus and menus.CloseAll then menus:CloseAll() end
		local deck = self.Controllers and self.Controllers.DeckController
		if deck then deck:Open() end
		return
	end

	-- The skill tree is its own full-screen UI for the same reason the Deck is:
	-- a branching diagram needs the whole viewport, not the ~70% a menu window
	-- leaves once its header and tab scaffold are in place.
	if id == "SkillTree" then
		local menus = self.Controllers and self.Controllers.MenuController
		if menus and menus.CloseAll then menus:CloseAll() end
		local tree = self.Controllers and self.Controllers.SkillTreeController
		if tree then tree:Toggle() end
		return
	end
	-- Everything else is handled by MenuController, which opens its own window
	-- for each sidebar button. The old "isn't built yet" notice dates from
	-- before those windows existed and would now fire alongside a menu that
	-- opens perfectly well.
end

function UIController:RefreshStats()
	if not profile then return end
	statRolls.Text = Format.comma(profile.stats.totalRolls)

	if luckyLabel then
		local every = GameConfig.LuckyRollEvery
		local done = profile.stats.totalRolls % every
		local ready = (done + 1) == every
		if luckyFill then
			TweenService:Create(luckyFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out), { Size = UDim2.new(ready and 1 or done / every, 0, 1, 0) }):Play()
		end
		if luckyStroke then luckyStroke.Color = ready and Color3.fromRGB(121, 255, 185) or ACCENT end
		luckyLabel.TextColor3 = ready and Color3.fromRGB(160, 255, 198) or Color3.fromRGB(195, 215, 255)
		if ready then
			-- The next roll is lucky at 9, 19, 29, ... completed rolls.
			luckyLabel.Text = ("LUCKY ROLL READY  %dx LUCK"):format(GameConfig.LuckyRollMultiplier)
		else
			luckyLabel.Text = ("%d / %d TO LUCKY ROLL"):format(done, every)
		end
	end
	statLuck.Text = ("%.2fx"):format(1 + (profile.upgrades.luck or 0) * GameConfig.LuckPerLevel)
end

function UIController:Announce(data)
	-- Two shapes go through this bar. A ROLL announcement carries cardId/variant
	-- and gets wrapped in "<who> rolled <tier> <card>". Anything carrying
	-- `message` is shown verbatim instead - admin command results, and anything
	-- else that needs the bar without pretending to be a pull.
	if data.message then
		announceBar.Text = data.message
		announceBar.TextColor3 = GOLD
	else
		local def = CardDefinitions.get(data.cardId)
		local variant = VariantConfig.get(data.variant)
		announceBar.Text = ("%s rolled %s %s"):format(
			data.player, variant.display, def and def.name or data.cardId)
		announceBar.TextColor3 = variant.rank > 1 and variant.color or GOLD
	end
	announcementVersion += 1
	local version = announcementVersion
	announceBar.Visible = true
	announceBar.Position = UDim2.new(0.5, 0, 0, 57)
	TweenService:Create(announceBar, TweenInfo.new(0.25, Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 66) }):Play()
	task.delay(6, function()
		if version == announcementVersion then announceBar.Visible = false end
	end)
end

function UIController:DoRoll()
	if rollBusy then return end
	rollBusy = true
	rollButton.TextTransparency = 0.55
	Remotes.RequestRoll:FireServer()

	local cd = GameConfig.BaseRollCooldown
	if profile then
		cd = math.max(GameConfig.MinRollCooldown,
			GameConfig.BaseRollCooldown * (1 - (profile.upgrades.rollSpeed or 0) * GameConfig.RollSpeedPerLevel))
	end
	task.delay(cd, function()
		rollBusy = false
		rollButton.TextTransparency = 0
	end)
end

-- ── build ──────────────────────────────────────────────────

function UIController:Init()
	local playerGui = player:WaitForChild("PlayerGui")

	-- Download the navigation artwork before exposing the HUD. Without this,
	-- freshly joined clients briefly see empty button faces while Roblox fetches
	-- each image. The callback also makes a permanently unavailable asset obvious
	-- in the client log instead of silently leaving a blank icon.
	local preloadIcons = {}
	for _, item in ipairs(NAV) do
		local preloadIcon = Instance.new("ImageLabel")
		preloadIcon.Name = "Preload_" .. item.id
		preloadIcon.Image = item.image
		preloadIcon.Visible = false
		preloadIcon.Parent = playerGui
		preloadIcons[#preloadIcons + 1] = preloadIcon
	end
	-- OFF THE CRITICAL PATH, DELIBERATELY.
	--
	-- PreloadAsync yields until every asset resolves, and Bootstrap runs each
	-- controller's Init one after another on a single thread. So while this
	-- waited, NOTHING else on the client existed: no HUD, no battle screen, no
	-- overworld encounter cards. On a cold cache or a slow CDN that is a minute
	-- of the player staring at an empty game, and if an icon never resolves it
	-- never loads at all.
	--
	-- Spawned instead, so Init returns immediately and the rest of the client
	-- boots. The cost is that a nav button can show an empty face for the first
	-- moment, which is strictly better than the game not starting.
	task.spawn(function()
		local preloadOk, preloadError = pcall(function()
			ContentProvider:PreloadAsync(preloadIcons, function(assetId, status)
				if status == Enum.AssetFetchStatus.Failure then
					warn(("[UI] Failed to preload navigation icon %s"):format(assetId))
				end
			end)
		end)
		for _, preloadIcon in ipairs(preloadIcons) do
			preloadIcon:Destroy()
		end
		if not preloadOk then
			warn(("[UI] Navigation icon preload failed: %s"):format(tostring(preloadError)))
		end
	end)

	-- Card and support artwork, warmed on the same terms: spawned, so it never
	-- delays the HUD. This is what stops the scattered blank faces - a tile or a
	-- battle portrait drawn later hits a cache that is already hot, instead of
	-- racing a cold fetch that Roblox will not retry if it loses.
	task.spawn(function()
		local ok, err = pcall(function()
			ArtLoader.warm(ArtLoader.cardArtIds())
		end)
		if not ok then
			warn(("[UI] Card art preload failed: %s"):format(tostring(err)))
		end
	end)

	gui = new("ScreenGui", {
		Name = "CardClashHUD", Parent = player:WaitForChild("PlayerGui"),
		ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
	})
	-- No background frame: the lobby stays visible behind the HUD.

	-- top stats
	local top = new("Frame", { Parent = gui, Name = "Stats", Position = UDim2.new(0, 180, 0, 14),
		Size = UDim2.new(0, 366, 0, 48), BackgroundTransparency = 1 },
	{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local function chip(order, title, tint)
		local f = new("Frame", { Parent = top, Name = title, Size = UDim2.new(0, 116, 1, 0),
			LayoutOrder = order })
		surface(f, tint, 12)
		new("Frame", { Parent = f, BorderSizePixel = 0, BackgroundColor3 = tint,
			Position = UDim2.new(0, 10, 0, 12), Size = UDim2.new(0, 3, 1, -24) }, { corner(2) })
		label({ Parent = f, Position = UDim2.new(0, 22, 0, 7), Size = UDim2.new(1, -29, 0, 11),
			Text = title, TextSize = 9, TextColor3 = MUTED })
		return label({ Parent = f, Position = UDim2.new(0, 22, 0, 22),
			Size = UDim2.new(1, -29, 0, 19), Text = "0", TextSize = 17,
			TextTruncate = Enum.TextTruncate.AtEnd })
	end
	statRolls = chip(1, "TOTAL ROLLS", Color3.fromRGB(176, 176, 182))
	statLuck = chip(2, "LUCK", Color3.fromRGB(132, 240, 176))
	statName = chip(3, "PLAYER", Color3.fromRGB(180, 153, 255))
	statName.Text = player.Name

	announceBar = label({ Parent = gui, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66), Size = UDim2.new(0.52, 0, 0, 32), Text = "",
		TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = false, ZIndex = 8 })
	surface(announceBar, GOLD, 10)
	new("UIPadding", { Parent = announceBar, PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) })

	toastLabel = label({ Parent = gui, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 98), Size = UDim2.new(0.42, 0, 0, 38), Text = "",
		TextSize = 14, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true, Visible = false, ZIndex = 9 })
	surface(toastLabel, GOLD, 12)
	new("UIPadding", { Parent = toastLabel, PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) })

	----------------------------------------------------------------
	-- left navigation: image-only buttons, uniform cells
	----------------------------------------------------------------
	-- CELL is the whole button now, not just its icon. The caption moved INSIDE
	-- the button, so LABEL_H is a band reserved within the face rather than extra
	-- height stacked underneath it - which is why the cell height is plain CELL
	-- and no longer CELL + LABEL_H.
	local CELL = 66
	local LABEL_H = 20
	local GAP = 10

	local navWidth = CELL * 2 + GAP
	local navHeight = math.ceil(#NAV / 2) * (CELL + GAP) - GAP

	local nav = new("Frame", { Parent = gui, Name = "Navigation", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 20),
		Size = UDim2.new(0, navWidth, 0, navHeight),
		BackgroundTransparency = 1 },
	{ new("UIGridLayout", {
		CellSize = UDim2.new(0, CELL, 0, CELL),
		CellPadding = UDim2.new(0, GAP, 0, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder }) })

	-- Each button gets the same animated border as the cards, tinted to its own
	-- colour, over its own translucent box. One shared panel behind the whole
	-- column flattened them into a single block; a box per button keeps each one
	-- reading as a separate control.
	local function borderSpec(colour: Color3)
		local lighter = colour:Lerp(Color3.new(1, 1, 1), 0.5)
		local darker = colour:Lerp(Color3.new(0, 0, 0), 0.35)
		return {
			baseColour = colour,
			baseThickness = 2,
			baseTransparency = 0.3,
			-- First and last must match or the gradient jumps on each wrap.
			glowColours = { colour, lighter, darker, lighter, colour },
			travel = 3,
			corner = 12,
		}
	end

	for i, item in ipairs(NAV) do
		local holder = new("Frame", {
			Parent = nav, LayoutOrder = i, BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
		})


		-- ONE layer of chrome, not four.
		--
		-- This used to be a translucent navy panel, a blue-to-tint gradient, a
		-- navy caption plate and a tinted edge light all stacked around a 66px
		-- icon. Now it is a single dark glass plate: neutral grey top to near
		-- black bottom, translucent enough that the world reads through it, so
		-- the icon has something to sit on without the column turning into nine
		-- coloured boxes.
		--
		-- ClipsDescendants keeps the light sweep inside the face. Strokes render
		-- outside the element, so the rarity border is unaffected.
		local btn = new("ImageButton", {
			Parent = holder, Name = item.id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
			BackgroundTransparency = 0.26,
			Image = "",
			AutoButtonColor = false, ClipsDescendants = true,
		}, { new("UICorner", { CornerRadius = UDim.new(0, 12) }) })
		new("UIGradient", {
			Parent = btn,
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(64, 64, 70), Color3.fromRGB(13, 13, 16)),
		})
		local holderScale = new("UIScale", { Parent = btn, Scale = 1 })

		-- The icon fills nearly the whole face - 2px of plate showing all round,
		-- just enough to read as a frame. It used to be shortened by LABEL_H to
		-- keep a clear band for the caption, which left the artwork small in a
		-- big empty box. The caption sits over the bottom of it instead, with an
		-- outline heavy enough to stay readable against the art.
		new("ImageLabel", {
			Parent = btn, Name = "Icon", BackgroundTransparency = 1,
			Image = item.image, ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.new(0, 2, 0, 2),
			Size = UDim2.new(1, -4, 1, -4),
			ZIndex = 2,
		})

		-- CELL is passed explicitly: a button styled before its first layout
		-- reports a size of zero, which would size the glow off a fallback.
		Shine.applySpec(btn, borderSpec(item.glow), CELL, "nav:" .. item.id)

		-- A narrow highlight that slides across the face, like light catching
		-- glass. Kept faint and infrequent: nine buttons sweeping constantly
		-- would pull attention away from whatever the player is actually doing.
		-- NOT rotated. A rotated GuiObject ignores its parent's ClipsDescendants,
		-- so a tilted sweep escaped the button and streaked across the lobby.
		-- Any slant has to come from the source image instead.
		local sweep = new("ImageLabel", {
			Parent = btn, Name = "Sweep", BackgroundTransparency = 1,
			Image = SWEEP_IMAGE, ImageTransparency = 0.78,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(-0.4, 0, 0.5, 0),
			Size = UDim2.new(0.5, 0, 1, 0),
			ScaleType = Enum.ScaleType.Stretch, ZIndex = 3,
		})

		-- Every button sweeps together, so the column reads as one surface catching
		-- light rather than nine separate blinking controls. No stagger: the
		-- tweens are created in the same frame and share a duration, so they stay
		-- locked in step for as long as they run.
		sweeps[#sweeps + 1] = sweep

		-- Sits over the bottom of the icon. ZIndex 4 puts it above the sweep at 3,
		-- so the light passes behind the word instead of washing it out.
		local caption = new("TextLabel", {
			Parent = btn, AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.new(1, -6, 0, LABEL_H),
			BackgroundTransparency = 1, Text = item.label,
			FontFace = Theme.font(), TextSize = 12,
			TextColor3 = Color3.fromRGB(242, 242, 244), TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		})
		-- TextScaled with a cap: "Battle Pass" is the longest caption and does not
		-- fit a 66px face at 12px, so it shrinks to fit while every shorter label
		-- stays at the authored size instead of ballooning to fill the band.
		new("UITextSizeConstraint", { Parent = caption, MinTextSize = 7, MaxTextSize = 12 })
		-- A heavy outline is the ONLY thing keeping the caption readable now, so
		-- it is solid and a little thicker than before.
		--
		-- It replaces a rectangular plate that used to sit behind the text. That
		-- plate was the black band poking out past the button's rounded corners:
		-- ClipsDescendants crops to the element's RECTANGLE, not to its UICorner,
		-- so a square child pinned to the bottom edge always squared off the two
		-- bottom corners. An outline has no corners to escape from.
		new("UIStroke", { Parent = caption, Color = Color3.new(0, 0, 0),
			Thickness = 2, Transparency = 0, LineJoinMode = Enum.LineJoinMode.Round })

		local activeScaleTween
		local function scaleTo(target: number, duration: number, style)
			if activeScaleTween then activeScaleTween:Cancel() end
			activeScaleTween = TweenService:Create(holderScale,
				TweenInfo.new(duration, style, Enum.EasingDirection.Out), { Scale = target })
			activeScaleTween:Play()
		end

		local hovering = false
		local function hover(active)
			hovering = active
			-- The plate solidifies under the pointer, which reads as the button
			-- lighting up rather than just growing.
			TweenService:Create(btn, TweenInfo.new(0.16),
				{ BackgroundTransparency = active and 0.08 or 0.26 }):Play()
			TweenService:Create(caption, TweenInfo.new(0.16),
				{ TextColor3 = active and Color3.new(1, 1, 1) or Color3.fromRGB(242, 242, 244) }):Play()
			scaleTo(active and 1.075 or 1, 0.16, Enum.EasingStyle.Quad)
		end
		btn.MouseEnter:Connect(function() hover(true) end)
		btn.MouseLeave:Connect(function() hover(false) end)
		btn.SelectionGained:Connect(function() hover(true) end)
		btn.SelectionLost:Connect(function() hover(false) end)
		Sfx.bindButton(btn)
		-- Touch never fires MouseEnter, so the press carries the feedback there.
		btn.MouseButton1Down:Connect(function()
			scaleTo(0.94, 0.07, Enum.EasingStyle.Quad)
		end)
		btn.MouseButton1Up:Connect(function()
			scaleTo(hovering and 1.075 or 1, 0.16, Enum.EasingStyle.Back)
		end)

		btn.Activated:Connect(function() self:OpenScreen(item.id) end)
	end

	----------------------------------------------------------------
	-- bottom roll bar
	----------------------------------------------------------------
	-- All three buttons are AUTHORED designs, not rebuilds. Each lives in its own
	-- disabled ScreenGui under StarterGui; at startup the TextButton is lifted out
	-- and reparented into the bar, keeping its artwork, strokes, corner and text
	-- exactly as drawn. Rebuilding them in code was the wrong instinct: the copy
	-- always drifts from the original.
	--
	-- Each sits inside a wrapper because the designs are 750x185 in fixed pixels.
	-- The wrapper is the size the layout should reserve, and a UIScale shrinks the
	-- button into it - scaling the button itself would leave its children at their
	-- original pixel sizes.
	--
	-- Auto and Quick are held smaller than Roll on purpose: Roll is the verb of
	-- the whole game, and three buttons at equal weight give the player nothing to
	-- aim at.
	local ROLL_W, ROLL_H = 300, 74
	local SIDE_W, SIDE_H = 190, 47
	local CAPTION_H = 20

	local bar = new("Frame", { Parent = gui, Name = "RollDock", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(0, 730, 0, 98),
		BackgroundTransparency = 1 },
	{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12), VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder }) })
	-- No dock plate. The three roll buttons are authored designs that already
	-- carry their own faces, so wrapping them in another rounded rectangle just
	-- put a big grey slab across the bottom of the screen. They float now and
	-- the layout alone groups them.

	-- Lifts an authored button out of its design ScreenGui into `seat`, scaled to
	-- `width`. Returns nil when the design is missing so callers can fall back.
	local function adopt(designName: string, seat: Instance, width: number)
		local design = playerGui:WaitForChild(designName, 10)
		local authored = design and design:FindFirstChild("roll")
		if not (authored and authored:IsA("TextButton")) then
			warn(("[UI] StarterGui.%s.roll not found - using a plain button"):format(designName))
			return nil
		end

		authored.Parent = seat
		authored.AnchorPoint = Vector2.new(0.5, 0.5)
		authored.Position = UDim2.new(0.5, 0, 0.5, 0)
		authored.ClipsDescendants = true

		-- Scale off the AUTHORED pixel width, never AbsoluteSize: a button styled
		-- before its first layout pass still reports a size of zero.
		local uiScale = authored:FindFirstChildOfClass("UIScale")
			or new("UIScale", { Parent = authored })
		if authored.Size.X.Offset > 0 then
			uiScale.Scale = width / authored.Size.X.Offset
		end

		local sweep = new("ImageLabel", {
			Parent = authored, Name = "Sweep", BackgroundTransparency = 1,
			Image = SWEEP_IMAGE, ImageTransparency = 0.78,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(-0.4, 0, 0.5, 0),
			Size = UDim2.new(0.22, 0, 1, 0), ScaleType = Enum.ScaleType.Stretch, ZIndex = 6,
		})
		sweeps[#sweeps + 1] = sweep

		Sfx.bindButton(authored)
		bindScaleFeedback(authored, uiScale, uiScale.Scale)
		return authored
	end

	-- Auto and Quick are toggles. The state used to live in a little chip pinned
	-- under each button, which meant two shapes for one control and a second
	-- thing that looked clickable but was not. The state now goes on the button's
	-- OWN label - "auto roll: ON" - so the thing you press is the thing that
	-- tells you what it is doing.
	--
	-- Which label that is differs per design: auto roll draws its text through a
	-- GradientText child (that child is what carries the rainbow), quick roll
	-- uses the button's own Text.
	local function sideButton(order: number, designName: string, fallbackText: string)
		local holder = new("Frame", { Parent = bar, LayoutOrder = order,
			Size = UDim2.new(0, SIDE_W, 1, 0), BackgroundTransparency = 1 })
		local seat = new("Frame", { Parent = holder, BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 0, SIDE_H) })

		local btn = adopt(designName, seat, SIDE_W)
		if not btn then
			btn = new("TextButton", { Parent = seat, Size = UDim2.new(1, 0, 1, 0),
				BackgroundColor3 = PANEL, BackgroundTransparency = 0.1,
				Text = fallbackText, TextSize = 13, TextColor3 = MUTED },
			{ corner(12), stroke(Color3.fromRGB(96, 96, 104), 2) })
		end

		local maxText = btn.TextSize
		local target = btn:FindFirstChild("GradientText")
		if not target then
			-- Quick roll draws its text on the BUTTON itself, and ClipsDescendants
			-- does not crop an object's own text - only its children. So the longer
			-- "quick roll: OFF" ran straight off both ends of the artwork. Moving it
			-- onto a child label fixes that and gives it something to be scaled
			-- against. The font comes off the button, so it keeps the authored
			-- family and its Bold weight - the same face the roll button uses.
			target = new("TextLabel", {
				Parent = btn, Name = "StateText", BackgroundTransparency = 1,
				Text = btn.Text, FontFace = btn.FontFace,
				TextColor3 = btn.TextColor3, ZIndex = 5,
			})
			new("UIStroke", { Parent = target, Color = Color3.new(0, 0, 0),
				Thickness = 2, Transparency = 0.35, LineJoinMode = Enum.LineJoinMode.Round })
			btn.Text = ""
		end

		-- BOTH labels get the same box and are scaled into it, which is what makes
		-- auto roll and quick roll come out the same size. They did not before:
		-- quick roll was scaled to fit its face while auto roll's GradientText
		-- auto-sized to its own text, so it rendered noticeably smaller. 88% of
		-- the face leaves a margin the artwork can breathe in while landing close
		-- to the weight of the roll button's own lettering.
		target.AutomaticSize = Enum.AutomaticSize.None
		target.AnchorPoint = Vector2.new(0.5, 0.5)
		target.Position = UDim2.fromScale(0.5, 0.5)
		target.Size = UDim2.new(0.88, 0, 0.66, 0)
		target.TextXAlignment = Enum.TextXAlignment.Center
		target.TextYAlignment = Enum.TextYAlignment.Center
		target.TextScaled = true
		if not target:FindFirstChildOfClass("UITextSizeConstraint") then
			new("UITextSizeConstraint", { Parent = target,
				MinTextSize = 9, MaxTextSize = maxText })
		end

		return btn, target, target.Text
	end

	-- `*Base` is the authored wording ("auto roll"), kept so the state can be
	-- appended without hardcoding the label the designer chose.
	local autoText, autoBase, quickText, quickBase
	autoButton, autoText, autoBase = sideButton(1, "AutoRollDesign", "auto roll")

	local rollHolder = new("Frame", { Parent = bar, LayoutOrder = 2,
		Size = UDim2.new(0, ROLL_W, 0, ROLL_H), BackgroundTransparency = 1 })
	rollButton = adopt("RollDesign", rollHolder, ROLL_W)
	if not rollButton then
		-- Fall back to something clickable rather than leaving the player with no
		-- roll button at all.
		rollButton = new("TextButton", { Parent = rollHolder,
			Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = ACCENT,
			Text = "ROLL", TextSize = 24, TextColor3 = Color3.new(1, 1, 1) },
		{ corner(14) })
	end

	quickButton, quickText, quickBase = sideButton(3, "QuickRollDesign", "quick roll")

	-- One place that renders a toggle's state, so ON and OFF cannot drift apart.
	-- Auto roll's colour is owned by the rainbow gradient, so only its opacity
	-- moves; quick roll has no gradient, so it brightens to white.
	local function setToggleState(target, base, on, rainbow)
		target.Text = base .. (on and ": ON" or ": OFF")
		local goal = { TextTransparency = on and 0 or 0.34 }
		if not rainbow then
			goal.TextColor3 = on and Color3.new(1, 1, 1) or Color3.fromRGB(196, 196, 202)
		end
		TweenService:Create(target, TweenInfo.new(0.18), goal):Play()
	end
	setToggleState(autoText, autoBase, false, true)
	setToggleState(quickText, quickBase, false, false)

	-- The lucky-roll readout: a count over a thin rail, sitting just above the
	-- buttons. Compact on purpose - it is a cadence you glance at between rolls,
	-- not something to read - so it is narrower than the dock, the label is small
	-- and quiet, and the rail is the part that actually carries the information.
	local luckyMeter = new("Frame", { Parent = gui, Name = "LuckyRollMeter",
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -118),
		Size = UDim2.new(0, 268, 0, 28), BackgroundTransparency = 1 })
	luckyLabel = label({ Parent = luckyMeter, Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 15), Text = "0 / " .. tostring(GameConfig.LuckyRollEvery) .. " TO LUCKY ROLL",
		TextSize = 11, TextColor3 = Color3.fromRGB(206, 206, 212),
		TextXAlignment = Enum.TextXAlignment.Center })
	new("UIStroke", { Parent = luckyLabel, Color = Color3.new(0, 0, 0),
		Thickness = 2, Transparency = 0.05, LineJoinMode = Enum.LineJoinMode.Round })

	-- Fully rounded ends, and dark enough to read over sand, grass or a night
	-- sky without a plate behind it.
	local track = new("Frame", { Parent = luckyMeter, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, -8, 0, 6), BackgroundColor3 = Color3.fromRGB(8, 8, 10),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0, ClipsDescendants = true }, { corner(3) })
	luckyStroke = new("UIStroke", { Parent = track, Color = Color3.fromRGB(128, 128, 136),
		Thickness = 1, Transparency = 0.45 })
	luckyFill = new("Frame", { Parent = track, Name = "Progress", Size = UDim2.new(),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, { corner(3) })
	-- Grey into gold rather than the old blue-to-mint ramp. Gold is the one warm
	-- accent the HUD keeps, shared with the announce bar and the toasts.
	new("UIGradient", { Parent = luckyFill,
		Color = ColorSequence.new(Color3.fromRGB(168, 168, 176), GOLD) })
	-- A bright cap riding the leading edge, so the bar reads as filling rather
	-- than as a static coloured strip. It is a child of the fill, so it follows
	-- for free, and the track clips it away at zero progress.
	new("Frame", { Parent = luckyFill, Name = "Head", AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 248, 224), BorderSizePixel = 0, ZIndex = 2 })

	-- Keep the complete dock and navigation usable on smaller viewports.
	local navScale = new("UIScale", { Parent = nav })
	local barScale = new("UIScale", { Parent = bar })
	local meterScale = new("UIScale", { Parent = luckyMeter })
	local statScale = new("UIScale", { Parent = top })
	local cameraConnection
	local function fitHUD()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local viewport = camera.ViewportSize
		local dockScale = math.clamp((viewport.X - 28) / 730, 0.45, 1)
		barScale.Scale = dockScale
		meterScale.Scale = dockScale
		-- Tucked right against the top of the dock rather than floating above it.
		luckyMeter.Position = UDim2.new(0.5, 0, 1, -(16 + 92 * dockScale))
		navScale.Scale = math.clamp((viewport.Y - 150) / navHeight, 0.52, 1)
		statScale.Scale = math.clamp((viewport.X - 160) / 366, 0.5, 1)
		top.Position = UDim2.new(0, viewport.X < 600 and 106 or 180, 0, 14)
	end
	local function followCamera()
		if cameraConnection then cameraConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		if camera then cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitHUD) end
		fitHUD()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(followCamera)
	followCamera()

	----------------------------------------------------------------
	-- auto roll rainbow
	----------------------------------------------------------------
	-- Auto roll is the premium control, so its label runs a continuous rainbow.
	--
	-- The hue is cycled by REBUILDING the ColorSequence every frame rather than
	-- sliding UIGradient.Offset. Offset CLAMPS at the ends of the sequence, so a
	-- travelling gradient smears its first and last colour across the text on
	-- every wrap - that stutter is what makes most versions of this look cheap.
	-- Turning the hue instead has no ends to hit: keypoint 0 and keypoint 1 sit
	-- exactly one full turn apart, so they are always the same colour and the
	-- loop is seamless in both directions.
	--
	-- Saturation and value sit deliberately under maximum. fromHSV(h, 1, 1) is
	-- the neon primary set, which is precisely what "too bright" looks like on a
	-- dark plate; pulling both back reads as lit metal instead of a highlighter.
	local RAINBOW_STOPS = 12    -- ColorSequence allows 20; 12 is already smooth
	local RAINBOW_PERIOD = 3.2  -- seconds per full turn of the wheel
	local RAINBOW_SAT = 0.68
	local RAINBOW_VAL = 0.97

	local rainbowText = autoButton:FindFirstChild("GradientText")
	local rainbow = rainbowText and rainbowText:FindFirstChild("Rainbow")
	if rainbow and rainbow:IsA("UIGradient") then
		local keys = table.create(RAINBOW_STOPS)
		RunService.RenderStepped:Connect(function()
			local phase = (os.clock() % RAINBOW_PERIOD) / RAINBOW_PERIOD
			for i = 1, RAINBOW_STOPS do
				local t = (i - 1) / (RAINBOW_STOPS - 1)
				keys[i] = ColorSequenceKeypoint.new(t,
					Color3.fromHSV((t + phase) % 1, RAINBOW_SAT, RAINBOW_VAL))
			end
			rainbow.Color = ColorSequence.new(keys)
		end)
	else
		warn("[UI] AutoRollDesign.roll.GradientText.Rainbow missing - no rainbow")
	end

	rollButton.Activated:Connect(function() self:DoRoll() end)

	autoButton.Activated:Connect(function()
		autoRoll = not autoRoll
		setToggleState(autoText, autoBase, autoRoll, true)
		Remotes.SetAutoRoll:FireServer(autoRoll)
	end)

	quickButton.Activated:Connect(function()
		quickRoll = not quickRoll
		setToggleState(quickText, quickBase, quickRoll, false)
	end)

	-- Started here so the roll button sweeps in step with the nav column.
	for _, sweep in ipairs(sweeps) do
		TweenService:Create(sweep,
			TweenInfo.new(1.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut,
				-1, false, 4.2),
			{ Position = UDim2.new(1.4, 0, 0.5, 0) }):Play()
	end

	----------------------------------------------------------------
	-- shared panel
	----------------------------------------------------------------
	panelRoot = new("Frame", { Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 560, 0, 470),
		BackgroundColor3 = PANEL, BackgroundTransparency = 0.05, Visible = false, ZIndex = 5 },
	{ corner(15), pad(12), stroke(ACCENT, 2) })

	panelTitle = label({ Parent = panelRoot, Size = UDim2.new(1, -40, 0, 24), Text = "PANEL",
		TextSize = 17, ZIndex = 6 })

	local closeBtn = new("TextButton", { Parent = panelRoot, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 28, 0, 28),
		BackgroundColor3 = Color3.fromRGB(210, 70, 80), Text = "X",
		FontFace = Theme.font(), TextSize = 14, TextColor3 = Color3.new(1, 1, 1), ZIndex = 6 },
	{ corner(8) })
	closeBtn.Activated:Connect(function() self:ClosePanel() end)

	panelBody = new("ScrollingFrame", { Parent = panelRoot, Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 1, -34), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ZIndex = 6 },
	{ new("UIGridLayout", { CellSize = UDim2.new(0, 118, 0, 158),
		CellPadding = UDim2.new(0, 10, 0, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })

	----------------------------------------------------------------
	-- world stations
	----------------------------------------------------------------
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local screen = prompt.Parent and prompt.Parent:GetAttribute("Screen")
		if screen then self:OpenScreen(screen) end
	end)

	Remotes.ProfileSync.OnClientEvent:Connect(function(data)
		profile = data
		self:RefreshStats()
	end)

	-- Controllers finish connecting after the server's join-time sync, so ask
	-- once on startup rather than waiting for the first roll to populate stats.
	task.defer(function() Remotes.RequestSync:FireServer() end)
	Remotes.Announce.OnClientEvent:Connect(function(data) self:Announce(data) end)
end

return UIController
