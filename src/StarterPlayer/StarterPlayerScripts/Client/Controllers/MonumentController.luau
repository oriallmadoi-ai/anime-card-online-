--!strict
-- THE LOBBY MONUMENT
--
-- WHAT IT SHOWS, AND WHY IT IS BUILT ON THE CLIENT.
-- The card is the rarest one THIS player can currently pull - the deepest
-- entry in CardDefinitions.RarestFirst their encounter clears have unlocked.
-- Per-player by definition, so it is built locally and two players standing
-- side by side each see their own. Rebuilt on every ProfileSync.
--
-- HIERARCHY. This is the rule the whole file serves, in order:
--     CARD  >  halo / beam  >  orbits  >  pedestal  >  floor
-- Earlier passes inverted it - a hot accent-coloured ring and three crossing
-- orbits sat in front of the card and won the eye, so the monument read as
-- "ring with a card behind it". Every choice below is about keeping the card
-- the cleanest and most dominant silhouette in the composition. Anything that
-- would cross the card's footprint has been pushed out, dimmed, or cut.
--
-- COLOUR. Three families only: dark navy, white/soft cyan, and a little
-- violet. The card's rarity band no longer paints anything at full strength -
-- it is blended 55% toward white and used as a TINT on the card's rim and the
-- halo's inner edge. A saturated band colour on a 30-stud ring is what made
-- this look cheap.
--
-- THE CARD ALWAYS FACES YOU. It sways through a narrow arc; it does not spin.
-- A full rotation shows the near-black card back for half of every cycle and
-- crosses edge-on twice a turn. Note HomeYaw: a Part's "Front" face is its -Z,
-- so a card built at identity faces AWAY from the spawn at +Z.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local EncounterModes = require(ReplicatedStorage.Shared.Config.EncounterModes)
local EncounterDefinitions = require(ReplicatedStorage.Shared.Config.EncounterDefinitions)
local RarityBands = require(ReplicatedStorage.Shared.Config.RarityBands)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local RarityFormat = require(ReplicatedStorage.Shared.Util.RarityFormat)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local MonumentController = {}
MonumentController.Name = "MonumentController"

----------------------------------------------------------------
-- TUNING
----------------------------------------------------------------

local M = {
	-- Centre of the "Open central feature platform": top surface y = 0.58,
	-- 106.8 studs across.
	Origin = Vector3.new(-8000, 0.58, 0),

	-- CARD. The hero. Nothing else may cross its footprint.
	CardHeight = 38,
	CardThickness = 0.8,
	CardCentreY = 43,
	-- 300 and NOT higher. CardRenderer authors the card's vertical furniture
	-- in fixed pixels against a 240px reference and clamps its own vScale() at
	-- 1, so a larger canvas does not scale the type with it - it just strands
	-- reference-sized text in the middle of a huge face.
	FaceWidth = 300,

	-- MOTION. A full, continuous rotation at 5 degrees/sec - 72 seconds a turn,
	-- slow enough to read as hovering rather than spinning. HomeYaw sets where
	-- it starts: a Part's "Front" face is its -Z, so without it the live face
	-- begins pointed away from the spawn.
	--
	-- The cost of a full turn is that the back faces you for half of it, and
	-- the card back is near-black encounter art. The back SurfaceGui is unlit
	-- and over-bright to compensate, but it will never carry the front's
	-- presence - that is the trade a 360 makes.
	HomeYaw = 180,
	SpinSpeed = 5,          -- degrees/sec
	BobHeight = 1.0,
	BobPeriod = 12,
	TiltAngle = 1.2,
	TiltPeriod = 17,
	SweepPeriod = 13,       -- seconds between light sweeps across the face
	SweepTravel = 1.5,      -- seconds one sweep takes

	-- HALO. Four broken arcs in the card's plane, behind it. This replaces the
	-- accent-coloured orbit ring: a closed hot ring reads as a neon tube, four
	-- cool segments read as something containing an artifact.
	HaloRadius = 27,
	HaloInnerRadius = 22.5,
	HaloSegments = 72,
	HaloArcPeriod = 18,     -- segments per arc-plus-gap -> 4 arcs
	HaloArcOn = 13,
	HaloSpin = 1.6,         -- degrees/sec, barely perceptible
	DiscRadius = 33,

	-- BEAM. Behind the card, never across it.
	HaloBack = 2.4,         -- studs behind the card plane

	-- CRYSTAL CLUSTER. Stands on the pedestal in the gap under the card. This
	-- is the one polychrome object in the build, and it only works BECAUSE
	-- everything around it is navy and white - a rainbow in a rainbow is noise,
	-- a rainbow in a monochrome room is treasure.
	-- Height is capped by the card, not by taste: the card's bottom edge is at
	-- CardCentreY - CardHeight/2 - BobHeight = 23, and the cluster stands on
	-- the pedestal at 3.3. Anything over ~19 and the tall point spears the
	-- card. So the size went sideways instead - a wide low cluster reads bigger
	-- than a narrow tall one, and the reference is as wide as it is tall.
	ClusterHeight = 18,
	ClusterSpread = 17,     -- cluster-radius unit, in studs
	-- The reference's points are CHUNKY. At the authored diameters they came
	-- out as slivers, which reads as grass rather than as gemstone.
	ClusterGirth = 1.35,
	ClusterSpin = -2.5,     -- degrees/sec, counter to the card

	-- The monument's heartbeat. Everything that flares, flares on this - the
	-- crystal cores, the card's rim, the key light - so the whole thing
	-- breathes as one object instead of as a pile of separate animations.
	PulsePeriod = 9,
	PulseTravel = 1.7,

	-- ORBITS. Two. One level ring below the card, one diagonal wide enough to
	-- clip only the corners. Both carry travelling fragments.
	Orbits = {
		{ radius = 31, tilt = 0, yOffset = -16, speed = 5,
		  thickness = 0.3, depth = 1.0, fragments = 5, drift = 0.22 },
		{ radius = 35, tilt = 34, yOffset = 1, speed = -4,
		  thickness = 0.26, depth = 0.85, fragments = 4, drift = -0.16 },
	},
	OrbitSegments = 72,

	-- PEDESTAL. Dark metal with a bright core that throws light UP at the card.
	PedestalRadius = 19,
	PedestalHeight = 2.2,
	CapRadius = 15.5,
	CoreRadius = 5,
	EngraveCount = 16,

	-- FLOOR. Radial lines that point at the card, plus pulses running inward.
	PanelCount = 8,
	PanelInner = 23,
	PanelOuter = 47,
	RadialCount = 24,
	RunnerCount = 8,
	RunnerPeriod = 4.5,

	-- WALL. A containment ring enclosing the whole central platform, in place
	-- of freestanding masts. Masts of any size were always going to read as
	-- objects scattered around the monument; a wall makes the platform one
	-- enclosed room with the card at its centre, which is the only way the
	-- floor stops being "ground the monument stands on".
	--
	-- SIX sectors, not eight, and the count is load-bearing. Bearing 90 degrees
	-- is the spawn axis; with six sectors the mids land on 60/120/180/... so a
	-- 26-degree doorway opens exactly on the approach and you look straight
	-- through it at the card. That is what lets the wall be 26 studs tall
	-- instead of 16 - at eight sectors a panel sat dead ahead and every stud of
	-- wall ate two studs of card.
	-- Per-sector heights, so the ring has a skyline instead of a flat rim. The
	-- doorway on the approach (between sectors 1 and 2) gets the two lowest,
	-- which keeps the sightline to the card open as you walk in.
	WallHeights = { 13, 20, 15, 22, 14, 18 },
	WallRadius = 50,
	WallHeight = 18,        -- fallback if WallHeights is short
	WallThickness = 2.8,
	WallSectors = 6,
	WallSpan = 34,          -- degrees of wall per sector; the rest is doorway
	WallSegs = 7,
	WallLean = 14,          -- degrees inward, so the ring funnels toward the card
	ChaseSpeed = 0.42,      -- revolutions/sec of the light chasing the ring

	-- GATES. Tall markers standing in the doorways, carrying the verticality
	-- the wall has to give up.
	GateHeight = 30,

	-- SHARDS. Few and large, at three heights.
	ShardCount = 5,
	ShardScale = 6.5,
	ShardSpeed = 3.5,

	-- TEXT.
	FadeIn = 22,
	FadeOut = 30,
	FadeRate = 0.38,        -- per 1/15s tick; ~0.25s to full
}

-- Navy, white/cyan, violet. Nothing else.
local C = {
	ink = Color3.fromRGB(10, 14, 24),
	hull = Color3.fromRGB(30, 38, 54),
	steel = Color3.fromRGB(52, 64, 86),
	silver = Color3.fromRGB(150, 166, 186),
	white = Color3.fromRGB(236, 244, 255),
	cyan = Color3.fromRGB(150, 205, 240),
	violet = Color3.fromRGB(150, 125, 225),
}

local INK = C.ink

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------

local player = Players.LocalPlayer

local folder: Folder? = nil
local cardBody: BasePart? = nil
local cardRim: BasePart? = nil
local sweepBar: BasePart? = nil
local haloHub: BasePart? = nil
local crystalModel: Model? = nil
local crystalCores: { { part: BasePart, phase: number } } = {}
local keyLight: SpotLight? = nil
local coreLight: SpotLight? = nil
local corePad: BasePart? = nil
local orbits: { { hub: BasePart, tilt: number, speed: number, yOffset: number } } = {}
local fragments: { { part: BasePart, hub: BasePart, radius: number, angle: number, drift: number } } = {}
local runners: { { part: BasePart, angle: number, phase: number } } = {}
local wallSlots: { { part: BasePart, bearing: number } } = {}
local shards: { { part: BasePart, angle: number, radius: number, height: number, phase: number } } = {}
local plaqueGui: BillboardGui? = nil
local plaquePanel: Frame? = nil
local plaqueScale: UIScale? = nil
local plaqueAnchor: BasePart? = nil

local renderConn: RBXScriptConnection? = nil
local fadeConn: RBXScriptConnection? = nil
local shownCardId: string? = nil
local cardWidth = 28
local clock0 = os.clock()
local textAlpha = 0
local fadeAccumulator = 0

local function log(fmt: string, ...)
	print(("[Monument] " .. fmt):format(...))
end

local function new(class: string, props: { [string]: any }): any
	local inst = Instance.new(class)
	local parent = props.Parent
	for k, v in pairs(props) do
		if k ~= "Parent" then (inst :: any)[k] = v end
	end
	if parent then inst.Parent = parent end
	return inst
end

local function dress(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

----------------------------------------------------------------
-- BANDS
----------------------------------------------------------------

-- One anchored hub carries a whole band; segments are welded children, so
-- animating a band costs ONE CFrame write per frame rather than seventy.
-- `axis` is "flat" for a ring lying in XZ, or "face" for a ring standing in XY
-- (the halo, which has to sit in the card's plane rather than around it).
local function buildBand(parent: Instance, name: string, centre: Vector3, axis: string,
	radius: number, thickness: number, depth: number, colour: Color3,
	material: Enum.Material, transparency: number, reflectance: number,
	segments: number, gapEvery: number?, gapOn: number?): BasePart

	local hub = new("Part", {
		Parent = parent, Name = name,
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(centre),
		Transparency = 1,
	})
	dress(hub)

	local step = math.pi * 2 / segments
	-- 1.06 overlap so joints close on the outside of the corner.
	local segLength = 2 * radius * math.tan(step / 2) * 1.06

	for s = 0, segments - 1 do
		if gapEvery and gapOn and (s % gapEvery) >= gapOn then
			continue
		end
		local a = s * step
		local offset, size
		if axis == "face" then
			offset = CFrame.Angles(0, 0, a) * CFrame.new(radius, 0, 0)
				* CFrame.Angles(0, 0, math.rad(90))
			size = Vector3.new(segLength, thickness, depth)
		else
			offset = CFrame.Angles(0, a, 0) * CFrame.new(radius, 0, 0)
				* CFrame.Angles(0, math.rad(90), 0)
			size = Vector3.new(segLength, thickness, depth)
		end
		local seg = new("Part", {
			Parent = hub, Name = "Seg" .. s,
			Size = size,
			CFrame = hub.CFrame * offset,
			Color = colour,
			Material = material,
			Transparency = transparency,
			Reflectance = reflectance,
		})
		dress(seg)
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1, weld.Parent = hub, seg, hub
		seg.Anchored = false
	end

	return hub
end

----------------------------------------------------------------
-- WHICH CARD
----------------------------------------------------------------

-- RarestFirst may hold ids or definition tables depending on how the list was
-- assembled; normalise rather than assume.
local function idOf(entry: any): string?
	if type(entry) == "string" then return entry end
	if type(entry) == "table" then return entry.id end
	return nil
end

local function bestPullableCard(clears: { [string]: number }?): string?
	local ordered = CardDefinitions.RarestFirst
	if type(ordered) ~= "table" then return CardDefinitions.MostCommonId end
	for _, entry in ipairs(ordered) do
		local id = idOf(entry)
		if id and CardDefinitions.exists(id) and EncounterModes.isUnlocked(id, clears) then
			return id
		end
	end
	-- Everything locked should be impossible - the starter cards are absent
	-- from the Unlocks table on purpose - but a monument with nothing on it is
	-- worse than one showing the commonest card.
	return idOf(ordered[#ordered]) or CardDefinitions.MostCommonId
end

----------------------------------------------------------------
-- FLOOR
----------------------------------------------------------------

local function buildFloor(parent: Folder)
	local o = M.Origin

	-- Segmented panels. Trapezoids pointing inward, so the floor plating
	-- itself aims at the card instead of being a neutral ground it stands on.
	local length = M.PanelOuter - M.PanelInner
	local mid = (M.PanelOuter + M.PanelInner) * 0.5
	for index = 1, M.PanelCount do
		local a = (index / M.PanelCount) * math.pi * 2 + math.pi / M.PanelCount
		local face = CFrame.lookAt(
			Vector3.new(o.X + math.cos(a) * mid, o.Y + 0.05, o.Z + math.sin(a) * mid),
			Vector3.new(o.X, o.Y + 0.05, o.Z))
		local panel = new("Part", {
			Parent = parent, Name = "Panel" .. index,
			Size = Vector3.new(14, 0.12, length),
			CFrame = face,
			Color = C.hull,
			Material = Enum.Material.Metal,
			Reflectance = 0.14,
		})
		dress(panel)
	end

	-- Radial engraved lines. Dim: these are the BOTTOM of the hierarchy and
	-- must never compete with the card.
	for index = 1, M.RadialCount do
		local a = (index / M.RadialCount) * math.pi * 2
		local line = new("Part", {
			Parent = parent, Name = "Radial" .. index,
			Size = Vector3.new(length - 2, 0.1, 0.22),
			CFrame = CFrame.new(o.X + math.cos(a) * mid, o.Y + 0.13, o.Z + math.sin(a) * mid)
				* CFrame.Angles(0, -a, 0),
			Color = C.cyan,
			Material = Enum.Material.Neon,
			Transparency = 0.72,
		})
		dress(line)
	end

	-- Pulses running INWARD along those lines, toward the card. Direction is
	-- the whole point: outward pulses read as a shockwave, inward pulses read
	-- as the floor feeding the thing in the middle.
	table.clear(runners)
	for index = 1, M.RunnerCount do
		local a = (index / M.RunnerCount) * math.pi * 2
		local runner = new("Part", {
			Parent = parent, Name = "Runner" .. index,
			Size = Vector3.new(6, 0.11, 0.4),
			CFrame = CFrame.new(o.X, o.Y + 0.16, o.Z),
			Color = C.white,
			Material = Enum.Material.Neon,
			Transparency = 1,
		})
		dress(runner)
		table.insert(runners, { part = runner, angle = a, phase = index / M.RunnerCount })
	end
end

----------------------------------------------------------------
-- PEDESTAL
----------------------------------------------------------------

local function buildPedestal(parent: Folder, tint: Color3)
	local o = M.Origin

	local body = new("Part", {
		Parent = parent, Name = "PedestalBody",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(M.PedestalHeight, M.PedestalRadius * 2, M.PedestalRadius * 2),
		CFrame = CFrame.new(o.X, o.Y + M.PedestalHeight * 0.5, o.Z)
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = C.hull,
		Material = Enum.Material.Metal,
		Reflectance = 0.18,
	})
	dress(body)

	local cap = new("Part", {
		Parent = parent, Name = "PedestalCap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.55, M.CapRadius * 2, M.CapRadius * 2),
		CFrame = CFrame.new(o.X, o.Y + M.PedestalHeight + 0.2, o.Z)
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = C.steel,
		Material = Enum.Material.Metal,
		Reflectance = 0.26,
	})
	dress(cap)

	-- Engraved lines on the cap. Thin, cool, and mostly transparent - detail
	-- you notice standing on it, not from across the lobby.
	local top = o.Y + M.PedestalHeight + 0.48
	for index = 1, M.EngraveCount do
		local a = (index / M.EngraveCount) * math.pi * 2
		local r = (M.CoreRadius + M.CapRadius) * 0.5
		local groove = new("Part", {
			Parent = parent, Name = "Engrave" .. index,
			Size = Vector3.new(M.CapRadius - M.CoreRadius - 1, 0.08, 0.16),
			CFrame = CFrame.new(o.X + math.cos(a) * r, top, o.Z + math.sin(a) * r)
				* CFrame.Angles(0, -a, 0),
			Color = C.cyan,
			Material = Enum.Material.Neon,
			Transparency = 0.62,
		})
		dress(groove)
	end

	-- The core. Small, white and bright - the one hot spot at ground level.
	local core = new("Part", {
		Parent = parent, Name = "Core",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, M.CoreRadius * 2, M.CoreRadius * 2),
		CFrame = CFrame.new(o.X, top + 0.1, o.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.white,
		Material = Enum.Material.Neon,
		Transparency = 0.06,
	})
	dress(core)
	corePad = core

	-- Light thrown UP at the card. An uplight is what separates a pedestal
	-- from a glowing disc: the card picks up a lit lower edge from it.
	local rig = new("Part", {
		Parent = parent, Name = "CoreLightRig",
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = CFrame.new(o.X, top + 0.6, o.Z) * CFrame.Angles(math.rad(90), 0, 0),
		Transparency = 1,
	})
	dress(rig)
	coreLight = new("SpotLight", {
		Parent = rig, Color = C.white, Brightness = 2.4, Range = 70,
		Angle = 42, Face = Enum.NormalId.Front, Shadows = false,
	})

	new("PointLight", {
		Parent = core, Color = tint, Brightness = 0.7, Range = 30, Shadows = false,
	})
end

----------------------------------------------------------------
-- FINS
----------------------------------------------------------------

-- Stands a part on the deck at a given bearing, leaning inward. lookAt, NOT
-- CFrame.Angles(0, -a, 0): the latter does not aim a part's face at the
-- centre. With lookAt, local -Z is inward and local X is tangential, so Size
-- reads (width along the ring, height, thickness) and a negative pitch about
-- local X tips the top toward the card.
local function seat(radius: number, bearing: number, lean: number): CFrame
	local o = M.Origin
	return CFrame.lookAt(
		Vector3.new(o.X + math.cos(bearing) * radius, o.Y, o.Z + math.sin(bearing) * radius),
		Vector3.new(o.X, o.Y, o.Z)) * CFrame.Angles(math.rad(-lean), 0, 0)
end

local function buildWall(parent: Folder)
	table.clear(wallSlots)
	local R, T = M.WallRadius, M.WallThickness
	local span = math.rad(M.WallSpan)
	local step = span / M.WallSegs
	-- 1.03 overlap so neighbouring panels close at the joint instead of showing
	-- a hairline of deck between them.
	local chord = 2 * R * math.tan(step / 2) * 1.03

	for s = 1, M.WallSectors do
		local H = M.WallHeights[s] or M.WallHeight
		local mid = (s / M.WallSectors) * math.pi * 2
		local first = mid - span / 2

		for k = 0, M.WallSegs - 1 do
			local a = first + step * (k + 0.5)
			local foot = seat(R, a, M.WallLean)

			local panel = new("Part", {
				Parent = parent, Name = string.format("Wall%d_%d", s, k),
				Size = Vector3.new(chord, H, T),
				CFrame = foot * CFrame.new(0, H * 0.5, 0),
				Color = C.hull,
				Material = Enum.Material.Metal,
				Reflectance = 0.18,
			})
			dress(panel)

			-- A recessed slot on the INNER face. Every slot is registered so the
			-- animation can run a light around the whole ring.
			local slot = new("Part", {
				Parent = parent, Name = string.format("WallSlot%d_%d", s, k),
				Size = Vector3.new(chord * 0.2, H * 0.66, 0.34),
				CFrame = foot * CFrame.new(0, H * 0.46, -(T * 0.5 + 0.17)),
				Color = C.cyan,
				Material = Enum.Material.Neon,
				Transparency = 0.6,
			})
			dress(slot)
			table.insert(wallSlots, { part = slot, bearing = a })

			-- Top cap, proud of the panel, so the ring keeps a hard silhouette
			-- against the dome instead of fading out at its top edge.
			local cap = new("Part", {
				Parent = parent, Name = string.format("WallCap%d_%d", s, k),
				Size = Vector3.new(chord, 1.1, T * 1.4),
				CFrame = foot * CFrame.new(0, H - 0.2, 0),
				Color = C.steel,
				Material = Enum.Material.Metal,
				Reflectance = 0.3,
			})
			dress(cap)

			-- Crown light sitting ON the cap, so the top edge glows from OUTSIDE
			-- the ring too. The first cut put every light on the inner face, which
			-- left the approach looking at a blank dark band.
			local crown = new("Part", {
				Parent = parent, Name = string.format("WallCrown%d_%d", s, k),
				Size = Vector3.new(chord, 0.3, T * 1.45),
				CFrame = foot * CFrame.new(0, H + 0.4, 0),
				Color = C.white,
				Material = Enum.Material.Neon,
				Transparency = 0.25,
			})
			dress(crown)

			-- A band around the OUTSIDE, two-thirds up.
			local band = new("Part", {
				Parent = parent, Name = string.format("WallBand%d_%d", s, k),
				Size = Vector3.new(chord, 0.4, 0.26),
				CFrame = foot * CFrame.new(0, H * 0.68, T * 0.5 + 0.13),
				Color = C.cyan,
				Material = Enum.Material.Neon,
				Transparency = 0.45,
			})
			dress(band)

			-- Ribs on the outer face, every other panel, so the ring has relief
			-- from the approach rather than reading as a smooth drum.
			if k % 2 == 0 then
				local rib = new("Part", {
					Parent = parent, Name = string.format("WallRib%d_%d", s, k),
					Size = Vector3.new(chord * 0.3, H * 0.92, 0.7),
					CFrame = foot * CFrame.new(0, H * 0.46, T * 0.5 + 0.35),
					Color = C.steel,
					Material = Enum.Material.Metal,
					Reflectance = 0.28,
				})
				dress(rib)
			end

			-- Footing strip where the ring meets the deck, both faces.
			local footing = new("Part", {
				Parent = parent, Name = string.format("WallFoot%d_%d", s, k),
				Size = Vector3.new(chord, 0.9, T * 1.6),
				CFrame = foot * CFrame.new(0, 0.45, 0),
				Color = C.steel,
				Material = Enum.Material.Metal,
				Reflectance = 0.22,
			})
			dress(footing)
		end

		-- Pilasters closing each end of the sector, so the doorways read as cut
		-- openings rather than as the wall simply stopping. They stand a little
		-- proud of their own sector's height, which is what makes the varied
		-- skyline read as deliberate rather than as an unfinished wall.
		for _, edge in ipairs({ first, first + span }) do
			local foot = seat(R, edge, M.WallLean)
			local jamb = new("Part", {
				Parent = parent, Name = "WallJamb",
				Size = Vector3.new(2, H + 2.6, T * 1.7),
				CFrame = foot * CFrame.new(0, (H + 2.6) * 0.5, 0),
				Color = C.steel,
				Material = Enum.Material.Metal,
				Reflectance = 0.26,
			})
			dress(jamb)

			-- The jamb's own light, readable from both sides of the doorway.
			local edgeLight = new("Part", {
				Parent = parent, Name = "WallJambLight",
				Size = Vector3.new(0.45, H * 0.86, T * 1.78),
				CFrame = foot * CFrame.new(0, H * 0.5, 0),
				Color = C.white,
				Material = Enum.Material.Neon,
				Transparency = 0.35,
			})
			dress(edgeLight)
		end
	end
end


----------------------------------------------------------------
-- HALO
----------------------------------------------------------------

local function buildHalo(parent: Folder, tint: Color3)
	local centre = Vector3.new(M.Origin.X, M.CardCentreY, M.Origin.Z - M.HaloBack)

	-- The outer ring: four white arcs. "face" axis, so it stands in the card's
	-- plane rather than lying around it.
	local hub = buildBand(parent, "HaloOuter", centre, "face",
		M.HaloRadius, 0.34, 0.9, C.white, Enum.Material.Neon, 0.22, 0,
		M.HaloSegments, M.HaloArcPeriod, M.HaloArcOn)
	haloHub = hub

	-- The inner ring carries the rarity tint, offset half a slot so its arcs
	-- sit in the outer ring's gaps.
	local inner = buildBand(parent, "HaloInner", centre, "face",
		M.HaloInnerRadius, 0.22, 0.7, tint, Enum.Material.Neon, 0.45, 0,
		M.HaloSegments, M.HaloArcPeriod, M.HaloArcOn)
	inner.CFrame = CFrame.new(centre)
		* CFrame.Angles(0, 0, math.pi * 2 / M.HaloSegments * (M.HaloArcPeriod * 0.5))
	inner.Parent = parent
	-- Re-seat the welded children at the rotated hub.
	for _, child in ipairs(inner:GetChildren()) do
		if child:IsA("BasePart") then child.Anchored = false end
	end
end

----------------------------------------------------------------
-- BEAM
----------------------------------------------------------------

-- The crystal cluster. ONE shard mesh and ONE rock mesh, assembled here from
-- tinted clones rather than exported as a single model - a MeshPart carries a
-- single Color, so a one-mesh cluster could only ever be one colour, and the
-- whole point of the reference is that every point is a different one.
--
-- Each crystal is two parts: a Glass shell for the facets and refraction, and
-- a smaller Neon core nested inside it for the light. Neon alone is flat and
-- unfaceted; Glass alone is dead. The pair is what reads as lit from within.
--
-- LAYOUT is shared with the Blender file that authored the meshes:
--   gx, gy  ground position, in cluster-radius units
--   h, d    height and diameter, as fractions of the cluster's size
--   lean    degrees tipped AWAY from the centre, so the fan opens outward
--   yaw     spin about the crystal's own axis, so no two catch light alike
local CLUSTER = {
	{ gx =  0.00, gy =  0.03, h = 1.00, d = 0.175, lean =  4, yaw =  12,
	  colour = Color3.fromRGB(255, 120, 16) },
	{ gx = -0.15, gy = -0.02, h = 0.74, d = 0.152, lean = 16, yaw =  28,
	  colour = Color3.fromRGB(255,  41,  51) },
	{ gx = -0.29, gy =  0.06, h = 0.56, d = 0.132, lean = 27, yaw =  44,
	  colour = Color3.fromRGB(224,  51, 214) },
	{ gx =  0.16, gy = -0.04, h = 0.83, d = 0.158, lean = 14, yaw = -22,
	  colour = Color3.fromRGB( 41, 217, 255) },
	{ gx =  0.31, gy =  0.04, h = 0.60, d = 0.134, lean = 25, yaw = -38,
	  colour = Color3.fromRGB( 66, 112, 255) },
	{ gx = -0.08, gy =  0.18, h = 0.65, d = 0.142, lean =  9, yaw =  18,
	  colour = Color3.fromRGB( 66, 247, 133) },
	{ gx =  0.11, gy =  0.19, h = 0.50, d = 0.126, lean = 11, yaw = -14,
	  colour = Color3.fromRGB(168,  84, 255) },
	{ gx = -0.37, gy = -0.10, h = 0.34, d = 0.106, lean = 36, yaw =  58,
	  colour = Color3.fromRGB(209,  61, 255) },
	{ gx =  0.40, gy = -0.08, h = 0.31, d = 0.100, lean = 34, yaw = -52,
	  colour = Color3.fromRGB( 51, 242, 219) },
}

-- Chips of dead rock crystal around the bed, in the reference's grey. These
-- are what make the glowing ones look like they GREW there.
local CHIPS = {
	{ gx = -0.52, gy =  0.10, h = 0.16, d = 0.075, lean = 48, yaw =  20 },
	{ gx =  0.54, gy =  0.14, h = 0.14, d = 0.070, lean = 52, yaw = -30 },
	{ gx = -0.30, gy = -0.34, h = 0.13, d = 0.068, lean = 58, yaw =  70 },
	{ gx =  0.26, gy = -0.36, h = 0.15, d = 0.072, lean = 55, yaw = -65 },
	{ gx =  0.02, gy = -0.44, h = 0.12, d = 0.062, lean = 62, yaw =  15 },
	{ gx = -0.14, gy =  0.40, h = 0.17, d = 0.078, lean = 40, yaw = -20 },
	{ gx =  0.36, gy =  0.34, h = 0.12, d = 0.064, lean = 50, yaw =  35 },
}

-- Stands a shard at a ground offset, tipped away from the cluster's centre.
-- Rotating about Y by -theta aims local +X outward; rotating about Z by -lean
-- then tips the top that way. Doing it in the other order tips it toward a
-- fixed world axis instead of outward, and the fan collapses.
local function shardCFrame(base: CFrame, gx: number, gy: number,
	spread: number, lean: number, yaw: number, height: number): CFrame
	local theta = math.atan2(gy, gx)
	return base
		* CFrame.new(gx * spread, 0, gy * spread)
		* CFrame.Angles(0, -theta, 0)
		* CFrame.Angles(0, 0, math.rad(-lean))
		* CFrame.Angles(0, math.rad(yaw), 0)
		* CFrame.new(0, height * 0.5, 0)
end

local function buildCrystal(parent: Folder, tint: Color3)
	local o = M.Origin
	local meshes = ReplicatedStorage.Shared:FindFirstChild("MonumentMeshes")
	local shardMesh = meshes and meshes:FindFirstChild("Shard")
	local rockMesh = meshes and meshes:FindFirstChild("Rock")
	if not (shardMesh and shardMesh:IsA("BasePart")) then
		warn("[Monument] Shard mesh missing from MonumentMeshes")
		return
	end

	local spread, tall = M.ClusterSpread, M.ClusterHeight
	-- Sits ON the pedestal, not floating above it. The reference cluster grows
	-- out of rock, and a floating one would fight the card for "the thing in
	-- the air".
	local base = CFrame.new(o.X, o.Y + M.PedestalHeight + 0.72, o.Z)

	local model = new("Model", { Parent = parent, Name = "CrystalCluster" })
	crystalModel = model
	table.clear(crystalCores)

	if rockMesh and rockMesh:IsA("BasePart") then
		local bed = rockMesh:Clone()
		bed.Name = "CrystalBed"
		-- The rock is authored ~1.0 wide and 0.36 tall, so scaling X and Z by
		-- the spread and letting Y follow would give a 9-stud boulder. Squash it.
		bed.Size = Vector3.new(spread * 2.3, 5.5, spread * 2.3)
		bed.CFrame = base * CFrame.new(0, tall * 0.09, 0)
		bed.Color = Color3.fromRGB(28, 34, 48)
		bed.Material = Enum.Material.Slate
		bed.Reflectance = 0.08
		bed.Parent = model
		dress(bed)
	end

	for index, c in ipairs(CLUSTER) do
		local h, d = c.h * tall, c.d * spread * M.ClusterGirth
		local cf = shardCFrame(base, c.gx, c.gy, spread, c.lean, c.yaw, h)

		local shell = shardMesh:Clone()
		shell.Name = "Shard" .. index
		shell.Size = Vector3.new(d, h, d)
		shell.CFrame = cf
		shell.Color = c.colour
		shell.Material = Enum.Material.Glass
		-- Every point of transparency here is a point of colour lost off the
		-- core behind it, so the shell is kept only as thick as it needs to be
		-- to read as faceted glass.
		shell.Transparency = 0.2
		shell.Reflectance = 0.3
		shell.Parent = model
		dress(shell)

		-- The core is the same mesh at half the diameter, so it is always
		-- inside the shell whatever the shell's proportions - no hand fitting.
		local core = shardMesh:Clone()
		core.Name = "Core" .. index
		core.Size = Vector3.new(d * 0.58, h * 0.88, d * 0.58)
		core.CFrame = cf
		-- Only slightly lifted toward white. At 0.34 the whole cluster came out
		-- pastel: Neon already renders at full brightness, so washing the colour
		-- out first just throws away the saturation the reference lives on.
		-- 0.15 keeps the hue and still blooms hot through the glass.
		core.Color = c.colour:Lerp(Color3.new(1, 1, 1), 0.15)
		core.Material = Enum.Material.Neon
		core.Transparency = 0.08
		core.Reflectance = 0
		core.Parent = model
		dress(core)
		table.insert(crystalCores, { part = core, phase = index * 0.9 })

		-- Six of the nine carry a light, scaled by how tall the point is. Nine
		-- coloured PointLights stacked in one spot is where Roblox starts
		-- dropping them per-frame, and the two smallest add nothing at range.
		-- This is the bit that actually paints the lobby: red, amber, cyan,
		-- green and blue spilling onto navy plating and the card's underside.
		if c.h >= 0.5 then
			new("PointLight", {
				Parent = core, Color = c.colour,
				Brightness = 2.2 + c.h * 1.6,
				Range = 26 + c.h * 16,
				Shadows = false,
			})
		end
	end

	for index, c in ipairs(CHIPS) do
		local h, d = c.h * tall, c.d * spread * M.ClusterGirth
		local chip = shardMesh:Clone()
		chip.Name = "Chip" .. index
		chip.Size = Vector3.new(d, h, d)
		chip.CFrame = shardCFrame(base, c.gx, c.gy, spread, c.lean, c.yaw, h)
		chip.Color = Color3.fromRGB(46, 54, 72)
		chip.Material = Enum.Material.Slate
		chip.Reflectance = 0.14
		chip.Parent = model
		dress(chip)
	end

	-- Sparks lifting off the cluster, tinted by whichever point they leave.
	-- ColorSequence runs the spectrum, so the motes above it are rainbow too
	-- rather than one averaged colour.
	local spark = new("Part", {
		Parent = model, Name = "SparkAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = base * CFrame.new(0, tall * 0.4, 0),
		Transparency = 1,
	})
	dress(spark)
	new("ParticleEmitter", {
		Parent = new("Attachment", { Parent = spark }),
		Name = "Sparks",
		Texture = EncounterDefinitions.Assets.Dot,
		Rate = 26,
		Lifetime = NumberRange.new(3.5, 7),
		Speed = NumberRange.new(1.5, 3.5),
		Drag = 1.6,
		Acceleration = Vector3.new(0, 1.4, 0),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 120, 16)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 41, 51)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(66, 247, 133)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(41, 217, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(209, 61, 255)),
		}),
		LightEmission = 1, LightInfluence = 0, ZOffset = 0.5,
	})

	model.WorldPivot = base
end

----------------------------------------------------------------
-- ORBITS
----------------------------------------------------------------

local function buildOrbits(parent: Folder)
	table.clear(orbits)
	table.clear(fragments)
	local o = M.Origin

	for index, spec in ipairs(M.Orbits) do
		local centre = Vector3.new(o.X, M.CardCentreY + spec.yOffset, o.Z)
		local hub = buildBand(parent, "Orbit" .. index, centre, "flat",
			spec.radius, spec.thickness, spec.depth, C.silver,
			Enum.Material.Metal, 0.35, 0.4, M.OrbitSegments)
		table.insert(orbits, {
			hub = hub, tilt = spec.tilt, speed = spec.speed, yOffset = spec.yOffset,
		})

		-- Fragments travelling along the path. These carry the motion, which
		-- lets the band itself stay dim and thin.
		for f = 1, spec.fragments do
			local frag = new("Part", {
				Parent = parent, Name = string.format("Frag%d_%d", index, f),
				Size = Vector3.new(0.9, 0.9, 0.9),
				CFrame = CFrame.new(centre),
				Color = C.white,
				Material = Enum.Material.Neon,
				Transparency = 0.08,
			})
			dress(frag)
			table.insert(fragments, {
				part = frag, hub = hub, radius = spec.radius,
				angle = (f / spec.fragments) * math.pi * 2, drift = spec.drift,
			})
		end
	end
end

----------------------------------------------------------------
-- SHARDS
----------------------------------------------------------------

local function buildShards(parent: Folder, tint: Color3)
	table.clear(shards)
	local meshes = ReplicatedStorage.Shared:FindFirstChild("MonumentMeshes")
	local template = meshes and meshes:FindFirstChild("Crystal")
	if not (template and template:IsA("BasePart")) then return end

	-- Five large shards at three heights, rather than a belt of small ones.
	-- Fewer and bigger reads as deliberate; many and small reads as debris.
	local heights = { 14, -9, 20, -16, 5 }
	local radii = { 38, 33, 42, 36, 45 }
	for index = 1, M.ShardCount do
		local a = (index / M.ShardCount) * math.pi * 2
		local scale = M.ShardScale * (0.82 + (index % 3) * 0.14)
		local shard = template:Clone()
		shard.Name = "Shard" .. index
		shard.Size = template.Size * scale
		shard.Color = C.hull
		shard.Material = Enum.Material.Glass
		shard.Transparency = 0.45
		shard.Reflectance = 0.35
		shard.CFrame = CFrame.new(M.Origin.X, M.CardCentreY, M.Origin.Z)
		shard.Parent = parent
		dress(shard)

		-- A thin inner glow: a smaller neon copy nested inside the glass, so
		-- the shard lights from within instead of being a tinted lump.
		local core = template:Clone()
		core.Name = "ShardCore"
		core.Size = template.Size * scale * 0.42
		core.Color = tint
		core.Material = Enum.Material.Neon
		core.Transparency = 0.35
		core.Reflectance = 0
		core.CFrame = shard.CFrame
		core.Parent = shard
		dress(core)
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1, weld.Parent = shard, core, shard
		core.Anchored = false

		table.insert(shards, {
			part = shard,
			angle = a,
			radius = radii[index],
			height = M.CardCentreY + heights[index],
			phase = a * 1.7,
		})
	end
end

----------------------------------------------------------------
-- CARD
----------------------------------------------------------------

local function buildCard(parent: Folder, cardId: string, tint: Color3)
	local aspect = EncounterDefinitions.Card.Aspect
	local h = M.CardHeight
	local w = h / aspect
	cardWidth = w
	local centre = CFrame.new(M.Origin.X, M.CardCentreY, M.Origin.Z)

	-- The rarity rim. A neon slab just larger than the card, right behind it:
	-- the card hides the middle, so only an edge shows. TINTED, not saturated -
	-- a full-strength band colour here is what read as a pink neon tube.
	local rim = new("Part", {
		Parent = parent, Name = "CardRim",
		Size = Vector3.new(w + 0.8, h + 0.8, M.CardThickness * 0.5),
		CFrame = centre,
		Color = tint,
		Material = Enum.Material.Neon,
		Transparency = 0.38,
	})
	dress(rim)
	cardRim = rim

	local body = new("Part", {
		Parent = parent, Name = "Card",
		Size = Vector3.new(w, h, M.CardThickness),
		CFrame = centre,
		Color = INK,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.04,
	})
	dress(body)
	body.CastShadow = true
	cardBody = body

	-- The sweep. Travels across the FRONT of the card, which is its -Z.
	local sweep = new("Part", {
		Parent = parent, Name = "Sweep",
		Size = Vector3.new(w * 0.16, h * 1.02, 0.06),
		CFrame = centre,
		Color = C.white,
		Material = Enum.Material.Neon,
		Transparency = 1,
	})
	dress(sweep)
	sweepBar = sweep

	local faceW = M.FaceWidth
	local faceH = math.floor(faceW * aspect)

	local face = new("SurfaceGui", {
		Parent = body, Name = "Face",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(faceW, faceH),
		LightInfluence = 0,
		Brightness = 1.2,
		MaxDistance = 900,
		ZOffset = 0.02,
	})
	local card = CardRenderer.create(face, faceW)
	CardRenderer.update(card, { cardId = cardId, variant = "Standard", level = 0 })
	-- A monument is not an owned copy, so a level pill reading "0" is noise.
	if card.levelPill then card.levelPill.Visible = false end

	local back = new("SurfaceGui", {
		Parent = body, Name = "Back",
		Face = Enum.NormalId.Back,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(faceW, faceH),
		LightInfluence = 0,
		Brightness = 1.6,
		MaxDistance = 900,
		ZOffset = 0.02,
	})
	new("ImageLabel", {
		Parent = back,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		Image = EncounterDefinitions.Assets.CardBack,
		ScaleType = Enum.ScaleType.Crop,
	})

	-- KEY LIGHT from above, paired with the pedestal's uplight. Two sources
	-- with the card between them is what gives it a lit top and bottom edge
	-- and stops it reading as a flat decal hanging in the air.
	local rig = new("Part", {
		Parent = parent, Name = "KeyLightRig",
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = CFrame.new(M.Origin.X, M.CardCentreY + h * 0.72, M.Origin.Z)
			* CFrame.Angles(math.rad(-90), 0, 0),
		Transparency = 1,
	})
	dress(rig)
	keyLight = new("SpotLight", {
		Parent = rig, Color = C.white, Brightness = 2.6, Range = 95,
		Angle = 52, Face = Enum.NormalId.Front, Shadows = true,
	})
end

----------------------------------------------------------------
-- PARTICLES
----------------------------------------------------------------

local function emitterAt(parent: Folder, name: string, y: number, props: { [string]: any })
	local anchor = new("Part", {
		Parent = parent, Name = name .. "Anchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(M.Origin.X, y, M.Origin.Z),
		Transparency = 1,
	})
	dress(anchor)
	local att = new("Attachment", { Parent = anchor })
	props.Parent = att
	props.Name = name
	new("ParticleEmitter", props)
end

local function buildParticles(parent: Folder)
	local dot = EncounterDefinitions.Assets.Dot

	-- Two layers only. The earlier build had three and they added up to haze.
	emitterAt(parent, "Embers", M.Origin.Y + M.PedestalHeight + 0.9, {
		Texture = dot, Rate = 14,
		Lifetime = NumberRange.new(8, 14),
		Speed = NumberRange.new(0.8, 1.8),
		Drag = 2,
		Acceleration = Vector3.new(0, 1, 0),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Cylinder,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.26),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(C.white),
		LightEmission = 1, LightInfluence = 0, ZOffset = 0.5,
	})

	emitterAt(parent, "Motes", M.CardCentreY, {
		Texture = dot, Rate = 6,
		Lifetime = NumberRange.new(9, 15),
		Speed = NumberRange.new(0.3, 1),
		Drag = 0.8,
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.4, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(C.violet),
		LightEmission = 1, LightInfluence = 0, ZOffset = 0.5,
	})
end

----------------------------------------------------------------
-- PLAQUE
----------------------------------------------------------------

local function buildPlaque(parent: Folder, cardId: string, tint: Color3)
	local def = CardDefinitions.get(cardId)
	local top = M.Origin.Y + M.PedestalHeight + 0.6

	local anchor = new("Part", {
		Parent = parent, Name = "PlaqueAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(M.Origin.X, top + 5.5, M.Origin.Z + 6),
		Transparency = 1,
	})
	dress(anchor)
	plaqueAnchor = anchor

	local billboard = new("BillboardGui", {
		Parent = anchor, Name = "Plaque",
		Size = UDim2.fromOffset(420, 124),
		AlwaysOnTop = false,
		-- Roblox culls at 40; the fade below already reached zero at 30, so the
		-- cull is only a backstop.
		MaxDistance = 40,
		LightInfluence = 0,
		Enabled = false,
	})
	plaqueGui = billboard

	local panel = new("Frame", {
		Parent = billboard, Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	})
	new("UICorner", { Parent = panel, CornerRadius = UDim.new(0, 8) })
	new("UIStroke", { Parent = panel, Color = C.cyan, Thickness = 1.5, Transparency = 0.3 })
	plaquePanel = panel
	plaqueScale = new("UIScale", { Parent = panel, Scale = 0.94 })

	-- Museum-placard hierarchy: category, subject, detail. Leading with the
	-- name buries the one line that explains WHAT you are looking at.
	new("TextLabel", {
		Parent = panel, Name = "Eyebrow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "RAREST CARD YOU CAN PULL",
		FontFace = Theme.font(),
		TextSize = 15,
		TextColor3 = C.cyan,
	})

	new("TextLabel", {
		Parent = panel, Name = "CardName",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 46),
		Text = def and def.name or cardId,
		FontFace = Theme.font(),
		TextSize = 38,
		TextColor3 = C.white,
	})

	-- "1 IN 100,000", not "1 / 100,000". Players say "one in", and a slash
	-- reads as a fraction at a glance.
	local odds = def and RarityFormat.denominator(def.baseRarity) or ""
	odds = (odds:gsub("%s*/%s*", " IN "))
	new("TextLabel", {
		Parent = panel, Name = "Odds",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 82),
		Size = UDim2.new(1, 0, 0, 30),
		Text = odds:upper(),
		FontFace = Theme.font(),
		TextSize = 24,
		TextColor3 = tint,
	})
end

----------------------------------------------------------------
-- ANIMATION
----------------------------------------------------------------

local function animate()
	local t = os.clock() - clock0
	local o = M.Origin

	local bob = math.sin(t * math.pi * 2 / M.BobPeriod) * M.BobHeight
	local y = M.CardCentreY + bob

	-- One shared beat, read by everything below. This went missing when the
	-- pulse ring was cut, and the crystal cores were left multiplying by a nil
	-- upvalue once per frame per core.
	local beat = (t % M.PulsePeriod) / M.PulseTravel
	local flare = beat <= 1 and (1 - smoothstep(beat)) or 0

	if cardBody then
		local yaw = math.rad(M.HomeYaw) + math.rad(M.SpinSpeed) * t
		local tilt = math.rad(M.TiltAngle) * math.sin(t * math.pi * 2 / M.TiltPeriod)
		local cf = CFrame.new(o.X, y, o.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0)
		cardBody.CFrame = cf

		if cardRim then
			-- A hair behind the card, so the rim reads as light bleeding out
			-- from under it rather than as a second slab.
			cardRim.CFrame = cf * CFrame.new(0, 0, 0.14)
			cardRim.Transparency = 0.38 - 0.04 * math.sin(t * 0.9) - 0.1 * flare
		end

		if sweepBar then
			-- The card's FRONT is its -Z, so the sweep rides at negative Z.
			local phase = t % M.SweepPeriod
			if phase < M.SweepTravel then
				local p = phase / M.SweepTravel
				local x = (p * 2 - 1) * (cardWidth * 0.6)
				sweepBar.CFrame = cf * CFrame.new(x, 0, -(M.CardThickness * 0.5 + 0.08))
				-- Brightest mid-pass, fading at both edges.
				sweepBar.Transparency = 0.45 + 0.55 * math.abs(p * 2 - 1)
			else
				sweepBar.Transparency = 1
			end
		end
	end

	if haloHub then
		haloHub.CFrame = CFrame.new(o.X, y, o.Z - M.HaloBack)
			* CFrame.Angles(0, 0, math.rad(M.HaloSpin) * t)
	end

	if crystalModel then
		-- The whole cluster turns as one, slowly and counter to the card. It
		-- does NOT bob: it is standing on rock, and floating rock reads as a
		-- mistake rather than as magic.
		crystalModel:PivotTo(CFrame.new(o.X, M.Origin.Y + M.PedestalHeight + 0.72, o.Z)
			* CFrame.Angles(0, math.rad(M.ClusterSpin) * t, 0))
		for _, core in ipairs(crystalCores) do
			-- Each core breathes on its own offset, so the cluster shimmers
			-- instead of pulsing as one slab of light, and they all lift
			-- together on the monument's beat.
			core.part.Transparency = 0.12 - 0.08 * flare
				+ 0.06 * math.sin(t * 0.8 + core.phase)
		end
	end
	if corePad then
		corePad.Transparency = 0.06 + 0.04 * math.sin(t * 1.1) - 0.05 * flare
	end
	if keyLight then keyLight.Brightness = 2.6 + flare * 0.8 end

	for _, orbit in ipairs(orbits) do
		-- Driven from elapsed time, never a per-frame accumulator: this runs
		-- inside RenderStepped, so anything that yields here stalls the render
		-- step for every frame after it.
		orbit.hub.CFrame = CFrame.new(o.X, M.CardCentreY + orbit.yOffset + bob * 0.4, o.Z)
			* CFrame.Angles(0, math.rad(orbit.speed) * t, 0)
			* CFrame.Angles(math.rad(orbit.tilt), 0, 0)
	end

	for _, frag in ipairs(fragments) do
		-- Travels ALONG the band, on top of the band's own rotation.
		local a = frag.angle + frag.drift * t
		frag.part.CFrame = frag.hub.CFrame * CFrame.Angles(0, a, 0)
			* CFrame.new(frag.radius, 0, 0)
	end

	for _, s in ipairs(shards) do
		local a = s.angle + math.rad(M.ShardSpeed) * t
		local sy = s.height + math.sin(t * 0.4 + s.phase) * 2.4
		s.part.CFrame = CFrame.new(
			o.X + math.cos(a) * s.radius, sy, o.Z + math.sin(a) * s.radius
		) * CFrame.Angles(
			math.sin(t * 0.25 + s.phase) * 0.3,
			a * 0.8 + t * 0.12,
			math.rad(18) + math.sin(t * 0.3 + s.phase) * 0.2
		)
	end

	-- A light chasing round the containment ring. One transparency write per
	-- slot and no CFrames: the cheapest way to put motion on forty-eight
	-- panels, and it is what stops the wall reading as scenery.
	local chase = (t * M.ChaseSpeed % 1) * math.pi * 2
	for _, slot in ipairs(wallSlots) do
		-- Angular distance from the chase head, wrapped to [0, pi].
		local d = math.abs((slot.bearing - chase + math.pi) % (math.pi * 2) - math.pi)
		slot.part.Transparency = 0.6 - 0.48 * (1 - smoothstep(d / 0.9))
	end
	for _, runner in ipairs(runners) do
		-- Travels INWARD, toward the card.
		local p = ((t / M.RunnerPeriod) + runner.phase) % 1
		local r = M.PanelOuter - (M.PanelOuter - M.PanelInner + 4) * p
		runner.part.CFrame = CFrame.new(
			o.X + math.cos(runner.angle) * r, o.Y + 0.16, o.Z + math.sin(runner.angle) * r
		) * CFrame.Angles(0, -runner.angle, 0)
		-- Fades in at the rim and out as it arrives, so nothing pops.
		runner.part.Transparency = 0.25 + 0.75 * math.abs(p * 2 - 1)
	end
end

----------------------------------------------------------------
-- PROXIMITY TEXT
----------------------------------------------------------------

local function updatePlaqueFade(dt: number)
	-- 15 Hz. Indistinguishable from per-frame for a fade, and a twentieth of
	-- the cost - this runs for every player in the lobby, forever.
	fadeAccumulator += dt
	if fadeAccumulator < 1 / 15 then return end
	fadeAccumulator = 0

	local billboard, panel, anchor = plaqueGui, plaquePanel, plaqueAnchor
	if not (billboard and panel and anchor) then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local target = 0
	if root and root:IsA("BasePart") then
		-- Measured to the CHARACTER, not the camera. Players zoom out, and text
		-- that vanishes when you scroll the mouse wheel feels broken.
		local d = (root.Position - anchor.Position).Magnitude
		target = smoothstep((M.FadeOut - d) / (M.FadeOut - M.FadeIn))
	end

	-- Eased toward the target rather than mapped straight off distance. This is
	-- also what stops flicker at the boundary: standing exactly on the edge,
	-- the target oscillates but alpha only drifts.
	textAlpha += (target - textAlpha) * M.FadeRate

	local visible = textAlpha > 0.01
	-- A fully transparent BillboardGui still costs layout and draw every frame.
	billboard.Enabled = visible
	if not visible then return end

	local fade = 1 - textAlpha
	panel.BackgroundTransparency = 0.12 + fade * 0.88
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Transparency = 0.3 + fade * 0.7 end
	for _, child in ipairs(panel:GetChildren()) do
		if child:IsA("TextLabel") then child.TextTransparency = fade end
	end
	-- Arrives rather than appears.
	if plaqueScale then plaqueScale.Scale = 0.94 + textAlpha * 0.06 end
end

----------------------------------------------------------------
-- LIFECYCLE
----------------------------------------------------------------

local function teardown()
	if renderConn then renderConn:Disconnect(); renderConn = nil end
	if fadeConn then fadeConn:Disconnect(); fadeConn = nil end
	if folder then folder:Destroy(); folder = nil end
	cardBody, cardRim, sweepBar, haloHub = nil, nil, nil, nil
	crystalModel = nil
	table.clear(crystalCores)
	keyLight, coreLight, corePad = nil, nil, nil
	plaqueGui, plaquePanel, plaqueScale, plaqueAnchor = nil, nil, nil, nil
	textAlpha = 0
	table.clear(orbits)
	table.clear(fragments)
	table.clear(runners)
	table.clear(shards)
	table.clear(wallSlots)
end

local function build(cardId: string)
	teardown()
	shownCardId = cardId

	local def = CardDefinitions.get(cardId)
	local band = def and RarityBands.forDenominator(def.baseRarity).color
		or VariantConfig.get("Standard").color
	-- Blended toward white. The band still identifies the rarity, but as a
	-- TINT - at full saturation on a 27-stud ring it reads as a neon tube and
	-- takes the top of the hierarchy away from the card.
	local tint = band:Lerp(Color3.new(1, 1, 1), 0.55)

	folder = new("Folder", { Parent = Workspace, Name = "LobbyMonument" })
	local f = folder :: Folder

	buildFloor(f)
	buildPedestal(f, tint)
	buildWall(f)
	buildHalo(f, tint)
	buildCard(f, cardId, tint)
	buildCrystal(f, tint)
	buildOrbits(f)
	buildShards(f, tint)
	buildParticles(f)
	buildPlaque(f, cardId, tint)

	renderConn = RunService.RenderStepped:Connect(animate)
	fadeConn = RunService.Heartbeat:Connect(updatePlaqueFade)
	log("showing %s", cardId)
end

local function refresh(profile: any)
	local clears = (type(profile) == "table" and type(profile.encounters) == "table")
		and profile.encounters or {}
	local best = bestPullableCard(clears)
	if best and best ~= shownCardId then
		build(best)
	end
end

function MonumentController:Init()
	-- Built from whatever is known now so the plaza is never empty, then
	-- corrected the moment the real profile lands.
	task.defer(function()
		if not shownCardId then
			local ok, err = pcall(function() refresh(nil) end)
			if not ok then warn("[Monument] initial build failed: " .. tostring(err)) end
		end
	end)

	Remotes.ProfileSync.OnClientEvent:Connect(function(profile)
		local ok, err = pcall(function() refresh(profile) end)
		if not ok then warn("[Monument] rebuild failed: " .. tostring(err)) end
	end)
end

function MonumentController:Start()
	log("online")
end

return MonumentController
