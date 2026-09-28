--!strict
-- Elder Essence I..V, the item that levels cards.
--
-- WHAT IT LOOKS LIKE AND WHY
-- One object photographed five times, not five objects. A faceted crystal vial
-- with a metal cap and an orbiting ring - the ring is the deliberate callback
-- to the Elder Coin, which wears an inlaid ring of its own, so the two read as
-- the same family. Between tiers the SILHOUETTE never changes; only
--   * the accent colour, taken from that tier's VariantConfig entry
--   * how bright and how saturated the core is
--   * how many orbiting shards are lit (0, 2, 3, 4, 5)
-- which is what lets someone see that V beats IV without having to read it.
--
-- Modelled and rendered in Blender against a tier-tinted sky - the cap and
-- ring are metal, and metal shows whatever the world gives it, so a single
-- blue sky was painting every tier's cap the same navy until the sky was
-- tinted per tier too.
--
-- I..IV ARE STILLS. Only V animates, the same 25-frame sway on one 5x5 sheet
-- the Elder Coin uses. Every tier could have been animated, but five moving
-- things in one Backpack row is noise, and "the top one is alive" is a louder
-- signal than "they all wiggle".

local RunService = game:GetService("RunService")

local ElderEssence = {}

-- Blender output, cropped to a box shared by all five tiers AND the animation,
-- so a row of essences lines up instead of each vial sitting at its own size.
ElderEssence.Art = {
	I   = "rbxassetid://109324609755546",
	II  = "rbxassetid://104167451061271",
	III = "rbxassetid://125200727098887",
	IV  = "rbxassetid://79300643035921",
	V   = "rbxassetid://78715753558197",
}

-- Tier V only: 25 frames, 5x5 at 200px.
ElderEssence.Sheet = "rbxassetid://137098933933986"
ElderEssence.Cell = 200
ElderEssence.Columns = 5
ElderEssence.Frames = 25
ElderEssence.Fps = 12

ElderEssence.Tiers = { "I", "II", "III", "IV", "V" }

-- Which VariantConfig tier each essence wears. Presentation only - the border,
-- the badge letter and the text gradient all come from here, so restyling a
-- card tier restyles its essence with it and they can never drift apart.
ElderEssence.Variant = {
	I = "Standard", II = "Gilded", III = "Astral",
	IV = "Transcendent", V = "Cosmic",
}

local RECT = Vector2.new(ElderEssence.Cell, ElderEssence.Cell)

local labels: { ImageLabel } = {}
local elapsed = 0
local current = -1
local connection: RBXScriptConnection? = nil

local function offsetFor(frame: number): Vector2
	return Vector2.new((frame % ElderEssence.Columns) * ElderEssence.Cell,
		math.floor(frame / ElderEssence.Columns) * ElderEssence.Cell)
end

-- One loop for every animated essence on screen, and it stops itself when the
-- last one is destroyed. Advancing on a frame boundary rather than every render
-- step means 12 property writes a second per vial, not 60.
local function ensureLoop()
	if connection then return end
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local frame = math.floor(elapsed * ElderEssence.Fps) % ElderEssence.Frames

		local alive = false
		for i = #labels, 1, -1 do
			if labels[i] and labels[i].Parent then
				alive = true
			else
				table.remove(labels, i)
			end
		end
		if not alive then
			if connection then connection:Disconnect() end
			connection = nil
			current = -1
			return
		end

		if frame == current then return end
		current = frame
		local offset = offsetFor(frame)
		for _, label in ipairs(labels) do
			label.ImageRectOffset = offset
		end
	end)
end

-- Creates the vial for `tier` under `parent`. Callers pass their own size and
-- position through `props`; this module never assumes a layout.
--
-- The animated/still split is handled HERE rather than by callers, so nobody
-- has to remember that V is the special one.
function ElderEssence.attach(parent: Instance, tier: string,
	props: { [string]: any }?): ImageLabel

	local label = Instance.new("ImageLabel")
	label.Name = "ElderEssence" .. tier
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)

	local animated = tier == "V"
	if animated then
		label.Image = ElderEssence.Sheet
		label.ImageRectSize = RECT
		label.ImageRectOffset = offsetFor(current >= 0 and current or 0)
		label.ScaleType = Enum.ScaleType.Stretch
	else
		label.Image = ElderEssence.Art[tier] or ElderEssence.Art.I
		label.ScaleType = Enum.ScaleType.Fit
	end

	if props then
		for key, value in pairs(props) do
			if key ~= "Parent" then (label :: any)[key] = value end
		end
	end

	label.Parent = parent
	if animated then
		table.insert(labels, label)
		ensureLoop()
	end
	return label
end

return ElderEssence
