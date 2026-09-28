--!strict
-- The title header every big screen wears: Backpack, Deck, Skill Tree.
--
-- WHY THIS EXISTS
-- The three screens each had their own hand-rolled copy of the same ribbon, so
-- "fix the header" meant editing three files and hoping they still matched. They
-- did not: the corner radii, the tip sizes and the spark proportions had all
-- drifted apart. One component, three call sites.
--
-- WHAT CHANGED, AND WHY IT LOOKED UNFINISHED
-- The old ribbon was a near-square slab (5px corners) with a 45-degree diamond
-- floating just off its right edge, a hairline running from the diamond most of
-- the way across the screen, and a large four-blade starburst laid over the
-- left end. Three separate things sat NEXT TO the plate rather than belonging
-- to it, which is exactly what reads as placeholder art.
--
-- So: the plate is properly rounded, the starburst became a contained icon
-- badge INSIDE the plate, and the diamond and the hairline are gone. What is
-- left is one object with an icon, a title and a highlight - the same anatomy
-- as every other button in the game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.UI.Theme)

local PanelHeader = {}

local INK = Color3.fromRGB(8, 8, 12)
local WHITE = Color3.new(1, 1, 1)

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for key, value in pairs(props) do
		if key ~= "Parent" then (inst :: any)[key] = value end
	end
	if children then
		for _, child in ipairs(children) do child.Parent = inst end
	end
	if parent then inst.Parent = parent end
	return inst
end

-- opts:
--   Parent, Name, Position, Size   standard layout
--   accent                          the screen's colour
--   shade                           what the gradient falls towards (optional)
--   text, textSize                  the title
--   zIndex                          base; the header uses zIndex .. zIndex+4
function PanelHeader.create(opts: { [string]: any })
	local accent: Color3 = opts.accent or Color3.fromRGB(150, 92, 245)
	local shade: Color3 = opts.shade or accent:Lerp(INK, 0.34)
	local z: number = opts.zIndex or 10
	local height: number = opts.height or 52

	-- An ImageLabel, not a Frame, and deliberately so: MenuAnimator fades the
	-- header by tweening ImageTransparency on this object. Swapping the class
	-- would break the open animation on every menu at once.
	local plate = new("ImageLabel", {
		Parent = opts.Parent,
		Name = opts.Name or "Header",
		Position = opts.Position,
		Size = opts.Size or UDim2.new(1, 0, 0, height),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Image = "",
		ImageTransparency = 1,
		ZIndex = z,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, math.floor(height * 0.28)) }),
		new("UIStroke", { Color = INK, Thickness = 3, Transparency = 0.02 }),
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, accent:Lerp(WHITE, 0.26)),
				ColorSequenceKeypoint.new(0.54, accent),
				ColorSequenceKeypoint.new(1, shade),
			}),
		}),
	})

	-- A catch-light along the top, inset so it stops inside the rounded corners
	-- instead of running into them. Faded at both ends for the same reason.
	local highlight = new("Frame", {
		Parent = plate, Name = "TopHighlight",
		Position = UDim2.new(0, 16, 0, 4),
		Size = UDim2.new(1, -32, 0, 2),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = z + 1,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	new("UIGradient", {
		Parent = highlight,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.18, 0),
			NumberSequenceKeypoint.new(0.82, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	----------------------------------------------------------------
	-- icon badge
	----------------------------------------------------------------
	-- The old starburst was a loose ornament laid over the ribbon at whatever
	-- size looked right that day. Contained in a badge it becomes an icon: it
	-- scales with the header, it cannot collide with the title, and it gives the
	-- left end a deliberate shape instead of a ragged one.
	local badgeSize = math.floor(height * 0.68)
	local badge = new("Frame", {
		Parent = plate, Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, math.floor(height * 0.16), 0.5, 0),
		Size = UDim2.fromOffset(badgeSize, badgeSize),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.16,
		BorderSizePixel = 0,
		ZIndex = z + 2,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, math.floor(badgeSize * 0.32)) }),
		new("UIStroke", { Color = WHITE, Thickness = 1.4, Transparency = 0.66 }),
	})

	local blade = math.floor(badgeSize * 0.62)
	local thin = math.max(3, math.floor(badgeSize * 0.11))
	for index, rotation in ipairs({ 0, 45, 90, 135 }) do
		local long = index % 2 == 0
		new("Frame", {
			Parent = badge, Name = "Blade" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(long and thin or blade, long and blade or thin),
			Rotation = rotation,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = z + 3,
		}, {
			new("UICorner", { CornerRadius = UDim.new(1, 0) }),
			new("UIStroke", { Color = INK, Thickness = 1.2, Transparency = 0.25 }),
		})
	end

	----------------------------------------------------------------
	-- title
	----------------------------------------------------------------
	local titleX = math.floor(height * 0.16) + badgeSize + math.floor(height * 0.22)
	local title = new("TextLabel", {
		Parent = plate, Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, titleX, 0.5, 0),
		Size = UDim2.new(1, -(titleX + 20), 0.66, 0),
		BackgroundTransparency = 1,
		Text = opts.text or "",
		FontFace = Theme.font(),
		TextColor3 = WHITE,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextStrokeColor3 = INK,
		TextStrokeTransparency = 0.15,
		ZIndex = z + 3,
	}, {
		new("UITextSizeConstraint", {
			MinTextSize = 14,
			MaxTextSize = opts.textSize or math.floor(height * 0.54),
		}),
		new("UIStroke", {
			Color = INK, Thickness = 2.4,
			LineJoinMode = Enum.LineJoinMode.Round,
		}),
	})

	return {
		plate = plate,
		title = title,
		badge = badge,
		setText = function(value: string) title.Text = value end,
		setAccent = function(colour: Color3, newShade: Color3?)
			plate.BackgroundColor3 = colour
			local gradient = plate:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, colour:Lerp(WHITE, 0.26)),
					ColorSequenceKeypoint.new(0.54, colour),
					ColorSequenceKeypoint.new(1, newShade or colour:Lerp(INK, 0.34)),
				})
			end
		end,
	}
end

return PanelHeader
