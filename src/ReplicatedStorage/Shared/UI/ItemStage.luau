--!nonstrict
-- ItemStage: how a Backpack item is PRESENTED, as opposed to what it is.
--
-- Two jobs, both about making an item read as a collectible rather than an
-- icon:
--   * mount() puts an item's art in a tile or on the inspect pedestal. The
--     Elder Coin is its real 3D model (ElderCoin.viewport). An Elder Essence
--     keeps its own Blender render (ElderEssence.attach - V still plays its
--     25-frame sheet) and gains an idle float plus effects that grow with the
--     tier, so I -> V reads as a ladder without anything being written.
--   * platform() is the display pedestal in the inspect panel: a rune disc
--     turning in real perspective, a light from above and a few motes.
--
-- SAME ARCHITECTURE AS ElderCoin / ElderEssence. One Heartbeat loop drives
-- every entry; an entry is dropped the moment its root leaves the tree and the
-- loop disconnects itself when none are left. There is no tween per sprite.
--
-- GATED. An entry may name a `gate` - the Backpack window - and does no work
-- while that gate is hidden. The gate also carries a "PanelVisibility"
-- attribute while the window fades in or out; every effect multiplies its
-- alpha by it, so the effects fade with the window instead of popping. Effect
-- layers are tagged NoFade so the window's own fade leaves them alone.
--
-- THE LADDER, kept deliberately quiet:
--   I    a floor shadow and the faintest glow
--   II   a warm glow behind the vial
--   III  the glow, plus two motes drifting up
--   IV   a stronger glow, three motes and a slow energy pulse
--   V    a glow that walks the Cosmic palette, a turning rune halo, four
--        motes and the occasional glint
--
-- SUMMON CORES use the same ladder idea, one step per FAMILY (Basic quiet,
-- Cosmic walking its palette with a rune halo), and each level inside a family
-- nudges the same effects a little further. The core art is the family's
-- image; the level numeral is drawn on a plate beneath it on the pedestal and
-- by the tile's own tier badge in the grid.
--
-- CARD FORGE MATERIALS (kind "coreitem": Elder Core Essence, Elder Wrench) are
-- staged the same way as a core, with their own art and colour and no numeral
-- plate: quiet for a common material, the Cosmic palette for the wrench.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ElderCoin = require(ReplicatedStorage.Shared.UI.ElderCoin)
local ElderEssence = require(ReplicatedStorage.Shared.UI.ElderEssence)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)
local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)

local ItemStage = {}

local TAU = math.pi * 2
local entries = {}
local connection = nil
local clock = 0

local function ensureLoop()
	if connection then return end
	connection = RunService.Heartbeat:Connect(function(dt)
		clock += dt
		for i = #entries, 1, -1 do
			local e = entries[i]
			local root = e.root
			if not root.Parent then
				table.remove(entries, i)
			elseif root.Visible and (e.gate == nil or e.gate.Visible) then
				local vis = e.visibility
				if e.gate then
					vis *= (e.gate:GetAttribute("PanelVisibility") or 1)
				end
				e.boost += (e.boostTarget - e.boost) * math.min(1, dt * 9)
				e.step(e, clock, vis)
			end
		end
		if #entries == 0 and connection then
			connection:Disconnect()
			connection = nil
		end
	end)
end

local function register(entry)
	entry.boost = 0
	entry.boostTarget = 0
	entry.visibility = 1
	table.insert(entries, entry)
	ensureLoop()
	return entry
end

local function sprite(parent, image, props)
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Image = image
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.ScaleType = Enum.ScaleType.Stretch
	label.Active = false
	for key, value in pairs(props) do
		label[key] = value
	end
	label.Parent = parent
	return label
end

local function square(label)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.Parent = label
	return label
end

local function layer(parent, name, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

-- `rest` is the transparency the effect wants at full visibility.
local function alpha(rest, vis)
	return 1 - (1 - math.clamp(rest, 0, 1)) * vis
end

-- Samples a looping palette whose first and last colours match - the same
-- rule VariantConfig's glowColours already follow for Shine and TextShine.
local function sample(colours, t)
	local span = #colours - 1
	local pos = (t % 1) * span
	local i = math.floor(pos)
	local a = colours[i + 1]
	local b = colours[i + 2] or colours[1]
	return a:Lerp(b, pos - i)
end

local TIER_FX = {
	I   = { aura = 0.95, auraSize = 0.84, motes = 0, float = 0.013 },
	II  = { aura = 0.86, auraSize = 0.92, motes = 0, float = 0.015 },
	III = { aura = 0.8,  auraSize = 0.98, motes = 2, float = 0.017 },
	IV  = { aura = 0.74, auraSize = 1.02, motes = 3, float = 0.019, pulse = true },
	V   = { aura = 0.68, auraSize = 1.06, motes = 4, float = 0.021, ring = true, sparkle = true, cosmic = true },
}

local function handleFor(root, art, entry)
	local handle = { root = root, art = art, entry = entry }
	function handle.setBoost(_, value) entry.boostTarget = value end
	function handle.setVisibility(_, value) entry.visibility = math.clamp(value, 0, 1) end
	function handle.destroy() root:Destroy() end
	return handle
end

local function mountEssence(parent, item, opts)
	local preview = opts.size == "preview"
	local tier = item.tier or "I"
	local spec = TIER_FX[tier] or TIER_FX.I
	local variant = VariantConfig.get(item.variant or ElderEssence.Variant[tier] or "Standard")
	local tint = variant.color
	local palette = spec.cosmic and variant.border and variant.border.glowColours or nil

	local root = layer(parent, "ItemStage", opts.zIndex or 1)
	local back = layer(root, "Back", 1)
	back:SetAttribute("NoFade", true)
	local float = layer(root, "Float", 2)
	local front = layer(root, "Front", 3)
	front:SetAttribute("NoFade", true)

	local shadow = sprite(back, VfxAssets.Glow, { Name = "Shadow", ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.5, Position = UDim2.fromScale(0.5, 0.93), Size = UDim2.fromScale(0.56, 0.12), ZIndex = 1 })
	local aura = sprite(back, VfxAssets.Glow, { Name = "Aura", ImageColor3 = tint, ImageTransparency = spec.aura,
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(spec.auraSize, spec.auraSize), ZIndex = 2 })
	local ring = spec.ring and sprite(back, VfxAssets.Rune, { Name = "Halo", ImageColor3 = tint, ImageTransparency = 0.9,
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.94, 0.94), ZIndex = 3 }) or nil
	local pulse = spec.pulse and sprite(back, VfxAssets.Shock, { Name = "Pulse", ImageColor3 = tint, ImageTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.5, 0.5), ZIndex = 3 }) or nil

	-- The vial itself: the existing render, untouched.
	local art = ElderEssence.attach(float, tier, { Size = UDim2.fromScale(0.94, 0.94), ZIndex = 2 })

	local motes = {}
	local count = spec.motes > 0 and (spec.motes + (preview and 2 or 0)) or 0
	for i = 1, count do
		local seed = (i * 0.618034) % 1
		motes[i] = {
			label = square(sprite(front, VfxAssets.Mote, { Name = "Mote", ImageColor3 = tint,
				ImageTransparency = 1, Size = UDim2.fromScale(0.05, 0.05), ZIndex = 2 })),
			phase = seed,
			x = 0.3 + 0.4 * ((i * 0.37 + 0.11) % 1),
			period = 2.6 + seed * 1.6,
			size = (preview and 0.034 or 0.05) * (0.75 + 0.5 * seed),
		}
	end
	local sparkles = {}
	if spec.sparkle then
		for i, spot in ipairs({ Vector2.new(0.3, 0.3), Vector2.new(0.7, 0.44), Vector2.new(0.38, 0.72) }) do
			sparkles[i] = {
				label = square(sprite(front, VfxAssets.Spark, { Name = "Glint", ImageColor3 = Color3.new(1, 1, 1),
					ImageTransparency = 1, Position = UDim2.fromScale(spot.X, spot.Y), Size = UDim2.fromScale(0.12, 0.12), ZIndex = 3 })),
				phase = i * 0.29,
			}
		end
	end

	local phase = opts.phase or math.random()
	local amp = spec.float * (preview and 1.35 or 1)
	local entry = register({ root = root, gate = opts.gate })
	entry.step = function(e, t, vis)
		local boost = e.boost
		local breathe = math.sin((t / 3.4 + phase) * TAU)
		local rise = amp * breathe
		float.Position = UDim2.fromScale(0.5, 0.5 - rise)
		local k = 1 - 3 * rise
		shadow.Size = UDim2.fromScale(0.56 * k, 0.12 * k)
		shadow.ImageTransparency = alpha(0.5 + 4 * rise, vis)

		local tintNow = palette and sample(palette, t / 6 + phase) or tint
		if palette then aura.ImageColor3 = tintNow end
		aura.ImageTransparency = alpha(spec.aura - 0.03 * breathe - 0.07 * boost, vis)

		if ring then
			ring.Rotation = (t * 9) % 360
			ring.ImageTransparency = alpha(0.9 - 0.03 * breathe - 0.05 * boost, vis)
			if palette then ring.ImageColor3 = sample(palette, t / 6 + phase + 0.33) end
		end
		if pulse then
			local p = ((t + phase * 2.8) % 2.8) / 2.8
			local s = 0.42 + 0.62 * p
			pulse.Size = UDim2.fromScale(s, s)
			pulse.ImageTransparency = alpha(1 - (0.3 + 0.1 * boost) * (1 - p) ^ 2, vis)
		end
		for _, m in ipairs(motes) do
			local p = (t / m.period + m.phase) % 1
			local a = math.sin(p * math.pi)
			m.label.Position = UDim2.fromScale(m.x + 0.05 * math.sin((t / 1.9 + m.phase) * TAU), 0.84 - 0.66 * p)
			local size = m.size * (0.55 + 0.45 * a)
			m.label.Size = UDim2.fromScale(size, size)
			m.label.ImageTransparency = alpha(1 - (0.6 + 0.2 * boost) * a, vis)
			if palette then m.label.ImageColor3 = sample(palette, t / 6 + m.phase) end
		end
		for _, s in ipairs(sparkles) do
			local glint = math.max(0, math.sin((t / 2.9 + s.phase) * TAU)) ^ 12
			s.label.ImageTransparency = alpha(1 - 0.9 * glint, vis)
			local size = 0.08 + 0.08 * glint
			s.label.Size = UDim2.fromScale(size, size)
		end
	end
	return handleFor(root, art, entry)
end

local function mountCoin(parent, item, opts)
	local preview = opts.size == "preview"
	local variant = VariantConfig.get(item.variant or "Cosmic")
	local palette = variant.border and variant.border.glowColours or nil

	local root = layer(parent, "ItemStage", opts.zIndex or 1)
	local back = layer(root, "Back", 1)
	back:SetAttribute("NoFade", true)
	local coinLayer = layer(root, "Coin", 2)

	local shadow = sprite(back, VfxAssets.Glow, { Name = "Shadow", ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.45, Position = UDim2.fromScale(0.5, 0.93), Size = UDim2.fromScale(0.62, 0.12), ZIndex = 1 })
	local aura = sprite(back, VfxAssets.Glow, { Name = "Aura", ImageColor3 = variant.color, ImageTransparency = 0.8,
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.04, 1.04), ZIndex = 2 })

	local phase = opts.phase or math.random()
	local view = ElderCoin.viewport(coinLayer, { Size = UDim2.fromScale(1, 1), ZIndex = 1 }, {
		gate = opts.gate,
		phase = phase,
		period = preview and 9 or 8,
		bob = preview and 0.07 or 0.05,
		tilt = -14,
		wobble = 2.5,
		fill = preview and 0.74 or 0.86,
		lightSwing = preview and 0.6 or 0.3,
	})
	local baseLight = view:IsA("ViewportFrame") and view.LightColor or nil

	local entry = register({ root = root, gate = opts.gate })
	entry.step = function(e, t, vis)
		local breathe = math.sin((t / 3.6 + phase) * TAU)
		if palette then aura.ImageColor3 = sample(palette, t / 7 + phase) end
		aura.ImageTransparency = alpha(0.8 - 0.035 * breathe - 0.08 * e.boost, vis)
		shadow.ImageTransparency = alpha(0.45, vis)
		if baseLight then
			view.LightColor = baseLight:Lerp(Color3.new(1, 1, 1), 0.3 * e.boost)
		end
	end
	return handleFor(root, view, entry)
end

local CORE_FX = {
	Basic  = { aura = 0.9,  auraSize = 0.9,  motes = 0, float = 0.014 },
	Gilded = { aura = 0.84, auraSize = 0.96, motes = 2, float = 0.016 },
	Divine = { aura = 0.8,  auraSize = 1.0,  motes = 3, float = 0.018, pulse = true },
	Secret = { aura = 0.76, auraSize = 1.04, motes = 3, float = 0.019, pulse = true, sparkle = true },
	Cosmic = { aura = 0.7,  auraSize = 1.08, motes = 4, float = 0.021, pulse = true, ring = true, sparkle = true, cosmic = true },
}

-- Card Forge materials, by the tier they borrow their look from.
local ITEM_FX = {
	Standard = { aura = 0.88, auraSize = 0.92, motes = 2, float = 0.015 },
	Cosmic   = { aura = 0.76, auraSize = 1.02, motes = 3, float = 0.018, ring = true, sparkle = true, cosmic = true },
}

-- A Summon Core: the family's art floating over its own glow, plus a numeral
-- plate on the pedestal. opts.numeral forces the plate on (true) or off
-- (false); by default only the inspect pedestal ("preview") draws it, because
-- a grid tile already shows the level in its tier badge.
-- A forge material (kind "coreitem") goes through here too, with its own
-- image, colour and ITEM_FX, and never a numeral.
local function mountCore(parent, item, opts)
	local preview = opts.size == "preview"
	local isMaterial = item.kind == "coreitem"
	local family = SummonCoreConfig.Families[item.family or "Basic"] or SummonCoreConfig.Families.Basic
	local spec = CORE_FX[family.id] or CORE_FX.Basic
	local level = math.max(1, item.level or 1)
	local tint = family.colour
	local image = family.image
	if isMaterial then
		spec = ITEM_FX[item.variant or "Standard"] or ITEM_FX.Standard
		level = 1
		tint = item.colour or VariantConfig.get(item.variant or "Standard").color
		image = item.image or ""
	end
	local palette = spec.cosmic and VariantConfig.get("Cosmic").border.glowColours or nil
	-- Each level inside a family lifts the same effects a notch.
	local lift = (level - 1) * 0.025

	local root = layer(parent, "ItemStage", opts.zIndex or 1)
	local back = layer(root, "Back", 1)
	back:SetAttribute("NoFade", true)
	local float = layer(root, "Float", 2)
	local front = layer(root, "Front", 3)
	front:SetAttribute("NoFade", true)

	local shadow = sprite(back, VfxAssets.Glow, { Name = "Shadow", ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.5, Position = UDim2.fromScale(0.5, 0.93), Size = UDim2.fromScale(0.56, 0.12), ZIndex = 1 })
	local auraRest = spec.aura - lift
	local aura = sprite(back, VfxAssets.Glow, { Name = "Aura", ImageColor3 = tint, ImageTransparency = auraRest,
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(spec.auraSize + lift, spec.auraSize + lift), ZIndex = 2 })
	local ring = spec.ring and sprite(back, VfxAssets.Rune, { Name = "Halo", ImageColor3 = tint, ImageTransparency = 0.9,
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.96, 0.96), ZIndex = 3 }) or nil
	local pulse = spec.pulse and sprite(back, VfxAssets.Shock, { Name = "Pulse", ImageColor3 = tint, ImageTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(0.5, 0.5), ZIndex = 3 }) or nil

	local art = sprite(float, image, { Name = isMaterial and "Material" or "Core", Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9), ScaleType = Enum.ScaleType.Fit, ZIndex = 2 })

	local showNumeral = opts.numeral
	if showNumeral == nil then showNumeral = preview end
	if isMaterial then showNumeral = false end
	if showNumeral then
		local plate = Instance.new("Frame")
		plate.Name = "Numeral"
		plate.AnchorPoint = Vector2.new(0.5, 0.5)
		plate.Position = UDim2.fromScale(0.5, 0.97)
		plate.Size = UDim2.fromScale(0.3, 0.13)
		plate.BackgroundColor3 = Color3.fromRGB(13, 12, 20)
		plate.BackgroundTransparency = 0.12
		plate.BorderSizePixel = 0
		plate.ZIndex = 4
		plate.Parent = root
		local plateCorner = Instance.new("UICorner")
		plateCorner.CornerRadius = UDim.new(0.5, 0)
		plateCorner.Parent = plate
		local plateStroke = Instance.new("UIStroke")
		plateStroke.Color = tint
		plateStroke.Transparency = 0.35
		plateStroke.Thickness = 1.2
		plateStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		plateStroke.Parent = plate
		local label = Instance.new("TextLabel")
		label.Name = "Value"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = SummonCoreConfig.roman(level)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = tint:Lerp(Color3.new(1, 1, 1), 0.35)
		label.ZIndex = 5
		label.Parent = plate
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.16, 0)
		pad.PaddingBottom = UDim.new(0.16, 0)
		pad.Parent = label
	end

	local motes = {}
	local count = spec.motes > 0 and (spec.motes + (preview and 2 or 0)) or 0
	for i = 1, count do
		local seed = (i * 0.618034) % 1
		motes[i] = {
			label = square(sprite(front, VfxAssets.Mote, { Name = "Mote", ImageColor3 = tint,
				ImageTransparency = 1, Size = UDim2.fromScale(0.05, 0.05), ZIndex = 2 })),
			phase = seed,
			x = 0.3 + 0.4 * ((i * 0.37 + 0.11) % 1),
			period = 2.6 + seed * 1.6,
			size = (preview and 0.034 or 0.05) * (0.75 + 0.5 * seed),
		}
	end
	local sparkles = {}
	if spec.sparkle then
		for i, spot in ipairs({ Vector2.new(0.28, 0.26), Vector2.new(0.72, 0.4), Vector2.new(0.36, 0.74) }) do
			sparkles[i] = {
				label = square(sprite(front, VfxAssets.Spark, { Name = "Glint", ImageColor3 = Color3.new(1, 1, 1),
					ImageTransparency = 1, Position = UDim2.fromScale(spot.X, spot.Y), Size = UDim2.fromScale(0.12, 0.12), ZIndex = 3 })),
				phase = i * 0.29,
			}
		end
	end

	local phase = opts.phase or math.random()
	local amp = spec.float * (preview and 1.35 or 1)
	local entry = register({ root = root, gate = opts.gate })
	entry.step = function(e, t, vis)
		local boost = e.boost
		local breathe = math.sin((t / 3.4 + phase) * TAU)
		local rise = amp * breathe
		float.Position = UDim2.fromScale(0.5, 0.5 - rise)
		float.Rotation = 1.4 * math.sin((t / 5.1 + phase) * TAU)
		local k = 1 - 3 * rise
		shadow.Size = UDim2.fromScale(0.56 * k, 0.12 * k)
		shadow.ImageTransparency = alpha(0.5 + 4 * rise, vis)

		local tintNow = palette and sample(palette, t / 6 + phase) or tint
		if palette then aura.ImageColor3 = tintNow end
		aura.ImageTransparency = alpha(auraRest - 0.03 * breathe - 0.07 * boost, vis)

		if ring then
			ring.Rotation = (t * 9) % 360
			ring.ImageTransparency = alpha(0.88 - 0.03 * breathe - 0.05 * boost - lift, vis)
			if palette then ring.ImageColor3 = sample(palette, t / 6 + phase + 0.33) end
		end
		if pulse then
			local p = ((t + phase * 2.8) % 2.8) / 2.8
			local s = 0.42 + 0.62 * p
			pulse.Size = UDim2.fromScale(s, s)
			pulse.ImageTransparency = alpha(1 - (0.3 + 0.1 * boost + lift) * (1 - p) ^ 2, vis)
		end
		for _, m in ipairs(motes) do
			local p = (t / m.period + m.phase) % 1
			local a = math.sin(p * math.pi)
			m.label.Position = UDim2.fromScale(m.x + 0.05 * math.sin((t / 1.9 + m.phase) * TAU), 0.84 - 0.66 * p)
			local size = m.size * (0.55 + 0.45 * a)
			m.label.Size = UDim2.fromScale(size, size)
			m.label.ImageTransparency = alpha(1 - (0.6 + 0.2 * boost) * a, vis)
			if palette then m.label.ImageColor3 = sample(palette, t / 6 + m.phase) end
		end
		for _, s in ipairs(sparkles) do
			local glint = math.max(0, math.sin((t / 2.9 + s.phase) * TAU)) ^ 12
			s.label.ImageTransparency = alpha(1 - 0.9 * glint, vis)
			local size = 0.08 + 0.08 * glint
			s.label.Size = UDim2.fromScale(size, size)
		end
	end
	return handleFor(root, art, entry)
end

-- Puts `item`'s art under `parent`, filling it. opts:
--   size   "card" (grid tile) or "preview" (inspect pedestal)
--   gate   the window; nothing animates while it is hidden
--   phase  0..1, desynchronises idle loops between copies
--   numeral  Summon Cores only: force the level plate on or off
-- Returns a handle: handle:setBoost(0..1) for hover, handle:setVisibility(0..1)
-- for a caller-driven fade, handle:destroy().
function ItemStage.mount(parent, item, opts)
	opts = opts or {}
	if item.kind == "coin" or item.id == "ElderCoin" then
		return mountCoin(parent, item, opts)
	end
	if item.kind == "core" or item.kind == "coreitem" then
		return mountCore(parent, item, opts)
	end
	return mountEssence(parent, item, opts)
end

-- The inspect panel's pedestal. Fills `parent` (the stage) and sits behind
-- the item. Returns a handle with setColor(colour, palette?) - pass a palette
-- (a glowColours list) to have the pedestal walk it, as Cosmic items do.
function ItemStage.platform(parent, opts)
	opts = opts or {}
	local color = opts.color or Color3.fromRGB(150, 110, 255)
	local palette = nil

	local root = layer(parent, "Pedestal", opts.zIndex or 1)
	root:SetAttribute("NoFade", true)

	local top = sprite(root, VfxAssets.Glow, { Name = "TopLight", ImageColor3 = Color3.fromRGB(196, 180, 255),
		ImageTransparency = 0.9, Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromScale(1.3, 0.95), ZIndex = 1 })
	local floor = sprite(root, VfxAssets.Glow, { Name = "FloorGlow", ImageColor3 = color, ImageTransparency = 0.66,
		Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromScale(0.95, 0.26), ZIndex = 2 })

	-- A real disc seen at a low angle, so the rune foreshortens properly as it
	-- turns - a squashed 2D image cannot rotate without shearing.
	local disc = Instance.new("ViewportFrame")
	disc.Name = "RuneDisc"
	disc.BackgroundTransparency = 1
	disc.BorderSizePixel = 0
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.8)
	disc.Size = UDim2.fromScale(1, 0.36)
	disc.Ambient = Color3.new(1, 1, 1)
	disc.LightColor = Color3.new(0, 0, 0)
	disc.LightDirection = Vector3.new(0, -1, 0)
	disc.ZIndex = 3
	disc.Parent = root
	local plate = Instance.new("Part")
	plate.Name = "Plate"
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.CastShadow = false
	plate.Transparency = 1
	plate.Size = Vector3.new(4, 0.02, 4)
	plate.CFrame = CFrame.new()
	plate.Parent = disc
	local rune = Instance.new("Decal")
	rune.Name = "Rune"
	rune.Face = Enum.NormalId.Top
	rune.Texture = VfxAssets.Rune
	rune.Color3 = color
	rune.Transparency = 0.3
	rune.Parent = plate
	local camera = Instance.new("Camera")
	camera.FieldOfView = 24
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 2.05, 6.3), Vector3.zero)
	camera.Parent = disc
	disc.CurrentCamera = camera

	local motes = {}
	for i = 1, 6 do
		local seed = (i * 0.618034) % 1
		motes[i] = {
			label = square(sprite(root, VfxAssets.Mote, { Name = "Mote", ImageColor3 = color, ImageTransparency = 1,
				Size = UDim2.fromScale(0.02, 0.02), ZIndex = 4 })),
			phase = seed,
			x = 0.32 + 0.36 * ((i * 0.41 + 0.07) % 1),
			period = 3.4 + seed * 2.2,
			size = 0.016 + 0.014 * seed,
		}
	end

	local entry = register({ root = root, gate = opts.gate })
	entry.step = function(_, t, vis)
		plate.CFrame = CFrame.Angles(0, math.rad(t * 7), 0)
		disc.ImageTransparency = 1 - vis
		local breathe = math.sin((t / 4.2) * TAU)
		if palette then
			local c = sample(palette, t / 7)
			rune.Color3 = c
			floor.ImageColor3 = c
		end
		floor.ImageTransparency = alpha(0.66 - 0.04 * breathe, vis)
		top.ImageTransparency = alpha(0.9 - 0.02 * breathe, vis)
		for _, m in ipairs(motes) do
			local p = (t / m.period + m.phase) % 1
			local a = math.sin(p * math.pi)
			m.label.Position = UDim2.fromScale(m.x + 0.03 * math.sin((t / 2.3 + m.phase) * TAU), 0.8 - 0.55 * p)
			local size = m.size * (0.6 + 0.4 * a)
			m.label.Size = UDim2.fromScale(size, size)
			m.label.ImageTransparency = alpha(1 - 0.55 * a, vis)
			if palette then m.label.ImageColor3 = sample(palette, t / 7 + m.phase) end
		end
	end

	local handle = { root = root, disc = disc }
	function handle.setColor(_, newColor, newPalette)
		color = newColor
		palette = newPalette
		if not newPalette then
			local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			game:GetService("TweenService"):Create(rune, info, { Color3 = newColor }):Play()
			game:GetService("TweenService"):Create(floor, info, { ImageColor3 = newColor }):Play()
			for _, m in ipairs(motes) do
				m.label.ImageColor3 = newColor
			end
		end
	end
	function handle.destroy() root:Destroy() end
	return handle
end

return ItemStage
