--!nonstrict
-- Anime Card Online
-- Standard sidebar menu controller.
--
-- This replaces ONLY the normal menu windows:
-- Backpack, Quests, Battle Pass, Teleport, Shop, Settings and Codes.
-- Deck and Skill Tree remain controlled by their existing specialised controllers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LeaderboardVisibility = require(ReplicatedStorage.Shared.UI.LeaderboardVisibility)
local TweenService = game:GetService("TweenService")

local MenuConfig = require(ReplicatedStorage.Shared.Config.MenuConfig)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local ElderCoin = require(ReplicatedStorage.Shared.UI.ElderCoin)
local ElderEssence = require(ReplicatedStorage.Shared.UI.ElderEssence)
local BookDefinitions = require(ReplicatedStorage.Shared.Config.BookDefinitions)
local Polish = require(ReplicatedStorage.Shared.UI.MenuPolish)
local UITheme = require(ReplicatedStorage.Shared.UI.UITheme)
local InventoryPresentation = require(ReplicatedStorage.Shared.UI.InventoryPresentation)
local SettingsPresentation = require(ReplicatedStorage.Shared.UI.SettingsPresentation)
local StorePresentation = require(ReplicatedStorage.Shared.UI.StorePresentation)
local MountDefinitions = require(ReplicatedStorage.Shared.Config.MountDefinitions)
local EncounterModes = require(ReplicatedStorage.Shared.Config.EncounterModes)
local MountRemotes = require(ReplicatedStorage.Shared.Net.MountRemotes)

local MenuController = {}
MenuController.Name = "MenuController"

local player = Players.LocalPlayer
local mainGui = nil
local dim = nil
local root = nil
local activeMenu = nil
local windows = {}
local sidebarButtons = {}
local latestProfile = nil
local backpackRefresh = nil

local MENU_TABS = {
	Backpack = { "All", "Currency", "Essence" },
	Quests = { "Daily", "Weekly", "Story" },
	BattlePass = { "Free", "Premium" },
	-- No tabs. These two are short lists, not dashboards, and an empty tab
	-- strip is just a gap - buildWindow reads a zero-length list as "compact"
	-- and re-lays the chrome around it.
	Teleport = {},
	Shop = { "Featured", "Packs", "Currency" },
	Mounts = {},
	-- Settings is not here: like the Backpack it is its own window
	-- (SettingsPresentation), not the standard chrome.
	Codes = { "Redeem", "Active" },
}

local BG = Color3.fromRGB(19, 26, 42)
local BG_2 = Color3.fromRGB(13, 19, 32)
local BG_3 = Color3.fromRGB(35, 46, 67)
local CARD = Color3.fromRGB(25, 34, 52)
-- From UITheme, which exists so every menu draws text the same. Each panel
-- used to carry its own near-white and its own grey, all a few points apart,
-- which is exactly the drift that module was written to stop.
local TEXT = UITheme.Text
local MUTED = UITheme.TextMuted
local STROKE = Color3.fromRGB(72, 79, 99)
local RED = Color3.fromRGB(246, 72, 69)

local function new(className, props, children)
	local object = Instance.new(className)
	if object:IsA("GuiObject") then
		object.BorderSizePixel = 0
		if props and props.Parent and props.Parent:IsA("GuiObject") then object.ZIndex = props.Parent.ZIndex + 1 end
	end
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then
			object[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = object
	end
	if props and props.Parent then
		object.Parent = props.Parent
	end
	return object
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color, thickness, transparency)
	return new("UIStroke", {
		Color = color or STROKE,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
	})
end

local function padding(left, right, top, bottom)
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, left or 0),
		PaddingRight = UDim.new(0, right or left or 0),
		PaddingTop = UDim.new(0, top or left or 0),
		PaddingBottom = UDim.new(0, bottom or top or left or 0),
	})
end

local function gameFont(object)
	local ok, font = pcall(function()
		return Theme.font()
	end)
	if ok and font then
		object.FontFace = font
	else
		object.Font = Enum.Font.Gotham
	end
end

local function textLabel(parent, text, size, color)
	local label = new("TextLabel", {
		Parent = parent,
		BackgroundTransparency = 1,
		Text = text or "",
		TextColor3 = color or TEXT,
		TextSize = size or 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	gameFont(label)
	if (size or 16) <= 14 then label.Font = Enum.Font.GothamMedium end
	return label
end

local function normalize(value)
	return (string.lower(tostring(value)):gsub("[^%w]", ""))
end

local function buttonMatches(button, aliases)
	local candidates = { normalize(button.Name) }
	if button:IsA("TextButton") then
		table.insert(candidates, normalize(button.Text))
	end
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			if descendant.Text ~= "" then
				table.insert(candidates, normalize(descendant.Text))
			end
		end
	end
	for _, candidate in ipairs(candidates) do
		for _, alias in ipairs(aliases) do
			if candidate == normalize(alias) then
				return true
			end
		end
	end
	return false
end

local function findMainGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local preferred = playerGui:WaitForChild("CardClashHUD", 12)
	if preferred and preferred:IsA("ScreenGui") then
		return preferred
	end
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") then
			for _, descendant in ipairs(child:GetDescendants()) do
				if descendant:IsA("GuiButton") and descendant.Name == "Backpack" then
					return child
				end
			end
		end
	end
	error("[MenuController] Could not find CardClashHUD.")
end

local function findSidebarButtons()
	for _, menuName in ipairs(MenuConfig.Order) do
		local data = MenuConfig.Menus[menuName]
		sidebarButtons[menuName] = nil
		for _, descendant in ipairs(mainGui:GetDescendants()) do
			if descendant:IsA("GuiButton") and buttonMatches(descendant, data.ButtonAliases) then
				sidebarButtons[menuName] = descendant
				break
			end
		end
	end
end

local function wipe(container)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function accentGradient(parent, data, rotation)
	return new("UIGradient", {
		Parent = parent,
		Rotation = rotation or 0,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, data.Color1),
			ColorSequenceKeypoint.new(0.52, data.Color2),
			ColorSequenceKeypoint.new(1, data.Color3),
		}),
	})
end

local function makeInfoMessage(parent, titleText, bodyText, accent)
	local frame = new("Frame", {
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 128),
		BackgroundColor3 = CARD,
	}, { corner(13), stroke(STROKE, 1, 0.2), padding(18, 18, 14, 14) })

	local dot = new("Frame", {
		Parent = frame,
		Size = UDim2.fromOffset(6, 54),
		Position = UDim2.fromOffset(0, 14),
		BackgroundColor3 = accent,
	}, { corner(3) })

	local title = textLabel(frame, titleText, 18, TEXT)
	title.Position = UDim2.fromOffset(18, 0)
	title.Size = UDim2.new(1, -22, 0, 28)

	local body = textLabel(frame, bodyText, 14, MUTED)
	body.Position = UDim2.fromOffset(18, 34)
	body.Size = UDim2.new(1, -22, 0, 46)
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
	Polish.surface(frame, accent)
	return frame
end

local function makeSimpleRow(parent, titleText, subtitleText, accent, rightText)
	local row = new("Frame", {
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 82),
		BackgroundColor3 = CARD,
	}, { corner(12), stroke(STROKE, 1, 0.25) })

	new("Frame", {
		Parent = row,
		Size = UDim2.fromOffset(5, 48),
		Position = UDim2.fromOffset(14, 17),
		BackgroundColor3 = accent,
	}, { corner(3) })

	local title = textLabel(row, titleText, 17, TEXT)
	title.Position = UDim2.fromOffset(32, 14)
	title.Size = UDim2.new(1, -180, 0, 25)

	local subtitle = textLabel(row, subtitleText, 13, MUTED)
	subtitle.Position = UDim2.fromOffset(32, 40)
	subtitle.Size = UDim2.new(1, -180, 0, 24)

	if rightText then
		local right = textLabel(row, rightText, 13, accent)
		right.AnchorPoint = Vector2.new(1, 0.5)
		right.Position = UDim2.new(1, -18, 0.5, 0)
		right.Size = UDim2.fromOffset(132, 30)
		right.TextSize = 11
		right.BackgroundColor3 = accent:Lerp(BG_3, 0.85)
		right.BackgroundTransparency = 0.2
		right.TextXAlignment = Enum.TextXAlignment.Center
		corner(9).Parent = right
		local pillStroke = stroke(accent, 1, 0.65)
		pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		pillStroke.Parent = right
	end
	Polish.surface(row, accent)
	Polish.hover(row, accent, 1.005)
	return row
end

local function buildQuestsContent(content, tab, data)
	wipe(content)
	new("UIListLayout", { Parent = content, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })
	for i = 1, 4 do
		makeSimpleRow(content, ("%s QUEST %d"):format(string.upper(tab), i), "New objectives will appear here when this quest track opens.", data.Color2, "COMING SOON")
	end
end

local function buildBattlePassContent(content, tab, data)
	wipe(content)
	local intro = makeInfoMessage(content, string.upper(tab) .. " TRACK", "Discover a new season of rewards. This track opens with the next battle pass.", data.Color2)
	intro.Size = UDim2.new(1, 0, 0, 128)

	local track = new("Frame", {
		Parent = content,
		Position = UDim2.fromOffset(0, 144),
		Size = UDim2.new(1, 0, 0, 210),
		BackgroundColor3 = CARD,
	}, { corner(13), stroke(STROKE, 1, 0.2), padding(22, 22, 22, 22) })

	local bar = new("Frame", {
		Parent = track,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.58, 0),
		Size = UDim2.new(1, -90, 0, 8),
		BackgroundColor3 = BG_3,
	}, { corner(4) })

	for i = 1, 6 do
		local node = new("Frame", {
			Parent = track,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.07 + ((i - 1) / 5) * 0.86, 0, 0.58, 0),
			Size = UDim2.fromOffset(58, 58),
			BackgroundColor3 = BG_2,
		}, { corner(14), stroke(data.Color2, 2, 0.15) })
		local number = textLabel(node, tostring(i), 18, data.Color2)
		number.Size = UDim2.fromScale(1, 1)
		number.TextXAlignment = Enum.TextXAlignment.Center
	end

	Polish.surface(track, data.Color2)
	local title = textLabel(track, "SEASON PROGRESS", 15, TEXT)
	title.Size = UDim2.new(1, 0, 0, 24)
	local status = textLabel(track, "NEW SEASON • COMING SOON", 13, MUTED)
	status.Position = UDim2.new(0, 0, 1, -26)
	status.Size = UDim2.new(1, 0, 0, 20)
	status.TextXAlignment = Enum.TextXAlignment.Center
end

local travelBusy = false
local recentTravel = {}
-- Real screenshots, taken in-game at each destination. The brief was
-- deliberately spare: a picture, the name, and the word TELEPORT. Everything
-- the old panel carried - badge numbers, tags, blurbs, "arrive safely beside
-- the island portal" - is text nobody reads on the way somewhere else.
local destinations = {
	{ id = "Lobby", title = "LOBBY",
	  image = "rbxassetid://119615652978700", color = Color3.fromRGB(99, 181, 255) },
	{ id = "ArlongPark", title = "PIRATE SHARK PARK",
	  image = "rbxassetid://129560145820984", color = Color3.fromRGB(89, 220, 187) },
	{ id = "RoshiHouse", title = "KAME HOUSE",
	  image = "rbxassetid://123198873892022", color = Color3.fromRGB(255, 151, 185) },
}

local function rememberTravel(id)
	for i = #recentTravel, 1, -1 do
		if recentTravel[i] == id then table.remove(recentTravel, i) end
	end
	table.insert(recentTravel, 1, id)
	while #recentTravel > 3 do table.remove(recentTravel) end
end

local function buildTeleportContent(content, tab, data)
	wipe(content)
	new("UIListLayout", { Parent = content, Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder })

	local current = player:GetAttribute("CurrentDestination") or "Lobby"

	for index, d in ipairs(destinations) do
		local here = current == d.id
		local card = new("Frame", { Parent = content, Name = d.id, LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 158), BackgroundColor3 = CARD,
			ClipsDescendants = true },
			{ corner(16), stroke(here and STROKE or d.color, 1.5, here and 0.6 or 0.32) })

		local shot = new("ImageLabel", { Parent = card, Name = "Shot",
			Size = UDim2.new(1, 0, 0, 104), BackgroundColor3 = BG_2,
			Image = d.image, ScaleType = Enum.ScaleType.Crop,
			ImageTransparency = here and 0.45 or 0 }, { corner(16) })

		-- A scrim under the name. These are bright skies and pale sand, and
		-- white text over them is unreadable without one.
		local scrim = new("Frame", { Parent = shot, Name = "Scrim",
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 48),
			BackgroundColor3 = Color3.fromRGB(6, 10, 18) })
		new("UIGradient", { Parent = scrim, Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0.12) }) })

		local name = textLabel(shot, d.title, 17, TEXT)
		name.Name = "LocationName"
		name.Position = UDim2.fromOffset(14, 72)
		name.Size = UDim2.new(1, -28, 0, 24)
		name.ZIndex = scrim.ZIndex + 1
		new("UIStroke", { Parent = name, Color = Color3.fromRGB(5, 9, 16),
			Thickness = 2, Transparency = 0.3 })

		local button = new("TextButton", { Parent = card, Name = "TravelButton",
			Position = UDim2.new(0, 12, 0, 112), Size = UDim2.new(1, -24, 0, 36),
			Text = "", BackgroundColor3 = here and BG_3 or d.color,
			AutoButtonColor = false, Active = not here, Selectable = not here },
			{ corner(10) })
		local caption = textLabel(button, here and "CURRENT" or "TELEPORT", 14,
			here and MUTED or Color3.fromRGB(14, 20, 32))
		caption.Size = UDim2.fromScale(1, 1)
		caption.TextXAlignment = Enum.TextXAlignment.Center
		if not here then
			Polish.hover(button, d.color, 1.02)
			Polish.sweep(button, d.color, 0.9)
		end

		button.Activated:Connect(function()
			if travelBusy or here then return end
			travelBusy = true
			caption.Text = "\u{2026}"
			local ok, result = pcall(function()
				return Remotes.RequestTravel:InvokeServer(d.id)
			end)
			travelBusy = false
			if ok and type(result) == "table" and result.ok then
				rememberTravel(d.id)
				MenuController:CloseAll()
			elseif button.Parent then
				caption.Text = "TRY AGAIN"
				caption.TextColor3 = RED
			end
		end)
	end
end

local function buildShopContent(content, tab, data)
	wipe(content)
	local grid = new("UIGridLayout", {
		Parent = content,
		CellSize = UDim2.fromOffset(230, 240),
		CellPadding = UDim2.fromOffset(16, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	Polish.grid(content, grid, 230, 1.04, 4)
	for i = 1, 3 do
		local card = new("Frame", {
			Parent = content,
			LayoutOrder = i,
			BackgroundColor3 = CARD,
		}, { corner(14), stroke(data.Color2, 1.5, 0.18) })
		Polish.surface(card, data.Color2, 0.13)
		Polish.hover(card, data.Color2, 1.015)
		Polish.sweep(card, data.Color2, 0.94)
		local art = new("ImageLabel", {
			Parent = card,
			BackgroundTransparency = 1,
			Image = data.IconImage,
			ImageColor3 = data.Color2,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 25),
			Size = UDim2.fromOffset(92, 92),
		})
		local title = textLabel(card, ({Featured = {"FEATURED COLLECTION", "LIMITED COLLECTION", "DAILY SELECTION"}, Packs = {"STARTER PACK", "COLLECTOR PACK", "PREMIUM PACK"}, Currency = {"COIN BUNDLE", "COIN CHEST", "COIN VAULT"}})[tab][i], 16, TEXT)
		title.Position = UDim2.new(0, 12, 0, 132)
		title.Size = UDim2.new(1, -24, 0, 25)
		title.TextXAlignment = Enum.TextXAlignment.Center
		local sub = textLabel(card, "New arrivals on the way", 13, MUTED)
		sub.Position = UDim2.new(0, 12, 0, 160)
		sub.Size = UDim2.new(1, -24, 0, 22)
		sub.TextXAlignment = Enum.TextXAlignment.Center
		local tag = textLabel(card, "COMING SOON", 12, data.Color2)
		tag.Position = UDim2.new(0, 12, 1, -42)
		tag.Size = UDim2.new(1, -24, 0, 22)
		tag.TextXAlignment = Enum.TextXAlignment.Center
	end
end

local function buildCodesContent(content, tab, data)
	wipe(content)
	if tab == "Active" then
		new("UIListLayout", { Parent = content, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })
		makeInfoMessage(content, "ACTIVE CODES", "New reward codes will appear here when they become available.", data.Color2)
		return
	end

	local box = new("Frame", {
		Parent = content,
		Size = UDim2.new(1, 0, 0, 245),
		BackgroundColor3 = CARD,
	}, { corner(14), stroke(STROKE, 1, 0.2), padding(24, 24, 22, 22) })

	local title = textLabel(box, "REDEEM A CODE", 21, TEXT)
	title.Size = UDim2.new(1, 0, 0, 32)
	local help = textLabel(box, "Have a reward code? Enter it below. Code redemption is coming soon.", 13, MUTED)
	help.Position = UDim2.fromOffset(0, 36)
	help.Size = UDim2.new(1, 0, 0, 42)
	help.TextWrapped = true

	local input = new("TextBox", {
		Parent = box,
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, -170, 0, 52),
		BackgroundColor3 = BG_3,
		PlaceholderText = "ENTER CODE",
		PlaceholderColor3 = MUTED,
		Text = "",
		TextColor3 = TEXT,
		TextSize = 16,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, { corner(11), stroke(STROKE, 1, 0.15), padding(14, 14, 0, 0) })
	gameFont(input)

	local redeem = new("TextButton", {
		Parent = box,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 94),
		Size = UDim2.fromOffset(154, 52),
		BackgroundColor3 = data.Color1,
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 16,
		AutoButtonColor = false,
	}, { corner(11), stroke(data.Color2, 1, 0.2) })
	gameFont(redeem)
	local redeemCaption = textLabel(redeem, "REDEEM", 16, TEXT)
	redeemCaption.Size = UDim2.fromScale(1, 1); redeemCaption.TextXAlignment = Enum.TextXAlignment.Center
	redeem.BackgroundColor3 = Color3.new(1, 1, 1)
	accentGradient(redeem, data, 0)
	Polish.hover(redeem, data.Color2)
	Polish.surface(box, data.Color2)
	local inputStroke = input:FindFirstChildOfClass("UIStroke")
	input.Focused:Connect(function() TweenService:Create(inputStroke, TweenInfo.new(0.16), {Color = data.Color2, Transparency = 0}):Play() end)
	input.FocusLost:Connect(function() TweenService:Create(inputStroke, TweenInfo.new(0.16), {Color = STROKE, Transparency = 0.25}):Play() end)

	local status = textLabel(box, "", 13, data.Color2)
	status.Position = UDim2.fromOffset(0, 162)
	status.Size = UDim2.new(1, 0, 0, 30)
	status.TextXAlignment = Enum.TextXAlignment.Center

	redeem.Activated:Connect(function()
		if input.Text == "" then
			status.Text = "Enter a code first."
		else
			status.Text = "Code redemption is not available yet. Check back soon."
		end
	end)
end

-- One card per mount, owned or not: a mount you cannot use yet is the reason
-- to go and fight something, so hiding it would hide the goal. Same card shape
-- as the teleport panel - art on top, name, one action - because these two are
-- now the same size and open from the same sidebar.
local function buildMountsContent(content, tab, data)
	wipe(content)

	local profile = latestProfile
	local owned = (profile and profile.mounts) or {}
	local equipped = profile and profile.equippedMount or nil

	new("UIListLayout", { Parent = content, Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder })

	for index, mountId in ipairs(MountDefinitions.Order) do
		local def = MountDefinitions.get(mountId)
		if def then
			local isOwned = owned[mountId] == true
			local isEquipped = equipped == mountId
			local accent = isOwned and data.Color2 or STROKE

			local card = new("Frame", { Parent = content, Name = mountId,
				LayoutOrder = index, Size = UDim2.new(1, 0, 0, 182),
				BackgroundColor3 = CARD, ClipsDescendants = true },
				{ corner(16), stroke(accent, 1.5, isOwned and 0.32 or 0.62) })

			-- WHITE background, not BG_2. A UIGradient multiplies whatever colour
			-- is underneath it, so tinting a near-black frame leaves it near-black
			-- and the plate renders as a dead rectangle.
			local art = new("Frame", { Parent = card, Name = "Art",
				Size = UDim2.new(1, 0, 0, 96),
				BackgroundColor3 = Color3.new(1, 1, 1) }, { corner(16) })
			Polish.gradient(art, accent:Lerp(BG, 0.68), BG_2, 25)
			-- Falls back to the menu's own icon, so a mount added without art gets
			-- a plate that looks deliberate rather than an empty black box.
			local artwork = (def.icon and def.icon ~= "") and def.icon or data.IconImage
			if artwork and artwork ~= "" then
				local icon = new("ImageLabel", { Parent = art, BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(72, 72), Image = artwork,
					ScaleType = Enum.ScaleType.Fit,
					ImageTransparency = isOwned and 0 or 0.6 })
				icon.ZIndex = art.ZIndex + 2
			end

			local name = textLabel(card, def.name, 17, isOwned and TEXT or MUTED)
			name.Position = UDim2.fromOffset(14, 100)
			name.Size = UDim2.new(1, -28, 0, 22)

			local subtitle
			if isOwned then
				subtitle = isEquipped and "EQUIPPED  \u{00B7}  PRESS R TO RIDE"
					or ("%dx SPEED"):format(def.SpeedMultiplier)
			else
				local req = MountDefinitions.requirement(mountId)
				local stage = req and EncounterModes.get(req.difficulty) or nil
				subtitle = req
					and ("BEAT %s ON %s"):format(req.encounter,
						(stage and stage.display or req.difficulty):upper())
					or "LOCKED"
			end
			local sub = textLabel(card, subtitle, 12, MUTED)
			sub.Position = UDim2.fromOffset(14, 121)
			sub.Size = UDim2.new(1, -28, 0, 16)

			if isOwned then
				local button = new("TextButton", { Parent = card, Name = "Action",
					Position = UDim2.new(0, 12, 0, 140), Size = UDim2.new(1, -24, 0, 34),
					BackgroundColor3 = isEquipped and BG_3 or data.Color2,
					Text = "", AutoButtonColor = false }, { corner(10) })
				local caption = textLabel(button, isEquipped and "UNEQUIP" or "EQUIP", 14,
					isEquipped and TEXT or Color3.fromRGB(16, 22, 34))
				caption.Size = UDim2.fromScale(1, 1)
				caption.TextXAlignment = Enum.TextXAlignment.Center
				Polish.hover(button, data.Color2, 1.02)

				local busy = false
				button.Activated:Connect(function()
					if busy then return end
					busy = true
					caption.Text = "\u{2026}"
					task.spawn(function()
						local ok = pcall(function()
							if isEquipped then
								return MountRemotes.Action:InvokeServer("unequip", {})
							end
							return MountRemotes.Action:InvokeServer("equip", { mountId = mountId })
						end)
						busy = false
						if not ok then caption.Text = isEquipped and "UNEQUIP" or "EQUIP" end
						-- The profile comes back down through ProfileSync, which
						-- redraws this panel; no local state to keep in step.
					end)
				end)
			else
				local bar = new("Frame", { Parent = card, Name = "LockedBar",
					Position = UDim2.new(0, 12, 0, 140), Size = UDim2.new(1, -24, 0, 34),
					BackgroundColor3 = BG_2 }, { corner(10), stroke(STROKE, 1, 0.65) })
				local caption = textLabel(bar, "LOCKED", 13, MUTED)
				caption.Size = UDim2.fromScale(1, 1)
				caption.TextXAlignment = Enum.TextXAlignment.Center
			end
		end
	end
end

local builders = {
	Quests = buildQuestsContent,
	BattlePass = buildBattlePassContent,
	Teleport = buildTeleportContent,
	Shop = buildShopContent,
	Mounts = buildMountsContent,
	Codes = buildCodesContent,
}

local function setBodyContent(record, tab)
	if not record or not record.content then return end
	local builder = builders[record.name]
	if builder then
		builder(record.content, tab, record.data)
	end
	for tabName, button in pairs(record.tabButtons) do
		local selected = tabName == tab
		button.BackgroundColor3 = selected and Color3.new(1, 1, 1) or BG_3
		local caption = button:FindFirstChild("Caption")
		if caption then caption.TextColor3 = selected and TEXT or MUTED end
		local grad = button:FindFirstChild("SelectedGradient")
		if grad then grad.Enabled = selected end
		local marker = button:FindFirstChild("ActiveLine")
		if marker then marker.Visible = selected end
		local outline = button:FindFirstChildOfClass("UIStroke")
		if outline then
			outline.Color = selected and record.data.Color2 or STROKE
			outline.Transparency = selected and 0.15 or 0.6
			button:SetAttribute("RestStrokeColor", outline.Color)
			button:SetAttribute("RestStrokeTransparency", outline.Transparency)
		end
	end
	record.content.CanvasPosition = Vector2.zero
	record.selectedTab = tab
end

local MENU_DESCRIPTIONS = {
	Quests = "Take on new challenges and grow your collection.",
	BattlePass = "A new season. A new collection of rewards.",
	Teleport = "Choose where your next adventure begins.",
	Shop = "Discover something extraordinary.",
	Mounts = "Ride something that gets you there faster.",
	Codes = "A little bonus for your next adventure.",
}

local function buildWindow(menuName)
	if menuName == "Backpack" then
		local record, refresh = InventoryPresentation.createWindow(root,
			function() return latestProfile end, function() MenuController:CloseAll() end)
		windows.Backpack = record
		backpackRefresh = refresh
		return record
	end
	if menuName == "Settings" then
		-- Two volume bars. The buses and the saving live in AudioController;
		-- the window only draws them.
		local audio = MenuController.Controllers and MenuController.Controllers.AudioController
		local record = SettingsPresentation.createWindow(root, audio, function() MenuController:CloseAll() end)
		windows.Settings = record
		return record
	end
	if menuName == "Shop" then
		-- The Store: game passes and bundles in one window, no tabs. The old
		-- Featured / Packs / Currency window is in ServerStorage.BeforeStoreRevamp.
		local record = StorePresentation.createWindow(root, function() MenuController:CloseAll() end)
		windows.Shop = record
		return record
	end
	local data = MenuConfig.Menus[menuName]
	local tabs = MENU_TABS[menuName]
	local holder = new("Frame", {
		Parent = root, Name = menuName .. "Window", AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(data.Width or 1200, data.Height or 680),
		BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 82,
	}, {corner(22), stroke(data.Color1:Lerp(TEXT, 0.12), 2, 0.2)})
	Polish.gradient(holder, Color3.fromRGB(31, 41, 62), Color3.fromRGB(14, 20, 34))
	local scale = new("UIScale", {Parent = holder, Scale = 1})
	local inset = new("Frame", {Parent = holder, Name = "InnerRim", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), ZIndex = 83},
		{corner(18), stroke(Color3.fromRGB(139, 171, 214), 1, 0.88)})
	local header = new("Frame", {
		Parent = holder, Name = "Header", Position = UDim2.fromOffset(20, 18),
		Size = UDim2.new(1, -40, 0, 90), BackgroundColor3 = Color3.new(1, 1, 1),
		ClipsDescendants = true, ZIndex = 84,
	}, {corner(16), stroke(data.Color2, 1, 0.5)})
	Polish.gradient(header, Color3.fromRGB(25, 43, 69):Lerp(data.Color1, 0.28), Color3.fromRGB(16, 24, 40), 10)
	Polish.sweep(header, data.Color2, 0.93)
	new("Frame", {Parent = header, Name = "HeaderAccent", Position = UDim2.new(0, 20, 1, -3),
		Size = UDim2.new(1, -40, 0, 2), BackgroundColor3 = data.Color2, BackgroundTransparency = 0.35, ZIndex = 86},
		{corner(2), new("UIGradient", {Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.7), NumberSequenceKeypoint.new(1, 1)})})})
	local iconBox = new("Frame", {Parent = header, Name = "IconBadge",
		Position = UDim2.fromOffset(16, 15), Size = UDim2.fromOffset(60, 60),
		BackgroundColor3 = Color3.fromRGB(13, 23, 40), ZIndex = 87},
		{corner(17), stroke(data.Color2, 1.5, 0.35)})
	Polish.gradient(iconBox, data.Color1:Lerp(Color3.fromRGB(32, 43, 61), 0.8), Color3.fromRGB(12, 20, 34))
	new("ImageLabel", {Parent = iconBox, Name = "Icon", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16),
		Image = data.IconImage, ScaleType = Enum.ScaleType.Fit, ZIndex = 88})
	local title = textLabel(header, data.Title, 30, TEXT)
	title.Name = "Title"; title.Position = UDim2.fromOffset(92, 14); title.Size = UDim2.new(1, -184, 0, 36)
	title.ZIndex = 88
	new("UIStroke", {Parent = title, Color = Color3.fromRGB(8, 15, 26), Thickness = 1.6, Transparency = 0.18})
	local subtitle = textLabel(header, MENU_DESCRIPTIONS[menuName], 14, MUTED)
	subtitle.Name = "Subtitle"; subtitle.Position = UDim2.fromOffset(94, 51); subtitle.Size = UDim2.new(1, -188, 0, 22)
	subtitle.ZIndex = 88; subtitle.Font = Enum.Font.GothamMedium
	local close = new("TextButton", {Parent = header, Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(46, 46), BackgroundColor3 = Color3.fromRGB(57, 33, 47),
		Text = "", AutoButtonColor = false, ZIndex = 90},
		{corner(13), stroke(Color3.fromRGB(250, 123, 139), 1.5, 0.4)})
	for _, angle in ipairs({45, -45}) do
		new("Frame", {Parent = close, Name = "Cross", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 3),
			Rotation = angle, BackgroundColor3 = Color3.fromRGB(255, 221, 227), ZIndex = 91}, {corner(2)})
	end
	Polish.hover(close, Color3.fromRGB(255, 125, 148), 1.075)
	local tabBar = new("Frame", {Parent = holder, Name = "Tabs", Position = UDim2.fromOffset(24, 122),
		Size = UDim2.new(1, -48, 0, 46), BackgroundTransparency = 1, ZIndex = 85},
		{new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder})})
	local contentShell = new("Frame", {Parent = holder, Name = "ContentShell",
		Position = UDim2.fromOffset(24, 184), Size = UDim2.new(1, -48, 1, -226),
		BackgroundColor3 = BG_2, ClipsDescendants = true, ZIndex = 84},
		{corner(16), stroke(Color3.fromRGB(101, 129, 165), 1, 0.67)})
	local content = new("ScrollingFrame", {Parent = contentShell, Name = "Content",
		Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 1, -28),
		BackgroundTransparency = 1, ScrollBarThickness = 4, ScrollBarImageColor3 = data.Color2,
		ScrollBarImageTransparency = 0.25, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ZIndex = 85}, {padding(5, 10, 5, 10)})
	local footer = textLabel(holder, "ANIME CARD ONLINE", 11, Color3.fromRGB(116, 139, 174))
	footer.Name = "Footer"; footer.Position = UDim2.new(0, 30, 1, -31); footer.Size = UDim2.new(1, -60, 0, 18)
	footer.Font = Enum.Font.GothamMedium; footer.ZIndex = 85
	-- COMPACT MENUS. Rather than fork the whole builder for two panels, the
	-- standard chrome is re-laid-out here: smaller header, no tab strip, and
	-- the content pulled up into the space the strip would have taken.
	if #tabs == 0 then
		header.Position = UDim2.fromOffset(14, 13)
		header.Size = UDim2.new(1, -28, 0, 62)
		iconBox.Position = UDim2.fromOffset(11, 11)
		iconBox.Size = UDim2.fromOffset(40, 40)
		title.Position = UDim2.fromOffset(62, 8)
		title.Size = UDim2.new(1, -120, 0, 26)
		title.TextSize = 21
		subtitle.Position = UDim2.fromOffset(63, 33)
		subtitle.Size = UDim2.new(1, -122, 0, 18)
		subtitle.TextSize = 11
		close.Size = UDim2.fromOffset(34, 34)
		tabBar.Visible = false
		contentShell.Position = UDim2.fromOffset(14, 84)
		contentShell.Size = UDim2.new(1, -28, 1, -114)
		content.Position = UDim2.fromOffset(10, 10)
		content.Size = UDim2.new(1, -20, 1, -20)
		footer.Position = UDim2.new(0, 20, 1, -25)
		footer.TextSize = 10
	end

	local record = {name = menuName, data = data, holder = holder, scale = scale, content = content,
		tabButtons = {}, selectedTab = nil, baseScale = 1, motion = nil, transition = 0}
	local function fit()
		local size = root.AbsoluteSize
		if size.X < 1 or size.Y < 1 then return end
		if record.motion then record.motion:Cancel() end

		-- A menu that declared its own size keeps it. It is a fixed panel, not a
		-- window that grows toward the screen edges, so the only thing the
		-- viewport decides is whether it has to be scaled DOWN to fit at all.
		if data.Width and data.Height then
			record.baseScale = math.clamp(
				math.min((size.X - 40) / data.Width, (size.Y - 40) / data.Height), 0.35, 1)
			holder.Size = UDim2.fromOffset(data.Width, data.Height)
			scale.Scale = record.baseScale
			return
		end

		record.baseScale = math.min(1, math.max(0.1, (size.X - 28) / 760), math.max(0.1, (size.Y - 26) / 540))
		holder.Size = UDim2.fromOffset(math.clamp((size.X - 48) / record.baseScale, 760, 1280), math.clamp((size.Y - 48) / record.baseScale, 540, 780))
		scale.Scale = record.baseScale
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	for index, tabName in ipairs(tabs) do
		local tabButton = new("TextButton", {Parent = tabBar, Name = tabName, LayoutOrder = index,
			Size = UDim2.new(1 / #tabs, -(10 * (#tabs - 1) / #tabs), 0, 44), BackgroundColor3 = BG_3,
			Text = "", TextColor3 = MUTED, TextSize = 15, AutoButtonColor = false, ZIndex = 86},
			{corner(11), stroke(STROKE, 1, 0.6)})
		gameFont(tabButton)
		local caption = textLabel(tabButton, tabName, 15, MUTED)
		caption.Name = "Caption"; caption.Size = UDim2.fromScale(1, 1); caption.TextXAlignment = Enum.TextXAlignment.Center; caption.ZIndex = 88
		local selectedGradient = Polish.gradient(tabButton, data.Color1:Lerp(Color3.fromRGB(36, 60, 86), 0.42), data.Color3:Lerp(Color3.fromRGB(21, 33, 54), 0.6), 15)
		selectedGradient.Name = "SelectedGradient"; selectedGradient.Enabled = false
		new("Frame", {Parent = tabButton, Name = "ActiveLine", AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.new(0.45, 0, 0, 2),
			BackgroundColor3 = data.Color2, Visible = false, ZIndex = 87}, {corner(2)})
		Polish.hover(tabButton, data.Color2, 1.012)
		record.tabButtons[tabName] = tabButton
		tabButton.Activated:Connect(function() if record.selectedTab ~= tabName then setBodyContent(record, tabName) end end)
	end
	close.Activated:Connect(function() MenuController:CloseAll() end)
	windows[menuName] = record
	setBodyContent(record, tabs[1])
	return record
end

local backpackHudVisibility = {}
local function setBackpackHudHidden(hidden)
	for object, wasVisible in pairs(backpackHudVisibility) do
		if object.Parent then object.Visible = wasVisible end
	end
	table.clear(backpackHudVisibility)
	if hidden and mainGui then
		for _, name in ipairs({ "Stats", "Navigation", "RollDock", "LuckyRollMeter" }) do
			local object = mainGui:FindFirstChild(name)
			if object and object:IsA("GuiObject") then
				backpackHudVisibility[object] = object.Visible
				object.Visible = false
			end
		end
	end
end

function MenuController:CloseAll()
	setBackpackHudHidden(false)
	activeMenu = nil
	-- The leaderboard comes back unless something else is still hiding it.
	LeaderboardVisibility.show("Menu")
	if dim then
		TweenService:Create(dim, TweenInfo.new(0.16), {BackgroundTransparency = 1}):Play()
		task.delay(0.16, function() if not activeMenu then dim.Visible = false end end)
	end
	for _, record in pairs(windows) do
		if record.holder.Visible then
			if record.onClose then record.onClose() end
			record.transition += 1
			local transition = record.transition
			if record.motion then record.motion:Cancel() end
			record.motion = TweenService:Create(record.scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = record.baseScale * 0.965})
			record.motion:Play()
			task.delay(0.14, function()
				if record.transition == transition and activeMenu ~= record.name then
					record.holder.Visible = false
					record.scale.Scale = record.baseScale
				end
			end)
		end
	end
end

function MenuController:Open(menuName)
	if menuName == "Teleport" and windows.Teleport then setBodyContent(windows.Teleport, nil) end
	local record = windows[menuName]
	if not record then return end

	-- Do not let a standard window overlap the two specialised full-screen UIs.
	if self.Controllers then
		local deck = self.Controllers.DeckController
		if deck and deck.Close then deck:Close() end
		local tree = self.Controllers.SkillTreeController
		if tree and tree.Close then tree:Close() end
	end

	for name, other in pairs(windows) do
		if name ~= menuName then other.holder.Visible = false end
	end

	setBackpackHudHidden(menuName == "Backpack")
	activeMenu = menuName
	LeaderboardVisibility.hide("Menu")
	dim.Visible = true
	dim.BackgroundTransparency = 1
	TweenService:Create(dim, TweenInfo.new(menuName == "Backpack" and 0.24 or 0.22), {BackgroundTransparency = menuName == "Backpack" and 0.32 or 0.42}):Play()
	record.transition += 1
	if record.motion then record.motion:Cancel() end
	record.holder.Visible = true
	-- A window may describe its own entrance (the Backpack record does: a
	-- short, settled scale-in instead of the overshoot the other panels use).
	record.scale.Scale = record.baseScale * (record.openFrom or 0.94)
	record.motion = TweenService:Create(record.scale, record.openTween or TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = record.baseScale})
	record.motion:Play()

	if menuName == "Backpack" and backpackRefresh then
		backpackRefresh()
	end
	if record.onOpen then record.onOpen() end
end

function MenuController:Toggle(menuName)
	if activeMenu == menuName and windows[menuName] and windows[menuName].holder.Visible then
		self:CloseAll()
	else
		self:Open(menuName)
	end
end

function MenuController:Init()
	player:GetAttributeChangedSignal("CurrentDestination"):Connect(function() local id=player:GetAttribute("CurrentDestination"); if id then rememberTravel(id) end end)
	Remotes.ProfileSync.OnClientEvent:Connect(function(profile)
		latestProfile = profile
		-- The Mounts panel is drawn straight from the profile, so a sync is the
		-- only signal it needs to show an equip that just went through.
		--
		-- Redrawn whether or not it is on screen. Every window is built once at
		-- startup, which is BEFORE the first profile arrives, so a panel that only
		-- refreshed while visible would keep the "LOCKED" copy it was born with
		-- until something else happened to redraw it.
		local mounts = windows and windows.Mounts
		if mounts and mounts.content then
			setBodyContent(mounts, mounts.selectedTab or "Mounts")
		end
		if backpackRefresh then backpackRefresh() end
	end)
end

function MenuController:Start()
	mainGui = findMainGui()
	findSidebarButtons()

	root = new("Frame", {
		Parent = mainGui,
		Name = "MenuWindows",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 78,
	})

	dim = new("TextButton", {
		Parent = root,
		Name = "MenuDim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(5, 7, 12),
		BackgroundTransparency = 0.38,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 79,
	})
	dim.Activated:Connect(function()
		self:CloseAll()
	end)

	for _, menuName in ipairs(MenuConfig.Order) do
		buildWindow(menuName)
	end

	for _, menuName in ipairs(MenuConfig.Order) do
		local button = sidebarButtons[menuName]
		if button then
			button.Activated:Connect(function()
				self:Toggle(menuName)
			end)
		else
			warn("[MenuController] Could not find sidebar button for " .. menuName)
		end
	end

	-- The rest of the client already asks for this profile. This extra request is
	-- only a fallback for opening Backpack before the first sync arrives.
	if not latestProfile then
		task.defer(function()
			Remotes.RequestSync:FireServer()
		end)
	end
end

return MenuController