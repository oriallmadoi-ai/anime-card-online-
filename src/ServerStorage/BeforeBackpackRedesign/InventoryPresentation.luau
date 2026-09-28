--!nonstrict
-- Backpack presentation only. Quantities always come from the existing profile.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Format = require(ReplicatedStorage.Shared.Util.Format)
local ElderCoin = require(ReplicatedStorage.Shared.UI.ElderCoin)
local ElderEssence = require(ReplicatedStorage.Shared.UI.ElderEssence)
local BookDefinitions = require(ReplicatedStorage.Shared.Config.BookDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)

local Inventory = {}
local WHITE = Color3.fromRGB(244, 245, 248)
local MUTED = Color3.fromRGB(151, 156, 167)
local PANEL = Color3.fromRGB(16, 18, 23)
local SLOT = Color3.fromRGB(33, 35, 41)
local TABS = { "All", "Currency", "Essence" }

local function new(className, props, children)
	local object = Instance.new(className)
	if object:IsA("GuiObject") then object.BorderSizePixel = 0 end
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then object[key] = value end
	end
	for _, child in ipairs(children or {}) do child.Parent = object end
	object.Parent = props and props.Parent
	return object
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function outline(color, transparency)
	return new("UIStroke", { Color = color, Thickness = 1, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function label(parent, name, text, size, color, z)
	return new("TextLabel", { Parent = parent, Name = name, BackgroundTransparency = 1,
		Text = text, Font = Enum.Font.GothamMedium, TextSize = size, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = z or 90 })
end

local function tween(object, properties, duration)
	local motion = TweenService:Create(object, TweenInfo.new(duration or 0.12,
		Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
	motion:Play()
	return motion
end

-- All interaction scale lives on the inner button, never on a grid/layout cell.
-- Tokens cancel delayed click settles when a newer input takes over.
local function feedback(button, restScale, onHover)
	local scale = new("UIScale", { Parent = button, Name = "InteractionScale", Scale = 1 })
	local hovered, token, motion = false, 0, nil
	local function animate(value, duration)
		if motion then motion:Cancel() end
		motion = tween(scale, { Scale = value }, duration)
	end
	local function resting() return restScale and restScale(hovered) or (hovered and 1.04 or 1) end
	local function hover(value)
		hovered = value
		token += 1
		animate(resting(), 0.12)
		if onHover then onHover(value) end
	end
	button.MouseEnter:Connect(function() hover(true) end)
	button.MouseLeave:Connect(function() hover(false) end)
	button.SelectionGained:Connect(function() hover(true) end)
	button.SelectionLost:Connect(function() hover(false) end)
	button.MouseButton1Down:Connect(function()
		token += 1
		animate(0.95, 0.055)
	end)
	button.Activated:Connect(function()
		token += 1
		local current = token
		animate(0.95, 0.045)
		task.delay(0.045, function()
			if token ~= current or not button.Parent then return end
			animate(1.03, 0.07)
			task.delay(0.07, function()
				if token == current and button.Parent then animate(resting(), 0.08) end
			end)
		end)
	end)
	return function() token += 1; animate(resting(), 0.12) end
end

local function quantity(profile, path)
	local value = profile
	for _, key in ipairs(path) do
		if type(value) ~= "table" then return 0 end
		value = value[key]
	end
	return math.max(0, math.floor(tonumber(value) or 0))
end

-- Display descriptors, not another inventory. Essence IDs remain the saved book IDs.
function Inventory.items(profile)
	local items = { { id = "ElderCoin", name = "Elder Coin", category = "Currency",
		variant = "Cosmic", detail = "Skill tree currency", quantity = quantity(profile, { "currency", "elderCoins" }),
		art = function(parent)
			return ElderCoin.still(parent, { Size = UDim2.fromScale(0.88, 0.88), ZIndex = 88 })
		end } }
	for _, id in ipairs(BookDefinitions.Order) do
		local def = BookDefinitions.get(id)
		if def then
			table.insert(items, { id = id, name = def.name, category = "Essence", tier = def.tier,
				variant = def.variant, quantity = quantity(profile, { "books", id }),
				detail = def.toMax and "To max level" or ("+%d %s"):format(def.levels, def.levels == 1 and "Level" or "Levels"),
				art = function(parent)
					return ElderEssence.attach(parent, def.tier, { Size = UDim2.fromScale(0.94, 0.94), ZIndex = 88 })
				end })
		end
	end
	return items
end

function Inventory.CreateInventorySlot(parent, item, order, tooltip)
	local variant = VariantConfig.get(item.variant)
	local cell = new("Frame", { Parent = parent, Name = item.id, LayoutOrder = order,
		BackgroundTransparency = 1, ZIndex = 85 })
	local button = new("TextButton", { Parent = cell, Name = "Slot", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = SLOT, BackgroundTransparency = 0.2, ZIndex = 86 },
		{ corner(6), outline(variant.color, 0.28) })
	button:SetAttribute("ItemId", item.id)
	button:SetAttribute("Category", item.category)
	local border = button:FindFirstChildOfClass("UIStroke")
	-- The highest tier retains its established Cosmic palette, on the thin rim only.
	if item.variant == "Cosmic" and variant.border.glowColours then
		local points = {}
		for i, color in ipairs(variant.border.glowColours) do
			table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#variant.border.glowColours - 1), color))
		end
		border.Color = Color3.new(1, 1, 1)
		new("UIGradient", { Parent = border, Color = ColorSequence.new(points), Rotation = 25 })
	end
	local art = new("Frame", { Parent = button, Name = "Art", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromScale(0.88, 0.88), ZIndex = 87 })
	item.art(art)
	local count = label(button, "Quantity", "", 12, Color3.fromRGB(23, 26, 32), 91)
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -4, 0, 4)
	count.BackgroundColor3 = WHITE
	count.BackgroundTransparency = 0
	count.TextXAlignment = Enum.TextXAlignment.Center
	count.Font = Enum.Font.GothamBold
	corner(8).Parent = count
	if item.tier then
		local badge = label(button, "Tier", item.tier, 11, variant.color, 90)
		badge.Position = UDim2.fromOffset(4, 4)
		badge.Size = UDim2.fromOffset(23, 19)
		badge.BackgroundTransparency = 0.1
		badge.BackgroundColor3 = PANEL
		badge.TextXAlignment = Enum.TextXAlignment.Center
		corner(4).Parent = badge
	end
	local function update(nextItem)
		item = nextItem
		button:SetAttribute("Quantity", item.quantity)
		local value = item.quantity < 10000 and tostring(item.quantity) or Format.short(item.quantity)
		count.Text = "x" .. value
		count.Size = UDim2.fromOffset(math.max(26, 10 + #count.Text * 7), 20)
		count.Visible = true
	end
	feedback(button, nil, function(hovered)
		tween(button, { BackgroundColor3 = hovered and Color3.fromRGB(43, 46, 54) or SLOT })
		tween(border, { Transparency = hovered and 0 or 0.28 })
		tween(art, { Position = UDim2.new(0.5, 0, 0.54, hovered and -2 or 0) })
		if tooltip then tooltip(hovered, item, button) end
	end)
	update(item)
	return { cell = cell, button = button, update = update }
end

function Inventory.createWindow(root, getProfile, onClose)
	local holder = new("Frame", { Parent = root, Name = "BackpackWindow", Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Active = true, ZIndex = 82 })
	local scale = new("UIScale", { Parent = holder, Name = "WindowScale", Scale = 1 })
	local decoration = new("Frame", { Parent = holder, Name = "ContourLines",
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 82 })
	local segments = {}
	local function contour(points, transparency, thickness)
		for i = 1, #points - 1 do
			local line = new("Frame", { Parent = decoration, Name = "Contour", AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.fromRGB(211, 222, 237), BackgroundTransparency = transparency,
				ZIndex = 82 }, { corner(1) })
			table.insert(segments, { frame = line, a = points[i], b = points[i + 1], thickness = thickness or 1 })
		end
	end
	-- Fine, angular contour trails frame the inventory without filling the screen.
	contour({{0.037,0.29},{0.067,0.13},{0.20,0.062},{0.49,0.072},{0.70,0.051},{0.92,0.070},{0.969,0.16},{0.965,0.69},{0.915,0.88},{0.70,0.928},{0.37,0.915},{0.092,0.94},{0.029,0.79},{0.037,0.29}}, 0.58, 1.3)
	contour({{0.051,0.29},{0.080,0.151},{0.206,0.082},{0.49,0.092},{0.70,0.072},{0.905,0.090}}, 0.86)
	contour({{0.949,0.62},{0.899,0.858},{0.697,0.906},{0.37,0.894},{0.109,0.917}}, 0.84)
	contour({{0.071,0.74},{0.10,0.79},{0.30,0.79},{0.34,0.75},{0.71,0.75},{0.78,0.68},{0.926,0.68}}, 0.94)
	contour({{0.13,0.848},{0.36,0.848},{0.41,0.802},{0.59,0.802}}, 0.92)
	contour({{0.68,0.17},{0.89,0.17},{0.92,0.205},{0.92,0.39}}, 0.89)
	local title = label(holder, "Title", "BACKPACK", 25, WHITE, 85)
	title.Font = Enum.Font.GothamBold
	new("UIStroke", { Parent = title, Thickness = 1.5, Color = Color3.fromRGB(0,0,0), Transparency = 0.3 })
	local sub = label(holder, "SectionLabel", "INVENTORY", 11, MUTED, 85)
	local tabs = new("Frame", { Parent = holder, Name = "Tabs", BackgroundTransparency = 1, ZIndex = 84 },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder }) })
	local rail = new("Frame", { Parent = holder, Name = "CategoryRail", BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.88, ZIndex = 83 })
	local search = new("TextBox", { Parent = holder, Name = "Search", Text = "", ClearTextOnFocus = false,
		PlaceholderText = "Search items...", PlaceholderColor3 = Color3.fromRGB(160, 164, 175),
		TextColor3 = WHITE, Font = Enum.Font.GothamMedium, TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left, BackgroundColor3 = Color3.fromRGB(34, 36, 42),
		BackgroundTransparency = 0.23, ZIndex = 85 },
		{ corner(7), outline(Color3.fromRGB(138, 146, 163), 0.6), new("UIPadding", {
			PaddingLeft = UDim.new(0, 43), PaddingRight = UDim.new(0, 14) }) })
	local lens = new("Frame", { Parent = search, Name = "SearchIcon", BackgroundTransparency = 1,
		Position = UDim2.new(0, -26, 0.5, -7), Size = UDim2.fromOffset(13, 13), ZIndex = 86 },
		{ corner(20), outline(MUTED, 0.08) })
	new("Frame", { Parent = lens, Name = "Handle", Position = UDim2.fromOffset(10, 12),
		Size = UDim2.fromOffset(7, 2), Rotation = 45, BackgroundColor3 = MUTED, ZIndex = 86 }, { corner(1) })
	local searchBorder = search:FindFirstChildOfClass("UIStroke")
	search.Focused:Connect(function() tween(searchBorder, {Transparency = 0.12}) end)
	search.FocusLost:Connect(function() tween(searchBorder, {Transparency = 0.6}) end)
	local close = new("TextButton", { Parent = holder, Name = "Close", Text = "", AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(53, 57, 66), BackgroundTransparency = 0.3, ZIndex = 90 },
		{ corner(6), outline(Color3.fromRGB(144, 151, 165), 0.67) })
	for _, angle in ipairs({ -45, 45 }) do
		new("Frame", { Parent = close, Name = "Cross", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(17, 2),
			Rotation = angle, BackgroundColor3 = WHITE, ZIndex = 91 }, { corner(1) })
	end
	feedback(close, function(h) return h and 1.04 or 1 end)
	close.Activated:Connect(onClose)
	local content = new("ScrollingFrame", { Parent = holder, Name = "Content",
		BackgroundTransparency = 1, ScrollBarThickness = 2,
		ScrollBarImageColor3 = Color3.fromRGB(184, 192, 205), ScrollBarImageTransparency = 0.62,
		ScrollingDirection = Enum.ScrollingDirection.Y, ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 84 },
		{ new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
	local grid = new("UIGridLayout", { Parent = content, CellSize = UDim2.fromOffset(90, 90),
		CellPadding = UDim2.fromOffset(9, 9), SortOrder = Enum.SortOrder.LayoutOrder })
	local empty = label(holder, "Empty", "No matching items", 18, WHITE, 85)
	empty.TextXAlignment = Enum.TextXAlignment.Center
	local tip = new("Frame", { Parent = holder, Name = "ItemTooltip", Visible = false,
		Size = UDim2.fromOffset(222, 83), BackgroundColor3 = Color3.fromRGB(22, 25, 32),
		BackgroundTransparency = 0.06, ZIndex = 110 }, { corner(6), outline(Color3.fromRGB(133, 144, 161), 0.3) })
	local tipName = label(tip, "ItemName", "", 15, WHITE, 111)
	tipName.Position = UDim2.fromOffset(12, 9); tipName.Size = UDim2.new(1, -24, 0, 22)
	local tipDetail = label(tip, "Detail", "", 13, MUTED, 111)
	tipDetail.Position = UDim2.fromOffset(12, 33); tipDetail.Size = UDim2.new(1, -24, 0, 18)
	local tipCount = label(tip, "Owned", "", 12, MUTED, 111)
	tipCount.Position = UDim2.fromOffset(12, 56); tipCount.Size = UDim2.new(1, -24, 0, 17)
	local tipOwner = nil
	local function tooltip(visible, item, button)
		if not visible then
			if tipOwner == button then tip.Visible = false; tipOwner = nil end
			return
		end
		tipOwner = button
		tipName.Text = item.name; tipDetail.Text = item.detail
		tipCount.Text = "Owned: " .. Format.comma(item.quantity)
		local unit = math.max(scale.Scale, 0.01)
		local point = (button.AbsolutePosition - holder.AbsolutePosition) / unit
		local width, height = holder.AbsoluteSize.X / unit, holder.AbsoluteSize.Y / unit
		local x = math.clamp(point.X, 10, math.max(10, width - 232))
		local y = point.Y + button.AbsoluteSize.Y / unit + 9
		if y + 83 > height - 12 then y = point.Y - 92 end
		tip.Position = UDim2.fromOffset(x, math.max(12, y)); tip.Visible = holder.Visible
	end
	local record = { name = "Backpack", holder = holder, scale = scale, content = content,
		tabButtons = {}, selectedTab = "All", baseScale = 1, motion = nil, transition = 0 }
	local slots, tabRest = {}, {}
	local function refresh()
		if not holder.Parent then return end
		local hoveredItem = nil
		local profile = getProfile()
		local query = string.lower(search.Text):match("^%s*(.-)%s*$")
		local visible, order = {}, 0
		local totals = { All = 0, Currency = 0, Essence = 0 }
		for _, item in ipairs(Inventory.items(profile)) do
			totals.All += 1; totals[item.category] = (totals[item.category] or 0) + 1
			local matches = query == "" or string.find(string.lower(item.name .. " " .. item.detail), query, 1, true) ~= nil
			-- All defined essences stay visible, including x0, as in the original Backpack.
			if matches and (record.selectedTab == "All" or record.selectedTab == item.category) then
				order += 1; visible[item.id] = true
				if not slots[item.id] then slots[item.id] = Inventory.CreateInventorySlot(content, item, order, tooltip)
				else slots[item.id].update(item) end
				slots[item.id].cell.LayoutOrder = order
				if tipOwner == slots[item.id].button then hoveredItem = item end
			end
		end
		for name, button in pairs(record.tabButtons) do button.Text = name .. " (" .. totals[name] .. ")" end
		for id, slot in pairs(slots) do if not visible[id] then slot.cell:Destroy(); slots[id] = nil end end
		if hoveredItem and tipOwner and tipOwner.Parent then tooltip(true, hoveredItem, tipOwner)
		else tip.Visible = false; tipOwner = nil end
		empty.Visible = order == 0
		empty.Text = "No matching items"
	end
	local function selectTab(tab)
		tip.Visible = false; tipOwner = nil; record.selectedTab = tab
		for name, button in pairs(record.tabButtons) do
			local selected = name == tab
			button:SetAttribute("Selected", selected)
			tween(button, { BackgroundColor3 = selected and WHITE or PANEL,
				BackgroundTransparency = selected and 0 or 0.5,
				TextColor3 = selected and Color3.fromRGB(15, 17, 22) or WHITE })
			button.ActiveMarker.Visible = selected
			if tabRest[name] then tabRest[name]() end
		end
		content.CanvasPosition = Vector2.zero; refresh()
	end
	for order, name in ipairs(TABS) do
		local cell = new("Frame", { Parent = tabs, Name = name .. "Cell", LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, ZIndex = 85 })
		local button = new("TextButton", { Parent = cell, Name = name, Text = name,
			Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = WHITE,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = PANEL, BackgroundTransparency = 0.5,
			AutoButtonColor = false, ZIndex = 86 }, { corner(5) })
		new("Frame", { Parent = button, Name = "ActiveMarker", AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -10, 0.5, 0), Size = UDim2.fromOffset(3, 26),
			BackgroundColor3 = WHITE, Visible = false, ZIndex = 86 }, { corner(2) })
		record.tabButtons[name] = button
		button.Activated:Connect(function() selectTab(name) end)
		tabRest[name] = feedback(button, function(hovered) return (record.selectedTab == name or hovered) and 1.025 or 1 end)
	end
	search:GetPropertyChangedSignal("Text"):Connect(function()
		tip.Visible = false; tipOwner = nil; content.CanvasPosition = Vector2.zero; refresh()
	end)
	local function fit()
		local size = root.AbsoluteSize
		if size.X < 1 or size.Y < 1 then return end
		if record.motion then record.motion:Cancel() end
		record.baseScale = 1; scale.Scale = 1
		holder.Size = UDim2.fromOffset(size.X, size.Y)
		local u = math.clamp(math.min(size.X / 1600, size.Y / 900), 0.65, 1.4)
		local left = math.floor(size.X * 0.087)
		local top = math.floor(size.Y * 0.135)
		local sideWidth = math.floor(math.min(size.X * 0.162, 248 * u))
		local gridX = left + sideWidth + 30 * u
		local gridWidth = size.X * 0.92 - gridX
		local gridY = top + 64 * u
		local gridHeight = size.Y * 0.85 - gridY
		title.Position = UDim2.fromOffset(left, top + 2 * u)
		title.Size = UDim2.fromOffset(sideWidth, 29 * u); title.TextSize = math.floor(24 * u)
		sub.Position = UDim2.fromOffset(left + 1, top + 33 * u)
		sub.Size = UDim2.fromOffset(sideWidth, 16 * u); sub.TextSize = math.floor(10 * u)
		tabs.Position = UDim2.fromOffset(left, gridY + 6)
		tabs.Size = UDim2.fromOffset(sideWidth, gridHeight)
		tabs.UIListLayout.Padding = UDim.new(0, 12 * u)
		for _, button in pairs(record.tabButtons) do
			button.Parent.Size = UDim2.new(1, 0, 0, math.floor(48 * u))
			button.TextSize = math.floor(21 * u)
		end
		rail.Position = UDim2.fromOffset(gridX - 15 * u, gridY + 6)
		rail.Size = UDim2.fromOffset(1, gridHeight - 12)
		search.Position = UDim2.fromOffset(gridX + 6, top)
		search.Size = UDim2.fromOffset(math.max(130, gridWidth - 66 * u), 44 * u)
		search.TextSize = math.floor(18 * u)
		close.Position = UDim2.fromOffset(gridX + gridWidth - 44 * u, top)
		close.Size = UDim2.fromOffset(44 * u, 44 * u)
		content.Position = UDim2.fromOffset(gridX, gridY)
		content.Size = UDim2.fromOffset(gridWidth, gridHeight)
		local gap = math.max(6, math.floor(9 * u))
		local columns = math.clamp(math.floor((gridWidth - 12 + gap) / (85 * u + gap)), 4, 12)
		local cell = math.floor((gridWidth - 14 - (columns - 1) * gap) / columns)
		grid.CellSize = UDim2.fromOffset(cell, cell); grid.CellPadding = UDim2.fromOffset(gap, gap)
		grid.FillDirectionMaxCells = columns
		empty.Position = UDim2.fromOffset(gridX, gridY + 36 * u)
		empty.Size = UDim2.fromOffset(gridWidth, 32 * u)
		for _, segment in ipairs(segments) do
			local a = Vector2.new(segment.a[1] * size.X, segment.a[2] * size.Y)
			local b = Vector2.new(segment.b[1] * size.X, segment.b[2] * size.Y)
			local delta = b - a
			segment.frame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
			segment.frame.Size = UDim2.fromOffset(delta.Magnitude, segment.thickness * u)
			segment.frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		end
		tip.Visible = false; tipOwner = nil
	end
	local resize = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	holder.Destroying:Connect(function() resize:Disconnect() end)
	holder:GetPropertyChangedSignal("Visible"):Connect(function()
		tip.Visible = false; tipOwner = nil
		if not holder.Visible then search:ReleaseFocus() end
	end)
	content:GetPropertyChangedSignal("CanvasPosition"):Connect(function() tip.Visible = false; tipOwner = nil end)
	fit(); selectTab("All")
	return record, refresh
end

return Inventory
