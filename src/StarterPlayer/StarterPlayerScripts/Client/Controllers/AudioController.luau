--!strict
-- Anime Card Online
-- The mixer: two volume buses, Sound Effects and Music, driven by the bars in
-- the Settings menu.
--
-- ROUTING
-- Every Sound this client can hear is put on a bus as soon as it appears -
-- SoundService, the world and the PlayerGui are all watched - so no feature
-- has to remember to opt in, and sounds added later are covered too. A Sound
-- carrying the attribute AudioGroup = "Music" (set BEFORE it is parented)
-- goes on the Music bus; everything else is a sound effect. A Sound that
-- already has a SoundGroup is left alone.
--
-- LEVELS
-- A bar runs 0..1 and its bus gets the square of that (an "audio taper").
-- Loudness is heard logarithmically, so a straight 1:1 bar would change
-- almost nothing across its top half and everything in its last few pixels.
--
-- SAVING
-- The levels live in profile.settings (sfxVolume, musicVolume). They are
-- taken from the first ProfileSync only - after that this client is the
-- source of truth, so a sync already in flight can never snap a bar back -
-- and go up through Remotes.SetAudioSettings once a bar is let go, where
-- SettingsService records them.
--
-- Until the saved levels are known the Music bus is held silent. The track
-- fades in from nothing anyway, so the hold costs nothing audible, and a
-- player who turned music down does not get the start of every session at
-- full volume. The hold always lets go after a few seconds, saved or not.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local AudioController = {}
AudioController.Name = "AudioController"

-- Bus -> its key in profile.settings.
local BUSES = { SFX = "sfxVolume", Music = "musicVolume" }
-- A few quick taps on a bar become one request.
local SAVE_DELAY = 0.5

local levels: { [string]: number } = { SFX = 1, Music = 1 }
local groups: { [string]: SoundGroup } = {}
local changed = Instance.new("BindableEvent")
local loaded = false   -- the saved levels have been applied
local touched = false  -- the player has moved a bar this session
local musicHeld = true -- see the note above
local saveToken = 0

-- Fires (bus, level) whenever a level changes, from a bar or from the save.
AudioController.Changed = changed.Event

local function gain(bus: string): number
	if bus == "Music" and musicHeld then return 0 end
	local v = levels[bus] or 1
	return v * v
end

local function group(bus: string): SoundGroup
	local existing = groups[bus]
	if existing and existing.Parent then return existing end
	local g = Instance.new("SoundGroup")
	g.Name = bus
	g.Volume = gain(bus)
	g.Parent = SoundService
	groups[bus] = g
	return g
end

local function route(sound: Sound)
	if sound.SoundGroup then return end
	sound.SoundGroup = group(if sound:GetAttribute("AudioGroup") == "Music" then "Music" else "SFX")
end

local function watch(root: Instance)
	root.DescendantAdded:Connect(function(object)
		if object:IsA("Sound") then route(object) end
	end)
	for _, object in ipairs(root:GetDescendants()) do
		if object:IsA("Sound") then route(object) end
	end
end

local function set(bus: string, value: number)
	levels[bus] = value
	group(bus).Volume = gain(bus)
	changed:Fire(bus, value)
end

local function releaseMusic()
	if not musicHeld then return end
	musicHeld = false
	group("Music").Volume = gain("Music")
end

local function applySaved(profile: any)
	if loaded or touched then return end
	local settings = if type(profile) == "table" then profile.settings else nil
	if type(settings) ~= "table" then return end
	loaded = true
	for bus, key in pairs(BUSES) do
		local v = settings[key]
		if type(v) == "number" and v == v then
			set(bus, math.clamp(v, 0, 1))
		end
	end
	releaseMusic()
end

function AudioController:GetVolume(bus: string): number
	return levels[bus] or 1
end

-- `value` is 0..1 and is heard at once. Pass save = false while a bar is
-- still being dragged, then call Save() when it is let go.
function AudioController:SetVolume(bus: string, value: number, save: boolean?)
	if BUSES[bus] == nil then return end
	touched = true
	releaseMusic()
	local v = math.clamp(math.floor(value * 100 + 0.5) / 100, 0, 1)
	if v ~= levels[bus] then set(bus, v) end
	if save ~= false then self:Save() end
end

function AudioController:Save()
	touched = true
	saveToken += 1
	local mine = saveToken
	task.delay(SAVE_DELAY, function()
		if mine ~= saveToken then return end
		Remotes.SetAudioSettings:FireServer(levels.SFX, levels.Music)
	end)
end

function AudioController:Init()
	for bus in pairs(BUSES) do group(bus) end
	Remotes.ProfileSync.OnClientEvent:Connect(applySaved)
	watch(SoundService)
	watch(workspace)
end

function AudioController:Start()
	watch(Players.LocalPlayer:WaitForChild("PlayerGui"))
	-- The join-time sync can land before this listener existed, so ask once
	-- more if the saved levels have not shown up.
	task.delay(2, function()
		if not loaded and not touched then
			Remotes.RequestSync:FireServer()
		end
	end)
	-- Never hold the music for long, saved levels or not.
	task.delay(6, releaseMusic)
end

return AudioController
