--!strict
-- Sprint (hold Shift) and dash (Q). Every number that shapes how they feel.
--
-- ANIMATIONS
-- Paste the published ids below once you have uploaded Sprint and Dash from the
-- Animation Editor (rig: Workspace.AnimRig). Until then, Studio playtests use
-- the local copies in ReplicatedStorage.Shared.Animations automatically; live
-- servers need the real ids, because Roblox only plays uploaded animations.

local MovementConfig = {
	SprintAnimationId = "",   -- e.g. "rbxassetid://1234567890"
	DashAnimationId = "",

	-- sprint
	SprintSpeedMultiplier = 2.1,  -- 16 walk -> ~34 sprint

	-- dash
	DashSpeed = 78,               -- studs/sec during the burst
	DashTime = 0.4,               -- seconds of burst
}

return MovementConfig
