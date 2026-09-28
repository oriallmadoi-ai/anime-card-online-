--!strict
-- Builds ONE overworld encounter card.
--
-- Everything a player sees for an encounter is created here: the card body, the
-- live face, the back, the ground ring, the rarity edge light, the label and the
-- themed particles. The controller that owns these only positions and animates
-- them; it does not know what a card looks like. Restyling every encounter in
-- the world is an edit in this file and EncounterDefinitions, nowhere else.
--
-- WHY THE FACE IS A LIVE SurfaceGui AND NOT A BAKED TEXTURE.
-- The face is CardRenderer - the same builder the deck, the reveal and the
-- battle inspect use. So an encounter is not a PICTURE of a card, it IS one:
-- edit CardDefinitions or VariantConfig and the overworld updates with no
-- re-export, and the rarity border keeps the travelling Shine the rest of the
-- game uses. Baking would have frozen all of that into an image.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local ED = require(ReplicatedStorage.Shared.Config.EncounterDefinitions)

local EncounterCard = {}

local INK = Color3.fromRGB(7, 7, 11)

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------

local function new(class: string, props: { [string]: any }): any
	local inst = Instance.new(class)
	local parent = props.Parent
	for k, v in pairs(props) do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	if parent then inst.Parent = parent end
	return inst
end

-- The SAME rule CardRenderer uses to colour the border and the denominator, so
-- the ring, the edge light and the card's own outline can never disagree. If
-- that rule ever changes, it changes in one place and this follows.
local function rarityColour(variant): Color3
	return variant.color
end

local function dressPart(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Locked = true
end

----------------------------------------------------------------
-- CARD BODY
----------------------------------------------------------------

-- Returns the body and whether the real mesh was used.
--
-- CreateMeshPartAsync is the only way to bring a mesh in at runtime (MeshId is
-- not assignable on a live MeshPart), and it yields, so build() must be called
-- from a thread that is allowed to wait.
local function createBody(size: Vector3): (BasePart, boolean)
	local meshId = ED.CardMeshId
	if type(meshId) == "string" and meshId ~= "" then
		local ok, part = pcall(function()
			return AssetService:CreateMeshPartAsync(meshId, {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Precise,
			})
		end)
		if ok and typeof(part) == "Instance" and part:IsA("MeshPart") then
			part.Size = size
			part.Material = Enum.Material.SmoothPlastic
			part.Color = Color3.new(1, 1, 1)   -- let the baked atlas show unmodified
			return part, true
		end
		-- A bad id must not take the overworld down with it.
		warn(("[EncounterCard] CardMeshId %q could not be loaded (%s); using the Part fallback.")
			:format(meshId, tostring(part)))
	end

	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Block
	p.Size = size
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(24, 22, 30)
	return p, false
end

----------------------------------------------------------------
-- PARTICLES
----------------------------------------------------------------

local function buildEmitter(parent: BasePart, spec, tint: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = ED.texture(spec.texture)
	e.Color = ColorSequence.new(tint)
	e.Rate = spec.rate
	e.Lifetime = NumberRange.new(spec.life[1], spec.life[2])
	e.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
	e.SpreadAngle = Vector2.new(spec.spread, spec.spread)

	-- Constant size with an ENVELOPE, not a ramp: the envelope randomises size
	-- per particle, which is what makes a handful of droplets look like weather.
	-- A ramp would instead make every particle grow in unison, which reads as a
	-- pulse and draws the eye.
	local mid = (spec.size[1] + spec.size[2]) * 0.5
	local env = (spec.size[2] - spec.size[1]) * 0.5
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, mid, env),
		NumberSequenceKeypoint.new(1, mid, env),
	})

	-- Fade in and out rather than popping. The resting value is the spec's.
	local a = spec.transparency
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.22, a),
		NumberSequenceKeypoint.new(0.74, a),
		NumberSequenceKeypoint.new(1, 1),
	})

	e.Acceleration = spec.accel or Vector3.zero
	e.Drag = spec.drag or 0
	e.LightEmission = spec.light or 0.5
	e.LightInfluence = 0
	e.EmissionDirection = spec.dir or Enum.NormalId.Top
	e.Rotation = NumberRange.new(0, 360)
	if spec.rot then
		e.RotSpeed = NumberRange.new(spec.rot[1], spec.rot[2])
	end

	-- Parented to the PART, not an Attachment, so particles are born anywhere in
	-- the card's volume. From an attachment they would all stream out of a single
	-- point in the middle, which looks like a fountain rather than an aura.
	e.Parent = parent
	return e
end

----------------------------------------------------------------
-- LABEL
----------------------------------------------------------------

local function buildLabel(body: BasePart, name: string, entry, diff, height: number)
	local gui = new("BillboardGui", {
		Name = "Label",
		Parent = body,
		-- BillboardGui offset units scale with distance, so this is small on
		-- purpose: readable when you are at the card, a smudge by the time you are
		-- across the plaza. The old NPC nameplates were 220x64 and shouted from
		-- anywhere, which is the thing being fixed.
		Size = UDim2.fromOffset(196, 46),
		StudsOffsetWorldSpace = Vector3.new(0, -(height * 0.5) - 0.85, 0),
		AlwaysOnTop = false,
		LightInfluence = 0,
		-- Distant encounters stay clean silhouettes: past this the text is simply
		-- not drawn, which is both the look asked for and free performance.
		MaxDistance = 72,
		ClipsDescendants = false,
	})

	local root = new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})

	local title = new("TextLabel", {
		Name = "EnemyName",
		Parent = root,
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Text = string.upper(name),
		FontFace = Theme.font(),
		TextSize = 16,
		TextColor3 = Color3.fromRGB(246, 243, 255),
		TextTransparency = 1,
	})
	new("UIStroke", { Parent = title, Color = INK, Thickness = 2,
		LineJoinMode = Enum.LineJoinMode.Round, Transparency = 1 })

	-- Difficulty chip. AutomaticSize so the pill hugs its word instead of being a
	-- fixed bar that looks empty on "EASY" and cramped on "BOSS ENCOUNTER".
	local chip = new("Frame", {
		Name = "Chip",
		Parent = root,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 24),
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = INK,
		BackgroundTransparency = 1,
	})
	new("UICorner", { Parent = chip, CornerRadius = UDim.new(1, 0) })
	new("UIPadding", { Parent = chip,
		PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) })
	local chipStroke = new("UIStroke", { Parent = chip,
		Color = diff.color, Thickness = 1, Transparency = 1 })

	local chipText = new("TextLabel", {
		Parent = chip,
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Text = entry.IsBoss and ("\u{2726} " .. diff.text) or diff.text,
		FontFace = Theme.font(),
		TextSize = 10,
		TextColor3 = diff.color,
		TextTransparency = 1,
	})

	return {
		gui = gui, title = title, titleStroke = title:FindFirstChildOfClass("UIStroke"),
		chip = chip, chipStroke = chipStroke, chipText = chipText,
	}
end

----------------------------------------------------------------
-- BUILD
----------------------------------------------------------------

-- entry: one row of EncounterDefinitions.Data
-- Yields (CreateMeshPartAsync). Returns nil if the card id is unknown.
function EncounterCard.build(entry, parent: Instance)
	local def = CardDefinitions.get(entry.CardId)
	if not def then
		warn(("[EncounterCard] no card definition for %q; encounter skipped")
			:format(tostring(entry.CardId)))
		return nil
	end

	local variant = VariantConfig.get(entry.Variant or "Standard")
	local diff = ED.difficulty(entry.Difficulty)
	local effect = ED.effect(entry.Effect)
	local rarity = rarityColour(variant)
	local C = ED.Card

	local scale = entry.IsBoss and C.BossScale or 1
	local h = C.Height * scale
	local w = h / C.Aspect
	local t = C.Thickness * scale

	local model = Instance.new("Model")
	model.Name = "Encounter_" .. entry.CardId

	----------------------------------------------------------------
	-- body
	----------------------------------------------------------------
	local body, usedMesh = createBody(Vector3.new(w, h, t))
	body.Name = "Body"
	dressPart(body)
	body.CastShadow = true
	body.Parent = model
	model.PrimaryPart = body

	----------------------------------------------------------------
	-- live card face
	----------------------------------------------------------------
	local faceW = C.FaceWidth
	local faceH = math.floor(faceW * C.Aspect)

	local face = new("SurfaceGui", {
		Name = "Face",
		Parent = body,
		Face = ED.MeshFrontIsFlipped and Enum.NormalId.Back or Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(faceW, faceH),
		-- The artwork must not be muted by whatever the map's ambient happens to
		-- be; a card face reads as printed and lit, like the UI it came from.
		LightInfluence = 0,
		Brightness = 1.08,
		AlwaysOnTop = false,
		MaxDistance = 300,
		ZOffset = 0.02,   -- clear of the mesh's own front plate, so no z-fighting
	})

	local card = CardRenderer.create(face, faceW)
	CardRenderer.update(card, {
		cardId = entry.CardId,
		variant = variant.id,
		level = 0,
	})
	-- A world encounter is not an owned copy, so a level pill reading "0" is
	-- meaningless noise. Everything else on the face is true of the enemy.
	if card.levelPill then card.levelPill.Visible = false end

	----------------------------------------------------------------
	-- back
	----------------------------------------------------------------
	-- Only the fallback needs one drawn: the mesh already carries the real card
	-- back in its baked texture, which is the whole point of the mesh.
	if not usedMesh then
		local back = new("SurfaceGui", {
			Name = "Back",
			Parent = body,
			Face = ED.MeshFrontIsFlipped and Enum.NormalId.Front or Enum.NormalId.Back,
			SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
			CanvasSize = Vector2.new(faceW, faceH),
			LightInfluence = 0.15,
			AlwaysOnTop = false,
			MaxDistance = 300,
			ZOffset = 0.02,
		})
		new("ImageLabel", {
			Parent = back,
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = INK,
			BorderSizePixel = 0,
			Image = ED.Assets.CardBack,
			ScaleType = Enum.ScaleType.Crop,
		})
	end

	----------------------------------------------------------------
	-- rarity edge light
	----------------------------------------------------------------
	-- A neon slab a little larger than the card, sitting directly behind it. The
	-- card hides the middle, so only a rim of it shows - which is exactly the
	-- rarity-coloured edge light, with no texture and no per-frame work. It also
	-- survives being looked at from any angle, which a camera-facing glow sprite
	-- would not.
	local bleed = 0.30 * scale
	local glow = new("Part", {
		Name = "EdgeLight",
		Parent = model,
		Size = Vector3.new(w + bleed, h + bleed, 0.02),
		Material = Enum.Material.Neon,
		Color = rarity,
		Transparency = 0.62,
		CastShadow = false,
	})
	dressPart(glow)

	local light = new("PointLight", {
		Parent = body,
		Color = rarity,
		Range = (entry.IsBoss and 15 or 11),
		Brightness = 0.75,
		Shadows = false,
	})

	----------------------------------------------------------------
	-- ground ring
	----------------------------------------------------------------
	local ringSize = (entry.IsBoss and 9.0 or 6.4)
	local ring = new("Part", {
		Name = "GroundRing",
		Parent = model,
		Size = Vector3.new(ringSize, 0.05, ringSize),
		Transparency = 1,     -- the part is only a surface for the decal
		CastShadow = false,
	})
	dressPart(ring)
	local ringDecal = new("Decal", {
		Name = "Ring",
		Parent = ring,
		Face = Enum.NormalId.Top,
		Texture = ED.Assets.Ring,
		Color3 = rarity,
		Transparency = 0.62,
	})

	----------------------------------------------------------------
	-- label + prompt + particles
	----------------------------------------------------------------
	local label = buildLabel(body, def.name, entry, diff, h)

	local prompt = new("ProximityPrompt", {
		Name = "EncounterPrompt",
		Parent = body,
		ActionText = "Challenge",
		ObjectText = string.upper(def.name),
		KeyboardKeyCode = Enum.KeyCode.E,
		GamepadKeyCode = Enum.KeyCode.ButtonX,
		HoldDuration = 0,
		RequiresLineOfSight = false,
		MaxActivationDistance = entry.IsBoss and 14 or 12,
		Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton,
	})
	-- These attribute names are the CONTRACT with NPCEncounterController, which
	-- keys entirely off EncounterCardId. Renaming one silently stops encounters
	-- opening.
	prompt:SetAttribute("EncounterCardId", entry.CardId)
	prompt:SetAttribute("Difficulty", entry.Difficulty)
	prompt:SetAttribute("EncounterOrder", entry.Order)

	local emitters: { ParticleEmitter } = {}
	for _, spec in ipairs(effect.emitters) do
		table.insert(emitters, buildEmitter(body, spec, effect.tint))
	end

	model.Parent = parent

	return {
		entry = entry,
		def = def,
		variant = variant,
		rarity = rarity,
		tint = effect.tint,
		glowStrength = effect.glow or 0.9,

		model = model,
		body = body,
		face = face,
		card = card,
		glow = glow,
		light = light,
		ring = ring,
		ringDecal = ringDecal,
		label = label,
		prompt = prompt,
		emitters = emitters,

		usedMesh = usedMesh,
		scale = scale,
		width = w,
		height = h,
		thickness = t,

		-- filled in by the controller
		anchorCFrame = CFrame.identity,
		phase = 0,
		nearness = 0,
		asleep = false,
	}
end

----------------------------------------------------------------
-- PRESENTATION STATE
----------------------------------------------------------------

-- t = 0 when the player is far, 1 when they are at the card. `pulse` is a slow
-- 0..1 breath the controller supplies, phased per card.
--
-- Everything that reacts to proximity is gathered here, so "what does
-- approaching an encounter look like" has a single answer rather than being
-- smeared across the animation loop.
function EncounterCard.setNearness(h, t: number, pulse: number?)
	t = math.clamp(t, 0, 1)
	local p = pulse or 0.5
	h.nearness = t

	local g = h.glowStrength
	-- The breath is small and gets SMALLER as you approach: far away it is what
	-- makes the card read as alive, up close the steady glow reads as focused.
	local breath = (0.055 * (1 - t * 0.55)) * (p - 0.5) * 2
	h.glow.Transparency = math.clamp(0.72 - 0.26 * t * g - breath, 0, 1)
	h.light.Brightness = (0.55 + 0.75 * t) * g * (1 + breath * 0.9)
	h.ringDecal.Transparency = math.clamp(0.72 - 0.34 * t - breath * 0.7, 0, 1)

	-- Text arrives late and quickly, so distant cards stay clean silhouettes and
	-- the label does not creep in from halfway across the map.
	local text = math.clamp((t - 0.45) / 0.35, 0, 1)
	h.label.title.TextTransparency = 1 - text
	h.label.titleStroke.Transparency = 1 - text
	h.label.chipText.TextTransparency = 1 - text
	h.label.chipStroke.Transparency = 1 - text * 0.75
	h.label.chip.BackgroundTransparency = 1 - text * 0.55
end

-- Cards a long way off stop emitting and stop being lit. Nothing is destroyed,
-- so waking one is a single property write rather than a rebuild.
function EncounterCard.setAsleep(h, asleep: boolean)
	if h.asleep == asleep then return end
	h.asleep = asleep
	for _, e in ipairs(h.emitters) do
		e.Enabled = not asleep
	end
	h.light.Enabled = not asleep
	if asleep then
		EncounterCard.setNearness(h, 0)
	end
end

function EncounterCard.destroy(h)
	if h and h.model then
		h.model:Destroy()
	end
end

return EncounterCard
