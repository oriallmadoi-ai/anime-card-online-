--!strict
-- Background music.
--
-- Client-side, not a Sound sitting in the place file. Music is a per-player
-- thing: the volume, the mute, and eventually the track are all preferences,
-- and a sound parented into the world would be the same for everybody and
-- unreachable from a settings menu.
--
-- Parented to SoundService so it is not positional - a music bed that got
-- quieter when the camera moved would be a bug, not an effect.

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local MusicController = {}
MusicController.Name = "MusicController"

-- Add more entries and they will play in order, looping back to the first.
-- With one track the loop is just that track repeating.
local TRACKS = {
	{ id = "rbxassetid://97359889719505", volume = 0.35 },
}

-- Music never starts at full volume. Coming in at the target level on the same
-- frame the menu appears reads as a glitch; two seconds of ramp reads as the
-- game starting.
local FADE_IN = 2.0
local FADE_OUT = 1.2
-- Gap between tracks. Zero would butt the end of one against the start of the
-- next, which only works if they were written to be joined.
local GAP = 1.5

local sound: Sound? = nil
local index = 0
local enabled = true
local generation = 0
local fadeConn: RBXScriptConnection? = nil

local function currentTarget(): number
	local track = TRACKS[index]
	return (track and track.volume or 0.35)
end

-- Ramped by hand rather than with TweenService.
--
-- A tween on Sound.Volume for a Sound parented to SoundService runs to
-- completion without ever moving the property - the sound plays at zero for
-- ever and the game is silently silent, which is indistinguishable from the
-- asset having failed to load. Assigning Volume directly works fine, so the
-- interpolation is done here. It is a handful of lines and it is not subtle.
local function fadeTo(target: number, time: number)
	if not sound then return end
	if fadeConn then
		fadeConn:Disconnect()
		fadeConn = nil
	end

	local from = sound.Volume
	local elapsed = 0

	fadeConn = RunService.Heartbeat:Connect(function(dt)
		if not sound then return end
		elapsed += dt
		local a = math.clamp(elapsed / time, 0, 1)
		-- Ease out: most of the travel happens early, so the track is audible
		-- quickly and then settles rather than creeping in for two seconds.
		sound.Volume = from + (target - from) * (1 - (1 - a) ^ 2)
		if a >= 1 and fadeConn then
			fadeConn:Disconnect()
			fadeConn = nil
		end
	end)
end

local function playNext(mine: number)
	if mine ~= generation or not enabled or not sound then return end

	index = (index % #TRACKS) + 1
	local track = TRACKS[index]

	sound.SoundId = track.id
	sound.Volume = 0
	sound.TimePosition = 0
	sound:Play()
	fadeTo(track.volume, FADE_IN)
end

function MusicController:Init()
	sound = Instance.new("Sound")
	sound.Name = "BackgroundMusic"
	-- Looped is false even for a single track: Ended is what drives the
	-- playlist, and a looped sound never ends.
	sound.Looped = false
	sound.Volume = 0
	-- Puts it on the Music bus, which the Settings menu's MUSIC bar controls
	-- (see AudioController). Set before parenting: that is when it is routed.
	sound:SetAttribute("AudioGroup", "Music")
	sound.Parent = SoundService

	sound.Ended:Connect(function()
		local mine = generation
		task.delay(GAP, function() playNext(mine) end)
	end)

	-- A music asset that fails to load is silent, and silence is exactly what a
	-- muted game looks like - so say something rather than leave it ambiguous.
	task.delay(10, function()
		if sound and sound.SoundId ~= "" and not sound.IsLoaded then
			warn("[Music] " .. sound.SoundId .. " did not load - check the asset is "
				.. "owned by this experience's creator and is not still moderating.")
		end
	end)
end

function MusicController:Start()
	if #TRACKS == 0 then return end
	playNext(generation)
end

-- Kills the current track on the way out rather than cutting it, and picks
-- the playlist back up from the top when re-enabled. (The Settings menu's
-- MUSIC bar does not use this - it sets the Music bus in AudioController.)
function MusicController:SetEnabled(on: boolean)
	if on == enabled then return end
	enabled = on
	generation += 1

	if not sound then return end

	if on then
		index = 0
		playNext(generation)
	else
		local dying = sound
		fadeTo(0, FADE_OUT)
		task.delay(FADE_OUT, function()
			if not enabled and dying then dying:Stop() end
		end)
	end
end

function MusicController:IsEnabled(): boolean
	return enabled
end

-- Scales the current track's own level rather than replacing it, so a track
-- mixed quieter than the others stays quieter relative to them.
function MusicController:SetVolume(scale: number)
	if not sound then return end
	sound.Volume = math.clamp(scale, 0, 1) * currentTarget()
end

return MusicController
