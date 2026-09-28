--!strict
-- PoolMotion  (Script, RunContext = Client)
-- Workspace.ArlongPark.Environment.BattlePools.PoolMotion
--
-- Animates the two battle-zone pools with looping tweens only. Touches
-- decorative parts exclusively: the collidable PoolWater surface is tinted in
-- the build, never moved here, so the battle zone footprint is untouched.
--
-- Streaming-aware for the same reason as OceanMotion - see the note there.

local TweenService = game:GetService("TweenService")
local root = script.Parent

local animated: { [Instance]: boolean } = {}

local function loop(inst: Instance, time: number, props, delayTime: number?)
	TweenService:Create(
		inst,
		TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, delayTime or 0),
		props
	):Play()
end

local function setup()
	for _, group in ipairs(root:GetChildren()) do
		if group:IsA("Folder") then
			for i, p in ipairs(group:GetChildren()) do
				if p:IsA("BasePart") and not animated[p] then
					if p.Name:match("^Foam") then
						animated[p] = true
						loop(p, 2.0 + i * 0.3, { Transparency = 0.8 }, i * 0.25)
					elseif p.Name:match("^Caustic") then
						animated[p] = true
						local travel = (p:GetAttribute("Travel") :: number?) or 20
						loop(p, 5.5 + i * 0.9, { CFrame = p.CFrame + Vector3.new(0, 0, travel) }, i * 0.7)
						loop(p, 2.7 + i * 0.5, { Transparency = 0.93 }, i * 0.45)
					end
				end
			end
		end
	end
end

local queued = false
local function schedule()
	if queued then return end
	queued = true
	task.defer(function()
		queued = false
		setup()
	end)
end

root.DescendantAdded:Connect(schedule)
schedule()
