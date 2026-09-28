--!strict
-- Neon falloff border for the upgraded variants.
--
-- THE SHAPE OF THE EFFECT
--   card edge -> 1.6px bright core -> tight inner glow -> 11 thin shells whose
--   alpha decays on a curve -> invisible by ~7px out.
-- No layer boundary should be identifiable; the eye should read one continuous
-- falloff rather than a few stacked rectangles.
--
-- HOW THE FALLOFF IS BUILT
-- A UIStroke fills the band from the element edge outward to its thickness, so
-- a thin stroke sits INSIDE every thicker one. Stacking shells of increasing
-- thickness therefore composites: near the edge every shell overlaps and the
-- alpha sums to bright; further out only the faint wide shells remain. That
-- accumulation is what produces a smooth gradient from a set of flat layers.
--
-- Building it from nested Frames instead would mean fighting the card's
-- ClipsDescendants (which crops the artwork) and tracking the card's position
-- through grid layouts. Strokes render outside the element and ignore clipping,
-- so there is nothing to keep in sync.
--
-- The card's own rarity border is drawn separately and stays static. The glow
-- is only emitted light around it.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)

local Shine = {}

local SETTINGS = {
	GlowLayers = 11,
	GlowDistance = 9,            -- px the glow reaches at reference size
	CoreThickness = 2.4,
	CoreTransparency = 0.02,
	InnerGlowThickness = 4,
	InnerGlowTransparency = 0.34,
	FalloffPower = 2.4,          -- higher = tighter to the card
	GlowStrength = 0.72,         -- alpha of the innermost shell
	OuterStrength = 0.01,        -- alpha of the outermost shell
	RotationSpeed = 38,          -- degrees per second
}

-- Thickness only. FalloffPower and RotationSpeed are deliberately unchanged:
-- the first controls the shape of the fade and the second the motion, so
-- touching either would alter how the effect ANIMATES rather than how heavy it
-- looks. A thicker border should still travel exactly as it did before.

local CORE_NAME = "GlowCore"
local INNER_NAME = "GlowInner"
local SHELL_PREFIX = "GlowShell"
local BASE_NAME = "BaseStroke"

local function isOurs(name: string): boolean
	return name == CORE_NAME or name == INNER_NAME or name == BASE_NAME
		or name:sub(1, #SHELL_PREFIX) == SHELL_PREFIX
end

local suppressed: { [Instance]: { UIStroke } } = {}
local applied: { [Instance]: string } = {}

-- One shared loop drives every gradient in the game. A tween per gradient would
-- mean 13 tweens per card; with a grid of them that is a lot of scheduler work
-- for something a single rotation value can express.
local gradients: { UIGradient } = {}
local elapsed = 0

RunService.RenderStepped:Connect(function(dt)
	elapsed += dt
	local rotation = (elapsed * SETTINGS.RotationSpeed) % 360
	for i = #gradients, 1, -1 do
		local g = gradients[i]
		if g and g.Parent then
			g.Rotation = rotation
		else
			table.remove(gradients, i)
		end
	end
end)

local function colourSequence(colours: { Color3 }): ColorSequence
	local stops = {}
	for i, colour in ipairs(colours) do
		stops[#stops + 1] = ColorSequenceKeypoint.new((i - 1) / (#colours - 1), colour)
	end
	return ColorSequence.new(stops)
end

local function stroke(frame: GuiObject, name: string, thickness: number, transparency: number,
	sequence: ColorSequence?)
	local s = Instance.new("UIStroke")
	s.Name = name
	s.Color = Color3.new(1, 1, 1)
	s.Thickness = thickness
	s.Transparency = transparency
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = frame

	if sequence then
		local g = Instance.new("UIGradient")
		g.Color = sequence
		g.Rotation = 0
		g.Parent = s
		gradients[#gradients + 1] = g
	end
	return s
end

local function restoreBase(frame: Instance)
	local list = suppressed[frame]
	if not list then return end
	for _, s in ipairs(list) do
		if s.Parent then s.Enabled = true end
	end
	suppressed[frame] = nil
end

function Shine.remove(frame: GuiObject)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("UIStroke") and isOurs(child.Name) then
			child:Destroy()
		end
	end
	applied[frame] = nil
	restoreBase(frame)
end

-- Maps a colour back to its tier, so an older call that passed a colour rather
-- than a tier id still resolves. Callers can be reverted by a stale script
-- editor buffer, and a silent type error in a renderer is expensive to find.
local colourToVariant: { [string]: string } = {}
do
	local function key(c: Color3): string
		return ("%d,%d,%d"):format(
			math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
	end
	for id, v in pairs(VariantConfig.Data) do
		colourToVariant[key(v.color)] = id
		if v.border then
			if v.border.baseColour then colourToVariant[key(v.border.baseColour)] = id end
			if v.border.brightColour then colourToVariant[key(v.border.brightColour)] = id end
		end
	end
end

-- variantId: which tier to draw. width: the card's intended width in pixels.
function Shine.apply(frame: GuiObject, variantId: any, width: any, legacyWidth: any?)
	if not frame then return end

	if typeof(variantId) == "boolean" then
		local colour = width
		local resolved = nil
		if typeof(colour) == "Color3" then
			resolved = colourToVariant[("%d,%d,%d"):format(
				math.round(colour.R * 255), math.round(colour.G * 255), math.round(colour.B * 255))]
		end
		if not resolved then
			Shine.remove(frame)
			return
		end
		variantId = resolved
		width = typeof(legacyWidth) == "number" and legacyWidth or nil
	end

	if typeof(width) ~= "number" then width = nil end

	local variant = VariantConfig.get(variantId)
	local spec = variant.border
	if not spec then
		Shine.remove(frame)
		return
	end

	Shine.applySpec(frame, spec, width, variant.id)
end

-- Draws any border spec on any frame. Card tiers go through Shine.apply, which
-- looks the spec up; anything else - nav buttons, panels - can pass its own.
-- `key` only exists so a repaint with the same spec can skip the rebuild.
function Shine.applySpec(frame: GuiObject, spec, width: number?, key: string?)
	if not frame or not spec then return end
	key = key or "custom"

	local w = width or (frame.AbsoluteSize.X > 0 and frame.AbsoluteSize.X or 180)
	local scale = math.clamp(w / VariantConfig.BorderReferenceWidth, 0.5, 1.4)

	-- Repainting the same tier would restart the build for no visual gain.
	if applied[frame] == key then
		for _, child in ipairs(frame:GetChildren()) do
			if child:IsA("UIStroke") then
				local base = child:GetAttribute("BaseThickness")
				if base then child.Thickness = base * scale end
			end
		end
		return
	end

	Shine.remove(frame)
	applied[frame] = key

	-- Square corners under a rounded outline look like a mistake, so the card is
	-- rounded to match the border spec.
	--
	-- But only when the frame does not already carry its own radius. Equipped
	-- slots are authored in StarterGui with a radius chosen to match the holes
	-- drawn in the lineup artwork; overwriting that put a sharp-cornered image
	-- inside a rounded hole, which no amount of repositioning could fix.
	if spec.corner then
		local corner = frame:FindFirstChildOfClass("UICorner")
		if not corner then
			corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, math.round(spec.corner * scale))
			corner.Parent = frame
		end
	end

	-- The card may carry its own outline from the renderer; park it so it does
	-- not double up with the rarity border drawn below.
	local parked = {}
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("UIStroke") and not isOurs(child.Name) and child.Enabled then
			child.Enabled = false
			parked[#parked + 1] = child
		end
	end
	suppressed[frame] = parked

	local animated = spec.glowColours and #spec.glowColours >= 2
	if animated or spec.glowColour then
		-- A rotating multi-colour gradient, or a single flat colour. The
		-- falloff maths is identical either way, so an unanimated tier still
		-- sits in the same visual language as the animated ones.
		local sequence = animated and colourSequence(spec.glowColours) or nil
		local flat = spec.glowColour
		local strengthScale = spec.glowScale or 1
		local n = SETTINGS.GlowLayers

		-- Widest shell first so the thin bright ones end up on top.
		for i = n, 1, -1 do
			local t = i / n                                   -- 0..1 outward
			local thickness = SETTINGS.GlowDistance * t
			local falloff = (1 - t) ^ SETTINGS.FalloffPower
			local alpha = (SETTINGS.OuterStrength
				+ (SETTINGS.GlowStrength - SETTINGS.OuterStrength) * falloff) * strengthScale

			local s = stroke(frame, SHELL_PREFIX .. i, thickness * scale, 1 - alpha, sequence)
			if flat then s.Color = flat end
			s:SetAttribute("BaseThickness", thickness)
		end

		local inner = stroke(frame, INNER_NAME, SETTINGS.InnerGlowThickness * scale,
			1 - (1 - SETTINGS.InnerGlowTransparency) * strengthScale, sequence)
		if flat then inner.Color = flat end
		inner:SetAttribute("BaseThickness", SETTINGS.InnerGlowThickness)

		local core = stroke(frame, CORE_NAME, SETTINGS.CoreThickness * scale,
			1 - (1 - SETTINGS.CoreTransparency) * strengthScale, sequence)
		if flat then core.Color = flat end
		core:SetAttribute("BaseThickness", SETTINGS.CoreThickness)
	end

	-- The rarity border itself: crisp, static, drawn last so it sits on top.
	local base = stroke(frame, BASE_NAME, spec.baseThickness * scale, spec.baseTransparency)
	base.Color = spec.baseColour
	base:SetAttribute("BaseThickness", spec.baseThickness)

	frame.Destroying:Connect(function()
		suppressed[frame] = nil
		applied[frame] = nil
	end)
end

return Shine
