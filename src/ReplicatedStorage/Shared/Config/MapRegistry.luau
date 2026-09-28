--!strict
-- Every map in the game, in ONE table.
--
-- ── How maps are kept apart ────────────────────────────────────────────
-- All maps live in a single place, parked on a wide grid so that no map is
-- ever within sight of another. With StreamingEnabled a map 10,000 studs away
-- is not merely hidden - it is never sent to the client at all, so it costs
-- the player nothing in memory or draw calls.
--
-- This beats hiding maps behind fog (they still replicate and still render)
-- and beats separate places (a loading screen on every trip, and players split
-- across servers so a friend in the lobby is unreachable).
--
-- ── DO NOT set ModelStreamingMode = Persistent on map scenery ──────────
-- Persistent means "replicate to every player forever, wherever they are",
-- which defeats the entire grid: Arlong Park's island was briefly Persistent
-- and its mountains showed on the horizon from the lobby, 10,000 studs away.
--
-- The problem it was trying to solve is real, though. Under Default streaming
-- each part is sent independently, so standing at the south edge of the park
-- left the far northern mountains (~2,000 studs off) unstreamed and punched a
-- hole in the skyline. The fix is Atomic, not Persistent: a large backdrop
-- model streams in and out as ONE unit, so being anywhere inside the map
-- brings the whole thing, and being in another map brings none of it.
-- Measured: lobby 0/32 parts, either park edge 32/32.
--
-- ── Adding a map ───────────────────────────────────────────────────────
--   1. Build it inside ONE folder in Workspace, centred on MapRegistry.slot(i, j)
--      for a free (i, j) - use nextFreeSlot() to find one.
--   2. Put a part named `ArrivalPad_<name>` in it. TravelService finds
--      destinations purely by that name, so it needs no code change.
--   3. Add one entry to Maps below.
-- Nothing else in the codebase needs touching.
--
-- ── Why the grid is not centred on the world origin ────────────────────
-- Arlong Park was built at (2000, 0, 0) and carries ~13 million terrain cells.
-- Terrain cannot be relocated cheaply, so the grid is anchored on the park and
-- everything else moves around it. The lobby, being three objects, took slot
-- (-1, 0) instead.

local MapRegistry = {}

-- 10,000 studs between neighbours. Maps here are ~1,600 studs across, so the
-- nearest edge-to-edge gap is over 8,000 - far beyond any streaming radius.
MapRegistry.Spacing = 10000
MapRegistry.GridOrigin = Vector3.new(2000, 0, 0)

-- Roblox terrain is bounded to +-32,000 studs, which caps the usable grid at
-- roughly -3..3 on each axis: 49 slots. Well past what this game will need.
MapRegistry.SlotLimit = 3

function MapRegistry.slot(i: number, j: number): Vector3
	return MapRegistry.GridOrigin
		+ Vector3.new(i * MapRegistry.Spacing, 0, j * MapRegistry.Spacing)
end

-- ── Skies ──────────────────────────────────────────────────────────────
-- A Sky is a single global object, so it is swapped rather than duplicated.
-- Every field a map sets must be set by EVERY map, or travelling from one to
-- another leaves the previous map's stars or sun still showing.
local NEBULA = {
	SkyboxBk = "rbxassetid://129876530632297",
	SkyboxDn = "rbxassetid://108406529909981",
	SkyboxFt = "rbxassetid://104400530594543",
	SkyboxLf = "rbxassetid://73372229972523",
	SkyboxRt = "rbxassetid://87408857415924",
	SkyboxUp = "rbxassetid://137817405681365",
	SkyboxOrientation = Vector3.new(0, 0, 0),
	StarCount = 3000,
	CelestialBodiesShown = false,
}

-- A TRUE six-face cubemap. Each face was generated so that a pixel's colour is
-- a pure function of the 3D direction that pixel points at, which means two
-- faces meeting along a cube edge compute the same colour for the pixels on
-- that edge. Measured across all four horizon joins the worst disagreement is
-- 1/255 per channel - i.e. rounding. The seams cannot exist.
--
-- What was here before was one square image (77445932812310) repeated on all
-- six faces. Neighbouring faces had no reason to agree, so they didn't, and
-- the joins showed as hard diagonal edges across the sky. Yawing the cube 45
-- degrees only moved those edges; it could not remove them.
--
-- Orientation is left at zero: the faces are authored for the unrotated cube,
-- so any yaw here would misalign the horizon against the world.
local ARLONG_SKY = {
	SkyboxFt = "rbxassetid://100891749722619",
	SkyboxBk = "rbxassetid://81707614311924",
	SkyboxLf = "rbxassetid://130673524709630",
	SkyboxRt = "rbxassetid://115979563784926",
	SkyboxUp = "rbxassetid://97019709031667",
	SkyboxDn = "rbxassetid://100626654234150",
	SkyboxOrientation = Vector3.new(0, 0, 0),
	StarCount = 0,
	CelestialBodiesShown = true,
}

-- ── The maps ───────────────────────────────────────────────────────────
export type Map = {
	name: string,
	folder: string,
	slot: { number },
	centre: Vector3,
	radius: number,
	lighting: { [string]: any },
	atmosphere: { [string]: any }?,
	bloom: { [string]: any }?,
	depthOfField: { [string]: any }?,
	sky: { [string]: any }?,
}

MapRegistry.Maps = {
	{
		name = "Lobby",
		folder = "Lobby",
		slot = { -1, 0 },
		centre = MapRegistry.slot(-1, 0),
		radius = 700,
		lighting = {
			ClockTime = 14.2,
			Brightness = 3,
			Ambient = Color3.fromRGB(138, 142, 150),
			OutdoorAmbient = Color3.fromRGB(146, 152, 162),
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 1,
			ExposureCompensation = 0,
			ShadowSoftness = 0.2,
			ColorShift_Top = Color3.fromRGB(0, 0, 0),
			ColorShift_Bottom = Color3.fromRGB(0, 0, 0),
		},
		atmosphere = { Density = 0.28, Haze = 1.6, Glare = 0,
			Color = Color3.fromRGB(210, 226, 244),
			Decay = Color3.fromRGB(160, 190, 220) },
		bloom = { Intensity = 0.28, Size = 20, Threshold = 1.05 },
		depthOfField = {
			Enabled = false,
			FarIntensity = 0.1,
			FocusDistance = 0.05,
			InFocusRadius = 30,
			NearIntensity = 0.75,
		},
		sky = NEBULA,
	},
	{
		name = "ArlongPark",
		folder = "ArlongPark",
		slot = { 0, 0 },
		centre = MapRegistry.slot(0, 0),
		-- Wide enough to cover the jungle and the ridge, not just the plaza:
		-- the old 700 meant the lighting snapped back to lobby values as soon as
		-- a player walked out past the boundary walls.
		radius = 1700,
		lighting = {
			ClockTime = 14.6,
			Brightness = 2.6,
			Ambient = Color3.fromRGB(92, 98, 112),
			OutdoorAmbient = Color3.fromRGB(112, 124, 142),
			EnvironmentDiffuseScale = 0.7,
			EnvironmentSpecularScale = 0.8,
			ExposureCompensation = -0.08,
			ShadowSoftness = 0.14,
			ColorShift_Top = Color3.fromRGB(30, 20, 5),
			ColorShift_Bottom = Color3.fromRGB(8, 12, 20),
		},
		atmosphere = { Density = 0.18, Haze = 1.1, Glare = 0.05,
			Color = Color3.fromRGB(198, 216, 234),
			Decay = Color3.fromRGB(120, 155, 196) },
		bloom = { Intensity = 0.15, Size = 26, Threshold = 1.6 },
		-- The sky is infinitely far away, so a light far blur feathers the
		-- cubemap joins while the entire playable park stays sharp.
		depthOfField = {
			Enabled = true,
			FarIntensity = 0.28,
			FocusDistance = 450,
			InFocusRadius = 500,
			NearIntensity = 0,
		},
		sky = ARLONG_SKY,
	},
}

-- Lowest unused (i, j), scanning outward from the grid origin.
--
-- The keys go through string.format("%d") rather than plain concatenation.
-- `for i = -ring, ring` with ring = 0 yields NEGATIVE zero, and Luau renders
-- that as "-0", so "-0,-0" missed the "0,0" entry and this happily handed back
-- the slot Arlong Park is standing in. "%d" collapses -0 to 0.
local function key(i: number, j: number): string
	return string.format("%d,%d", i, j)
end

function MapRegistry.nextFreeSlot(): (number, number)
	local taken = {}
	for _, m in ipairs(MapRegistry.Maps) do
		taken[key(m.slot[1], m.slot[2])] = true
	end
	local L = MapRegistry.SlotLimit
	for ring = 0, L do
		for i = -ring, ring do
			for j = -ring, ring do
				if math.max(math.abs(i), math.abs(j)) == ring
					and not taken[key(i, j)] then
					-- + 0 normalises -0 to 0 on the way out too
					return i + 0, j + 0
				end
			end
		end
	end
	error("[MapRegistry] no free slot inside the terrain bounds")
end

function MapRegistry.byName(name: string)
	for _, m in ipairs(MapRegistry.Maps) do
		if m.name == name then return m end
	end
	return nil
end

-- Which map a world position falls in, or nil when it is outside them all.
function MapRegistry.at(position: Vector3)
	local best, bestD = nil, math.huge
	for _, m in ipairs(MapRegistry.Maps) do
		local d = (position - m.centre).Magnitude
		if d <= m.radius and d < bestD then
			best, bestD = m, d
		end
	end
	return best
end

return MapRegistry
