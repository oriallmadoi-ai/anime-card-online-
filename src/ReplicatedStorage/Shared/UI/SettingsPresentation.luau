--!nonstrict
-- Anime Card Online
-- The Settings window: a bar for sound effects, a bar for music, nothing else.
--
-- LOOK
-- The Backpack's panel language - dark lit panel, hairline rim, corner
-- brackets, the same header and close button - in blue and graphite instead
-- of violet. It is a short list, so it is a small fixed panel rather than a
-- window that stretches toward the edges of the screen.
--
-- THE BARS
-- Click anywhere on a bar to jump there, or drag it; touch works the same way.
-- The new level is heard while dragging and saved when the bar is let go. The
-- buses and the saving belong to AudioController - this only draws them. A
-- bar at zero reads OFF.
--
-- MenuController still opens and closes the window. Like the Backpack's
-- record, this one only describes how it enters and leaves (openFrom /
-- openTween / onOpen / onClose).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local MenuConfig = require(ReplicatedStorage.Shared.Config.MenuConfig)
local Sfx = require(ReplicatedStorage.Shared.UI.Sfx)

local SettingsPresentation = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TEXT = Color3.fromRGB(238, 242, 250)
local DIM = Color3.fromRGB(98, 108, 130)
local PANEL_TOP = Color3.fromRGB(25, 29, 40)
local PANEL_BOTTOM = Color3.fromRGB(10, 11, 16)
local ROW = Color3.fromRGB(19, 22, 31)
local TRACK = Color3.fromRGB(38, 43, 58)
local LINE = Color3.fromRGB(58, 66, 90)
-- Blue is an ACCENT here, never a fill: the rim, the brackets, the bars.
local ACCENT = Color3.fromRGB(56, 150, 255)
local ACCENT_HI = Color3.fromRGB(150, 205, 255)
local ACCENT_DEEP = Color3.fromRGB(26, 88, 214)
local CLOSE_BG = Color3.fromRGB(30, 34, 46)
local CLOSE_BG_HOT = Color3.fromRGB(78, 32, 50)
local CLOSE_HOT = Color3.fromRGB(255, 112, 134)

local QUART = Enum.EasingStyle.Quart
local QUAD = Enum.EasingStyle.Quad

-- Design size. One UIScale fits it to the screen.
local W, H = 440, 274
local ROW_TOP, ROW_H, ROW_GAP = 88, 76, 12

-- Top to bottom. `bus` is the AudioController bus the bar drives.
local BARS = {
	{ bus = "SFX", label = "SOUND EFFECTS" },
	{ bus = "Music", label = "MUSIC" },
}

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
		Text = value, Font = Enum.Font.GothamMedium, TextSize = size, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = z or 1 })
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
	local line = new("Frame", { Parent = parent, Name = name, BackgroundColor3 = color, ZIndex = 2 })
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
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(length, thickness), Rotation = angle,
			BackgroundColor3 = color, ZIndex = (parent.ZIndex or 1) + 1 }, { round() })
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
end

local function brackets(parent, inset, arm, color, transparency, z)
	for _, anchor in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		bracket(parent, anchor, inset, arm, color, transparency, z)
	end
end

----------------------------------------------------------------------
-- group fade (the Backpack's: see InventoryPresentation FADES)
----------------------------------------------------------------------

local FADE_PROPS = {
	Frame = { "BackgroundTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
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

function Fade:run(from, to, duration, style)
	self:stop(true)
	self.entries = self:capture()
	local start = os.clock()
	self:apply(from)
	self.conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / math.max(duration, 0.001), 0, 1)
		self:apply(from + (to - from) * TweenService:GetValue(t, style or QUAD, Enum.EasingDirection.Out))
		if t >= 1 then
			if self.conn then
				self.conn:Disconnect()
				self.conn = nil
			end
			if to <= 0 then self:stop(true) end
		end
	end)
end

----------------------------------------------------------------------
-- window
----------------------------------------------------------------------

-- `audio` is AudioController (GetVolume / SetVolume / Save / Changed). If it
-- is missing the bars still draw and move, they just have nothing to drive.
function SettingsPresentation.createWindow(root, audio, onClose)
	local holder = new("Frame", { Parent = root, Name = "SettingsWindow", Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, Active = true, ZIndex = 82 })
	local scale = new("UIScale", { Parent = holder, Name = "WindowScale", Scale = 1 })
	-- Clicks on the panel's empty areas must not fall through to MenuDim,
	-- which closes every menu. A Frame's Active does not stop the button
	-- underneath from firing; a button of our own, under everything else in
	-- the window, does. (The Backpack does the same.)
	new("TextButton", { Parent = holder, Name = "InputBlocker", Text = "", AutoButtonColor = false,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Selectable = false, ZIndex = 0 })

	-- Soft shadow and the faintest blue bloom, as stacked strokes.
	local shadow = new("Frame", { Parent = holder, Name = "Shadow", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 1 }, { corner(18) })
	for i, spec in ipairs({ { 3, 0.8 }, { 7, 0.88 }, { 12, 0.93 }, { 18, 0.96 }, { 26, 0.978 } }) do
		new("UIStroke", { Parent = shadow, Name = "Shade" .. i, Color = BLACK, Thickness = spec[1],
			Transparency = spec[2], LineJoinMode = Enum.LineJoinMode.Round })
	end
	new("UIStroke", { Parent = shadow, Name = "Bloom", Color = ACCENT, Thickness = 5, Transparency = 0.93,
		LineJoinMode = Enum.LineJoinMode.Round })

	-- The panel: graphite fading to near-black, lit from above.
	local panel = new("Frame", { Parent = holder, Name = "Panel", BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.04, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, {
		corner(18),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(PANEL_TOP, PANEL_BOTTOM) }),
	})
	local rim = new("UIStroke", { Parent = panel, Name = "Rim", Color = WHITE, Thickness = 1.2, Transparency = 0.25 })
	new("UIGradient", { Parent = rim, Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, ACCENT_HI:Lerp(LINE, 0.35)),
		ColorSequenceKeypoint.new(0.45, LINE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(32, 36, 50)),
	}) })
	new("Frame", { Parent = panel, Name = "InnerRim", BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2), ZIndex = 1 }, { corner(17), new("UIStroke", { Color = WHITE, Transparency = 0.95 }) })
	new("Frame", { Parent = panel, Name = "TopSheen", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 90), ZIndex = 1 },
		{ corner(18), new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.955), NumberSequenceKeypoint.new(1, 1) }) }) })
	hairline(panel, "TopLight", ACCENT_HI, 0.3, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0.62, 0, 0, 1) })
	brackets(panel, 10, 14, ACCENT_HI, 0.62, 3)

	------------------------------------------------------------------
	-- header
	------------------------------------------------------------------
	local header = new("Frame", { Parent = panel, Name = "Header", BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 66), ZIndex = 4 })
	local badge = new("Frame", { Parent = header, Name = "IconBadge", BackgroundColor3 = WHITE,
		Position = UDim2.fromOffset(22, 13), Size = UDim2.fromOffset(40, 40), ZIndex = 1 }, {
		corner(11),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ACCENT:Lerp(PANEL_TOP, 0.55), PANEL_BOTTOM:Lerp(ACCENT, 0.1)) }),
		outline(ACCENT, 0.45),
	})
	new("ImageLabel", { Parent = badge, Name = "Icon", BackgroundTransparency = 1, Image = MenuConfig.Menus.Settings.IconImage,
		ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.76, 0.76), ZIndex = 2 })
	local title = text(header, "Title", "SETTINGS", 26, TEXT, 2)
	title.Position = UDim2.fromOffset(74, 10)
	title.Size = UDim2.fromOffset(240, 30)
	new("UIStroke", { Parent = title, Thickness = 1.4, Color = BLACK, Transparency = 0.45 })
	local sub = text(header, "SectionLabel", "AUDIO", 12, DIM, 2)
	sub.Position = UDim2.fromOffset(75, 39)
	sub.Size = UDim2.fromOffset(200, 14)

	local close = new("TextButton", { Parent = header, Name = "Close", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0, 34), Size = UDim2.fromOffset(38, 38),
		BackgroundColor3 = CLOSE_BG, BackgroundTransparency = 0.08, ZIndex = 2 }, { corner(10) })
	local closeStroke = outline(LINE, 0.3)
	closeStroke.Parent = close
	cross(close, 15, 2, TEXT)
	local closeScale = new("UIScale", { Parent = close, Name = "InteractionScale", Scale = 1 })
	local closeOver = false
	local function paintClose()
		tween(close, { BackgroundColor3 = closeOver and CLOSE_BG_HOT or CLOSE_BG })
		tween(closeStroke, { Color = closeOver and CLOSE_HOT or LINE, Transparency = closeOver and 0.1 or 0.3 })
		tween(closeScale, { Scale = closeOver and 1.06 or 1 }, 0.12)
	end
	close.MouseEnter:Connect(function() closeOver = true; paintClose() end)
	close.MouseLeave:Connect(function() closeOver = false; paintClose() end)
	close.SelectionGained:Connect(function() closeOver = true; paintClose() end)
	close.SelectionLost:Connect(function() closeOver = false; paintClose() end)
	close.MouseButton1Down:Connect(function() tween(closeScale, { Scale = 0.92 }, 0.06) end)
	close.Activated:Connect(onClose)

	hairline(panel, "HeaderDivider", ACCENT_HI, 0.62, { Position = UDim2.fromOffset(22, 66),
		Size = UDim2.new(1, -44, 0, 1) })
	diamond(panel, "DividerTipL", 5, ACCENT_HI, 0.45, UDim2.fromOffset(22, 66.5), 3)
	diamond(panel, "DividerTipR", 5, ACCENT_HI, 0.45, UDim2.new(1, -22, 0, 66.5), 3)

	------------------------------------------------------------------
	-- the bars
	------------------------------------------------------------------
	local body = new("Frame", { Parent = panel, Name = "Body", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, ROW_TOP), Size = UDim2.new(1, -40, 0, #BARS * ROW_H + (#BARS - 1) * ROW_GAP),
		ZIndex = 4 })

	local screenGui = root:FindFirstAncestorOfClass("ScreenGui")
	local function pointerX(input)
		-- Input positions are measured below the top-bar inset; a ScreenGui
		-- that ignores the inset measures from the true screen edge.
		local x = input.Position.X
		if screenGui and screenGui.IgnoreGuiInset then x += GuiService:GetGuiInset().X end
		return x
	end

	local rows, connections = {}, {}
	for index, spec in ipairs(BARS) do
		local y = (index - 1) * (ROW_H + ROW_GAP)
		local frame = new("Frame", { Parent = body, Name = spec.bus, BackgroundColor3 = ROW,
			BackgroundTransparency = 0.2, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, ROW_H),
			ZIndex = 1 }, { corner(12) })
		new("UIStroke", { Parent = frame, Color = WHITE, Transparency = 0.93, Thickness = 1 })

		local label = text(frame, "Label", spec.label, 14, TEXT, 2)
		label.Font = Enum.Font.GothamBold
		label.Position = UDim2.fromOffset(18, 13)
		label.Size = UDim2.new(1, -120, 0, 20)
		local readout = text(frame, "Value", "", 14, ACCENT_HI, 2)
		readout.Font = Enum.Font.GothamBold
		readout.AnchorPoint = Vector2.new(1, 0)
		readout.Position = UDim2.new(1, -18, 0, 13)
		readout.Size = UDim2.fromOffset(80, 20)
		readout.TextXAlignment = Enum.TextXAlignment.Right

		-- The bar. Its button is a 26px strip around an 8px track, so it is
		-- as easy to catch with a finger as with a cursor.
		local bar = new("TextButton", { Parent = frame, Name = "Bar", Text = "", AutoButtonColor = false,
			BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 40), Size = UDim2.new(1, -36, 0, 26),
			Selectable = false, ZIndex = 3 })
		local track = new("Frame", { Parent = bar, Name = "Track", AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = TRACK,
			ZIndex = 3 }, { round(), outline(BLACK, 0.55) })
		local fill = new("Frame", { Parent = track, Name = "Fill", BackgroundColor3 = WHITE,
			Size = UDim2.fromScale(1, 1), ZIndex = 4 },
			{ round(), new("UIGradient", { Color = ColorSequence.new(ACCENT_DEEP, ACCENT) }) })
		local knob = new("Frame", { Parent = bar, Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = WHITE,
			ZIndex = 6 }, { round(), outline(ACCENT, 0, 2) })
		local glow = new("UIStroke", { Parent = knob, Name = "Glow", Color = ACCENT, Thickness = 7,
			Transparency = 0.88, LineJoinMode = Enum.LineJoinMode.Round, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		local knobScale = new("UIScale", { Parent = knob, Name = "InteractionScale", Scale = 1 })

		local level = audio and audio:GetVolume(spec.bus) or 1
		local dragging, hovered, touch = false, false, nil

		local function show(v)
			local percent = math.floor(v * 100 + 0.5)
			fill.Size = UDim2.fromScale(v, 1)
			fill.Visible = percent > 0
			knob.Position = UDim2.fromScale(v, 0.5)
			readout.Text = percent > 0 and (percent .. "%") or "OFF"
			readout.TextColor3 = percent > 0 and ACCENT_HI or DIM
		end

		local function paintKnob()
			tween(knobScale, { Scale = dragging and 1.18 or (hovered and 1.1 or 1) }, 0.12)
			tween(glow, { Transparency = dragging and 0.72 or (hovered and 0.8 or 0.88) }, 0.14)
		end

		local function drag(x)
			local width = track.AbsoluteSize.X
			if width < 1 then return end
			level = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
			show(level)
			if audio then audio:SetVolume(spec.bus, level, false) end
		end

		local function release()
			dragging = false
			touch = nil
			paintKnob()
			if audio then audio:Save() end
			-- Let the player hear where the effects level landed.
			if spec.bus == "SFX" then Sfx.play("Press") end
		end

		bar.MouseEnter:Connect(function() hovered = true; paintKnob() end)
		bar.MouseLeave:Connect(function() hovered = false; paintKnob() end)
		bar.InputBegan:Connect(function(input)
			local kind = input.UserInputType
			if dragging or (kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch) then return end
			dragging = true
			touch = if kind == Enum.UserInputType.Touch then input else nil
			paintKnob()
			drag(pointerX(input))
		end)
		-- Moves and releases are heard globally, so a drag keeps working (and
		-- simply clamps) once the pointer leaves the bar.
		table.insert(connections, UserInputService.InputChanged:Connect(function(input)
			if not dragging then return end
			if touch then
				if input ~= touch then return end
			elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			drag(pointerX(input))
		end))
		table.insert(connections, UserInputService.InputEnded:Connect(function(input)
			if not dragging then return end
			if touch then
				if input ~= touch then return end
			elseif input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			release()
		end))

		-- The saved level arrives with the first profile sync, which is after
		-- this window has been built.
		if audio and audio.Changed then
			table.insert(connections, audio.Changed:Connect(function(bus, v)
				if bus ~= spec.bus or dragging then return end
				level = v
				show(v)
			end))
		end

		show(level)
		table.insert(rows, { frame = frame, y = y, reset = function()
			hovered = false
			knobScale.Scale = dragging and 1.18 or 1
			glow.Transparency = dragging and 0.72 or 0.88
		end })
	end

	------------------------------------------------------------------
	-- record, sizing, entrance and exit
	------------------------------------------------------------------
	local record = { name = "Settings", holder = holder, scale = scale, tabButtons = {}, selectedTab = nil,
		baseScale = 1, motion = nil, transition = 0,
		-- The Backpack's short, settled scale-in rather than the overshoot.
		openFrom = 0.97,
		openTween = TweenInfo.new(0.3, QUART, Enum.EasingDirection.Out) }

	local function fit()
		local size = root.AbsoluteSize
		if size.X < 2 or size.Y < 2 then return end
		-- A panel this small can afford to stay readable on a phone, so it does
		-- not shrink with the screen the way the Backpack does; it only shrinks
		-- when it would not fit at all.
		local s = math.clamp(size.Y / 900, 0.85, 1.1)
		s = math.max(0.3, math.min(s, (size.X - 24) / W, (size.Y - 24) / H))
		if record.motion then
			record.motion:Cancel()
			record.motion = nil
		end
		record.baseScale = s
		scale.Scale = s
	end

	local panelFade = Fade.new(holder)

	function record.onOpen()
		panelFade:run(1, 0, 0.24, QUAD)
		header.Position = UDim2.fromOffset(0, -6)
		tween(header, { Position = UDim2.fromOffset(0, 0) }, 0.3, QUART)
		for i, row in ipairs(rows) do
			row.frame.Position = UDim2.fromOffset(0, row.y + 10)
			tween(row.frame, { Position = UDim2.fromOffset(0, row.y) }, 0.28 + 0.07 * i, QUART)
		end
	end

	function record.onClose()
		panelFade:run(0, 1, 0.14, QUAD)
	end

	holder:GetPropertyChangedSignal("Visible"):Connect(function()
		if holder.Visible then return end
		-- Hidden: hand every property back so the next entrance starts clean.
		panelFade:stop(true)
		header.Position = UDim2.fromOffset(0, 0)
		for _, row in ipairs(rows) do
			row.frame.Position = UDim2.fromOffset(0, row.y)
			row.reset()
		end
	end)

	local resize = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	holder.Destroying:Connect(function()
		resize:Disconnect()
		for _, connection in ipairs(connections) do connection:Disconnect() end
	end)
	fit()
	return record
end

return SettingsPresentation
