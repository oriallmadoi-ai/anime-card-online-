--!strict
-- Anime Card Online - mounts.
--
-- A mount is a vehicle the player owns, equips from the Mounts menu, and
-- summons with R. It is PURE TRAVERSAL: no damage, no combat interaction, no
-- stats. The old Rocket ability occupied this slot and was removed; R is free.
--
-- READ BY BOTH SIDES, like EncounterModes. The client draws the menu and
-- predicts the ride from this table; the server grants ownership and validates
-- every equip and summon against the same numbers. Sharing it is what stops the
-- menu from promising something the server will refuse.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MountDefinitions = {}

MountDefinitions.Order = { "FrankyBattleBike" }

-- Base walk speed a mount's SpeedMultiplier is measured against. Read from the
-- humanoid at mount time where possible; this is the fallback and the number
-- the menu quotes.
MountDefinitions.BaseWalkSpeed = 16

MountDefinitions.Data = {
	FrankyBattleBike = {
		id = "FrankyBattleBike",
		name = "Franky Battle Bike",
		blurb = "Cola-powered. Six times on foot, and it turns on a dime.",

		-- The model lives in ReplicatedStorage.Shared.MountModels under this name.
		model = "FrankyBattleBike",

		-- Icon for the Mounts menu row. Left empty until the art is uploaded; the
		-- row falls back to a silhouette rather than a broken image.
		icon = "",

		-- HANDLING. It drives like the character, not like a car: push a
		-- direction (camera-relative, same as walking) and it goes that way at
		-- full speed at once - no throttle, no acceleration, no coasting - and
		-- stops the moment you let go. Speed is a multiple of the rider's own
		-- walk speed, so a movement upgrade keeps the same relative gain.
		SpeedMultiplier = 6,

		-- How hard the body swings round to face where it is going. The bike
		-- MOVES in the new direction instantly; this is only how fast it turns
		-- to look that way. 18 is about a tenth of a second for a full 180.
		TurnResponsiveness = 18,

		LeanAngle = 22,            -- degrees the body rolls into a turn
		PitchSmoothing = 9,        -- how fast the bike settles onto a slope

		-- RIDE HEIGHT. Distance from the root to the ground; the drive loop
		-- raycasts down and holds the bike here rather than using suspension.
		RideHeight = 2.15,
		GroundProbe = 8,           -- how far down to look for ground
		MaxClimbAngle = 42,        -- degrees; steeper than this and it will not go

		-- Where the rider is put down when they get off.
		DismountOffset = Vector3.new(4.2, 1.5, 0),

		-- UNLOCK. Same shape as EncounterModes.Unlocks, and checked against the
		-- same profile.encounters table: the highest stage rank cleared per
		-- encounter. Pirate Shark on Impossible is rank 4.
		unlock = { encounter = "Arlong", difficulty = "Impossible" },
	},
}

function MountDefinitions.get(id: string?)
	return id and MountDefinitions.Data[id] or nil
end

function MountDefinitions.exists(id: any): boolean
	return type(id) == "string" and MountDefinitions.Data[id] ~= nil
end

-- Top speed in studs/sec for a given rider. Passing the humanoid's real walk
-- speed keeps the multiple honest when that changes.
function MountDefinitions.topSpeed(id: string, walkSpeed: number?): number
	local def = MountDefinitions.Data[id]
	if not def then return 0 end
	local base = walkSpeed
	if not base or base <= 0 then base = MountDefinitions.BaseWalkSpeed end
	return base * def.SpeedMultiplier
end

-- What a locked mount is waiting on, for the menu to explain itself.
function MountDefinitions.requirement(id: string)
	local def = MountDefinitions.Data[id]
	return def and def.unlock or nil
end

-- `clears` is profile.encounters: encounterId -> highest stage rank cleared.
-- Mirrors EncounterModes.isUnlocked so the two gates behave identically.
function MountDefinitions.isUnlocked(id: string, clears: { [string]: number }?): boolean
	local req = MountDefinitions.requirement(id)
	if not req then return true end
	local EncounterModes = require(ReplicatedStorage.Shared.Config.EncounterModes)
	local have = clears and clears[req.encounter] or 0
	return have >= EncounterModes.rank(req.difficulty)
end

-- Every mount the clear of `encounterId` at `difficulty` hands over. Used by the
-- encounter panel to advertise the reward before the fight, and by the server to
-- grant it after.
function MountDefinitions.grantedBy(encounterId: string, difficulty: string?): { string }
	local EncounterModes = require(ReplicatedStorage.Shared.Config.EncounterModes)
	local rank = EncounterModes.rank(difficulty)
	local out = {}
	for _, id in ipairs(MountDefinitions.Order) do
		local req = MountDefinitions.requirement(id)
		if req and req.encounter == encounterId and EncounterModes.rank(req.difficulty) == rank then
			table.insert(out, id)
		end
	end
	return out
end

return MountDefinitions
