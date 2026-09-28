--!strict
-- Builds the physical skill tree: one flat board in the world with real node
-- geometry and real connections, generated entirely from SkillDefinitions.
--
-- BUILT BY THE CLIENT, NOT THE SERVER, and that is not an optimisation - it is
-- required. A node's look depends on THIS player's ranks, so a server-built
-- model replicated to everyone would show every player somebody else's progress.
-- Client-created instances are also untouched by StreamingEnabled, which this
-- place uses, so the board cannot be streamed out from under the camera.
--
-- Nothing here reads input or profile data. It builds geometry and hands back a
-- table; the controller drives it.
--
-- COORDINATES
-- SkillDefinitions.Position is in STUDS on the board plane: X runs right, Y runs
-- "down" the board, which is +Z in the world. Adding a skill at
-- Position = Vector2.new(500, 250) places it there and wires its connections
-- automatically - there is no second layout table to keep in sync.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillDefinitions = require(ReplicatedStorage.Shared.Config.SkillDefinitions)
local SkillNodePart = require(ReplicatedStorage.Shared.World.SkillNodePart)
local SkillLinkBeam = require(ReplicatedStorage.Shared.World.SkillLinkBeam)

local SkillTreeBoard = {}

-- Parked far above the map so the board can never intersect the island, the
-- ocean, or a player. The camera is the only thing that ever goes there.
SkillTreeBoard.ORIGIN = Vector3.new(0, 6000, 0)

SkillTreeBoard.BACKGROUND_IMAGE = "rbxassetid://111282088873223"

local MARGIN = 190

local function toWorld(pos: Vector2): Vector3
	return SkillTreeBoard.ORIGIN + Vector3.new(pos.X, 0, pos.Y)
end

-- The extents of the authored tree, used both to size the backdrop and to give
-- the camera its pan limits. Derived from the definitions, so a skill added far
-- out to one side widens the board and the camera bounds together.
local function measure()
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge

	for _, id in ipairs(SkillDefinitions.Order) do
		local p = SkillDefinitions.Data[id].Position
		minX = math.min(minX, p.X)
		maxX = math.max(maxX, p.X)
		minY = math.min(minY, p.Y)
		maxY = math.max(maxY, p.Y)
	end

	if minX == math.huge then
		minX, maxX, minY, maxY = 0, 0, 0, 0
	end

	return {
		minX = minX - MARGIN, maxX = maxX + MARGIN,
		minY = minY - MARGIN, maxY = maxY + MARGIN,
		centre = Vector2.new((minX + maxX) / 2, (minY + maxY) / 2),
		width = (maxX - minX) + MARGIN * 2,
		depth = (maxY - minY) + MARGIN * 2,
	}
end

SkillTreeBoard.measure = measure

function SkillTreeBoard.build()
	local bounds = measure()

	local world = Instance.new("Model")
	world.Name = "SkillTreeWorld"

	----------------------------------------------------------------
	-- BACKGROUND
	----------------------------------------------------------------

	-- TILED, because A SINGLE PART CANNOT EXCEED 2048 STUDS ON AN AXIS. Asking for
	-- one giant plane silently gives back a 2048-stud one, and the camera then
	-- shows past its edges when zoomed out.
	--
	-- The earlier version only placed the texture on the centre section, which is
	-- why black edges appeared around it. This version textures EVERY backdrop
	-- tile, so the full visible board carries the same honeycomb artwork.
	local backdrop = Instance.new("Folder")
	backdrop.Name = "BackgroundPlane"
	backdrop.Parent = world

	local TILE = 1600
	local spanX = bounds.width * 3
	local spanZ = bounds.depth * 3
	local tilesX = math.ceil(spanX / TILE)
	local tilesZ = math.ceil(spanZ / TILE)

	for ix = 0, tilesX - 1 do
		for iz = 0, tilesZ - 1 do
			local tile = Instance.new("Part")
			tile.Name = ("Tile_%d_%d"):format(ix, iz)
			tile.Anchored = true
			tile.CanCollide = false
			tile.CanQuery = false
			tile.CanTouch = false
			tile.CastShadow = false
			tile.Material = Enum.Material.SmoothPlastic
			tile.Color = Color3.fromRGB(18, 18, 24)
			-- A hair of overlap, or seams between tiles can show as faint lines.
			tile.Size = Vector3.new(TILE + 2, 2, TILE + 2)
			tile.CFrame = CFrame.new(SkillTreeBoard.ORIGIN + Vector3.new(
				bounds.centre.X - spanX / 2 + TILE * (ix + 0.5),
				-6,
				bounds.centre.Y - spanZ / 2 + TILE * (iz + 0.5)))
			tile.Parent = backdrop

			local artGui = Instance.new("SurfaceGui")
			artGui.Name = "Texture"
			artGui.Face = Enum.NormalId.Top
			artGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			artGui.PixelsPerStud = 2
			artGui.LightInfluence = 0
			artGui.ZOffset = -1
			artGui.Parent = tile

			local art = Instance.new("ImageLabel")
			art.Name = "Background"
			art.BackgroundTransparency = 1
			art.Size = UDim2.fromScale(1, 1)
			art.Image = SkillTreeBoard.BACKGROUND_IMAGE
			art.ScaleType = Enum.ScaleType.Tile
			art.TileSize = UDim2.fromOffset(420, 420)
			art.ImageTransparency = 0.20
			art.Parent = artGui
		end
	end

	local nodesFolder = Instance.new("Folder")
	nodesFolder.Name = "Nodes"
	nodesFolder.Parent = world

	local linksFolder = Instance.new("Folder")
	linksFolder.Name = "Connections"
	linksFolder.Parent = world

	local target = Instance.new("Part")
	target.Name = "CameraTarget"
	target.Anchored = true
	target.CanCollide = false
	target.CanQuery = false
	target.CanTouch = false
	target.Transparency = 1
	target.Size = Vector3.new(1, 1, 1)
	target.CFrame = CFrame.new(
		SkillTreeBoard.ORIGIN + Vector3.new(bounds.centre.X, 0, bounds.centre.Y))
	target.Parent = world

	----------------------------------------------------------------
	-- CONNECTIONS, THEN NODES
	----------------------------------------------------------------

	-- Links first so a node's geometry always sits on top of the lines meeting it.
	-- Iterating Order rather than pairs keeps the build identical every session.
	local links = {}
	for _, id in ipairs(SkillDefinitions.Order) do
		local def = SkillDefinitions.Data[id]

		local reqIds = {}
		for reqId in pairs(def.Requirements or {}) do
			table.insert(reqIds, reqId)
		end
		table.sort(reqIds)

		for _, reqId in ipairs(reqIds) do
			local parentDef = SkillDefinitions.Data[reqId]
			if parentDef then
				table.insert(links, {
					link = SkillLinkBeam.create(
						linksFolder,
						toWorld(parentDef.Position),
						toWorld(def.Position),
						parentDef.Colour
					),
					from = reqId,
					to = id,
					needed = def.Requirements[reqId],
				})
			end
		end
	end

	local nodes = {}
	for _, id in ipairs(SkillDefinitions.Order) do
		local def = SkillDefinitions.Data[id]
		def.Id = id
		nodes[id] = SkillNodePart.create(nodesFolder, def, toWorld(def.Position))
	end

	return {
		world = world,
		nodes = nodes,
		links = links,
		nodesFolder = nodesFolder,
		bounds = bounds,
		centre = SkillTreeBoard.ORIGIN + Vector3.new(bounds.centre.X, 0, bounds.centre.Y),
	}
end

return SkillTreeBoard
