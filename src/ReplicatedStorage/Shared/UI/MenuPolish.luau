--!nonstrict
-- Presentation helpers scoped to the standard menus. Deck and Skill Tree do not use this module.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sweep = require(ReplicatedStorage.Shared.UI.Sweep)
local Polish = {}
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(9, 13, 24)

function Polish.gradient(parent, top, bottom, rotation)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
	return gradient
end

function Polish.surface(frame, accent, depth)
	frame.BackgroundColor3 = WHITE
	Polish.gradient(frame, Color3.fromRGB(32, 42, 63):Lerp(accent, depth or 0.07), Color3.fromRGB(15, 21, 35))
	local line = frame:FindFirstChildOfClass("UIStroke")
	if line then line.Color = accent:Lerp(Color3.fromRGB(95, 112, 148), 0.58); line.Transparency = 0.42 end
end

function Polish.hover(button, accent, amount)
	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", button)
	local line = button:FindFirstChildOfClass("UIStroke")
	local resting = line and line.Transparency or 0.5
	local restingColor = line and line.Color
	local over = false
	local tween
	local function pose(value, highlighted)
		if tween then tween:Cancel() end
		tween = TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = value})
		tween:Play()
		if line then TweenService:Create(line, TweenInfo.new(0.16), {
			Transparency = highlighted and 0.06 or (button:GetAttribute("RestStrokeTransparency") or resting),
			Color = highlighted and accent or (button:GetAttribute("RestStrokeColor") or restingColor),
		}):Play() end
	end
	button.MouseEnter:Connect(function() over = true; pose(amount or 1.025, true) end)
	button.MouseLeave:Connect(function() over = false; pose(1, false) end)
	if button:IsA("GuiButton") then
		button.SelectionGained:Connect(function() over = true; pose(amount or 1.025, true) end)
		button.SelectionLost:Connect(function() over = false; pose(1, false) end)
		button.MouseButton1Down:Connect(function() pose(0.975, true) end)
		button.MouseButton1Up:Connect(function() pose(over and (amount or 1.025) or 1, over) end)
	end
end

function Polish.sweep(frame, accent, transparency)
	return Sweep.attach(frame, {tint = accent, transparency = transparency or 0.93, width = 0.32, zIndex = frame.ZIndex + 1})
end

function Polish.grid(content, grid, preferredWidth, aspect, maxColumns)
	local function resize()
		local totalScale = 1
		local ancestor = content
		while ancestor do
			local scaler = ancestor:FindFirstChildOfClass("UIScale")
			if scaler then totalScale *= scaler.Scale end
			ancestor = ancestor.Parent
		end
		local available = math.max(100, content.AbsoluteSize.X / math.max(0.01, totalScale) - 24)
		local columns = math.clamp(math.floor((available + 16) / (preferredWidth + 16)), 1, maxColumns or 6)
		local width = math.floor((available - 16 * (columns - 1)) / columns)
		grid.CellSize = UDim2.fromOffset(width, math.floor(width * aspect))
	end
	resize()
	local connection = content:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	grid.Destroying:Once(function() connection:Disconnect() end)
end

return Polish