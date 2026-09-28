--!strict
-- Interface sound effects.
--
-- Sounds are POOLED rather than created per play. Hovering across a grid of
-- cards fires dozens of times a second, and a fresh Sound instance per hover
-- would churn instances and leave them for the collector.
--
-- Hover is also RATE LIMITED. Dragging the cursor across a row would otherwise
-- machine-gun the sample; a short cooldown keeps it to one blip per card.
--
-- The ids below are engine-shipped files (rbxasset://), so they need no upload
-- and cannot fail moderation. Swap SOUNDS.Hover / SOUNDS.Press for your own
-- "whoop" once it is uploaded - nothing else needs to change.

local SoundService = game:GetService("SoundService")

local Sfx = {}

Sfx.Sounds = {
	Hover = {
		id = "rbxassetid://124476359159008",
		volume = 0.28,
		pitch = 1.0,
	},

	Press = {
		id = "rbxassetid://9080070218",
		volume = 0.45,
		pitch = 1.0,
	},
}

local HOVER_COOLDOWN = 0.06

local pool: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}

local function get(name: string): Sound?
	local spec = Sfx.Sounds[name]
	if not spec then return nil end

	local sound = pool[name]
	if not sound or not sound.Parent then
		sound = Instance.new("Sound")
		sound.Name = "Sfx_" .. name
		sound.SoundId = spec.id
		sound.Volume = spec.volume
		sound.PlaybackSpeed = spec.pitch
		-- Parented to SoundService so it is not positional and is unaffected by
		-- whatever the camera is doing.
		sound.Parent = SoundService
		pool[name] = sound
	end
	return sound
end

function Sfx.play(name: string)
	local sound = get(name)
	if not sound then return end

	if name == "Hover" then
		local now = os.clock()
		if (now - (lastPlayed[name] or 0)) < HOVER_COOLDOWN then return end
		lastPlayed[name] = now
	end

	-- Restarting rather than cloning: rapid presses re-trigger the same sample
	-- instead of stacking copies on top of each other.
	sound.TimePosition = 0
	sound:Play()
end

-- Attaches hover and press sounds to any GuiButton in one call.
function Sfx.bindButton(button: GuiButton)
	if not button then return end
	button.MouseEnter:Connect(function() Sfx.play("Hover") end)
	button.MouseButton1Down:Connect(function() Sfx.play("Press") end)
end

return Sfx
