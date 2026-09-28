--!strict
-- PortalFX  (Script, RunContext = Client)
-- Workspace.ArlongPark.PortalToLobby.PortalFX
--
-- Presentation only. It never teleports anybody - TravelService (server) still
-- owns that, driven by the same ProximityPrompt. Delete this script and the
-- portal keeps working, it just stops looking alive.
--
-- STREAMING. Workspace.StreamingEnabled is on and this portal is ~2000 studs
-- from the lobby spawn, so a client that joins in the lobby receives this
-- script long before it receives the portal's parts. A plain WaitForChild at
-- the top logs an "Infinite yield" warning and, worse, keeps a reference to
-- instances that are destroyed and rebuilt each time the player leaves and
-- returns. Everything is therefore wired up per stream-in and torn down on
-- stream-out.

local TweenService           = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players                = game:GetService("Players")

local portal = script.Parent
local player = Players.LocalPlayer

-- ---- TUNING -----------------------------------------------------------
local IDLE  = { lightBrightness = 1.1, lightRange = 18, surface = 0.52, core = 0.74, moteRate = 7,  text = Color3.fromRGB(238, 228, 255) }
local NEAR  = { lightBrightness = 2.0, lightRange = 26, surface = 0.36, core = 0.56, moteRate = 15, text = Color3.fromRGB(252, 248, 255) }
local HOVER = { lightBrightness = 2.8, lightRange = 30, surface = 0.26, core = 0.44, moteRate = 22, text = Color3.fromRGB(255, 255, 255) }

local APPROACH_TIME = 0.35
local FLASH_TIME    = 0.16
local FADE_TIME     = 0.34      -- ~0.5s total
-- -----------------------------------------------------------------------

local function ease(t: number) return TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) end

-- Live handles for whatever is currently streamed in. Nil means "portal not
-- present right now", and every handler below no-ops in that state.
local parts: any = nil
local connections: { RBXScriptConnection } = {}

local function applyState(state, time: number)
	if not parts then return end
	local info = ease(time)
	TweenService:Create(parts.light,   info, { Brightness = state.lightBrightness, Range = state.lightRange }):Play()
	TweenService:Create(parts.surface, info, { Transparency = state.surface }):Play()
	TweenService:Create(parts.core,    info, { Transparency = state.core }):Play()
	TweenService:Create(parts.label,   info, { TextColor3 = state.text }):Play()
	parts.motes.Rate = state.moteRate
end

local function chime(pitch: number, volume: number)
	if not parts then return end
	local s = Instance.new("Sound")
	s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	s.PlaybackSpeed = pitch
	s.Volume = volume
	s.Parent = parts.surface
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
	task.delay(3, function() if s.Parent then s:Destroy() end end)
end

local function flash()
	if not parts then return end
	parts.burst:Emit(28)
	chime(0.72, 0.55)

	local gui = Instance.new("ScreenGui")
	gui.Name = "PortalFlash"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(126, 84, 216)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	TweenService:Create(frame, ease(FLASH_TIME), { BackgroundTransparency = 0.12 }):Play()
	task.delay(FLASH_TIME, function()
		TweenService:Create(
			frame,
			TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		):Play()
		task.delay(FADE_TIME + 0.05, function() gui:Destroy() end)
	end)
end

-- Collects the handles, or returns nil if any piece has not streamed in yet.
local function gather()
	local surface = portal:FindFirstChild("Surface")
	local glow    = portal:FindFirstChild("Glow")
	if not (surface and glow) then return nil end

	local hub    = surface:FindFirstChild("FXHub")
	local prompt = surface:FindFirstChild("TravelPrompt")
	local bb     = surface:FindFirstChild("BillboardGui")
	local core   = glow:FindFirstChild("Core")
	if not (hub and prompt and bb and core) then return nil end

	local light = hub:FindFirstChild("PortalLight")
	local motes = hub:FindFirstChild("Motes")
	local burst = hub:FindFirstChild("Burst")
	local label = bb:FindFirstChildWhichIsA("TextLabel")
	if not (light and motes and burst and label) then return nil end

	return {
		surface = surface, prompt = prompt, core = core,
		light = light, motes = motes, burst = burst, label = label,
	}
end

local function teardown()
	for _, c in ipairs(connections) do c:Disconnect() end
	table.clear(connections)
	parts = nil
end

local function build()
	if parts then return end
	local found = gather()
	if not found then return end
	parts = found

	-- Idle pulse: one looping tween, no per-frame cost.
	TweenService:Create(
		parts.core,
		TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = parts.core.Size * Vector3.new(0.9, 0.94, 1) }
	):Play()

	local function isOurs(p) return parts ~= nil and p == parts.prompt end

	-- Engine proximity events: no distance polling anywhere in this script.
	table.insert(connections, ProximityPromptService.PromptShown:Connect(function(p)
		if isOurs(p) then applyState(NEAR, APPROACH_TIME) end
	end))
	table.insert(connections, ProximityPromptService.PromptHidden:Connect(function(p)
		if isOurs(p) then applyState(IDLE, APPROACH_TIME * 1.6) end
	end))
	table.insert(connections, ProximityPromptService.PromptButtonHoldBegan:Connect(function(p)
		if isOurs(p) then applyState(HOVER, 0.12); chime(1.35, 0.28) end
	end))
	table.insert(connections, ProximityPromptService.PromptButtonHoldEnded:Connect(function(p)
		if isOurs(p) then applyState(NEAR, 0.2) end
	end))
	table.insert(connections, ProximityPromptService.PromptTriggered:Connect(function(p, who)
		if isOurs(p) and who == player then
			flash()
			applyState(HOVER, 0.1)
			task.delay(0.6, function() applyState(IDLE, 0.4) end)
		end
	end))

	-- Stream-out: the surface is destroyed, so drop the stale handles and wait
	-- to be rebuilt on the next stream-in.
	table.insert(connections, parts.surface.AncestryChanged:Connect(function(_, newParent)
		if not newParent then teardown() end
	end))

	applyState(IDLE, 0)
end

local queued = false
local function schedule()
	if queued then return end
	queued = true
	task.defer(function()
		queued = false
		build()
	end)
end

portal.DescendantAdded:Connect(schedule)
schedule()
