--!strict
-- Who may hide the Battle Power leaderboard, and when it comes back.
--
-- WHY THIS EXISTS
-- Several screens hide the leaderboard while they are up - every menu window,
-- the Deck, the Card Forge, the Skill Tree and battles - and each used to do it
-- by remembering the leaderboard's Enabled flag on the way in and writing it
-- back on the way out. Those memories clobbered each other. Opening the Deck,
-- the Forge or the Skill Tree first calls MenuController:CloseAll(), which
-- "restored" a flag that had never been saved (it defaulted to hidden), and
-- switching straight from one menu to another saved "hidden" as the state to
-- go back to. Either way the leaderboard vanished for the rest of the session.
--
-- NOW each screen only says "hidden because of me" and "not any more", and the
-- leaderboard shows exactly when nobody is asking for it to be hidden. Nothing
-- is remembered, so nothing can be remembered wrong - and two screens hiding
-- it at once is fine: it waits for both.

local Players = game:GetService("Players")

local LeaderboardVisibility = {}

local GUI_NAME = "BattlePowerLeaderboard"
local reasons: { [string]: boolean } = {}
local attached: ScreenGui? = nil

local function target(): ScreenGui?
	if attached and attached.Parent then return attached end
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild(GUI_NAME)
	if gui and gui:IsA("ScreenGui") then
		attached = gui
		return gui
	end
	return nil
end

local function apply()
	local gui = target()
	if gui then
		gui.Enabled = next(reasons) == nil
	end
end

-- The leaderboard's controller hands its gui over once it is built, so a screen
-- that asked for it hidden before it existed is still obeyed.
function LeaderboardVisibility.attach(gui: ScreenGui)
	attached = gui
	apply()
end

function LeaderboardVisibility.hide(reason: string)
	reasons[reason] = true
	apply()
end

function LeaderboardVisibility.show(reason: string)
	reasons[reason] = nil
	apply()
end

function LeaderboardVisibility.isHidden(): boolean
	return next(reasons) ~= nil
end

return LeaderboardVisibility
