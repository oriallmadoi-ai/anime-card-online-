--!nonstrict
-- The skill tree screen.
--
-- The tree is NOT a GUI. It is real geometry on a flat board parked high above
-- the map, viewed straight down through a scriptable camera you drag and zoom
-- like a map. The flat UI is only what floats around it: a title plate, the
-- purse and the close button, an inspect panel for the selected skill, and two
-- small pills along the foot (the colour key and the controls).
--
-- THE OVERLAY'S LOOK
-- The Backpack's panel language - dark lit glass, hairline rims, corner
-- brackets, soft stacked-stroke shadows, one colour used as an ACCENT and
-- never as a fill - so the tree reads as the same game as the Backpack, the
-- Card Forge and Settings. The accent is the SELECTED SKILL'S category (mint
-- luck, amber coins, rose stats, a travelling rainbow for Elder), so the
-- panel, its emblem and its buttons always say which branch you are standing
-- in. Every plate slides and fades in when the tree opens, and the inspect
-- panel re-lights whenever the selection changes.
--
-- The client is a VIEWER. It never decides whether a purchase is legal - it asks
-- the server and repaints from whatever profile comes back, so the board cannot
-- show a rank the server did not grant. Effect text comes from the shared
-- SkillEffects registry, so "next: +8% luck" is written by the same code that
-- grants the +8%.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local SkillDefinitions = require(ReplicatedStorage.Shared.Config.SkillDefinitions)
local SkillEffects = require(ReplicatedStorage.Shared.Config.SkillEffects)
local SkillRemotes = require(ReplicatedStorage.Shared.Net.SkillRemotes)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local ElderCoin = require(ReplicatedStorage.Shared.UI.ElderCoin)
local UITheme = require(ReplicatedStorage.Shared.UI.UITheme)
local Sweep = require(ReplicatedStorage.Shared.UI.Sweep)
local Sfx = require(ReplicatedStorage.Shared.UI.Sfx)
local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)

local SkillTreeBoard = require(ReplicatedStorage.Shared.World.SkillTreeBoard)
local SkillNodePart = require(ReplicatedStorage.Shared.World.SkillNodePart)
local SkillLinkBeam = require(ReplicatedStorage.Shared.World.SkillLinkBeam)
local SkillTreeCamera = require(ReplicatedStorage.Shared.World.SkillTreeCamera)

local player = Players.LocalPlayer

local SkillTreeController = {}
SkillTreeController.Name = "SkillTreeController"

----------------------------------------------------------------------
-- palette (the Backpack's, so the two read as one family)
----------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TEXT = UITheme.Text
local MUTED = UITheme.TextMuted
local DIM = Color3.fromRGB(104, 110, 140)
local PANEL_TOP = Color3.fromRGB(24, 26, 41)
local PANEL_BOTTOM = Color3.fromRGB(9, 10, 17)
local SUNK = Color3.fromRGB(11, 12, 20)
local FIELD = Color3.fromRGB(29, 31, 48)
local LINE = Color3.fromRGB(62, 66, 100)
-- The tree's own violet: the accent when nothing is selected, and the flat
-- stand-in for Elder wherever a rainbow cannot go (a gradient behind text).
local ACCENT = Color3.fromRGB(150, 110, 255)
local ACCENT_HI = Color3.fromRGB(200, 176, 255)
local GOLD = Color3.fromRGB(255, 210, 110)
local GOOD = Color3.fromRGB(110, 232, 160)
local BAD = Color3.fromRGB(255, 112, 134)
local CLOSE_HOT_BG = Color3.fromRGB(78, 32, 50)

local QUART = Enum.EasingStyle.Quart
local QUAD = Enum.EasingStyle.Quad
local BACK = Enum.EasingStyle.Back

local TREE_ICON = "rbxassetid://87024386633723"

-- Design pixels. Each floating group carries one UIScale, set from the screen.
local EDGE = 18
local HEADER_W, HEADER_H = 452, 60
local TOP_H = 52
local PANEL_W = 360
local STAGE_H = 172
local BUTTON_H = { upgrade = 54, max = 42, reset = 34, maxed = 46 }

local CATEGORY_LABEL = { Luck = "LUCK", Coin = "COINS", Stat = "STATS", Elder = "ELDER" }
local LEGEND = { { "Luck", "LUCK" }, { "Coin", "COINS" }, { "Stat", "STATS" }, { "Elder", "ELDER" } }

local ui = {}
local groups = {}
local board = nil
local cam = nil
local selectedId: string? = nil
local hoveredId: string? = nil
local profile = nil
local isOpen = false
local hiddenGuis = {}

----------------------------------------------------------------------
-- small builders (same vocabulary as InventoryPresentation)
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

local function round()
	return new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function outline(color, transparency, thickness)
	return new("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function text(parent, name, value, size, color, z)
	return new("TextLabel", { Parent = parent, Name = name, BackgroundTransparency = 1,
		Text = value, FontFace = Theme.font(), TextSize = size, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = z or 1 })
end

-- An ink edge on a label: separation from whatever is behind it, not weight.
local function inked(label, thickness, transparency)
	new("UIStroke", { Parent = label, Color = BLACK, Thickness = thickness or 1.2,
		Transparency = transparency or 0.5, LineJoinMode = Enum.LineJoinMode.Round })
	return label
end

local function tween(object, properties, duration, style, direction)
	local motion = TweenService:Create(object, TweenInfo.new(duration or 0.14,
		style or QUAD, direction or Enum.EasingDirection.Out), properties)
	motion:Play()
	return motion
end

local function fadeEnds(peak)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, peak),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- A 1px line that fades out toward both ends.
local function hairline(parent, name, color, peak, props)
	local line = new("Frame", { Parent = parent, Name = name, BackgroundColor3 = color, ZIndex = 3 })
	for key, value in pairs(props or {}) do line[key] = value end
	new("UIGradient", { Parent = line, Transparency = fadeEnds(peak) })
	return line
end

local function diamond(parent, name, size, color, transparency, position, z)
	return new("Frame", { Parent = parent, Name = name, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.new(), Size = UDim2.fromOffset(size, size), Rotation = 45,
		BackgroundColor3 = color, BackgroundTransparency = transparency or 0, ZIndex = z or 3 })
end

local function cross(parent, length, thickness, color)
	for _, angle in ipairs({ -45, 45 }) do
		new("Frame", { Parent = parent, Name = "Cross", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(length, thickness),
			Rotation = angle, BackgroundColor3 = color, ZIndex = (parent.ZIndex or 1) + 2 }, { round() })
	end
end

-- An L-shaped corner accent. `anchor` picks the corner, (0,0) = top-left.
local function bracket(parent, anchor, inset, arm, color, transparency, z)
	local box = new("Frame", { Parent = parent, Name = "Bracket", BackgroundTransparency = 1, AnchorPoint = anchor,
		Position = UDim2.new(anchor.X, anchor.X == 0 and inset or -inset, anchor.Y, anchor.Y == 0 and inset or -inset),
		Size = UDim2.fromOffset(arm, arm), ZIndex = z })
	new("Frame", { Parent = box, Name = "H", AnchorPoint = anchor, Position = UDim2.fromScale(anchor.X, anchor.Y),
		Size = UDim2.new(1, 0, 0, 1.5), BackgroundColor3 = color, BackgroundTransparency = transparency, ZIndex = z })
	new("Frame", { Parent = box, Name = "V", AnchorPoint = anchor, Position = UDim2.fromScale(anchor.X, anchor.Y),
		Size = UDim2.new(0, 1.5, 1, 0), BackgroundColor3 = color, BackgroundTransparency = transparency, ZIndex = z })
	return box
end

local function brackets(parent, inset, arm, color, transparency, z)
	for _, anchor in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		bracket(parent, anchor, inset, arm, color, transparency, z)
	end
end

-- The Backpack's panel as a reusable plate: stacked-stroke shadow, graphite lit
-- from above, a rim brighter along its top edge, an inner hairline and a faint
-- sheen. Returns the panel to build on.
local function glass(holder, radius, sheen)
	local shadow = new("Frame", { Parent = holder, Name = "Shadow", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 1 }, { corner(radius) })
	for i, spec in ipairs({ { 3, 0.8 }, { 7, 0.88 }, { 12, 0.93 }, { 18, 0.96 } }) do
		new("UIStroke", { Parent = shadow, Name = "Shade" .. i, Color = BLACK, Thickness = spec[1],
			Transparency = spec[2], LineJoinMode = Enum.LineJoinMode.Round })
	end
	local panel = new("Frame", { Parent = holder, Name = "Panel", BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.04, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, {
		corner(radius),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(PANEL_TOP, PANEL_BOTTOM) }),
	})
	local rim = new("UIStroke", { Parent = panel, Name = "Rim", Color = WHITE, Thickness = 1.2, Transparency = 0.25 })
	new("UIGradient", { Parent = rim, Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, ACCENT_HI:Lerp(LINE, 0.35)),
		ColorSequenceKeypoint.new(0.45, LINE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 32, 50)),
	}) })
	new("Frame", { Parent = panel, Name = "InnerRim", BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2), ZIndex = 2 },
		{ corner(math.max(radius - 1, 0)), new("UIStroke", { Color = WHITE, Transparency = 0.95 }) })
	new("Frame", { Parent = panel, Name = "TopSheen", BackgroundColor3 = WHITE,
		Size = UDim2.new(1, 0, 0, sheen or 80), ZIndex = 2 },
		{ corner(radius), new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.955), NumberSequenceKeypoint.new(1, 1) }) }) })
	return panel
end

-- Clicks on a plain Frame are not "processed", so without one of these the
-- board camera behind would take every click on a panel as a pan or a pick.
local function blocker(holder)
	new("TextButton", { Parent = holder, Name = "InputBlocker", Text = "", AutoButtonColor = false,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Selectable = false, ZIndex = 0 })
end

----------------------------------------------------------------------
-- group fade (the Backpack's: see InventoryPresentation FADES)
----------------------------------------------------------------------

local FADE_PROPS = {
	Frame = { "BackgroundTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	ImageButton = { "BackgroundTransparency", "ImageTransparency" },
	ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
	UIStroke = { "Transparency" },
}

local Fade = {}
Fade.__index = Fade

function Fade.new(root)
	return setmetatable({ root = root, entries = nil, conn = nil }, Fade)
end

function Fade:capture()
	local list = {}
	local function walk(object)
		local props = FADE_PROPS[object.ClassName]
		if props then
			for _, prop in ipairs(props) do
				local rest = object[prop]
				if rest < 0.999 then
					table.insert(list, { object, prop, rest, rest })
				end
			end
		end
		for _, child in ipairs(object:GetChildren()) do walk(child) end
	end
	walk(self.root)
	return list
end

-- a = 0 is fully at rest, a = 1 is fully transparent.
function Fade:apply(a)
	for _, e in ipairs(self.entries) do
		local object = e[1]
		if object.Parent then
			local value = e[3] + (1 - e[3]) * a
			object[e[2]] = value
			e[4] = value
		end
	end
end

function Fade:stop(restore)
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if restore and self.entries then
		for _, e in ipairs(self.entries) do
			local object = e[1]
			-- Only hand back what nobody else has touched since we last wrote it.
			if object.Parent and math.abs(object[e[2]] - e[4]) < 0.002 then
				object[e[2]] = e[3]
			end
		end
		self.entries = nil
	end
end

function Fade:run(from, to, duration, onDone)
	self:stop(true)
	self.entries = self:capture()
	local start = os.clock()
	self:apply(from)
	self.conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / math.max(duration, 0.001), 0, 1)
		self:apply(from + (to - from) * TweenService:GetValue(t, QUAD, Enum.EasingDirection.Out))
		if t >= 1 then
			if self.conn then
				self.conn:Disconnect()
				self.conn = nil
			end
			if to <= 0 then self:stop(true) end
			if onDone then onDone() end
		end
	end)
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

-- Which skills each skill feeds, and the rank each of them needs from it: the
-- other half of Requirements, for the panel's LEADS TO list. Walked in board
-- order so the list reads the way the tree does.
local unlocksOf: { [string]: { { id: string, need: number } } } = {}
for _, id in ipairs(SkillDefinitions.Order) do
	local def = SkillDefinitions.Data[id]
	for reqId, need in pairs(def.Requirements or {}) do
		unlocksOf[reqId] = unlocksOf[reqId] or {}
		table.insert(unlocksOf[reqId], { id = id, need = need })
	end
end

----------------------------------------------------------------------
-- ACCENT AND RAINBOW
----------------------------------------------------------------------

-- Elder has no single colour. Everything that wears it is handed to ONE
-- heartbeat, which paints a travelling hue onto whichever property that thing
-- exposes - a UIStroke's Color, a label's TextColor3, a board part's Color -
-- so the panel, the node rims and the colour key all move together.
local rainbowTargets: { [Instance]: string } = {}
local rainbowConn = nil

local function startRainbow()
	if rainbowConn then return end
	local last = 0
	rainbowConn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last < 1 / 30 then return end
		last = now
		local colour = Color3.fromHSV((now * 0.18) % 1, 0.58, 1)
		local any = false
		for target, property in pairs(rainbowTargets) do
			if target.Parent then
				target[property] = colour
				any = true
			else
				rainbowTargets[target] = nil
			end
		end
		if not any and rainbowConn then
			rainbowConn:Disconnect()
			rainbowConn = nil
		end
	end)
end

local function stopRainbow()
	if rainbowConn then
		rainbowConn:Disconnect()
		rainbowConn = nil
	end
	table.clear(rainbowTargets)
end

-- Everything in the panel that wears the selected category, as
-- { instance, property }.
local accentParts = {}
local function accent(instance, property)
	table.insert(accentParts, { instance, property })
	return instance
end

-- Colours that are not one property (gradients, derived tints) are repainted
-- by these with a single flat colour; Elder hands them the tree's violet.
local accentPainters = {}

local function paintAccent(colour: Color3, rainbow: boolean)
	for _, entry in ipairs(accentParts) do
		local instance, property = entry[1], entry[2]
		if rainbow then
			rainbowTargets[instance] = property
		else
			rainbowTargets[instance] = nil
			instance[property] = colour
		end
	end
	local flat = rainbow and ACCENT or colour
	for _, painter in ipairs(accentPainters) do painter(flat) end
	if rainbow then startRainbow() end
end

----------------------------------------------------------------------
-- INSPECT PANEL
----------------------------------------------------------------------

-- The panel hugs what it is showing: stage, readout and buttons, never a tall
-- empty slab. It only scrolls when the screen is too short for the readout,
-- and it glides between heights when the selection changes.
local MIN_PANEL_H = 440
local panelTween = nil

local function resizePanel(instant: boolean?)
	local g = groups.Inspect
	if not (g and ui.infoLayout and ui.maxPanelH) then return end
	local s = math.max(g.scale.Scale, 0.01)
	local infoTop = 14 + STAGE_H + 12
	local content = ui.info.Visible and (ui.infoLayout.AbsoluteContentSize.Y / s + 8) or 96
	local needed = math.ceil(infoTop + content + 10 + (ui.buttonsH or 0))
	local height = math.clamp(needed, MIN_PANEL_H, ui.maxPanelH)
	local goal = UDim2.fromOffset(PANEL_W, height)
	if panelTween then
		panelTween:Cancel()
		panelTween = nil
	end
	if ui.inspect.Size == goal then return end
	if instant or not ui.screen.Enabled then
		ui.inspect.Size = goal
	else
		panelTween = tween(ui.inspect, { Size = goal }, 0.24, QUART)
	end
end

local function layoutButtons(instant: boolean?)
	if not ui.inspect then return end
	local y = 14
	local function place(object, height)
		object.Position = UDim2.new(0.5, 0, 1, -y)
		y += height + 8
	end
	place(ui.resetButton, BUTTON_H.reset)
	if ui.maxedBanner.Visible then place(ui.maxedBanner, BUTTON_H.maxed) end
	if ui.maxButton.Visible then place(ui.maxButton, BUTTON_H.max) end
	if ui.buyButton.Visible then place(ui.buyButton, BUTTON_H.upgrade) end
	-- The rule that separates what the skill IS from what you can DO with it.
	ui.buttonsRule.Position = UDim2.new(0.5, 0, 1, -(y + 2))
	local infoTop = 14 + STAGE_H + 12
	ui.info.Position = UDim2.fromOffset(16, infoTop)
	ui.info.Size = UDim2.new(1, -24, 1, -(infoTop + y + 10))
	ui.placeholder.Position = UDim2.fromOffset(16, infoTop + 6)
	ui.buttonsH = y
	resizePanel(instant)
end

local STATE_STYLE = {
	available = { "AVAILABLE", GOOD },
	owned = { "IN PROGRESS", nil },
	maxed = { "MAXED", GOLD },
	locked = { "LOCKED", BAD },
}

local function paintPrimary(enabled: boolean, def)
	local colour = def and (def.Rainbow and ACCENT or def.Colour) or ACCENT
	if enabled then
		ui.buyGradient.Color = ColorSequence.new(colour:Lerp(WHITE, 0.12), colour:Lerp(BLACK, 0.45))
		ui.buyGlow.Enabled = true
		ui.buyStroke.Transparency = 0.3
		ui.buyLabel.TextColor3 = WHITE
		ui.buySub.TextColor3 = WHITE
		ui.buySub.TextTransparency = 0.22
	else
		ui.buyGradient.Color = ColorSequence.new(FIELD, SUNK)
		ui.buyGlow.Enabled = false
		ui.buyStroke.Transparency = 0.55
		ui.buyLabel.TextColor3 = MUTED
		ui.buySub.TextColor3 = DIM
		ui.buySub.TextTransparency = 0
	end
end

local function requirementRow(order: number, name: string, have: number, need: number)
	local met = have >= need
	local tint = met and GOOD or BAD
	local row = new("Frame", { Parent = ui.reqBox, Name = "Req" .. order, LayoutOrder = order,
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), ZIndex = 5 })
	local mark = new("Frame", { Parent = row, Name = "Mark", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = tint, BackgroundTransparency = 0.84, ZIndex = 6 }, { round(), outline(tint, 0.35) })
	local tick = text(mark, "Tick", met and "\u{2713}" or "\u{2717}", 12, tint, 7)
	tick.Size = UDim2.fromScale(1, 1)
	tick.TextXAlignment = Enum.TextXAlignment.Center
	local label = text(row, "Name", name, 13, met and TEXT or MUTED, 6)
	label.Position = UDim2.fromOffset(26, 0)
	label.Size = UDim2.new(1, -120, 1, 0)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local count = text(row, "Count", ("%s / %s"):format(Format.comma(have), Format.comma(need)), 12, tint, 6)
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.fromScale(1, 0)
	count.Size = UDim2.new(0, 96, 1, 0)
	count.TextXAlignment = Enum.TextXAlignment.Right
	return row
end

local function unlockRow(order: number, childDef, need: number, have: number)
	local met = have >= need
	local row = new("Frame", { Parent = ui.unlockBox, Name = "Unlock" .. order, LayoutOrder = order,
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), ZIndex = 5 })
	diamond(row, "Dot", 8, childDef.Rainbow and ACCENT_HI or childDef.Colour, 0, UDim2.new(0, 9, 0.5, 0), 6)
	local label = text(row, "Name", childDef.Name, 13, met and TEXT or MUTED, 6)
	label.Position = UDim2.fromOffset(26, 0)
	label.Size = UDim2.new(1, -130, 1, 0)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local status = text(row, "Need", (met and "\u{2713} RANK %s" or "RANK %s"):format(Format.comma(need)),
		11, met and GOOD or DIM, 6)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.fromScale(1, 0)
	status.Size = UDim2.new(0, 104, 1, 0)
	status.TextXAlignment = Enum.TextXAlignment.Right
	return row
end

local function refreshPanel()
	if not ui.inspect then
		return
	end

	local def = selectedId and SkillDefinitions.get(selectedId)
	paintAccent(def and def.Colour or ACCENT, def and def.Rainbow or false)

	ui.placeholder.Visible = def == nil
	ui.info.Visible = def ~= nil
	ui.stageChips.Visible = def ~= nil

	if not def then
		ui.glyph.Text = "?"
		ui.buyButton.Visible = false
		ui.maxButton.Visible = false
		ui.maxedBanner.Visible = false
		layoutButtons()
		return
	end

	local rank = rankOf(def.Id)
	local maxed = rank >= def.MaxRank
	local state = stateOf(def)
	local tint = def.Rainbow and ACCENT_HI or def.Colour

	-- stage
	ui.glyph.Text = def.Glyph or "\u{25CF}"
	ui.categoryText.Text = CATEGORY_LABEL[def.Category] or string.upper(def.Category or "")
	ui.rankChipText.Text = ("RANK %s / %s"):format(Format.comma(rank), Format.comma(def.MaxRank))
	local style = STATE_STYLE[state] or STATE_STYLE.locked
	ui.stateText.Text = style[1]
	ui.stateText.TextColor3 = style[2] or tint
	ui.stateStroke.Color = style[2] or tint

	-- identity
	ui.name.Text = string.upper(def.Name)
	ui.rankText.Text = ("RANK %s / %s"):format(Format.comma(rank), Format.comma(def.MaxRank))
	local ratio = math.clamp(rank / math.max(def.MaxRank, 1), 0, 1)
	if maxed then
		ui.rankPercent.Text = "MAX"
	elseif rank > 0 and ratio < 0.001 then
		ui.rankPercent.Text = "<0.1%"
	else
		ui.rankPercent.Text = ("%.1f%%"):format(ratio * 100)
	end
	ui.rankFill.Visible = rank > 0
	tween(ui.rankFill, { Size = UDim2.fromScale(ratio, 1) }, 0.4, QUART)
	ui.desc.Text = def.Description

	-- now / next / cost
	local current = SkillEffects.DescribeRank(def, rank)
	ui.nowValue.Text = current or "No effect yet"
	ui.nowValue.TextColor3 = current and TEXT or DIM
	if maxed then
		ui.nextValue.Text = "Fully upgraded"
		ui.nextValue.TextColor3 = GOLD
	else
		ui.nextValue.Text = SkillEffects.DescribeRank(def, rank + 1) or "-"
		ui.nextValue.TextColor3 = GOOD
	end
	ui.costRow.Visible = not maxed
	ui.nextLine.Visible = not maxed
	local cost = not maxed and def.Cost(rank + 1) or 0
	if not maxed then
		ui.costValue.Text = Format.comma(cost)
		ui.costValue.TextColor3 = coins() >= cost and GOLD or BAD
	end

	-- requirements: one row each, with a tick or a cross, so a node blocked by
	-- three parents shows WHICH of the three is still missing.
	for _, row in ipairs(ui.reqRows) do row:Destroy() end
	table.clear(ui.reqRows)
	local reqIds = {}
	for reqId in pairs(def.Requirements or {}) do
		table.insert(reqIds, reqId)
	end
	table.sort(reqIds)
	if #reqIds == 0 then
		local none = text(ui.reqBox, "None", "Nothing - this is where the tree begins.", 12, DIM, 5)
		none.LayoutOrder = 1
		none.Size = UDim2.new(1, 0, 0, 18)
		table.insert(ui.reqRows, none)
	else
		for i, reqId in ipairs(reqIds) do
			local reqDef = SkillDefinitions.get(reqId)
			table.insert(ui.reqRows, requirementRow(i, reqDef and reqDef.Name or reqId,
				rankOf(reqId), def.Requirements[reqId]))
		end
	end

	-- what this skill feeds: each child, and the rank of THIS skill it waits on
	for _, row in ipairs(ui.unlockRows) do row:Destroy() end
	table.clear(ui.unlockRows)
	local children = unlocksOf[def.Id]
	if not children or #children == 0 then
		local none = text(ui.unlockBox, "None", "Nothing - this is the end of the path.", 12, DIM, 5)
		none.LayoutOrder = 1
		none.Size = UDim2.new(1, 0, 0, 18)
		table.insert(ui.unlockRows, none)
	else
		for i, child in ipairs(children) do
			table.insert(ui.unlockRows, unlockRow(i, SkillDefinitions.Data[child.id], child.need, rank))
		end
	end

	-- buttons
	ui.maxedBanner.Visible = maxed
	if maxed then
		ui.buyButton.Visible = false
		ui.maxButton.Visible = false
		ui.buyButton:SetAttribute("Enabled", false)
		ui.maxButton:SetAttribute("Enabled", false)
		layoutButtons()
		return
	end

	local affordable = coins() >= cost
	local unlocked = requirementsMet(def)
	local canBuy = affordable and unlocked

	ui.buyButton.Visible = true
	ui.buyLabel.Text = canBuy and "UPGRADE" or (not unlocked and "LOCKED" or "NOT ENOUGH COINS")
	if canBuy then
		ui.buySub.Text = ("+1 RANK  \u{00B7}  %s ELDER COINS"):format(Format.comma(cost))
	elseif not unlocked then
		ui.buySub.Text = "MEET THE REQUIREMENTS ABOVE FIRST"
	else
		local short = cost - coins()
		ui.buySub.Text = ("%s MORE ELDER %s NEEDED"):format(Format.comma(short), short == 1 and "COIN" or "COINS")
	end
	paintPrimary(canBuy, def)
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
		ui.maxLabel.Text = "MAX THIS SKILL"
	else
		ui.maxLabel.Text = ("SPEND MAX  \u{00B7}  +%s RANKS"):format(Format.comma(affordableRanks))
	end
	ui.maxButton:SetAttribute("Enabled", affordableRanks > 0 and unlocked)
	layoutButtons()
end

local function refreshProgress()
	if not ui.progressValue then return end
	local owned, total = 0, 0
	for _, id in ipairs(SkillDefinitions.Order) do
		total += 1
		if rankOf(id) > 0 then owned += 1 end
	end
	ui.progressValue.Text = ("%d / %d"):format(owned, total)
	tween(ui.progressFill, { Size = UDim2.fromScale(total > 0 and owned / total or 0, 1) }, 0.4, QUART)
end

----------------------------------------------------------------------
-- REFRESH
----------------------------------------------------------------------

local function refreshBoard()
	if board then
		for id, node in pairs(board.nodes) do
			SkillNodePart.setState(node, stateOf(node.def), rankOf(id))
			SkillNodePart.setSelected(node, id == selectedId)

			-- Elder nodes have no fixed colour. Their rim and halo go to the same
			-- driver as the panel - BasePart and UIStroke both expose a plain
			-- `.Color`, so one loop paints either. setState still tweens the rim
			-- on a state change; the driver overwrites it on the next frame, which
			-- is the intended precedence.
			if node.def.Rainbow and node.state ~= "locked" then
				rainbowTargets[node.rim] = "Color"
				rainbowTargets[node.halo] = "Color"
				if node.outer then rainbowTargets[node.outer] = "Color" end
				startRainbow()
			else
				rainbowTargets[node.rim] = nil
				rainbowTargets[node.halo] = nil
				if node.outer then rainbowTargets[node.outer] = nil end
			end
		end

		-- A connection lights only when the requirement it draws is satisfied, so
		-- the lit paths ARE the player's route through the tree at a glance.
		for _, entry in ipairs(board.links) do
			SkillLinkBeam.setActive(entry.link, rankOf(entry.from) >= entry.needed)
		end
	end

	if ui.coinLabel then
		ui.coinLabel.Text = Format.comma(coins())
	end
	refreshProgress()
	refreshPanel()
end

----------------------------------------------------------------------
-- MOTION
----------------------------------------------------------------------

local spinConn = nil
local function startSpin()
	if spinConn then return end
	spinConn = RunService.RenderStepped:Connect(function(dt)
		for _, arc in ipairs(ui.arcs or {}) do
			arc.gradient.Rotation = (arc.gradient.Rotation + arc.speed * dt) % 360
		end
	end)
end

local function stopSpin()
	if spinConn then
		spinConn:Disconnect()
		spinConn = nil
	end
end

-- Every plate slides a short way in from its own edge while it fades up - the
-- Backpack's settled entrance, spread across the screen.
local function playEntrance()
	local offsets = {
		Header = UDim2.fromOffset(0, -14),
		TopRight = UDim2.fromOffset(0, -14),
		Inspect = UDim2.fromOffset(30, 0),
		Footer = UDim2.fromOffset(0, 14),
	}
	for name, offset in pairs(offsets) do
		local g = groups[name]
		if g then
			g.holder.Position = g.rest + offset
			tween(g.holder, { Position = g.rest }, 0.4, QUART)
			g.fade:run(1, 0, 0.32)
		end
	end
	if ui.emblemScale then
		ui.emblemScale.Scale = 0.8
		tween(ui.emblemScale, { Scale = 1 }, 0.5, BACK)
	end
end

-- A different skill was picked: the panel re-lights rather than snapping.
local function playSwap()
	if not ui.info then return end
	ui.info.CanvasPosition = Vector2.zero
	ui.infoFade:run(1, 0, 0.22)
	ui.emblemScale.Scale = 0.84
	tween(ui.emblemScale, { Scale = 1 }, 0.42, BACK)
	ui.glow.Size = UDim2.fromOffset(220, 220)
	tween(ui.glow, { Size = UDim2.fromOffset(300, 300) }, 0.5, QUART)
end

-- A rank was bought: the emblem kicks and the stage flares.
local function punchEmblem()
	if not ui.emblemScale then return end
	ui.emblemScale.Scale = 1.18
	tween(ui.emblemScale, { Scale = 1 }, 0.6, Enum.EasingStyle.Elastic)
	ui.glow.ImageTransparency = 0.25
	tween(ui.glow, { ImageTransparency = 0.66 }, 0.7, QUAD)
	ui.stageFlash.BackgroundTransparency = 0.72
	tween(ui.stageFlash, { BackgroundTransparency = 1 }, 0.45, QUAD)
end

----------------------------------------------------------------------
-- SIZING
----------------------------------------------------------------------

local function fit()
	local gui = ui.screen
	if not gui then return end
	local size = gui.AbsoluteSize
	if size.X < 2 or size.Y < 2 then return end

	-- One scale for every plate, from the screen, then clamped so the inspect
	-- panel can always hold its own content.
	local s = math.clamp(math.min(size.X / 1720, size.Y / 960), 0.6, 1.08)
	s = math.max(0.42, math.min(s, (size.Y - 2 * EDGE) / 640))
	for _, g in pairs(groups) do g.scale.Scale = s end

	local top = EDGE + math.floor(HEADER_H * s) + 12
	groups.Header.rest = UDim2.fromOffset(EDGE, EDGE)
	-- Centred on the title plate's middle, which is taller than the cluster.
	groups.TopRight.rest = UDim2.new(1, -EDGE, 0, EDGE + math.floor((HEADER_H - TOP_H) * s / 2))
	groups.Inspect.rest = UDim2.new(1, -EDGE, 0, top)
	groups.Footer.rest = UDim2.new(0, EDGE, 1, -EDGE)
	-- The toast rides just above the foot pills rather than over them.
	groups.Toast.rest = UDim2.new(0.5, 0, 1, -(EDGE + math.floor(40 * s) + 12))
	for name, g in pairs(groups) do
		if name ~= "Toast" then g.holder.Position = g.rest end
	end
	ui.maxPanelH = math.max(MIN_PANEL_H, math.floor((size.Y - top - EDGE) / s))
	layoutButtons(true)
end

----------------------------------------------------------------------
-- OVERLAY
----------------------------------------------------------------------

local function group(parent, name, anchor, size)
	local holder = new("Frame", { Parent = parent, Name = name, AnchorPoint = anchor,
		Size = size, BackgroundTransparency = 1, ZIndex = 5 })
	local entry = { holder = holder, scale = new("UIScale", { Parent = holder, Scale = 1 }),
		rest = UDim2.new(), fade = Fade.new(holder) }
	groups[name] = entry
	return holder, entry
end

-- Hover lift and press squash, the Backpack's feel for every button here.
local function interactive(button, scale, onPaint)
	local over = false
	button.MouseEnter:Connect(function() over = true; onPaint(over) end)
	button.MouseLeave:Connect(function() over = false; onPaint(over) end)
	button.MouseButton1Down:Connect(function()
		if button:GetAttribute("Enabled") ~= false then tween(scale, { Scale = 0.965 }, 0.06) end
	end)
	button.MouseButton1Up:Connect(function() onPaint(over) end)
	Sfx.bindButton(button)
end

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
	-- button here would swallow the drags and clicks the camera needs. Every
	-- plate carries its own input blocker instead.

	------------------------------------------------------------------
	-- title plate
	------------------------------------------------------------------
	local header = group(gui, "Header", Vector2.new(0, 0), UDim2.fromOffset(HEADER_W, HEADER_H))
	blocker(header)
	local headerPanel = glass(header, 16, 56)
	hairline(headerPanel, "TopLight", ACCENT_HI, 0.3, { AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.6, 0, 0, 1) })
	brackets(headerPanel, 7, 10, ACCENT_HI, 0.62, 3)

	local badge = new("Frame", { Parent = headerPanel, Name = "IconBadge", BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(42, 42), ZIndex = 3 }, {
		corner(12),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ACCENT:Lerp(PANEL_TOP, 0.5), PANEL_BOTTOM:Lerp(ACCENT, 0.12)) }),
		outline(ACCENT, 0.45),
	})
	new("ImageLabel", { Parent = badge, Name = "Icon", BackgroundTransparency = 1, Image = TREE_ICON,
		ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8), ZIndex = 4 })
	local title = inked(text(headerPanel, "Title", "SKILL TREE", 26, TEXT, 4), 1.4, 0.45)
	title.Position = UDim2.fromOffset(66, 5)
	title.Size = UDim2.fromOffset(230, 30)
	local subtitle = text(headerPanel, "Subtitle", "ELDER UPGRADES", 12, DIM, 4)
	subtitle.Position = UDim2.fromOffset(67, 34)
	subtitle.Size = UDim2.fromOffset(200, 14)

	-- How much of the tree you own, at a glance.
	local progress = new("Frame", { Parent = headerPanel, Name = "Progress", AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(126, 40),
		BackgroundColor3 = SUNK, BackgroundTransparency = 0.25, ZIndex = 3 },
		{ corner(10), outline(WHITE, 0.92) })
	ui.progressValue = text(progress, "Value", "0 / 0", 16, TEXT, 4)
	ui.progressValue.Position = UDim2.fromOffset(12, 3)
	ui.progressValue.Size = UDim2.new(1, -24, 0, 19)
	local progressLabel = text(progress, "Label", "SKILLS OWNED", 9, DIM, 4)
	progressLabel.Position = UDim2.fromOffset(12, 21)
	progressLabel.Size = UDim2.new(1, -24, 0, 11)
	local progressTrack = new("Frame", { Parent = progress, Name = "Track", AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -5), Size = UDim2.new(1, -24, 0, 2), BackgroundColor3 = LINE,
		BackgroundTransparency = 0.3, ZIndex = 4 }, { round() })
	ui.progressFill = new("Frame", { Parent = progressTrack, Name = "Fill", Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = ACCENT_HI, ZIndex = 5 }, { round() })

	------------------------------------------------------------------
	-- purse and close
	------------------------------------------------------------------
	local cluster = group(gui, "TopRight", Vector2.new(1, 0), UDim2.fromOffset(320, TOP_H))
	new("UIListLayout", { Parent = cluster, FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder })

	local purse = new("Frame", { Parent = cluster, Name = "Purse", LayoutOrder = 1,
		Size = UDim2.fromOffset(236, TOP_H), BackgroundTransparency = 1, ZIndex = 5 })
	blocker(purse)
	local pursePanel = glass(purse, 14, 40)
	local coinBadge = new("Frame", { Parent = pursePanel, Name = "CoinBadge", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = WHITE, ZIndex = 3 }, {
		corner(10), outline(ElderCoin.Accent, 0.35, 1.2),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(38, 26, 78), Color3.fromRGB(12, 10, 26)) }),
	})
	ElderCoin.attach(coinBadge, { Size = UDim2.fromScale(0.92, 0.92), ZIndex = 4 })
	ui.coinLabel = inked(text(pursePanel, "Amount", "0", 20, GOLD, 4), 1.2, 0.5)
	ui.coinLabel.Position = UDim2.fromOffset(52, 0)
	ui.coinLabel.Size = UDim2.new(1, -122, 1, 0)
	ui.coinLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local coinCaption = text(pursePanel, "Caption", "ELDER\nCOINS", 9, DIM, 4)
	coinCaption.AnchorPoint = Vector2.new(1, 0.5)
	coinCaption.Position = UDim2.new(1, -12, 0.5, 0)
	coinCaption.Size = UDim2.fromOffset(58, 26)
	coinCaption.TextXAlignment = Enum.TextXAlignment.Right

	local closeHolder = new("Frame", { Parent = cluster, Name = "CloseHolder", LayoutOrder = 2,
		Size = UDim2.fromOffset(TOP_H, TOP_H), BackgroundTransparency = 1, ZIndex = 5 })
	local closePanel = glass(closeHolder, 14, 30)
	local closeHot = new("Frame", { Parent = closePanel, Name = "Hot", BackgroundColor3 = CLOSE_HOT_BG,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, { corner(14) })
	local close = new("TextButton", { Parent = closeHolder, Name = "Close", Text = "", AutoButtonColor = false,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6 })
	local closeGlyph = new("Frame", { Parent = closeHolder, Name = "Glyph", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 6 })
	cross(closeGlyph, 18, 2.2, TEXT)
	local closeRim = outline(BAD, 1, 1.4)
	closeRim.Parent = closePanel
	local closeScale = new("UIScale", { Parent = closeGlyph, Scale = 1 })
	interactive(close, closeScale, function(over)
		tween(closeHot, { BackgroundTransparency = over and 0.15 or 1 }, 0.14)
		tween(closeRim, { Transparency = over and 0.15 or 1 }, 0.14)
		tween(closeScale, { Scale = over and 1.1 or 1 }, 0.12)
	end)
	close.Activated:Connect(function()
		self:Close()
	end)

	------------------------------------------------------------------
	-- inspect panel
	------------------------------------------------------------------
	local inspect = group(gui, "Inspect", Vector2.new(1, 0), UDim2.fromOffset(PANEL_W, 640))
	ui.inspect = inspect
	blocker(inspect)
	local panel = glass(inspect, 18, 140)
	hairline(panel, "TopLight", ACCENT_HI, 0.3, { AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.62, 0, 0, 1) })
	brackets(panel, 10, 14, ACCENT_HI, 0.62, 3)

	-- THE STAGE: the selected node lifted off the board and blown up, on a
	-- measuring grid, with two scanning arcs turning around it.
	local stage = new("Frame", { Parent = panel, Name = "Stage", BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.02, Position = UDim2.fromOffset(14, 14),
		Size = UDim2.new(1, -28, 0, STAGE_H), ClipsDescendants = true, ZIndex = 3 }, { corner(14) })
	local stageGradient = new("UIGradient", { Parent = stage, Rotation = 90 })
	table.insert(accentPainters, function(colour)
		stageGradient.Color = ColorSequence.new(colour:Lerp(PANEL_TOP, 0.74), Color3.fromRGB(9, 9, 16))
	end)
	new("UIStroke", { Parent = stage, Color = WHITE, Transparency = 0.92, Thickness = 1 })
	for i = 1, 7 do
		new("Frame", { Parent = stage, Name = "GridV", BackgroundColor3 = WHITE, BackgroundTransparency = 0.955,
			Position = UDim2.new(i / 8, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 3 })
	end
	for i = 1, 3 do
		new("Frame", { Parent = stage, Name = "GridH", BackgroundColor3 = WHITE, BackgroundTransparency = 0.955,
			Position = UDim2.new(0, 0, i / 4, 0), Size = UDim2.new(1, 0, 0, 1), ZIndex = 3 })
	end
	ui.glow = accent(new("ImageLabel", { Parent = stage, Name = "Glow", BackgroundTransparency = 1,
		Image = VfxAssets.Glow, ImageTransparency = 0.66, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 300), ZIndex = 4 }), "ImageColor3")
	ui.stageFlash = new("Frame", { Parent = stage, Name = "Flash", BackgroundColor3 = WHITE,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 12 })

	local emblem = new("Frame", { Parent = stage, Name = "Emblem", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(150, 150), ZIndex = 5 })
	ui.emblemScale = new("UIScale", { Parent = emblem, Scale = 1 })
	ui.arcs = {}
	for i, spec in ipairs({ { 142, 70, 1.2 }, { 122, -110, 2 } }) do
		local ring = new("Frame", { Parent = emblem, Name = "Arc" .. i, BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(spec[1], spec[1]), ZIndex = 5 }, { round() })
		local arcStroke = accent(new("UIStroke", { Parent = ring, Color = ACCENT, Thickness = spec[3],
			Transparency = 0.05 }), "Color")
		local arcGradient = new("UIGradient", { Parent = arcStroke, Rotation = i * 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.28, 0.3),
				NumberSequenceKeypoint.new(0.46, 1),
				NumberSequenceKeypoint.new(1, 1),
			}) })
		table.insert(ui.arcs, { gradient = arcGradient, speed = spec[2] })
	end
	local disc = new("Frame", { Parent = emblem, Name = "Disc", BackgroundColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(100, 100), ZIndex = 6 }, { round() })
	local discGradient = new("UIGradient", { Parent = disc, Rotation = 90 })
	table.insert(accentPainters, function(colour)
		discGradient.Color = ColorSequence.new(colour:Lerp(SUNK, 0.7), SUNK)
	end)
	accent(new("UIStroke", { Parent = disc, Color = ACCENT, Thickness = 3, Transparency = 0 }), "Color")
	new("Frame", { Parent = disc, Name = "InnerRing", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -16, 1, -16), ZIndex = 7 },
		{ round(), new("UIStroke", { Color = WHITE, Transparency = 0.85, Thickness = 1 }) })
	ui.glyph = accent(inked(text(disc, "Glyph", "?", 44, WHITE, 8), 1.6, 0.35), "TextColor3")
	ui.glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.glyph.Position = UDim2.fromScale(0.5, 0.5)
	ui.glyph.Size = UDim2.fromScale(0.82, 0.82)
	ui.glyph.TextXAlignment = Enum.TextXAlignment.Center

	-- Chips riding the stage's corners and foot.
	ui.stageChips = new("Frame", { Parent = stage, Name = "Chips", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 9 })
	local function chip(name, anchor, position)
		local c = new("Frame", { Parent = ui.stageChips, Name = name, AnchorPoint = anchor, Position = position,
			Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = SUNK, BackgroundTransparency = 0.15, ZIndex = 9 },
			{ round(), new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
		local label = text(c, "Text", "", 11, TEXT, 10)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, 22)
		return c, label
	end
	local categoryChip, categoryText = chip("Category", Vector2.new(0, 0), UDim2.fromOffset(10, 10))
	local categoryStroke = accent(outline(ACCENT, 0.35), "Color")
	categoryStroke.Parent = categoryChip
	ui.categoryText = accent(categoryText, "TextColor3")
	local rankChip, rankChipText = chip("Rank", Vector2.new(1, 0), UDim2.new(1, -10, 0, 10))
	outline(WHITE, 0.88).Parent = rankChip
	ui.rankChipText = rankChipText
	local stateChip, stateText = chip("State", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -10))
	ui.stateStroke = outline(GOOD, 0.35)
	ui.stateStroke.Parent = stateChip
	ui.stateText = stateText
	brackets(stage, 8, 12, ACCENT_HI, 0.55, 10)

	-- THE READOUT: name, rank, what it does, what it costs, what it needs.
	local info = new("ScrollingFrame", { Parent = panel, Name = "Info", BackgroundTransparency = 1,
		ScrollBarThickness = 2, ScrollBarImageColor3 = ACCENT_HI, ScrollBarImageTransparency = 0.5,
		ScrollingDirection = Enum.ScrollingDirection.Y, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ZIndex = 3 },
		{ new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
			new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6) }) })
	ui.info = info
	ui.infoFade = Fade.new(info)

	ui.name = inked(text(info, "SkillName", "", 24, TEXT, 4), 1.2, 0.5)
	ui.name.LayoutOrder = 1
	ui.name.Size = UDim2.new(1, 0, 0, 30)
	ui.name.TextScaled = true
	new("UITextSizeConstraint", { Parent = ui.name, MaxTextSize = 24, MinTextSize = 14 })

	local rankRow = new("Frame", { Parent = info, Name = "RankRow", LayoutOrder = 2, BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16), ZIndex = 4 })
	ui.rankText = text(rankRow, "Rank", "", 12, MUTED, 4)
	ui.rankText.Size = UDim2.fromScale(0.7, 1)
	ui.rankPercent = accent(text(rankRow, "Percent", "", 12, ACCENT_HI, 4), "TextColor3")
	ui.rankPercent.AnchorPoint = Vector2.new(1, 0)
	ui.rankPercent.Position = UDim2.fromScale(1, 0)
	ui.rankPercent.Size = UDim2.fromScale(0.3, 1)
	ui.rankPercent.TextXAlignment = Enum.TextXAlignment.Right
	local rankTrack = new("Frame", { Parent = info, Name = "RankBar", LayoutOrder = 3, BackgroundColor3 = SUNK,
		Size = UDim2.new(1, 0, 0, 6), ZIndex = 4 }, { round(), outline(WHITE, 0.92) })
	ui.rankFill = accent(new("Frame", { Parent = rankTrack, Name = "Fill", BackgroundColor3 = ACCENT,
		Size = UDim2.fromScale(0, 1), ZIndex = 5 },
		{ round(), new("UISizeConstraint", { MinSize = Vector2.new(4, 0) }) }), "BackgroundColor3")

	ui.desc = text(info, "Description", "", 14, MUTED, 4)
	ui.desc.LayoutOrder = 4
	ui.desc.Size = UDim2.new(1, 0, 0, 0)
	ui.desc.AutomaticSize = Enum.AutomaticSize.Y
	ui.desc.TextWrapped = true
	ui.desc.TextYAlignment = Enum.TextYAlignment.Top

	local stats = new("Frame", { Parent = info, Name = "Stats", LayoutOrder = 5, BackgroundColor3 = SUNK,
		BackgroundTransparency = 0.3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 4 },
		{ corner(10), outline(WHITE, 0.94),
			new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2) }),
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })
	local function statRow(order, key)
		local row = new("Frame", { Parent = stats, Name = key, LayoutOrder = order, BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 32), ZIndex = 5 })
		local label = text(row, "Label", key, 11, DIM, 6)
		label.Size = UDim2.new(0, 56, 1, 0)
		local holder = new("Frame", { Parent = row, Name = "ValueHolder", AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1, ZIndex = 6 },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
		local value = text(holder, "Value", "", 14, TEXT, 6)
		value.LayoutOrder = 2
		value.AutomaticSize = Enum.AutomaticSize.X
		value.Size = UDim2.new(0, 0, 1, 0)
		value.TextXAlignment = Enum.TextXAlignment.Right
		local rule = new("Frame", { Parent = row, Name = "Line", BackgroundColor3 = WHITE, BackgroundTransparency = 0.93,
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 6 })
		return row, value, holder, rule
	end
	local _, nowValue = statRow(1, "NOW")
	ui.nowValue = nowValue
	local _, nextValue, _, nextLine = statRow(2, "NEXT")
	ui.nextValue, ui.nextLine = nextValue, nextLine
	local costRow, costValue, costHolder, costLine = statRow(3, "COST")
	ui.costRow, ui.costValue = costRow, costValue
	costLine.Visible = false
	ElderCoin.still(costHolder, { LayoutOrder = 1, AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(),
		Size = UDim2.fromOffset(18, 18), ZIndex = 7 })

	local reqBox = new("Frame", { Parent = info, Name = "Requirements", LayoutOrder = 6, BackgroundColor3 = SUNK,
		BackgroundTransparency = 0.3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 4 },
		{ corner(10), outline(WHITE, 0.94),
			new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9) }),
			new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local reqTitle = text(reqBox, "Title", "REQUIRES", 11, DIM, 5)
	reqTitle.LayoutOrder = 0
	reqTitle.Size = UDim2.new(1, 0, 0, 14)
	ui.reqBox = reqBox
	ui.reqRows = {}

	local unlockBox = new("Frame", { Parent = info, Name = "LeadsTo", LayoutOrder = 7, BackgroundColor3 = SUNK,
		BackgroundTransparency = 0.3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 4 },
		{ corner(10), outline(WHITE, 0.94),
			new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9) }),
			new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local unlockTitle = text(unlockBox, "Title", "LEADS TO", 11, DIM, 5)
	unlockTitle.LayoutOrder = 0
	unlockTitle.Size = UDim2.new(1, 0, 0, 14)
	ui.unlockBox = unlockBox
	ui.unlockRows = {}

	ui.infoLayout = info:FindFirstChildOfClass("UIListLayout")
	ui.infoLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		resizePanel()
	end)

	-- Nothing selected yet.
	ui.placeholder = new("Frame", { Parent = panel, Name = "Placeholder", BackgroundTransparency = 1,
		Visible = false, Size = UDim2.new(1, -32, 0, 90), ZIndex = 5 })
	diamond(ui.placeholder, "Mark", 10, ACCENT_HI, 0.55, UDim2.new(0.5, 0, 0, 10), 6)
	local placeholderText = text(ui.placeholder, "Text", "Pick a skill on the board to inspect it.", 14, MUTED, 6)
	placeholderText.Position = UDim2.fromOffset(0, 28)
	placeholderText.Size = UDim2.new(1, 0, 0, 40)
	placeholderText.TextWrapped = true
	placeholderText.TextXAlignment = Enum.TextXAlignment.Center

	-- ACTIONS, stacked up from the foot of the panel.
	ui.buttonsRule = hairline(panel, "ButtonsRule", ACCENT_HI, 0.7, { AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(1, -40, 0, 1) })

	local buy = new("TextButton", { Parent = panel, Name = "Upgrade", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(1, -28, 0, BUTTON_H.upgrade),
		BackgroundColor3 = WHITE, Visible = false, ZIndex = 5 }, { corner(12) })
	ui.buyButton = buy
	ui.buyGradient = new("UIGradient", { Parent = buy, Rotation = 90 })
	ui.buyStroke = accent(outline(ACCENT_HI, 0.3, 1.2), "Color")
	ui.buyStroke.Parent = buy
	ui.buyGlow = accent(new("UIStroke", { Parent = buy, Name = "Glow", Color = ACCENT, Thickness = 5,
		Transparency = 0.84, LineJoinMode = Enum.LineJoinMode.Round, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }), "Color")
	ui.buyScale = new("UIScale", { Parent = buy, Scale = 1 })
	ui.buyLabel = inked(text(buy, "Caption", "UPGRADE", 18, WHITE, 7), 1.2, 0.5)
	ui.buyLabel.AnchorPoint = Vector2.new(0.5, 0)
	ui.buyLabel.Position = UDim2.new(0.5, 0, 0, 8)
	ui.buyLabel.Size = UDim2.new(1, -24, 0, 22)
	ui.buyLabel.TextXAlignment = Enum.TextXAlignment.Center
	ui.buySub = text(buy, "Sub", "", 11, WHITE, 7)
	ui.buySub.AnchorPoint = Vector2.new(0.5, 0)
	ui.buySub.Position = UDim2.new(0.5, 0, 0, 31)
	ui.buySub.Size = UDim2.new(1, -24, 0, 14)
	ui.buySub.TextXAlignment = Enum.TextXAlignment.Center
	Sweep.attach(buy, { tint = WHITE, transparency = 0.84, width = 0.34, zIndex = 6 })
	interactive(buy, ui.buyScale, function(over)
		local enabled = buy:GetAttribute("Enabled") == true
		tween(ui.buyScale, { Scale = (over and enabled) and 1.025 or 1 }, 0.12)
		tween(ui.buyGlow, { Transparency = (over and enabled) and 0.7 or 0.84 }, 0.16)
	end)

	local max = new("TextButton", { Parent = panel, Name = "MaxOut", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(1, -28, 0, BUTTON_H.max),
		BackgroundColor3 = FIELD, BackgroundTransparency = 0.1, Visible = false, ZIndex = 5 }, { corner(10) })
	ui.maxButton = max
	local maxStroke = accent(outline(ACCENT, 0.25, 1.2), "Color")
	maxStroke.Parent = max
	ui.maxScale = new("UIScale", { Parent = max, Scale = 1 })
	ui.maxLabel = accent(inked(text(max, "Caption", "SPEND MAX", 15, ACCENT_HI, 7), 1, 0.55), "TextColor3")
	ui.maxLabel.Size = UDim2.fromScale(1, 1)
	ui.maxLabel.TextXAlignment = Enum.TextXAlignment.Center
	interactive(max, ui.maxScale, function(over)
		tween(ui.maxScale, { Scale = over and 1.02 or 1 }, 0.12)
		tween(max, { BackgroundColor3 = over and FIELD:Lerp(WHITE, 0.07) or FIELD }, 0.12)
		tween(maxStroke, { Transparency = over and 0 or 0.25 }, 0.12)
	end)

	ui.maxedBanner = new("Frame", { Parent = panel, Name = "MaxedBanner", AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.new(1, -28, 0, BUTTON_H.maxed), BackgroundColor3 = WHITE, Visible = false, ZIndex = 5 }, {
		corner(12),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(96, 74, 30), Color3.fromRGB(40, 30, 14)) }),
		outline(GOLD, 0.3, 1.2),
	})
	local maxedText = inked(text(ui.maxedBanner, "Caption", "FULLY UPGRADED", 16, GOLD, 6), 1.2, 0.5)
	maxedText.Size = UDim2.fromScale(1, 1)
	maxedText.TextXAlignment = Enum.TextXAlignment.Center

	-- RESET is two presses: the first arms it, the second (within three
	-- seconds) does it. Rebuying ranks is quick with SPEND MAX, but a stray
	-- click should still never wipe a tree.
	local reset = new("TextButton", { Parent = panel, Name = "Reset", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(1, -28, 0, BUTTON_H.reset),
		BackgroundColor3 = BAD, BackgroundTransparency = 1, ZIndex = 5 }, { corner(10) })
	ui.resetButton = reset
	local resetStroke = outline(BAD, 0.7, 1)
	resetStroke.Parent = reset
	local resetScale = new("UIScale", { Parent = reset, Scale = 1 })
	local resetLabel = text(reset, "Caption", "RESET TREE", 12, BAD, 7)
	resetLabel.Size = UDim2.fromScale(1, 1)
	resetLabel.TextXAlignment = Enum.TextXAlignment.Center
	local resetArmed, resetToken, resetOver = false, 0, false
	local function paintReset()
		resetLabel.Text = resetArmed and "PRESS AGAIN TO RESET  \u{00B7}  REFUNDS EVERY COIN" or "RESET TREE"
		resetLabel.TextColor3 = resetArmed and WHITE or BAD
		tween(reset, { BackgroundTransparency = resetArmed and 0.35 or (resetOver and 0.9 or 1) }, 0.12)
		tween(resetStroke, { Transparency = (resetArmed or resetOver) and 0.2 or 0.7 }, 0.12)
	end
	interactive(reset, resetScale, function(over)
		resetOver = over
		tween(resetScale, { Scale = over and 1.015 or 1 }, 0.12)
		paintReset()
	end)
	reset.Activated:Connect(function()
		if resetArmed then
			resetArmed = false
			paintReset()
			self:Reset()
			return
		end
		resetArmed = true
		resetToken += 1
		local mine = resetToken
		paintReset()
		task.delay(3, function()
			if mine == resetToken and resetArmed then
				resetArmed = false
				paintReset()
			end
		end)
	end)

	buy.Activated:Connect(function()
		self:Purchase("Purchase")
	end)
	max.Activated:Connect(function()
		self:Purchase("PurchaseMax")
	end)

	------------------------------------------------------------------
	-- the foot: colour key and controls
	------------------------------------------------------------------
	local footer = group(gui, "Footer", Vector2.new(0, 1), UDim2.fromOffset(720, 40))
	new("UIListLayout", { Parent = footer, FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder })
	local function pill(name, order, width)
		local holder = new("Frame", { Parent = footer, Name = name, LayoutOrder = order,
			Size = UDim2.fromOffset(width, 40), BackgroundTransparency = 1, ZIndex = 5 })
		blocker(holder)
		local pillPanel = glass(holder, 12, 28)
		return new("Frame", { Parent = pillPanel, Name = "Row", BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1), ZIndex = 3 }, {
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }) })
	end
	local function item(row, order)
		return new("Frame", { Parent = row, LayoutOrder = order, BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3 },
			{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder }) })
	end

	local legendRow = pill("Legend", 1, 318)
	for i, entry in ipairs(LEGEND) do
		local holder = item(legendRow, i)
		local dot = new("Frame", { Parent = holder, Name = "Dot", LayoutOrder = 1, Size = UDim2.fromOffset(9, 9),
			BackgroundColor3 = SkillDefinitions.CategoryColour[entry[1]] or ACCENT, ZIndex = 4 }, { round() })
		if entry[1] == SkillDefinitions.RainbowCategory then ui.legendRainbow = dot end
		local label = text(holder, "Label", entry[2], 11, MUTED, 4)
		label.LayoutOrder = 2
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, 20)
	end

	local controlsRow = pill("Controls", 2, 372)
	for i, entry in ipairs({ { "DRAG", "pan" }, { "SCROLL", "zoom" }, { "CLICK", "inspect" } }) do
		local holder = item(controlsRow, i)
		local key = new("Frame", { Parent = holder, Name = "Key", LayoutOrder = 1, Size = UDim2.fromOffset(0, 20),
			AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = FIELD, ZIndex = 4 },
			{ corner(6), outline(LINE, 0.25),
				new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }) })
		local keyText = text(key, "Text", entry[1], 10, TEXT, 5)
		keyText.AutomaticSize = Enum.AutomaticSize.X
		keyText.Size = UDim2.fromOffset(0, 20)
		local action = text(holder, "Action", entry[2], 12, MUTED, 4)
		action.LayoutOrder = 2
		action.AutomaticSize = Enum.AutomaticSize.X
		action.Size = UDim2.fromOffset(0, 20)
	end

	------------------------------------------------------------------
	-- toast
	------------------------------------------------------------------
	local toastHolder = new("Frame", { Parent = gui, Name = "Toast", AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -EDGE), Size = UDim2.fromOffset(0, 42), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(18, 19, 31), BackgroundTransparency = 0.04, Visible = false, ZIndex = 20 },
		{ corner(12), new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 18) }),
			new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder }) })
	groups.Toast = { holder = toastHolder, scale = new("UIScale", { Parent = toastHolder, Scale = 1 }),
		rest = UDim2.new(0.5, 0, 1, -EDGE), fade = Fade.new(toastHolder) }
	ui.toast = toastHolder
	ui.toastStroke = outline(GOOD, 0.35, 1.2)
	ui.toastStroke.Parent = toastHolder
	ui.toastDot = new("Frame", { Parent = toastHolder, Name = "Dot", LayoutOrder = 1, Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = GOOD, ZIndex = 21 }, { round() })
	ui.toastText = inked(text(toastHolder, "Text", "", 15, GOOD, 21), 1.2, 0.5)
	ui.toastText.LayoutOrder = 2
	ui.toastText.AutomaticSize = Enum.AutomaticSize.X
	ui.toastText.Size = UDim2.fromOffset(0, 42)

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	return gui
end

----------------------------------------------------------------------
-- ACTIONS
----------------------------------------------------------------------

local toastToken = 0

local function toast(message: string, colour: Color3)
	if not ui.toast then
		return
	end
	toastToken += 1
	local mine = toastToken
	local g = groups.Toast
	g.fade:stop(true)
	ui.toastText.Text = message
	ui.toastText.TextColor3 = colour
	ui.toastDot.BackgroundColor3 = colour
	ui.toastStroke.Color = colour
	ui.toast.Visible = true
	ui.toast.Position = g.rest + UDim2.fromOffset(0, 12)
	tween(ui.toast, { Position = g.rest }, 0.3, QUART)
	g.fade:run(1, 0, 0.2)
	task.delay(2.4, function()
		if mine ~= toastToken then return end
		g.fade:run(0, 1, 0.3, function()
			if mine ~= toastToken then return end
			ui.toast.Visible = false
			g.fade:stop(true)
		end)
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
			toast("Could not reach the server - try again", BAD)
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
			if id == selectedId then punchEmblem() end
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
			toast("Could not reach the server - try again", BAD)
			return
		end
		toast(tostring(reason), ok and GOLD or BAD)
	end)
end

local function selectNode(id: string?)
	if not id then
		return
	end
	local changed = id ~= selectedId
	selectedId = id
	refreshBoard()
	if changed then playSwap() end
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
	fit()
	if ui.legendRainbow then
		rainbowTargets[ui.legendRainbow] = "BackgroundColor3"
		startRainbow()
	end
	startSpin()
	playEntrance()
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
	-- The rainbow heartbeat and the arcs run on their own connections; leaving
	-- them going would keep repainting a screen nobody is looking at.
	stopRainbow()
	stopSpin()
	for _, g in pairs(groups) do
		g.fade:stop(true)
	end

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
		refreshBoard()
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
	refreshBoard()

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
