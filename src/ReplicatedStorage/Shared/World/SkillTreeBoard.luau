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
local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)

local SkillTreeBoard = {}

-- Parked far above the map so the board can never intersect the island, the
-- ocean, or a player. The camera is the only thing that ever goes there.
SkillTreeBoard.ORIGIN = Vector3.new(0, 6000, 0)

-- Kept for anything that still reads it; the board itself no longer uses it.
SkillTreeBoard.BACKGROUND_IMAGE = "rbxassetid://111282088873223"

local TILE = 1600
local TILE_PPS = 0.5
local GRID = 100
local MAJOR_EVERY = 4
local CROSS_PX = 14
-- A soft slate grey rather than near-black: light enough that the board reads
-- as a surface, dark enough that Neon rims and lit paths still glow on it.
-- Authored lighter than it looks: the renderer's tone curve pulls a flat
-- SurfaceGui colour down noticeably (42,45,58 came out almost navy-black).
local FLOOR = Color3.fromRGB(80, 83, 96)
local GRID_MINOR = Color3.fromRGB(122, 130, 164)
local GRID_MAJOR = Color3.fromRGB(160, 170, 214)
local AURA_LAYERS = {
	{ colour = Color3.fromRGB(140, 116, 255), alpha = 0.8, size = 1, y = 0.5 },
	{ colour = Color3.fromRGB(96, 156, 255), alpha = 0.88, size = 0.7, y = 0.62 },
}

-- A SurfaceGui on a TOP face takes its "up" from the part's local X; a quarter
-- turn about Y makes it read the way the board camera looks at it (the same
-- turn the node labels use).
local CANVAS_FACING = CFrame.Angles(0, math.rad(-90), 0)

-- HOW FAR BELOW THE NODES THE BACKGROUND LIVES, and why it is so far.
-- The camera sits ~3300 studs up, and at that distance the depth buffer can
-- only tell surfaces apart when they are roughly 7 studs or more apart. The
-- floor's SurfaceGui used to sit 5 studs under the nodes, close enough that it
-- drew straight over their Neon rims. Tens of studs of clearance keeps every
-- layer in order at any zoom; the camera is so far away that the extra depth
-- changes nothing you can see.
local FLOOR_Y = -121
local AURA_Y = -80

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

	-- A slate floor ruled with a faint measuring grid - minor lines every
	-- 100 studs, brighter major lines every 400 with a small cross where two
	-- majors meet - and a broad violet bloom sitting under the tree itself. The
	-- nodes and the lit paths are the only saturated things on it.
	--
	-- TILED, because A SINGLE PART CANNOT EXCEED 2048 STUDS ON AN AXIS. Asking for
	-- one giant plane silently gives back a 2048-stud one, and the camera then
	-- shows past its edges when zoomed out.
	--
	-- Tiles start on a multiple of the major spacing and are a whole number of
	-- majors wide, so every tile draws its lines at the same world positions and
	-- the grid runs across the seams unbroken. Each tile overlaps its neighbour
	-- by a stud (or a hairline gap can show between them), and that overlap is
	-- the same on both sides, so the line positions come out identical whichever
	-- way the canvas happens to be mirrored.
	local backdrop = Instance.new("Folder")
	backdrop.Name = "BackgroundPlane"
	backdrop.Parent = world

	local spanX = bounds.width * 3
	local spanZ = bounds.depth * 3
	local majorStep = GRID * MAJOR_EVERY
	local startX = math.floor((bounds.centre.X - spanX / 2) / majorStep) * majorStep
	local startZ = math.floor((bounds.centre.Y - spanZ / 2) / majorStep) * majorStep
	local tilesX = math.ceil((bounds.centre.X + spanX / 2 - startX) / TILE)
	local tilesZ = math.ceil((bounds.centre.Y + spanZ / 2 - startZ) / TILE)

	local function line(parent: Instance, vertical: boolean, at: number, width: number, colour: Color3, alpha: number)
		local f = Instance.new("Frame")
		f.Name = vertical and "V" or "H"
		f.BorderSizePixel = 0
		f.BackgroundColor3 = colour
		f.BackgroundTransparency = alpha
		if vertical then
			f.Position = UDim2.new(0, at - width / 2, 0, 0)
			f.Size = UDim2.new(0, width, 1, 0)
		else
			f.Position = UDim2.new(0, 0, 0, at - width / 2)
			f.Size = UDim2.new(1, 0, 0, width)
		end
		f.Parent = parent
		return f
	end

	local perTile = math.floor(TILE / GRID)
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
			tile.Color = FLOOR
			tile.Size = Vector3.new(TILE + 2, 2, TILE + 2)
			tile.CFrame = CFrame.new(SkillTreeBoard.ORIGIN + Vector3.new(
				startX + TILE * (ix + 0.5),
				FLOOR_Y,
				startZ + TILE * (iz + 0.5))) * CANVAS_FACING
			tile.Parent = backdrop

			local gui = Instance.new("SurfaceGui")
			gui.Name = "Grid"
			gui.Face = Enum.NormalId.Top
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = TILE_PPS
			gui.LightInfluence = 0
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			gui.Parent = tile

			local floor = Instance.new("Frame")
			floor.Name = "Floor"
			floor.BorderSizePixel = 0
			floor.BackgroundColor3 = FLOOR
			floor.Size = UDim2.fromScale(1, 1)
			floor.Parent = gui

			-- k = perTile is the next tile's k = 0, so each tile draws only its
			-- own near edge.
			for k = 0, perTile - 1 do
				local at = (1 + k * GRID) * TILE_PPS
				local major = k % MAJOR_EVERY == 0
				local width = major and 2 or 1
				local colour = major and GRID_MAJOR or GRID_MINOR
				local alpha = major and 0.8 or 0.9
				line(floor, true, at, width, colour, alpha)
				line(floor, false, at, width, colour, alpha)
			end

			-- A small cross on every major intersection.
			for kx = 0, perTile - 1, MAJOR_EVERY do
				for kz = 0, perTile - 1, MAJOR_EVERY do
					local cx = (1 + kx * GRID) * TILE_PPS
					local cz = (1 + kz * GRID) * TILE_PPS
					local mark = Instance.new("Frame")
					mark.Name = "Cross"
					mark.BackgroundTransparency = 1
					mark.AnchorPoint = Vector2.new(0.5, 0.5)
					mark.Position = UDim2.fromOffset(cx, cz)
					mark.Size = UDim2.fromOffset(CROSS_PX, CROSS_PX)
					mark.Parent = floor
					line(mark, true, CROSS_PX / 2, 2, GRID_MAJOR, 0.45)
					line(mark, false, CROSS_PX / 2, 2, GRID_MAJOR, 0.45)
				end
			end
		end
	end

	-- The bloom under the tree: a soft radial glow stretched over the tree's
	-- extents, sitting just above the floor. Capped at the 2048-stud part limit.
	local aura = Instance.new("Part")
	aura.Name = "Aura"
	aura.Anchored = true
	aura.CanCollide = false
	aura.CanQuery = false
	aura.CanTouch = false
	aura.CastShadow = false
	aura.Transparency = 1
	local auraW = math.min(2040, bounds.width * 1.25)
	local auraD = math.min(2040, bounds.depth * 1.25)
	aura.Size = Vector3.new(auraD, 0.2, auraW)
	aura.CFrame = CFrame.new(SkillTreeBoard.ORIGIN + Vector3.new(bounds.centre.X, AURA_Y, bounds.centre.Y)) * CANVAS_FACING
	aura.Parent = backdrop

	local auraGui = Instance.new("SurfaceGui")
	auraGui.Name = "Bloom"
	auraGui.Face = Enum.NormalId.Top
	auraGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	auraGui.PixelsPerStud = 0.25
	auraGui.LightInfluence = 0
	auraGui.Parent = aura

	for i, spec in ipairs(AURA_LAYERS) do
		local glow = Instance.new("ImageLabel")
		glow.Name = "Glow" .. i
		glow.BackgroundTransparency = 1
		glow.Image = VfxAssets.Glow
		glow.ImageColor3 = spec.colour
		glow.ImageTransparency = spec.alpha
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, spec.y)
		glow.Size = UDim2.fromScale(spec.size, spec.size)
		glow.Parent = auraGui
	end

	-- FLARES: a slow drift of tiny motes and the odd four-point glint over the
	-- tree. Few, faint and small on purpose - the board should feel alive, not
	-- busy, and nothing here may compete with a lit path or a breathing node.
	-- Particles are sized in studs, and the camera opens ~3000 studs up, so a
	-- 14-stud mote is only a few pixels across until you zoom in.
	--
	-- RATE IS ZERO ON PURPOSE. At the camera's distance the engine thins out
	-- rate-driven emission until nothing appears at all; an explicit Emit is
	-- never thinned. SkillTreeController emits these on a timer while the
	-- tree is open (see `flares` in the returned table).
	-- Three strips side by side: one part caps at 2048 studs and the opening
	-- view is wider than that, so a single part left bare bands down both
	-- sides of the screen. Each strip carries its own pair of emitters.
	local function fade(peak: number): NumberSequence
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, peak),
			NumberSequenceKeypoint.new(0.7, peak),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	local STRIP = 1360
	local stripDepth = math.min(2040, bounds.depth * 1.5)
	local moteList, glintList = {}, {}
	for i = -1, 1 do
		local strip = Instance.new("Part")
		strip.Name = "Flares"
		strip.Anchored = true
		strip.CanCollide = false
		strip.CanQuery = false
		strip.CanTouch = false
		strip.CastShadow = false
		strip.Transparency = 1
		strip.Size = Vector3.new(STRIP, 10, stripDepth)
		strip.CFrame = CFrame.new(SkillTreeBoard.ORIGIN + Vector3.new(bounds.centre.X + i * STRIP, 4, bounds.centre.Y))
		strip.Parent = backdrop

		local motes = Instance.new("ParticleEmitter")
		motes.Name = "Motes"
		motes.Texture = VfxAssets.Mote
		motes.Shape = Enum.ParticleEmitterShape.Box
		motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		motes.EmissionDirection = Enum.NormalId.Top
		motes.SpreadAngle = Vector2.new(85, 85)
		motes.Rate = 0
		motes.Lifetime = NumberRange.new(6, 10)
		motes.Speed = NumberRange.new(4, 11)
		motes.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.25, 14, 4),
			NumberSequenceKeypoint.new(0.75, 14, 4),
			NumberSequenceKeypoint.new(1, 0),
		})
		motes.Transparency = fade(0.45)
		motes.Color = ColorSequence.new(Color3.fromRGB(200, 212, 255), Color3.fromRGB(232, 214, 255))
		motes.LightEmission = 1
		motes.LightInfluence = 0
		motes.Parent = strip
		table.insert(moteList, motes)

		local glints = Instance.new("ParticleEmitter")
		glints.Name = "Glints"
		glints.Texture = VfxAssets.Spark
		glints.Shape = Enum.ParticleEmitterShape.Box
		glints.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		glints.EmissionDirection = Enum.NormalId.Top
		glints.SpreadAngle = Vector2.new(85, 85)
		glints.Rate = 0
		glints.Lifetime = NumberRange.new(1.6, 2.6)
		glints.Speed = NumberRange.new(0, 2)
		glints.Rotation = NumberRange.new(0, 90)
		glints.RotSpeed = NumberRange.new(-24, 24)
		glints.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 34, 8),
			NumberSequenceKeypoint.new(1, 0),
		})
		glints.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		glints.Color = ColorSequence.new(Color3.fromRGB(244, 240, 255))
		glints.LightEmission = 1
		glints.LightInfluence = 0
		glints.Parent = strip
		table.insert(glintList, glints)
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
		flares = { motes = moteList, glints = glintList },
		bounds = bounds,
		centre = SkillTreeBoard.ORIGIN + Vector3.new(bounds.centre.X, 0, bounds.centre.Y),
	}
end

return SkillTreeBoard
