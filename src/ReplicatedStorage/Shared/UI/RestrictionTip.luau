--!strict
-- The fine print on a card, shown while SHIFT is held.
--
-- WHY IT IS NOT ON THE CARD FACE.
-- A card's ability text should read as what the ability DOES. Caps and
-- conditions ("4 times max", "only below half HP") are rules you consult when
-- comparing cards, not prose you want to re-read every time you glance at one -
-- and they were making the longest descriptions shrink to fit. So they moved
-- here, and PassiveDefinitions.restrictions derives them from the same clause
-- data the engine enforces, which means the number shown can never disagree
-- with the number applied.
--
-- HOW IT BEHAVES.
-- Hovering a card with restrictions shows a small SHIFT chip. Holding shift
-- expands it into the full list. Releasing collapses it again. The chip is what
-- makes the feature discoverable at all - without it nobody presses shift.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local PassiveDefinitions = require(ReplicatedStorage.Shared.Config.PassiveDefinitions)
local RarityBands = require(ReplicatedStorage.Shared.Config.RarityBands)
local UITheme = require(ReplicatedStorage.Shared.UI.UITheme)

local RestrictionTip = {}

local INK   = Color3.fromRGB(5, 5, 9)
local PANEL = Color3.fromRGB(13, 13, 20)
-- One text colour across every menu, from UITheme. See MenuController.
local TEXT  = UITheme.Text
local MUTED = UITheme.TextMuted

local WIDTH = 244
local ROW_H = 17

local gui: ScreenGui? = nil
local panel: Frame
local header: TextLabel
local rowHolder: Frame
local rows: { TextLabel } = {}
local chip: Frame
local chipLabel: TextLabel

local anchor: GuiObject? = nil
local lines: { string } = {}
local accent = MUTED

local function new(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	local parent = props.Parent
	for k, v in pairs(props) do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	if children then
		for _, c in ipairs(children) do c.Parent = inst end
	end
	if parent then inst.Parent = parent end
	return inst
end

local render: () -> ()

local function build()
	if gui then return end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = new("ScreenGui", {
		Name = "RestrictionTip",
		Parent = playerGui,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		-- Above the deck screen and its hover pop-out, below the battle board.
		DisplayOrder = 90,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})

	panel = new("Frame", {
		Name = "Panel", Parent = gui,
		Size = UDim2.fromOffset(WIDTH, 60),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0, Visible = false, ZIndex = 2,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 12) }),
		new("UIStroke", { Name = "Edge", Color = MUTED, Thickness = 1.4, Transparency = 0.15 }),
	})

	header = new("TextLabel", {
		Parent = panel,
		Position = UDim2.fromOffset(13, 10),
		Size = UDim2.new(1, -26, 0, 13),
		BackgroundTransparency = 1,
		Text = "RESTRICTIONS",
		FontFace = Theme.font(), TextSize = 11,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
	})

	rowHolder = new("Frame", {
		Parent = panel,
		Position = UDim2.fromOffset(13, 28),
		Size = UDim2.new(1, -26, 1, -38),
		BackgroundTransparency = 1, ZIndex = 3,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- The collapsed state: a small prompt that shift will reveal more.
	chip = new("Frame", {
		Name = "Chip", Parent = gui,
		Size = UDim2.fromOffset(96, 22),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0, Visible = false, ZIndex = 2,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 8) }),
		new("UIStroke", { Name = "Edge", Color = MUTED, Thickness = 1, Transparency = 0.4 }),
	})
	chipLabel = new("TextLabel", {
		Parent = chip, Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "\u{21E7} SHIFT  LIMITS",
		FontFace = Theme.font(), TextSize = 11,
		TextColor3 = MUTED, ZIndex = 3,
	})

	-- Wired here rather than in an Init the callers have to remember: one pair of
	-- connections for the whole game, installed the first time anything asks for
	-- a tip. A new hover site only has to call setTarget.
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			render()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			render()
		end
	end)
end

local function ensureRows(count: number)
	for i = #rows + 1, count do
		local label = new("TextLabel", {
			Parent = rowHolder, LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, ROW_H),
			BackgroundTransparency = 1,
			Text = "", FontFace = Theme.font(), TextSize = 12,
			TextColor3 = TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true, ZIndex = 4,
		})
		rows[i] = label
	end
end

-- Places a frame beside the anchor: to its right by default, flipped to the
-- left when that would run off screen, and clamped vertically. Anything that
-- opens half off the edge is worse than not opening.
local function place(frame: GuiObject, height: number)
	if not anchor or not anchor.Parent or not gui then return end
	local a = anchor
	local view = gui.AbsoluteSize
	local pos, size = a.AbsolutePosition, a.AbsoluteSize

	local x = pos.X + size.X + 10
	if x + frame.AbsoluteSize.X > view.X - 8 then
		x = pos.X - frame.AbsoluteSize.X - 10
	end
	x = math.clamp(x, 8, math.max(8, view.X - frame.AbsoluteSize.X - 8))

	local y = pos.Y + size.Y / 2 - height / 2
	y = math.clamp(y, 8, math.max(8, view.Y - height - 8))

	frame.Position = UDim2.fromOffset(x, y)
end

local function shiftHeld(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

function render()
	if not gui then return end

	if not anchor or not anchor.Parent or not anchor.Visible or #lines == 0 then
		gui.Enabled = false
		panel.Visible = false
		chip.Visible = false
		return
	end

	gui.Enabled = true

	if shiftHeld() then
		chip.Visible = false
		ensureRows(#lines)
		for i, label in ipairs(rows) do
			local line = lines[i]
			label.Visible = line ~= nil
			if line then label.Text = "\u{2022}  " .. line end
		end
		local height = 28 + #lines * (ROW_H + 4) + 8
		panel.Size = UDim2.fromOffset(WIDTH, height)
		local edge = panel:FindFirstChild("Edge") :: UIStroke
		if edge then edge.Color = accent end
		header.TextColor3 = accent
		panel.Visible = true
		place(panel, height)
	else
		panel.Visible = false
		local edge = chip:FindFirstChild("Edge") :: UIStroke
		if edge then edge.Color = accent end
		chipLabel.TextColor3 = accent
		chip.Visible = true
		place(chip, 22)
	end
end

----------------------------------------------------------------
-- PUBLIC
----------------------------------------------------------------

-- cardId: the card being hovered. anchorObject: what to sit beside - normally
-- the hover pop-out rather than the small tile, so the tip lands next to the
-- thing the player is actually reading.
function RestrictionTip.setTarget(cardId: string?, anchorObject: GuiObject?)
	build()

	local def = cardId and (CardDefinitions.get(cardId) or SupportDefinitions.get(cardId))
	if not def or not anchorObject then
		RestrictionTip.clear()
		return
	end

	lines = PassiveDefinitions.restrictions(def.passive)
	anchor = anchorObject
	accent = RarityBands.forDenominator(def.baseRarity).color
	render()
end

-- Passing the anchor makes this a no-op when a DIFFERENT card has already taken
-- over, which is what stops a stale MouseLeave from closing the tip for the
-- card the mouse has just moved onto.
function RestrictionTip.clear(anchorObject: GuiObject?)
	if anchorObject and anchor ~= anchorObject then return end
	anchor = nil
	lines = {}
	if gui then
		gui.Enabled = false
		panel.Visible = false
		chip.Visible = false
	end
end

return RestrictionTip
