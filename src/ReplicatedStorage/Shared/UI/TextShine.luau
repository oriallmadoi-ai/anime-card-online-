--!strict
-- Animated colour gradients for TEXT - the counterpart to Shine, which does
-- borders. Shine paints the outline of a card; this paints the writing on it.
-- Both read their palette from VariantConfig, so a tier's whole look is still
-- described in one place and nowhere else.
--
-- WHY THE PHASE IS RESAMPLED RATHER THAN OFFSET
-- The obvious way to travel a gradient is to slide UIGradient.Offset. Offset
-- CLAMPS: past the ends of the sequence the first and last colours smear out
-- across the text, and the wrap shows up as a visible stutter once per cycle.
-- So instead the ColorSequence is rebuilt each frame by sampling the palette at
-- (t + phase) and wrapping around. Provided the palette's first and last colours
-- match, the sampled function is periodic - keypoint 0 and keypoint 1 are always
-- the same colour - and the loop has no seam at all. Same trick the auto roll
-- rainbow uses, generalised from the hue wheel to an arbitrary palette.
--
-- ONE LOOP FOR EVERYTHING. A grid can hold hundreds of tiles, and a
-- RenderStepped connection each would be hundreds of connections doing
-- identical maths on the same clock.
--
-- A NOTE ON WIDTH: a UIGradient maps across its parent's BOUNDING BOX, not
-- across the glyphs. On a label much wider than its text most of the palette
-- lands on empty space either side of the word, and the text only ever shows
-- the middle slice. Callers that care should let the label size to its text.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)

local TextShine = {}

local GRADIENT_NAME = "VariantTextGradient"
local STOPS = 16          -- ColorSequence allows 20; 16 is smooth on short text
local WHITE = Color3.new(1, 1, 1)

local active: { [UIGradient]: any } = {}
local started = false

-- Palette sampled as a loop. colours[1] and colours[#colours] are expected to
-- match; if they do not, the seam this whole module exists to avoid comes back.
local function sample(colours: { Color3 }, t: number): Color3
	local span = #colours - 1
	local pos = (t % 1) * span
	local i = math.floor(pos)
	local a = colours[i + 1]
	local b = colours[i + 2] or colours[1]
	return a:Lerp(b, pos - i)
end

local function repaint(gradient: UIGradient, spec, phase: number)
	local keys = table.create(STOPS)
	for i = 1, STOPS do
		local t = (i - 1) / (STOPS - 1)
		keys[i] = ColorSequenceKeypoint.new(t, sample(spec.colours, t + phase))
	end
	gradient.Color = ColorSequence.new(keys)
end

local function startLoop()
	if started then return end
	started = true
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for gradient, spec in pairs(active) do
			if gradient.Parent then
				repaint(gradient, spec, (now % spec.travel) / spec.travel)
			else
				-- Tiles are destroyed and rebuilt constantly as the grid refilters.
				active[gradient] = nil
			end
		end
	end)
end

-- Paints `textObject` with the tier's travelling gradient, or strips it if the
-- tier has none. Safe to call every refresh: the gradient is reused in place.
--
-- CALL ORDER MATTERS. A UIGradient MULTIPLIES the object's TextColor3, so a
-- label left on the tier's flat colour would tint the whole palette through it.
-- Callers set TextColor3 as they always did and then call this, which forces
-- white where a gradient is taking over and leaves the flat colour alone where
-- it is not.
function TextShine.apply(textObject: Instance?, variantId: string)
	if not textObject then return end

	local spec = VariantConfig.get(variantId).textGradient
	local gradient = textObject:FindFirstChild(GRADIENT_NAME)

	if not spec then
		if gradient then
			active[gradient :: UIGradient] = nil
			gradient:Destroy()
		end
		return
	end

	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = GRADIENT_NAME
		gradient.Parent = textObject
	end
	(gradient :: UIGradient).Rotation = spec.rotation or 0;
	(textObject :: any).TextColor3 = WHITE

	active[gradient :: UIGradient] = spec
	-- Painted once here so the text is never flat for the frame before the loop
	-- next runs; a grid refilter would otherwise flicker on every keystroke.
	repaint(gradient :: UIGradient, spec, 0)
	startLoop()
end

function TextShine.remove(textObject: Instance?)
	local gradient = textObject and textObject:FindFirstChild(GRADIENT_NAME)
	if gradient then
		active[gradient :: UIGradient] = nil
		gradient:Destroy()
	end
end

return TextShine
