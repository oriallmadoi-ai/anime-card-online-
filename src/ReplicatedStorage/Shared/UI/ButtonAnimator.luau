--!strict
-- ReplicatedStorage > Shared > UI > ButtonAnimator
--
-- Hover / press feel for every menu button, in one place.
--
-- Attach() only adds VISUAL behaviour. It never touches Activated, so a button
-- that already has game logic wired to it keeps working untouched - which is the
-- whole reason this is a separate module rather than part of button creation.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UITheme = require(ReplicatedStorage.Shared.UI.UITheme)

local ButtonAnimator = {}

local HOVER = TweenInfo.new(UITheme.Motion.Hover, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLICK = TweenInfo.new(UITheme.Motion.Click, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- opts:
--   Accent      Color3   border colour at rest and on hover
--   Stroke      UIStroke optional, brightened on hover
--   Glow        GuiObject optional, faded in on hover
--   RestFill    number   background transparency at rest
--   HoverFill   number   background transparency on hover
--   Sound       function optional, called once on hover
function ButtonAnimator.Attach(button: GuiButton, opts)
	opts = opts or {}

	local scale = button:FindFirstChild("BtnScale") :: UIScale?
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "BtnScale"
		scale.Scale = UITheme.Scale.Rest
		scale.Parent = button
	end

	local stroke = opts.Stroke
	local glow = opts.Glow
	local restFill = opts.RestFill or UITheme.SectionTransparency
	local hoverFill = opts.HoverFill or math.max(0, restFill - 0.12)

	local restStroke = stroke and stroke.Transparency or 0.45
	local hovered = false
	local held = false

	-- One place decides the target scale, so a mouse that leaves while the button
	-- is still held cannot strand it at the pressed size.
	local function targetScale(): number
		if held then return UITheme.Scale.Click end
		if hovered then return UITheme.Scale.Hover end
		return UITheme.Scale.Rest
	end

	local function apply(info: TweenInfo)
		TweenService:Create(scale :: UIScale, info, { Scale = targetScale() }):Play()
	end

	button.MouseEnter:Connect(function()
		hovered = true
		if opts.Sound then opts.Sound() end
		apply(HOVER)
		if button:IsA("GuiObject") then
			TweenService:Create(button, HOVER, { BackgroundTransparency = hoverFill }):Play()
		end
		if stroke then
			TweenService:Create(stroke, HOVER, {
				Transparency = 0,
				Thickness = UITheme.Stroke.ButtonHover,
			}):Play()
		end
		if glow then
			TweenService:Create(glow, HOVER, { BackgroundTransparency = 0.72 }):Play()
		end
	end)

	button.MouseLeave:Connect(function()
		hovered = false
		held = false
		apply(HOVER)
		if button:IsA("GuiObject") then
			TweenService:Create(button, HOVER, { BackgroundTransparency = restFill }):Play()
		end
		if stroke then
			TweenService:Create(stroke, HOVER, {
				Transparency = restStroke,
				Thickness = UITheme.Stroke.Button,
			}):Play()
		end
		if glow then
			TweenService:Create(glow, HOVER, { BackgroundTransparency = 1 }):Play()
		end
	end)

	button.MouseButton1Down:Connect(function()
		held = true
		apply(CLICK)
	end)

	-- Rebound uses Back so the button springs past its resting size for a frame.
	button.MouseButton1Up:Connect(function()
		held = false
		TweenService:Create(
			scale :: UIScale,
			TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = targetScale() }
		):Play()
	end)

	return scale
end

return ButtonAnimator
