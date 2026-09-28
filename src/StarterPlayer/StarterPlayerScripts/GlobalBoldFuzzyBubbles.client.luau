local FONT_FACE = Font.fromId(11322590111, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local connected = setmetatable({}, { __mode = "k" })

local function isTextObject(instance)
	return instance:IsA("TextLabel")
		or instance:IsA("TextButton")
		or instance:IsA("TextBox")
end

local function applyFont(instance)
	if connected[instance] or not isTextObject(instance) then
		return
	end

	connected[instance] = true

	local function enforce()
		if instance.Parent and instance.FontFace ~= FONT_FACE then
			instance.FontFace = FONT_FACE
		end
	end

	enforce()
	instance:GetPropertyChangedSignal("FontFace"):Connect(enforce)
end

for _, instance in ipairs(game:GetDescendants()) do
	applyFont(instance)
end

game.DescendantAdded:Connect(applyFont)
