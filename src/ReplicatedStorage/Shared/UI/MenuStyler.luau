--!strict
-- ReplicatedStorage > Shared > UI > MenuStyler
--
-- The component library the menus are built from. A menu should be able to say
-- "give me a panel, two sections and three buttons in gold" and get something
-- structurally identical to every other menu, differing only in accent colour.
--
-- LAYER ORDER, outermost to innermost. Getting this wrong is what made the old
-- panel look flat, so it is written down rather than implied:
--
--     drop shadow  (soft, offset down, sits BEHIND everything)
--     accent border (thick, hugs the panel - not a second box around it)
--     panel body    (translucent, vertical gradient, accent-tinted)
--     texture       (very faint diagonal weave)
--     inner highlight (1px, just inside the border, top-lit)
--     content

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.UI.UITheme)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local ButtonAnimator = require(ReplicatedStorage.Shared.UI.ButtonAnimator)

local MenuStyler = {}

local WHITE = Color3.new(1, 1, 1)

local function new(className: string, props): any
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		(object :: any)[key] = value
	end
	return object
end

local function font(textObject)
	local ok, face = pcall(function() return Theme.font() end)
	if ok and face then
		textObject.FontFace = face
	else
		-- Fallback only, and deliberately NOT a Bold weight: the game font is
		-- never bolded, so the emergency face must not be either.
		textObject.Font = Enum.Font.Gotham
	end
end

local function typeScale(textObject, step)
	new("UITextSizeConstraint", {
		Parent = textObject,
		MinTextSize = step.Min,
		MaxTextSize = step.Max,
	})
end
MenuStyler.TypeScale = typeScale

function MenuStyler.Corner(parent: Instance, radius: number)
	return new("UICorner", { Parent = parent, CornerRadius = UDim.new(0, radius) })
end

function MenuStyler.Padding(parent: Instance, amount: number)
	return new("UIPadding", {
		Parent = parent,
		PaddingTop = UDim.new(0, amount),
		PaddingBottom = UDim.new(0, amount),
		PaddingLeft = UDim.new(0, amount),
		PaddingRight = UDim.new(0, amount),
	})
end

-- ── DROP SHADOW ────────────────────────────────────────────
-- Roblox has no blur for UI, so a shadow is stacked frames: each ring is bigger,
-- rounder and fainter than the last. Six is enough to read as diffuse without
-- costing a meaningful number of instances.
function MenuStyler.Shadow(parent: GuiObject, zIndex: number)
	local holder = new("Frame", {
		Name = "DropShadow",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	})

	for i = 1, 6 do
		local spread = 4 + (i * 5)
		local ring = new("Frame", {
			Name = ("Shadow_%d"):format(i),
			Parent = holder,
			AnchorPoint = Vector2.new(0.5, 0.5),
			-- Offset downward so the light reads as coming from above.
			Position = UDim2.new(0.5, 0, 0.5, math.floor(spread * 0.45)),
			Size = UDim2.new(1, spread * 2, 1, spread * 2),
			BackgroundColor3 = UITheme.Shadow,
			BackgroundTransparency = 0.80 + (0.033 * i),
			BorderSizePixel = 0,
			ZIndex = zIndex,
		})
		MenuStyler.Corner(ring, UITheme.Radius.Panel + spread)
	end

	return holder
end

-- ── PANEL TEXTURE ──────────────────────────────────────────
-- A faint diagonal weave. Deliberately near-invisible: it exists to stop large
-- flat fills from looking like dead space, not to be noticed.
function MenuStyler.Texture(parent: GuiObject, accent: Color3, zIndex: number)
	local holder = new("Frame", {
		Name = "PanelTexture",
		Parent = parent,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = zIndex,
	})

	local STRIPES = 16
	for i = 1, STRIPES do
		local line = new("Frame", {
			Name = ("Stripe_%02d"):format(i),
			Parent = holder,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale((i - 0.5) / STRIPES, 0.5),
			Size = UDim2.new(0, 2, 2.4, 0),
			Rotation = 28,
			BackgroundColor3 = UITheme.lighten(accent, 0.55),
			BackgroundTransparency = 0.955,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		})
		-- Fade each stripe out top and bottom so the weave has no hard ends.
		new("UIGradient", {
			Parent = line,
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0.00, 1),
				NumberSequenceKeypoint.new(0.35, 0.25),
				NumberSequenceKeypoint.new(0.65, 0.25),
				NumberSequenceKeypoint.new(1.00, 1),
			}),
		})
	end

	return holder
end

-- ── PANEL ─────────────────────────────────────────────────
-- Applies the full layered treatment to an existing CanvasGroup. Takes the group
-- rather than creating one, so the caller keeps ownership of sizing and of the
-- GroupTransparency the open/close animation drives.
function MenuStyler.Panel(window: CanvasGroup, accent: Color3, zIndex: number)
	-- The window itself carries NO fill and NO gradient.
	--
	-- A UIGradient parented to a CanvasGroup does not tint that group's
	-- background - it tints the whole COMPOSITED GROUP, every child included. The
	-- first version of this put the panel shade directly on the window, which
	-- multiplied every section, button and label underneath it by the gradient and
	-- rendered the entire menu near-black with a vertical falloff. Proved it by
	-- forcing a child to pure red and watching it come back dark red.
	--
	-- So the fill lives in its own child frame, and the gradient goes there.
	window.BackgroundTransparency = 1
	window.BorderSizePixel = 0
	MenuStyler.Corner(window, UITheme.Radius.Panel)

	local fill = new("Frame", {
		Name = "PanelFill",
		Parent = window,
		Size = UDim2.fromScale(1, 1),
		-- White, because the gradient below multiplies this and is the single
		-- source of the panel's colour.
		BackgroundColor3 = WHITE,
		BackgroundTransparency = UITheme.PanelTransparency,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	})
	MenuStyler.Corner(fill, UITheme.Radius.Panel)

	-- Vertical gradient: lighter at the top, so the panel reads as lit from above
	-- rather than as a flat fill.
	new("UIGradient", {
		Name = "PanelShade",
		Parent = fill,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, UITheme.tint(UITheme.PanelTop, accent, 0.16)),
			ColorSequenceKeypoint.new(0.55, UITheme.tint(UITheme.Panel, accent, 0.10)),
			ColorSequenceKeypoint.new(1.00, UITheme.tint(UITheme.PanelBottom, accent, 0.06)),
		}),
	})

	MenuStyler.Texture(window, accent, zIndex + 1)

	-- Inner highlight. ApplyStrokeMode.Border on a slightly inset frame gives a
	-- 1px catch-light just inside the accent border - the detail that sells the
	-- panel as having thickness.
	local inner = new("Frame", {
		Name = "InnerHighlight",
		Parent = window,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -7, 1, -7),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex + 2,
	})
	MenuStyler.Corner(inner, UITheme.Radius.Panel - 4)
	local innerStroke = new("UIStroke", {
		Parent = inner,
		Thickness = UITheme.Stroke.PanelInner,
		Color = WHITE,
		Transparency = 0.86,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
	new("UIGradient", {
		Parent = innerStroke,
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.00, 0.35),
			NumberSequenceKeypoint.new(0.50, 0.90),
			NumberSequenceKeypoint.new(1.00, 1.00),
		}),
	})

	return window
end

-- The accent border. Lives on the panel itself so it hugs the real edge instead
-- of floating as a second box, and travels slowly so the menu feels alive.
function MenuStyler.AccentBorder(window: GuiObject, c1: Color3, c2: Color3, c3: Color3)
	local stroke = new("UIStroke", {
		Name = "AccentBorder",
		Parent = window,
		Thickness = UITheme.Stroke.Panel,
		Transparency = 0,
		Color = WHITE,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})

	local gradient = new("UIGradient", {
		Parent = stroke,
		Offset = Vector2.new(-1, 0),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, c1),
			ColorSequenceKeypoint.new(0.32, c2),
			ColorSequenceKeypoint.new(0.50, UITheme.lighten(c2, 0.72)),
			ColorSequenceKeypoint.new(0.68, c3),
			ColorSequenceKeypoint.new(1.00, c1),
		}),
	})

	TweenService:Create(
		gradient,
		TweenInfo.new(4.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true),
		{ Offset = Vector2.new(1, 0) }
	):Play()

	return stroke
end

-- ── SECTION ──────────────────────────────────────────────
-- An inner container. Content belongs in one of these, never straight on the
-- panel - that is what made the old menu one empty rectangle.
function MenuStyler.Section(parent: GuiObject, accent: Color3, props)
	props = props or {}

	local frame = new("Frame", {
		Name = props.Name or "Section",
		Parent = parent,
		Position = props.Position or UDim2.fromScale(0, 0),
		Size = props.Size or UDim2.fromScale(1, 1),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		-- Same reason as the panel: the vertical gradient added below carries only
		-- Transparency, so this one keeps its real colour rather than white.
		BackgroundColor3 = UITheme.tint(UITheme.Section, accent, 0.08),
		BackgroundTransparency = UITheme.SectionTransparency,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	MenuStyler.Corner(frame, UITheme.Radius.Section)

	new("UIStroke", {
		Parent = frame,
		Thickness = UITheme.Stroke.Section,
		Color = UITheme.lighten(accent, 0.25),
		Transparency = 0.62,
		LineJoinMode = Enum.LineJoinMode.Round,
	})

	-- Subtle top-down fade only; the section must stay clearly lighter than the
	-- panel across its whole height.
	new("UIGradient", {
		Parent = frame,
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.00, 0.00),
			NumberSequenceKeypoint.new(1.00, 0.10),
		}),
	})

	return frame
end

-- ── SECTION TITLE ──────────────────────────────────────────
function MenuStyler.SectionTitle(parent: GuiObject, text: string, accent: Color3, props)
	props = props or {}

	local holder = new("Frame", {
		Name = "SectionTitle",
		Parent = parent,
		Position = props.Position or UDim2.fromScale(0, 0),
		Size = props.Size or UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = (props.ZIndex or 1),
	})

	-- A short accent bar reads as a heading marker without needing a rule across
	-- the whole width.
	local bar = new("Frame", {
		Name = "AccentBar",
		Parent = holder,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 3, 0.72, 0),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ZIndex = (props.ZIndex or 1),
	})
	MenuStyler.Corner(bar, 2)

	local label = new("TextLabel", {
		Name = "Label",
		Parent = holder,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.new(1, -10, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = UITheme.Text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeColor3 = UITheme.Ink,
		TextStrokeTransparency = 0.55,
		ZIndex = (props.ZIndex or 1),
	})
	font(label)
	typeScale(label, UITheme.Type.Section)

	return holder, label
end

-- ── BODY TEXT ────────────────────────────────────────────
function MenuStyler.Text(parent: GuiObject, text: string, step, props)
	props = props or {}
	local label = new("TextLabel", {
		Name = props.Name or "Text",
		Parent = parent,
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		Position = props.Position or UDim2.fromScale(0, 0),
		Size = props.Size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = props.Color or UITheme.TextMuted,
		TextScaled = true,
		TextWrapped = props.Wrapped == true,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Left,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextStrokeColor3 = UITheme.Ink,
		TextStrokeTransparency = props.StrokeTransparency or 0.7,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	font(label)
	typeScale(label, step or UITheme.Type.Body)
	return label
end

-- ── BUTTON ───────────────────────────────────────────────
function MenuStyler.Button(parent: GuiObject, text: string, accent: Color3, props)
	props = props or {}

	local button = new("TextButton", {
		Name = props.Name or "Button",
		Parent = parent,
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		Position = props.Position or UDim2.fromScale(0, 0),
		Size = props.Size or UDim2.new(0, 130, 0, 34),
		BackgroundColor3 = UITheme.tint(UITheme.Section, accent, 0.10),
		BackgroundTransparency = UITheme.SectionTransparency,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	MenuStyler.Corner(button, UITheme.Radius.Button)

	local stroke = new("UIStroke", {
		Parent = button,
		Thickness = UITheme.Stroke.Button,
		Color = accent,
		Transparency = 0.45,
		LineJoinMode = Enum.LineJoinMode.Round,
	})

	-- Text lives in a child label rather than on the button, so the button's own
	-- BackgroundTransparency can be tweened on hover without fading the caption.
	local label = new("TextLabel", {
		Name = "Label",
		Parent = button,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = UITheme.Text,
		TextScaled = true,
		TextStrokeColor3 = UITheme.Ink,
		TextStrokeTransparency = 0.6,
		ZIndex = (props.ZIndex or 1) + 1,
	})
	font(label)
	typeScale(label, props.TypeStep or UITheme.Type.Body)
	MenuStyler.Padding(label, 6)

	ButtonAnimator.Attach(button, {
		Accent = accent,
		Stroke = stroke,
		RestFill = UITheme.SectionTransparency,
		Sound = props.Sound,
	})

	return button, label, stroke
end

-- ── CLOSE BUTTON ───────────────────────────────────────────
function MenuStyler.CloseButton(parent: GuiObject, accent: Color3, zIndex: number, sound)
	local button = new("TextButton", {
		Name = "CloseButton",
		Parent = parent,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -52, 0, 12),
		Size = UDim2.fromOffset(52, 42),
		BackgroundColor3 = Color3.fromRGB(242, 76, 68),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = zIndex,
	})
	-- Fully round: a circle reads as "dismiss" and cannot be mistaken for one of
	-- the rounded-square content buttons.
	MenuStyler.Corner(button, UITheme.Radius.Pill)

	local glow = new("Frame", {
		Name = "HoverGlow",
		Parent = button,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.5, 1.5),
		BackgroundColor3 = Color3.fromRGB(255, 96, 88),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex - 1,
	})
	MenuStyler.Corner(glow, UITheme.Radius.Pill)

	local stroke = new("UIStroke", {
		Name = "CloseStroke",
		Parent = button,
		Color = Color3.new(1, 1, 1),
		Thickness = 2,
		Transparency = 0.08,
		LineJoinMode = Enum.LineJoinMode.Round,
	})

	local glyph = new("TextLabel", {
		Name = "Glyph",
		Parent = button,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		-- Plain capital X, not ✕. The game font is FredokaOne, a display face with a
		-- limited glyph set - the multiplication-sign glyph falls back to a blank
		-- box, which is how the close button ended up looking like an empty circle.
		Text = "X",
		TextColor3 = UITheme.Text,
		TextScaled = true,
		TextStrokeColor3 = UITheme.Ink,
		TextStrokeTransparency = 0.5,
		ZIndex = zIndex + 1,
	})
	font(glyph)
	typeScale(glyph, { Min = 12, Max = 20 })
	MenuStyler.Padding(glyph, 9)

	ButtonAnimator.Attach(button, {
		Accent = Color3.fromRGB(255, 96, 88),
		Stroke = stroke,
		Glow = glow,
		RestFill = 0,
		HoverFill = 0.00,
		Sound = sound,
	})

	return button
end

return MenuStyler
