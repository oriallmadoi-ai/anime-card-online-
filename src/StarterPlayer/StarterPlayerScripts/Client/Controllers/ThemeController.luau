--!strict
-- Applies the game font everywhere, once, and keeps applying it to anything
-- created later.
--
-- Runs in Start rather than Init so every other controller has already built
-- its interface by the time we sweep. The DescendantAdded hooks then catch
-- anything spawned after that - dynamically built inventory rows, card
-- reveals, and the world-space labels on the lobby stations.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)

local ThemeController = {}
ThemeController.Name = "ThemeController"

function ThemeController:Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	Theme.bind(playerGui)

	-- BillboardGui and SurfaceGui labels live in the world, not PlayerGui.
	-- Styling them on the client is fine: every client runs this for itself.
	Theme.bind(Workspace)

	print("[Theme] font applied: " .. Theme.FontId)
end

return ThemeController
