--!strict
-- OceanMotion  (Script, RunContext = Client)
-- Workspace.ArlongPark.Environment.Ocean.OceanMotion
--
-- Every motion is a looping TweenService tween, so nothing runs per frame.
--
-- STREAMING. This place has Workspace.StreamingEnabled on, and Arlong Park sits
-- ~2000 studs from the lobby spawn. A client that joins in the lobby gets this
-- script long before it gets the water: the first pass would find nothing and,
-- if it only ran once, the ocean would stay frozen forever. Parts can also
-- stream out and back as the player leaves and returns, and each return is a
-- NEW instance whose tween has to be started again.
--
-- So: re-run on DescendantAdded, and keep a table of what is already animated
-- so re-runs cannot stack a second tween on the same part.

local TweenService = game:GetService("TweenService")
local ocean = script.Parent

local animated: { [Instance]: boolean } = {}

local function loopTween(inst: Instance, time: number, props, delayTime: number?)
	TweenService:Create(
		inst,
		TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, delayTime or 0),
		props
	):Play()
end

local SWELL = {
	{ name = "OceanShore",   amp = 0.34, time = 3.6, phase = 0.0 },
	{ name = "OceanShallow", amp = 0.30, time = 4.3, phase = 0.5 },
	{ name = "OceanNear",    amp = 0.26, time = 4.9, phase = 0.9 },
	{ name = "OceanMid",     amp = 0.20, time = 5.8, phase = 1.3 },
	{ name = "OceanFar",     amp = 0.14, time = 7.1, phase = 1.8 },
}

local function setup()
	-- Depth bands bob on their own periods, so the surface never reads as one
	-- rigid sheet. Amplitudes stay under 0.4 studs on purpose.
	for _, s in ipairs(SWELL) do
		local part = ocean:FindFirstChild(s.name)
		if part and not animated[part] then
			animated[part] = true
			loopTween(part, s.time, { CFrame = (part :: BasePart).CFrame + Vector3.new(0, s.amp, 0) }, s.phase)
		end
	end

	local foam = ocean:FindFirstChild("Foam")
	if foam then
		for i, p in ipairs(foam:GetChildren()) do
			if p:IsA("BasePart") and not animated[p] then
				animated[p] = true
				loopTween(p, 2.4 + i * 0.35, { Transparency = 0.82 }, i * 0.28)
			end
		end
	end

	local waves = ocean:FindFirstChild("Waves")
	if waves then
		for i, p in ipairs(waves:GetChildren()) do
			if p:IsA("BasePart") and not animated[p] then
				animated[p] = true
				local axis = p:GetAttribute("Axis")
				local dir = (p:GetAttribute("Dir") :: number?) or 1
				local step = (axis == "X") and Vector3.new(26 * dir, 0, 0) or Vector3.new(0, 0, 26 * dir)
				loopTween(p, 7 + i * 0.6, { CFrame = p.CFrame + step }, i * 0.4)
				loopTween(p, 3.1 + i * 0.4, { Transparency = 0.94 }, i * 0.5)
			end
		end
	end
end

-- Debounced to one call per frame: a stream-in fires DescendantAdded once per
-- part, and running the whole sweep 20 times in a row would be pure waste.
local queued = false
local function schedule()
	if queued then return end
	queued = true
	task.defer(function()
		queued = false
		setup()
	end)
end

ocean.DescendantAdded:Connect(schedule)
schedule()
