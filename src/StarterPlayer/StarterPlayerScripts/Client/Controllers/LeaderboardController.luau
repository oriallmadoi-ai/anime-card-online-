--!strict
-- Compact current-server Battle Power leaderboard.
-- Reads ONLY server-published Player Attributes from LeaderboardService.
-- No Battle Power is calculated or sent by the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LeaderboardVisibility = require(ReplicatedStorage.Shared.UI.LeaderboardVisibility)
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local ArtLoader = require(ReplicatedStorage.Shared.UI.ArtLoader)
local UITheme = require(ReplicatedStorage.Shared.UI.UITheme)

local localPlayer = Players.LocalPlayer

local LeaderboardController = {}
LeaderboardController.Name = "LeaderboardController"

-- Neutral greys, matching the rest of the HUD. These were all navy, which made
-- the board read as a different app pasted over the game.
local PANEL = Color3.fromRGB(15, 15, 18)
local ROW = Color3.fromRGB(26, 26, 30)
local ROW_LOCAL = Color3.fromRGB(42, 42, 47)
local LINE = Color3.fromRGB(104, 104, 112)
local LINE_LOCAL = Color3.fromRGB(188, 188, 196)
-- One text colour across every menu, from UITheme. See MenuController.
-- USERNAME was its own third near-white eight points off TEXT; that was drift,
-- not a hierarchy, so it joins the other two.
local TEXT = UITheme.Text
local MUTED = UITheme.TextMuted
local USERNAME = UITheme.Text
local RANK_COLORS = {
	Color3.fromRGB(255, 208, 112),
	Color3.fromRGB(222, 222, 226),
	Color3.fromRGB(226, 161, 122),
}

local gui: ScreenGui
local panel: Frame
local list: ScrollingFrame
local panelScale: UIScale
local subtitle: TextLabel
local collapseButton: TextButton
local collapseTween: Tween?
local isCollapsed = false

local EXPANDED_PANEL_SIZE = UDim2.fromOffset(350, 390)
local COLLAPSED_PANEL_SIZE = UDim2.fromOffset(350, 58)

local rows: { [Player]: any } = {}
local playerConnections: { [Player]: { RBXScriptConnection } } = {}
local refreshQueued = false

local function new(className: string, props: any, children: { Instance }?)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(inst :: any)[key] = value
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

local function corner(radius: number)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color: Color3, thickness: number, transparency: number?)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

local function label(props: any)
	local data = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = Theme.font(),
		TextColor3 = TEXT,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
	for key, value in pairs(props) do
		data[key] = value
	end
	return new("TextLabel", data)
end

local function addTextOutline(textObject: GuiObject, thickness: number, transparency: number?)
	new("UIStroke", {
		Parent = textObject,
		Color = Color3.new(0, 0, 0),
		Thickness = thickness,
		Transparency = transparency or 0.1,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

local function addMovingPowerGradient(textObject: TextLabel): (UIGradient, Tween)
	-- TextColor3 stays white so the UIGradient supplies the actual colors.
	textObject.TextColor3 = Color3.new(1, 1, 1)

	local gradient = new("UIGradient", {
		Parent = textObject,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 55, 35)),
			ColorSequenceKeypoint.new(0.28, Color3.fromRGB(255, 104, 35)),
			ColorSequenceKeypoint.new(0.52, Color3.fromRGB(255, 178, 48)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 92, 28)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(230, 42, 28)),
		}),
		Offset = Vector2.new(-0.45, 0),
		Rotation = 0,
	}) :: UIGradient

	local tween = TweenService:Create(
		gradient,
		TweenInfo.new(1.55, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true),
		{ Offset = Vector2.new(0.45, 0) }
	)
	tween:Play()

	return gradient, tween
end

local function disableDefaultPlayerList()
	-- Hide Roblox's built-in PlayerList so only our custom leaderboard is visible.
	-- SetCoreGuiEnabled can occasionally be called before CoreGui is ready, so retry safely.
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			return
		end
		task.wait(0.2)
	end
	warn("[LeaderboardController] Could not disable Roblox PlayerList")
end

local function setCollapsed(collapsed: boolean)
	isCollapsed = collapsed

	if collapseTween then
		collapseTween:Cancel()
	end

	if collapsed then
		-- Arrow points down when the leaderboard can be expanded again.
		collapseButton.Text = "▼"
	else
		-- Arrow points up while expanded, showing that it can be collapsed.
		collapseButton.Text = "▲"
		subtitle.Visible = true
		list.Visible = true
	end

	collapseTween = TweenService:Create(
		panel,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = collapsed and COLLAPSED_PANEL_SIZE or EXPANDED_PANEL_SIZE }
	)
	collapseTween:Play()

	if collapsed then
		task.delay(0.2, function()
			if isCollapsed then
				subtitle.Visible = false
				list.Visible = false
			end
		end)
	end
end

local function numberAttribute(player: Player, name: string): number
	local value = player:GetAttribute(name)
	return typeof(value) == "number" and value or 0
end

local function createRow(player: Player)
	if rows[player] then return rows[player] end

	local frame = new("Frame", {
		Parent = list,
		Name = "Player_" .. player.UserId,
		Size = UDim2.new(1, -4, 0, 72),
		BackgroundColor3 = player == localPlayer and ROW_LOCAL or ROW,
		BackgroundTransparency = player == localPlayer and 0.14 or 0.22,
		BorderSizePixel = 0,
		ClipsDescendants = false,
	}, {
		corner(13),
	}) :: Frame

	local rowStroke = stroke(player == localPlayer and LINE_LOCAL or LINE, player == localPlayer and 1.4 or 1, 0.14)
	rowStroke.Parent = frame

	new("UIGradient", {
		Parent = frame,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 206)),
		Rotation = 18,
	})
	frame.MouseEnter:Connect(function()
		TweenService:Create(frame, TweenInfo.new(0.15), { BackgroundTransparency = 0 }):Play()
		TweenService:Create(rowStroke, TweenInfo.new(0.15), { Transparency = 0 }):Play()
	end)
	frame.MouseLeave:Connect(function()
		TweenService:Create(frame, TweenInfo.new(0.18), {
			BackgroundTransparency = player == localPlayer and 0.14 or 0.22,
		}):Play()
		TweenService:Create(rowStroke, TweenInfo.new(0.18), { Transparency = 0.14 }):Play()
	end)

	local thumbnail = new("Frame", {
		Parent = frame,
		Position = UDim2.new(0, 9, 0.5, -26),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = Color3.fromRGB(22, 22, 30),
		BorderSizePixel = 0,
		ClipsDescendants = false,
	}, {
		corner(12),
	}) :: Frame

	local rarityStroke = stroke(MUTED, 1.6, 0.1)
	rarityStroke.Parent = thumbnail

	local art = new("ImageLabel", {
		Parent = thumbnail,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(22, 22, 30),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Image = "",
		ScaleType = Enum.ScaleType.Crop,
		ClipsDescendants = true,
		ZIndex = 2,
	}, {
		corner(10),
	}) :: ImageLabel

	local placeholder = label({
		Parent = thumbnail,
		Size = UDim2.fromScale(1, 1),
		Text = "?",
		TextSize = 20,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	}) :: TextLabel

	local rankLabel = label({
		Parent = thumbnail, Name = "Rank",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 5, 1, 5),
		Size = UDim2.fromOffset(25, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(30, 30, 34),
		Text = "", TextSize = 10,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 8,
	}) :: TextLabel
	corner(6).Parent = rankLabel
	stroke(Color3.fromRGB(150, 150, 158), 1, 0.28).Parent = rankLabel

	if player == localPlayer then
		local you = label({
			Parent = frame, Name = "You",
			Position = UDim2.new(1, -38, 0, 9),
			Size = UDim2.fromOffset(29, 16),
			BackgroundColor3 = Color3.fromRGB(62, 62, 68),
			BackgroundTransparency = 0,
			Text = "YOU", TextSize = 8,
			TextColor3 = Color3.fromRGB(212, 212, 218),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		corner(5).Parent = you
	end

	local usernameText = label({
		Parent = frame,
		Position = UDim2.new(0, 72, 0, 5),
		Size = UDim2.new(1, player == localPlayer and -114 or -80, 0, 21),
		Text = player.Name,
		TextColor3 = USERNAME,
		TextSize = 17,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}) :: TextLabel
	addTextOutline(usernameText, 1.5, 0.14)

	local powerText = label({
		Parent = frame,
		Position = UDim2.new(0, 72, 0, 26),
		Size = UDim2.new(1, -80, 0, 23),
		Text = "Loading...",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 17,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}) :: TextLabel
	addTextOutline(powerText, 1.35, 0.16)
	local powerGradient, powerTween = addMovingPowerGradient(powerText)

	local rollsText = label({
		Parent = frame,
		Position = UDim2.new(0, 72, 0, 49),
		Size = UDim2.new(1, -80, 0, 17),
		Text = "",
		TextColor3 = TEXT,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}) :: TextLabel
	addTextOutline(rollsText, 1.05, 0.32)

	local row = {
		frame = frame,
		stroke = rowStroke,
		thumbnail = thumbnail,
		rarityStroke = rarityStroke,
		rank = rankLabel,
		art = art,
		placeholder = placeholder,
		username = usernameText,
		power = powerText,
		powerGradient = powerGradient,
		powerTween = powerTween,
		rolls = rollsText,
		lastCardId = nil,
		lastVariant = nil,
	}
	rows[player] = row
	return row
end

local function updateRow(player: Player, row: any, rank: number)
	row.frame.LayoutOrder = rank
	row.rank.Text = "#" .. tostring(rank)
	row.rank.TextColor3 = RANK_COLORS[rank] or TEXT
	row.username.Text = player.Name

	if player:GetAttribute("LeaderboardReady") ~= true then
		row.power.Text = "Loading..."
		row.rolls.Text = ""
		row.art.Image = ""
		row.placeholder.Visible = true
		return
	end

	local battlePower = numberAttribute(player, "BattlePower")
	local totalRolls = numberAttribute(player, "TotalRolls")
	row.power.Text = Format.comma(battlePower) .. " Battle Power"
	row.rolls.Text = Format.comma(totalRolls) .. " Rolls"

	local cardIdValue = player:GetAttribute("BestCardId")
	local variantValue = player:GetAttribute("BestCardVariant")
	local cardId = typeof(cardIdValue) == "string" and cardIdValue or ""
	local variant = typeof(variantValue) == "string" and variantValue or "Standard"

	if cardId ~= row.lastCardId or variant ~= row.lastVariant then
		row.lastCardId = cardId
		row.lastVariant = variant

		local def = cardId ~= "" and CardStats.definition(cardId) or nil
		local artId = def and def.art or ""
		-- The tier's colour, not the rarity band's. Shine.apply below draws this
		-- same thumbnail's border from VariantConfig, so a band-tinted stroke put
		-- two different colours on one frame - a Gilded card ringed in green.
		row.rarityStroke.Color = def and VariantConfig.get(variant).color or MUTED
		if artId and artId ~= "" then
			ArtLoader.set(row.art, artId)
			row.placeholder.Visible = false
		else
			row.art.Image = ""
			row.placeholder.Visible = true
		end

		-- Reuse the game's existing card variant border/effect system.
		Shine.apply(row.thumbnail, variant, 52)
	end
end

local function sortedPlayers(): { Player }
	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		local powerA = numberAttribute(a, "BattlePower")
		local powerB = numberAttribute(b, "BattlePower")
		if powerA ~= powerB then
			return powerA > powerB
		end

		local rollsA = numberAttribute(a, "TotalRolls")
		local rollsB = numberAttribute(b, "TotalRolls")
		if rollsA ~= rollsB then
			return rollsA > rollsB
		end

		return a.UserId < b.UserId
	end)
	return players
end

local function refresh()
	refreshQueued = false
	for rank, player in ipairs(sortedPlayers()) do
		local row = rows[player] or createRow(player)
		updateRow(player, row, rank)
	end
end

local function scheduleRefresh()
	if refreshQueued then return end
	refreshQueued = true
	task.defer(refresh)
end

local function disconnectPlayer(player: Player)
	local connections = playerConnections[player]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		playerConnections[player] = nil
	end

	local row = rows[player]
	if row then
		if row.powerTween then
			row.powerTween:Cancel()
		end
		if row.thumbnail then
			Shine.remove(row.thumbnail)
		end
		if row.frame then
			row.frame:Destroy()
		end
		rows[player] = nil
	end
end

local function watchPlayer(player: Player)
	if playerConnections[player] then return end
	createRow(player)

	local connections = {}
	for _, attributeName in ipairs({
		"BattlePower",
		"TotalRolls",
		"BestCardId",
		"BestCardVariant",
		"BestCardRarity",
		"LeaderboardReady",
		}) do
		table.insert(connections, player:GetAttributeChangedSignal(attributeName):Connect(scheduleRefresh))
	end
	playerConnections[player] = connections
	scheduleRefresh()
end

local function updateScale()
	local camera = Workspace.CurrentCamera
	if not camera or not panelScale then return end
	local viewport = camera.ViewportSize

	-- Keep it compact and tucked into the top-right on smaller screens.
	local widthScale = viewport.X / 1600
	local heightScale = viewport.Y / 900
	panelScale.Scale = math.clamp(math.min(widthScale, heightScale), 0.72, 1.0)
end

function LeaderboardController:Init()
	task.spawn(disableDefaultPlayerList)

	local playerGui = localPlayer:WaitForChild("PlayerGui")

	gui = new("ScreenGui", {
		Name = "BattlePowerLeaderboard",
		Parent = playerGui,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3,
	}) :: ScreenGui
	-- Shown or hidden from here on by LeaderboardVisibility alone.
	LeaderboardVisibility.attach(gui)

	panel = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = EXPANDED_PANEL_SIZE,
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {
		corner(16),
		stroke(Color3.fromRGB(120, 120, 128), 1.2, 0.2),
	}) :: Frame

	panelScale = new("UIScale", { Parent = panel, Scale = 1 }) :: UIScale

	local headerBand = new("Frame", {
		Parent = panel, Name = "HeaderBand",
		Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 0, 54),
		BackgroundColor3 = Color3.fromRGB(34, 34, 38),
		BorderSizePixel = 0,
	}, { corner(15) })
	new("UIGradient", {
		Parent = headerBand,
		Color = ColorSequence.new(Color3.fromRGB(228, 228, 232), Color3.fromRGB(94, 94, 102)),
		Rotation = 8,
	})
	local emblem = label({
		Parent = panel, Name = "PowerEmblem",
		Position = UDim2.fromOffset(11, 10),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Color3.fromRGB(58, 58, 64), BackgroundTransparency = 0,
		Text = "BP", TextSize = 12,
		TextColor3 = Color3.fromRGB(210, 210, 216),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	corner(10).Parent = emblem
	stroke(Color3.fromRGB(196, 196, 204), 1, 0.25).Parent = emblem

	local header = label({
		Parent = panel,
		Position = UDim2.new(0, 53, 0, 9),
		Size = UDim2.new(1, -107, 0, 21),
		Text = "LEADERBOARD",
		TextSize = 18,
		TextColor3 = TEXT,
	}) :: TextLabel
	addTextOutline(header, 1.35, 0.25)

	subtitle = label({
		Parent = panel,
		Position = UDim2.new(0, 53, 0, 30),
		Size = UDim2.new(1, -107, 0, 14),
		Text = "CURRENT SERVER  •  LIVE RANKINGS",
		TextSize = 9,
		TextColor3 = MUTED,
	}) :: TextLabel

	collapseButton = new("TextButton", {
		Parent = panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 11),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Color3.fromRGB(44, 44, 50),
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = Theme.font(),
		Text = "▲",
		TextColor3 = TEXT,
		TextSize = 16,
		ZIndex = 20,
	}, {
		corner(8),
		stroke(Color3.fromRGB(92, 92, 112), 1, 0.18),
	}) :: TextButton
	addTextOutline(collapseButton, 1, 0.3)

	collapseButton.MouseEnter:Connect(function()
		TweenService:Create(
			collapseButton,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(76, 76, 84) }
		):Play()
	end)

	collapseButton.MouseLeave:Connect(function()
		TweenService:Create(
			collapseButton,
			TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.12, BackgroundColor3 = Color3.fromRGB(44, 44, 50) }
		):Play()
	end)

	collapseButton.Activated:Connect(function()
		setCollapsed(not isCollapsed)
	end)

	list = new("ScrollingFrame", {
		Parent = panel,
		Position = UDim2.new(0, 8, 0, 63),
		Size = UDim2.new(1, -16, 1, -71),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.fromRGB(176, 176, 184),
		ScrollBarImageTransparency = 0.22,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}, {
		new("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
		new("UIPadding", {
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 3),
			PaddingLeft = UDim.new(0, 2),
			PaddingRight = UDim.new(0, 2),
		}),
	}) :: ScrollingFrame

	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		disconnectPlayer(player)
		scheduleRefresh()
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end

	local function reconnectCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(reconnectCamera)
	reconnectCamera()

	refresh()
end

return LeaderboardController
