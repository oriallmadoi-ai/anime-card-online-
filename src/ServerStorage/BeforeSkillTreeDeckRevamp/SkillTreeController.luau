--!strict
-- The skill tree screen.
--
-- The tree is NOT a GUI. It is real geometry on a flat board parked high above
-- the map, viewed straight down through a scriptable camera you drag and zoom
-- like a map. The only flat UI is the overlay: a header and a details panel.
--
-- The client is a VIEWER. It never decides whether a purchase is legal - it asks
-- the server and repaints from whatever profile comes back, so the board cannot
-- show a rank the server did not grant. Effect text comes from the shared
-- SkillEffects registry, so "next: +8% luck" is written by the same code that
-- grants the +8%.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local SkillDefinitions = require(ReplicatedStorage.Shared.Config.SkillDefinitions)
local SkillEffects = require(ReplicatedStorage.Shared.Config.SkillEffects)
local SkillRemotes = require(ReplicatedStorage.Shared.Net.SkillRemotes)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local ElderCoin = require(ReplicatedStorage.Shared.UI.ElderCoin)
local PanelHeader = require(ReplicatedStorage.Shared.UI.PanelHeader)
local UITheme = require(ReplicatedStorage.Shared.UI.UITheme)

local SkillTreeBoard = require(ReplicatedStorage.Shared.World.SkillTreeBoard)
local SkillNodePart = require(ReplicatedStorage.Shared.World.SkillNodePart)
local SkillLinkBeam = require(ReplicatedStorage.Shared.World.SkillLinkBeam)
local SkillTreeCamera = require(ReplicatedStorage.Shared.World.SkillTreeCamera)

local player = Players.LocalPlayer

local SkillTreeController = {}
SkillTreeController.Name = "SkillTreeController"

local PANEL    = Color3.fromRGB(23, 24, 37)
local LINE     = Color3.fromRGB(52, 54, 78)
-- One text colour across every menu, from UITheme. See MenuController.
local TEXT     = UITheme.Text
local MUTED    = UITheme.TextMuted
local ACCENT   = Color3.fromRGB(150, 110, 255)
local GOLD     = Color3.fromRGB(255, 214, 110)
local GOOD     = Color3.fromRGB(104, 226, 140)
local BAD      = Color3.fromRGB(255, 116, 116)

local PANEL_W = 330

local ui = {}
local board = nil
local cam = nil
local selectedId: string? = nil
local hoveredId: string? = nil
local profile = nil
local isOpen = false
local hiddenGuis = {}

local function new(class: string, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = inst end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end

local function corner(r: number)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(colour: Color3, thickness: number?, transparency: number?)
	return new("UIStroke", {
		Color = colour,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
	})
end

local function text(props, children)
	local d = {
		BackgroundTransparency = 1,
		FontFace = Theme.font(),
		TextColor3 = TEXT,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in pairs(props) do d[k] = v end
	return new("TextLabel", d, children)
end

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------

local function ranks()
	return (profile and profile.skills) or {}
end

local function rankOf(id: string): number
	return ranks()[id] or 0
end

local function coins(): number
	return (profile and profile.currency and profile.currency.elderCoins) or 0
end

-- Mirrors the server's rule exactly. The server still re-checks on purchase, so
-- this only decides what a node LOOKS like.
local function requirementsMet(def): boolean
	for reqId, reqRank in pairs(def.Requirements or {}) do
		if rankOf(reqId) < reqRank then
			return false
		end
	end
	return true
end

local function stateOf(def): string
	local rank = rankOf(def.Id)
	if rank >= def.MaxRank then
		return "maxed"
	elseif rank > 0 then
		return "owned"
	elseif requirementsMet(def) then
		return "available"
	end
	return "locked"
end

----------------------------------------------------------------------
-- DETAILS PANEL
----------------------------------------------------------------------

-- The panel wears the SELECTED SKILL'S category colour: green for luck, yellow
-- for coins, red for stats. Elder is the exception - it has no single colour, so
-- its border runs a rainbow instead, driven by the one heartbeat below rather
-- than a tween per element.
local rainbowTargets = {}
local rainbowRunning = false
local stopRainbow

function stopRainbow()
	rainbowRunning = false
	table.clear(rainbowTargets)
end

local function startRainbow()
	if rainbowRunning then
		return
	end
	rainbowRunning = true
	task.spawn(function()
		while rainbowRunning do
			local hue = (os.clock() * 0.18) % 1
			local colour = Color3.fromHSV(hue, 0.62, 1)
			for target in pairs(rainbowTargets) do
				if target.Parent then
					target.Color = colour
				else
					rainbowTargets[target] = nil
				end
			end
			task.wait(1 / 30)
		end
	end)
end

local function setPanelAccent(def)
	if not ui.panelStroke then
		return
	end

	-- The details panel AND the skill action buttons wear the selected category:
	-- Luck = green, Coin = yellow, Stat = red, Elder = animated rainbow.
	local targets = { ui.panelStroke, ui.buyStroke, ui.maxStroke }
	for _, target in ipairs(targets) do
		if target then
			rainbowTargets[target] = nil
		end
	end

	if not def then
		ui.panelStroke.Color = ACCENT
		if ui.buyStroke then ui.buyStroke.Color = ACCENT end
		if ui.maxStroke then ui.maxStroke.Color = GOLD end
		if ui.pName then ui.pName.TextColor3 = TEXT end
		return
	end

	if def.Rainbow then
		for _, target in ipairs(targets) do
			if target then
				rainbowTargets[target] = true
			end
		end
		startRainbow()
	else
		for _, target in ipairs(targets) do
			if target then
				target.Color = def.Colour
			end
		end
	end

	ui.pName.TextColor3 = def.Rainbow and TEXT or def.Colour
end

local function refreshPanel()
	if not ui.panel then
		return
	end

	local def = selectedId and SkillDefinitions.get(selectedId)
	setPanelAccent(def)

	if not def then
		ui.pName.Text = "SELECT A SKILL"
		ui.pRank.Text = ""
		ui.pDesc.Text = "Drag to move around the board. Scroll to zoom. Click a node to inspect it."
		ui.pCurrent.Text = ""
		ui.pNext.Text = ""
		ui.pCost.Text = ""
		ui.pReq.Text = ""
		ui.buyButton.Visible = false
		ui.maxButton.Visible = false
		return
	end

	local rank = rankOf(selectedId :: string)
	local maxed = rank >= def.MaxRank

	ui.pName.Text = def.Name:upper()
	ui.pRank.Text = ("RANK %d / %d"):format(rank, def.MaxRank)
	ui.pDesc.Text = def.Description

	local current = SkillEffects.DescribeRank(def, rank)
	ui.pCurrent.Text = ("NOW    %s"):format(current or "no effect yet")
	ui.pCurrent.TextColor3 = current and TEXT or MUTED

	if maxed then
		ui.pNext.Text = "NEXT   fully upgraded"
		ui.pNext.TextColor3 = GOLD
	else
		ui.pNext.Text = ("NEXT   %s"):format(SkillEffects.DescribeRank(def, rank + 1) or "-")
		ui.pNext.TextColor3 = GOOD
	end

	-- Listed one per line with a tick or a cross, so a node blocked by three
	-- parents shows WHICH of the three is still missing.
	local reqIds = {}
	for reqId in pairs(def.Requirements or {}) do
		table.insert(reqIds, reqId)
	end
	table.sort(reqIds)

	if #reqIds == 0 then
		ui.pReq.Text = "REQUIRES   nothing"
		ui.pReq.TextColor3 = MUTED
	else
		local lines = { "REQUIRES" }
		local allMet = true
		for _, reqId in ipairs(reqIds) do
			local need = def.Requirements[reqId]
			local have = rankOf(reqId)
			local reqDef = SkillDefinitions.get(reqId)
			if have < need then allMet = false end
			table.insert(lines, ("   %s %s rank %d  (you have %d)")
				:format(have >= need and "\u{2713}" or "\u{2717}",
					reqDef and reqDef.Name or reqId, need, have))
		end
		ui.pReq.Text = table.concat(lines, "\n")
		ui.pReq.TextColor3 = allMet and GOOD or BAD
	end

	if maxed then
		ui.pCost.Text = ""
		ui.buyButton.Visible = false
		ui.maxButton.Visible = false
		return
	end

	local cost = def.Cost(rank + 1)
	local affordable = coins() >= cost
	local unlocked = requirementsMet(def)

	ui.pCost.Text = ("COST   %s Elder Coin%s"):format(Format.comma(cost), cost == 1 and "" or "s")
	ui.pCost.TextColor3 = affordable and TEXT or BAD

	local canBuy = affordable and unlocked

	ui.buyButton.Visible = true
	ui.buyLabel.Text = canBuy and "UPGRADE"
		or (not unlocked and "LOCKED" or "NOT ENOUGH COINS")

	local categoryColour = def.Colour
	ui.buyButton.BackgroundColor3 = canBuy
		and categoryColour:Lerp(Color3.fromRGB(22, 23, 35), 0.72)
		or Color3.fromRGB(40, 41, 58)

	-- Keep the category outline even when the button is unavailable; opacity tells
	-- the player it is disabled without losing the green/yellow/red/rainbow
	-- language of the selected branch.
	if not def.Rainbow then
		ui.buyStroke.Color = categoryColour
	end
	ui.buyStroke.Transparency = canBuy and 0.08 or 0.55
	ui.buyLabel.TextColor3 = canBuy and Color3.new(1, 1, 1) or MUTED
	ui.buyButton.AutoButtonColor = canBuy
	ui.buyButton:SetAttribute("Enabled", canBuy)

	-- How far the current balance actually reaches, walked rank by rank against
	-- the real cost curve. Dividing the balance by the next rank's price would be
	-- wrong on any skill whose cost rises - which is all of them.
	local affordableRanks, running = 0, coins()
	for r = rank + 1, def.MaxRank do
		local stepCost = def.Cost(r)
		if running < stepCost then break end
		running -= stepCost
		affordableRanks += 1
	end

	ui.maxButton.Visible = unlocked and affordableRanks > 1
	local remainingRanks = def.MaxRank - rank
	if affordableRanks >= remainingRanks then
		ui.maxLabel.Text = "MAX SKILL"
	else
		ui.maxLabel.Text = ("SPEND MAX  (+%s ranks)"):format(Format.comma(affordableRanks))
	end

	ui.maxButton.BackgroundColor3 = categoryColour:Lerp(Color3.fromRGB(20, 20, 32), 0.76)
	if not def.Rainbow then
		ui.maxStroke.Color = categoryColour
	end
	ui.maxStroke.Transparency = 0.08
	ui.maxLabel.TextColor3 = def.Rainbow and TEXT or categoryColour
	ui.maxButton:SetAttribute("Enabled", affordableRanks > 0 and unlocked)
end

----------------------------------------------------------------------
-- REFRESH
----------------------------------------------------------------------

local function refreshBoard()
	if not board then
		refreshPanel()
		return
	end

	for id, node in pairs(board.nodes) do
		SkillNodePart.setState(node, stateOf(node.def), rankOf(id))
		SkillNodePart.setSelected(node, id == selectedId)

		-- Elder nodes have no fixed colour. Their rim and halo are handed to the
		-- same driver that runs the panel border - BasePart and UIStroke both expose
		-- a plain `.Color`, so one loop can paint either. setState still tweens the
		-- rim on a state change; the driver simply overwrites it on the next frame,
		-- which is the intended precedence.
		if node.def.Rainbow and node.state ~= "locked" then
			rainbowTargets[node.rim] = true
			rainbowTargets[node.halo] = true
			startRainbow()
		else
			rainbowTargets[node.rim] = nil
			rainbowTargets[node.halo] = nil
		end
	end

	-- A connection lights only when the requirement it draws is satisfied, so the
	-- lit paths ARE the player's route through the tree at a glance.
	for _, entry in ipairs(board.links) do
		SkillLinkBeam.setActive(entry.link, rankOf(entry.from) >= entry.needed)
	end

	if ui.coinLabel then
		ui.coinLabel.Text = Format.comma(coins())
	end
	refreshPanel()
end

----------------------------------------------------------------------
-- OVERLAY
----------------------------------------------------------------------

function SkillTreeController:BuildOverlay()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = new("ScreenGui", {
		Name = "SkillTreeOverlay",
		Parent = playerGui,
		Enabled = false,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	ui.screen = gui

	-- NO BACKDROP. The board behind this IS the background, and a full-screen
	-- button here would swallow the drags and clicks the camera needs.
	local header = new("Frame", {
		Parent = gui, Name = "Header",
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundTransparency = 1,
		ZIndex = 10,
	})

	-- The title header, from the shared component. See PanelHeader for why the
	-- old diamond-and-hairline ribbon read as unfinished.
	PanelHeader.create({
		Parent = header,
		Name = "TitlePlate",
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.fromOffset(430, 48),
		accent = ACCENT,
		shade = ACCENT:Lerp(PANEL, 0.34),
		text = "SKILL TREE",
		textSize = 26,
		height = 48,
		zIndex = 10,
	})

	local purse = new("Frame", {
		Parent = header,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -150, 0.5, 0),
		Size = UDim2.fromOffset(178, 40),
		BackgroundColor3 = PANEL,
		ZIndex = 11,
	}, { corner(12), stroke(GOLD, 1.5, 0.35) })

	-- Cosmic badge behind the coin. Elder Coins are their own tier now, so the
	-- purse wears the same deep violet the reward tiles and the Backpack do
	-- rather than the old red secret-card treatment.
	local coinBadge = new("Frame", {
		Parent = purse,
		Position = UDim2.fromOffset(8, 5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = Color3.fromRGB(16, 14, 34),
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		ZIndex = 12,
	}, {
		corner(9),
		stroke(ElderCoin.Accent, 1.5, 0.28),
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 26, 78)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 10, 26)),
			}),
		}),
	})

	ElderCoin.attach(coinBadge, {
		Size = UDim2.fromScale(0.94, 0.94),
		ZIndex = 13,
	})

	ui.coinLabel = text({
		Parent = purse, Position = UDim2.fromOffset(48, 0),
		Size = UDim2.fromOffset(64, 40), Text = "0", TextSize = 19,
		TextColor3 = GOLD, ZIndex = 12,
	})

	text({
		Parent = purse, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(64, 32),
		Text = "ELDER\nCOINS", TextSize = 10, TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12,
	})

	local close = new("TextButton", {
		Parent = header, Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -30, 0.5, 0),
		Size = UDim2.fromOffset(52, 42),
		BackgroundColor3 = Color3.fromRGB(242, 76, 68), AutoButtonColor = false, Text = "X",
		FontFace = Theme.font(), TextSize = 19, TextColor3 = TEXT, ZIndex = 11,
	}, { corner(999), stroke(Color3.new(1, 1, 1), 2, 0.08) })
	close.Activated:Connect(function()
		self:Close()
	end)

	local panel = new("Frame", {
		Parent = gui, Name = "Details",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 82),
		Size = UDim2.new(0, PANEL_W, 1, -106),
		BackgroundColor3 = PANEL,
		-- Fully opaque. At any transparency the glowing nodes behind it read straight
		-- through the text, which is unreadable rather than atmospheric.
		BackgroundTransparency = 0,
		BorderSizePixel = 0, ZIndex = 4,
	}, {
		corner(16),
		new("UIPadding", {
			PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 20),
			PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20),
		}),
	})
	ui.panel = panel
	-- Kept as a reference, not just parented: setPanelAccent recolours it per
	-- selected skill and hands it to the rainbow driver for Elder nodes.
	ui.panelStroke = new("UIStroke", {
		Parent = panel, Color = ACCENT, Thickness = 2.4, Transparency = 0.12,
	})

	ui.pName = text({ Parent = panel, Size = UDim2.new(1, 0, 0, 26),
		Text = "SELECT A SKILL", TextSize = 19, ZIndex = 5 })
	ui.pRank = text({ Parent = panel, Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 16), Text = "", TextSize = 12,
		TextColor3 = MUTED, ZIndex = 5 })
	ui.pDesc = text({ Parent = panel, Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 60), Text = "", TextSize = 13, TextColor3 = MUTED,
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 5 })

	local function divider(y: number)
		return new("Frame", { Parent = panel, Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = LINE,
			BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 5 })
	end
	divider(122)

	ui.pCurrent = text({ Parent = panel, Position = UDim2.fromOffset(0, 136),
		Size = UDim2.new(1, 0, 0, 20), Text = "", TextSize = 13, ZIndex = 5 })
	ui.pNext = text({ Parent = panel, Position = UDim2.fromOffset(0, 158),
		Size = UDim2.new(1, 0, 0, 20), Text = "", TextSize = 13,
		TextColor3 = GOOD, ZIndex = 5 })
	divider(188)
	ui.pCost = text({ Parent = panel, Position = UDim2.fromOffset(0, 202),
		Size = UDim2.new(1, 0, 0, 20), Text = "", TextSize = 13,
		TextColor3 = GOLD, ZIndex = 5 })
	ui.pReq = text({ Parent = panel, Position = UDim2.fromOffset(0, 230),
		Size = UDim2.new(1, 0, 0, 96), Text = "", TextSize = 12, TextColor3 = MUTED,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 5 })

	-- Every button now carries its own outline rather than being a flat slab.
	-- `accent` is the colour that outline takes, so a button can be tinted to the
	-- category it acts on.
	local function actionButton(name: string, labelText: string, accent: Color3, y: number, height: number)
		local button = new("TextButton", {
			Parent = panel, Name = name,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, y),
			Size = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = Color3.fromRGB(30, 31, 48),
			AutoButtonColor = false,
			Text = "", Visible = false, ZIndex = 6,
		}, { corner(12) })

		local outline = new("UIStroke", {
			Parent = button, Color = accent, Thickness = 2.2, Transparency = 0.10,
		})

		local scale = new("UIScale", {
			Parent = button,
			Scale = 1,
		})

		-- Layered face rather than a flat rectangle.
		new("UIGradient", {
			Parent = button,
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.45, Color3.fromRGB(205, 205, 220)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(125, 126, 150)),
			}),
		})

		local label = text({
			Parent = button, Size = UDim2.fromScale(1, 1),
			Text = labelText, TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7,
		})

		local function tweenScale(target: number, duration: number)
			TweenService:Create(
				scale,
				TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = target }
			):Play()
		end

		button.MouseEnter:Connect(function()
			if button:GetAttribute("Enabled") ~= false then
				tweenScale(1.025, 0.10)
				outline.Thickness = 2.8
			end
		end)
		button.MouseLeave:Connect(function()
			tweenScale(1, 0.12)
			outline.Thickness = 2.2
		end)
		button.MouseButton1Down:Connect(function()
			if button:GetAttribute("Enabled") ~= false then
				tweenScale(0.975, 0.06)
			end
		end)
		button.MouseButton1Up:Connect(function()
			if button:GetAttribute("Enabled") ~= false then
				tweenScale(1.025, 0.08)
			end
		end)

		return button, label, outline
	end

	ui.buyButton, ui.buyLabel, ui.buyStroke = actionButton("Upgrade", "UPGRADE", ACCENT, -104, 46)
	ui.maxButton, ui.maxLabel, ui.maxStroke = actionButton("MaxOut", "MAX OUT", GOLD, -54, 42)
	ui.resetButton, ui.resetLabel, ui.resetStroke = actionButton("Reset", "RESET TREE", BAD, 0, 38)

	-- Reset is always available; the other two depend on the selected node.
	ui.resetButton.Visible = true

	ui.buyButton.Activated:Connect(function()
		self:Purchase("Purchase")
	end)
	ui.maxButton.Activated:Connect(function()
		self:Purchase("PurchaseMax")
	end)
	ui.resetButton.Activated:Connect(function()
		self:Reset()
	end)

	ui.hint = text({
		Parent = gui, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 38, 1, -18), Size = UDim2.fromOffset(520, 20),
		Text = "Drag to pan  \u{2022}  Scroll to zoom  \u{2022}  Click a node to inspect",
		TextSize = 13, TextColor3 = MUTED, ZIndex = 10,
	}, { stroke(Color3.new(0, 0, 0), 2.5) })

	ui.toast = text({
		Parent = gui, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(560, 24),
		Text = "", TextSize = 15, TextColor3 = BAD,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1, ZIndex = 20,
	}, { stroke(Color3.new(0, 0, 0), 2.5) })

	return gui
end

----------------------------------------------------------------------
-- ACTIONS
----------------------------------------------------------------------

local function toast(message: string, colour: Color3)
	if not ui.toast then
		return
	end
	ui.toast.Text = message
	ui.toast.TextColor3 = colour
	ui.toast.TextTransparency = 0
	task.delay(2.4, function()
		if ui.toast and ui.toast.Text == message then
			TweenService:Create(ui.toast, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		end
	end)
end

local purchasing = false

function SkillTreeController:Purchase(action: string)
	if purchasing or not selectedId then
		return
	end

	local button = action == "PurchaseMax" and ui.maxButton or ui.buyButton
	if button:GetAttribute("Enabled") ~= true then
		return
	end

	purchasing = true
	local id = selectedId

	task.spawn(function()
		-- pcall'd, and the flag cleared BEFORE anything else can fail. InvokeServer
		-- THROWS on the client if the server handler errors or the player leaves
		-- mid-call; without this the guard would stay true forever and the Upgrade
		-- button would go dead for the rest of the session with nothing shown.
		local sent, ok, reason = pcall(function()
			return SkillRemotes.Action:InvokeServer(action, id)
		end)
		purchasing = false

		if not sent then
			toast("could not reach the server, try again", BAD)
			return
		end

		if ok then
			local node = board and board.nodes[id]
			if node then
				SkillNodePart.punch(node)
			end
			-- Energy runs down every connection feeding this node, from each parent
			-- into the node just bought.
			if board then
				for _, entry in ipairs(board.links) do
					if entry.to == id then
						SkillLinkBeam.surge(entry.link)
					end
				end
			end
			toast(tostring(reason), GOOD)
			-- The profile sync the server sends next is what repaints the board.
			-- Refreshing here would race it and could redraw from the OLD profile.
		else
			toast(tostring(reason), BAD)
		end
	end)
end

-- Wipes every rank and refunds the coins. The server recomputes the refund from
-- the live cost curves, so the client neither knows nor needs to know the total.
function SkillTreeController:Reset()
	if purchasing then
		return
	end
	purchasing = true

	task.spawn(function()
		local sent, ok, reason = pcall(function()
			return SkillRemotes.Action:InvokeServer("Reset")
		end)
		purchasing = false

		if not sent then
			toast("could not reach the server, try again", BAD)
			return
		end
		toast(tostring(reason), ok and GOLD or BAD)
	end)
end

local function selectNode(id: string?)
	if not id then
		return
	end
	selectedId = id
	refreshBoard()
end

local function hoverNode(id: string?)
	if hoveredId == id then
		return
	end
	if board and hoveredId and board.nodes[hoveredId] then
		SkillNodePart.setHover(board.nodes[hoveredId], false)
	end
	hoveredId = id
	if board and id and board.nodes[id] then
		SkillNodePart.setHover(board.nodes[id], true)
	end
end

----------------------------------------------------------------------
-- CONTROLS
----------------------------------------------------------------------

-- The lobby HUD cannot simply be layered under the overlay any more: the board
-- is 3D, so a ScreenGui always draws in front of it whatever its DisplayOrder.
-- Every other gui is therefore switched off while the tree is open, and only
-- those actually on at the time are switched back - so a gui that was already
-- hidden does not get turned on when the tree closes.
local function setWorldGuisVisible(visible: boolean)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	if visible then
		for gui in pairs(hiddenGuis) do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		table.clear(hiddenGuis)
	else
		table.clear(hiddenGuis)
		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("ScreenGui") and gui.Enabled and gui ~= ui.screen then
				hiddenGuis[gui] = true
				gui.Enabled = false
			end
		end
	end
end

----------------------------------------------------------------------
-- LIGHTING
----------------------------------------------------------------------

-- The board is real geometry in the real world, so it is subject to the real
-- lighting - and this place runs an Atmosphere at Density 0.28 with Haze 1.6.
-- Haze washes distant objects toward the sky colour, and the camera sits ~2000
-- studs off the board, so untouched it renders as a pale blue smear with the
-- nodes barely visible through it. SunRays and DepthOfField add to it.
--
-- So while the tree is open the atmospherics are switched off and the world is
-- unlit: Neon still glows and every SurfaceGui already has LightInfluence 0, so
-- the board renders at exactly its authored colours while the dark plane goes
-- properly black instead of ambient-lit grey.
--
-- EVERY TOUCHED VALUE IS SAVED AND PUT BACK. LocationController owns lighting
-- for the lobby and islands; this borrows it briefly rather than redefining it,
-- and the player cannot travel while staring at the board.
local savedLighting = nil

local function setBoardLighting(on: boolean)
	local Lighting = game:GetService("Lighting")
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")

	if on then
		savedLighting = {
			ambient = Lighting.Ambient,
			outdoor = Lighting.OutdoorAmbient,
			brightness = Lighting.Brightness,
			shadows = Lighting.GlobalShadows,
			envDiffuse = Lighting.EnvironmentDiffuseScale,
			envSpecular = Lighting.EnvironmentSpecularScale,
			atmosphere = atmosphere and {
				instance = atmosphere,
				density = atmosphere.Density,
				haze = atmosphere.Haze,
				glare = atmosphere.Glare,
			} or nil,
			dof = dof and { instance = dof, enabled = dof.Enabled } or nil,
			sunRays = sunRays and { instance = sunRays, enabled = sunRays.Enabled } or nil,
		}

		Lighting.Ambient = Color3.new(0, 0, 0)
		Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
		Lighting.Brightness = 0
		Lighting.GlobalShadows = false
		Lighting.EnvironmentDiffuseScale = 0
		Lighting.EnvironmentSpecularScale = 0
		if atmosphere then
			atmosphere.Density = 0
			atmosphere.Haze = 0
			atmosphere.Glare = 0
		end
		if dof then dof.Enabled = false end
		if sunRays then sunRays.Enabled = false end
		return
	end

	local saved = savedLighting
	savedLighting = nil
	if not saved then
		return
	end

	Lighting.Ambient = saved.ambient
	Lighting.OutdoorAmbient = saved.outdoor
	Lighting.Brightness = saved.brightness
	Lighting.GlobalShadows = saved.shadows
	Lighting.EnvironmentDiffuseScale = saved.envDiffuse
	Lighting.EnvironmentSpecularScale = saved.envSpecular
	if saved.atmosphere and saved.atmosphere.instance.Parent then
		saved.atmosphere.instance.Density = saved.atmosphere.density
		saved.atmosphere.instance.Haze = saved.atmosphere.haze
		saved.atmosphere.instance.Glare = saved.atmosphere.glare
	end
	if saved.dof and saved.dof.instance.Parent then
		saved.dof.instance.Enabled = saved.dof.enabled
	end
	if saved.sunRays and saved.sunRays.instance.Parent then
		saved.sunRays.instance.Enabled = saved.sunRays.enabled
	end
end

-- Walking around while staring at a board 6000 studs away is nonsense, and the
-- default camera scripts would also fight the scriptable camera for control.
local function setControlsEnabled(enabled: boolean)
	local ok, controls = pcall(function()
		local playerScripts = player:WaitForChild("PlayerScripts", 5)
		local moduleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
		return require(moduleScript):GetControls()
	end)
	if ok and controls then
		if enabled then controls:Enable() else controls:Disable() end
	end
end

----------------------------------------------------------------------
-- OPEN / CLOSE
----------------------------------------------------------------------

-- Built on FIRST OPEN, not at startup. Generating a few dozen parts costs
-- nothing, but there is no reason to have them in Workspace for a player who
-- never opens the tree.
local function ensureBoard()
	if board then
		return
	end
	board = SkillTreeBoard.build()
	cam = SkillTreeCamera.new(board)
end

function SkillTreeController:Open()
	if isOpen then
		return
	end
	isOpen = true

	ensureBoard()
	board.world.Parent = Workspace

	-- Default the selection to the first thing the player can actually act on, so
	-- the panel is never empty on open.
	if not selectedId then
		for _, id in ipairs(SkillDefinitions.Order) do
			if stateOf(SkillDefinitions.Data[id]) == "available" then
				selectedId = id
				break
			end
		end
		selectedId = selectedId or SkillDefinitions.Order[1]
	end

	refreshBoard()

	setWorldGuisVisible(false)
	setControlsEnabled(false)
	setBoardLighting(true)

	cam:Start({
		onClick = selectNode,
		onHover = hoverNode,
	})

	ui.screen.Enabled = true
end

function SkillTreeController:Close()
	if not isOpen then
		return
	end
	isOpen = false

	if cam then
		cam:Stop()
	end
	hoverNode(nil)
	-- The rainbow heartbeat runs on its own thread; leaving it going would keep
	-- repainting a board nobody is looking at, every frame, forever.
	stopRainbow()

	ui.screen.Enabled = false
	setBoardLighting(false)
	setControlsEnabled(true)
	setWorldGuisVisible(true)

	-- Unparented rather than destroyed: rebuilding the board on every open would
	-- throw away the state and tweens for no gain.
	if board then
		board.world.Parent = nil
	end
end

function SkillTreeController:Toggle()
	if isOpen then
		self:Close()
	else
		self:Open()
	end
end

----------------------------------------------------------------------
-- LIFECYCLE
----------------------------------------------------------------------

function SkillTreeController:Init()
	-- The profile is the single source of truth for ranks and coins, and it
	-- already replicates through the existing ProfileSync - so there is no
	-- separate skill-state channel that could drift out of step with it.
	Remotes.ProfileSync.OnClientEvent:Connect(function(data)
		profile = data
		if board then
			refreshBoard()
		else
			refreshPanel()
		end
	end)

	SkillRemotes.Result.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and payload.type == "Coins" then
			toast(("+%d Elder Coins"):format(payload.amount or 0), GOLD)
		end
	end)
end

function SkillTreeController:Start()
	-- Built in Start, not Init: BuildOverlay yields on WaitForChild, and the
	-- client Bootstrap runs every Init sequentially on ONE thread - yielding there
	-- stalls every controller queued behind this one. MenuController learned that
	-- the hard way and deadlocked on the HUD for a full ten seconds.
	self:BuildOverlay()
	refreshPanel()

	-- The camera is scriptable only while the tree is open, so if the player dies
	-- or respawns with it open the camera has to be handed back or they are stuck
	-- staring at the board with no character control.
	player.CharacterAdded:Connect(function()
		if isOpen then
			self:Close()
		end
	end)

	print("[SkillTreeController] physical skill tree online")
end

return SkillTreeController
