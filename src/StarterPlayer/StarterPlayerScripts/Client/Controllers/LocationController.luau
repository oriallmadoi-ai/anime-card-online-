--!strict
-- Per-map lighting and sky.
--
-- Lighting is a single global object, so the server cannot give one player a
-- sunny island while another stands in the night-time lobby. Doing it on the
-- CLIENT means each player sees the lighting for wherever their own character
-- is standing, and nobody else is affected.
--
-- The map table itself lives in Shared.Config.MapRegistry, which is also what
-- defines where each map sits on the world grid. Keeping one list means a new
-- map cannot end up with a slot but no lighting, or vice versa.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MapRegistry = require(ReplicatedStorage.Shared.Config.MapRegistry)

local player = Players.LocalPlayer

local LocationController = {}
LocationController.Name = "LocationController"

local TRANSITION = 0.8

local current: string? = nil

local function applySky(spec)
	if not spec then return end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Name = "MapSky"
		sky.Parent = Lighting
	end
	-- Texture properties cannot be tweened, so the swap is instantaneous. It
	-- lands at the same moment the lighting tween starts, which reads as part
	-- of the same transition rather than a separate pop.
	for key, value in pairs(spec) do
		local ok = pcall(function() (sky :: any)[key] = value end)
		if not ok then
			warn("[LocationController] sky property rejected: " .. tostring(key))
		end
	end
end

local function applyDepthOfField(spec)
	if not spec then return end

	local effect = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if not effect then
		effect = Instance.new("DepthOfFieldEffect")
		effect.Name = "MapDepthOfField"
		effect.Parent = Lighting
	end

	-- Set the numeric profile before enabling it. Enabling first can expose
	-- Roblox's previous/default blur values for a frame during map transitions.
	for key, value in pairs(spec) do
		if key ~= "Enabled" then
			(effect :: any)[key] = value
		end
	end
	effect.Enabled = spec.Enabled == true
end

local function apply(entry)
	TweenService:Create(Lighting, TweenInfo.new(TRANSITION), entry.lighting):Play()

	local atmos = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmos and entry.atmosphere then
		TweenService:Create(atmos, TweenInfo.new(TRANSITION), entry.atmosphere):Play()
	end

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom and entry.bloom then
		TweenService:Create(bloom, TweenInfo.new(TRANSITION), entry.bloom):Play()
	end

	applyDepthOfField(entry.depthOfField)
	applySky(entry.sky)
end

-- Outside every radius, keep whatever is showing rather than snapping to a
-- default: a player falling off the map should not trigger a light change.
local function locationFor(position: Vector3)
	return MapRegistry.at(position)
end

function LocationController:Start()
	-- Polled rather than per-frame: lighting only needs to change when someone
	-- crosses between islands, and a raycast-free distance check once a second
	-- costs nothing.
	task.spawn(function()
		while true do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local entry = locationFor(root.Position)
				if entry and entry.name ~= current then
					current = entry.name
					apply(entry)
				end
			end
			task.wait(0.5)
		end
	end)

	print(("[LocationController] per-map lighting online - %d maps")
		:format(#MapRegistry.Maps))
end

return LocationController
