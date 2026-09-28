--!strict
-- Player preferences kept in the profile (profile.settings). For now, the two
-- volume levels from the Settings menu: sfxVolume and musicVolume, 0..1.
--
-- The client applies a change the moment a bar moves (AudioController); this
-- only records it, so the next session starts at the same levels. A save that
-- never had them reads as 1 (full volume) on the client, so older profiles
-- need no migration.
--
-- Values arrive from the client, so they are checked, clamped and rounded to
-- whole percents. DataService's debounced save absorbs a burst of changes
-- into a single write.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local SettingsService = {}
SettingsService.Name = "SettingsService"

local function level(value: any): number?
	if typeof(value) ~= "number" or value ~= value then return nil end
	return math.floor(math.clamp(value, 0, 1) * 100 + 0.5) / 100
end

function SettingsService:SetAudio(player: Player, sfx: any, music: any): boolean
	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	if not profile then return false end

	local s, m = level(sfx), level(music)
	if not s or not m then return false end

	if type(profile.settings) ~= "table" then profile.settings = {} end
	local settings = profile.settings
	if settings.sfxVolume == s and settings.musicVolume == m then return true end
	settings.sfxVolume = s
	settings.musicVolume = m
	-- No Sync: the client already shows these, and a full profile push for two
	-- numbers it sent us would be pure noise.
	DataService:MarkDirty(player)
	return true
end

function SettingsService:Init()
	Remotes.SetAudioSettings.OnServerEvent:Connect(function(player, sfx, music)
		self:SetAudio(player, sfx, music)
	end)
end

return SettingsService
