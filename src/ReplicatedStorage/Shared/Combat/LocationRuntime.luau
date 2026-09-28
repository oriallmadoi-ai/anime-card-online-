--!strict
-- Executes location definitions on the server. BattleService only asks this
-- module to apply a trigger; it does not know Green Planet's mechanic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocationDefinitions = require(ReplicatedStorage.Shared.Config.LocationDefinitions)
local BattleRuntime = require(ReplicatedStorage.Shared.Combat.BattleRuntime)

local LocationRuntime = {}

local function push(events, eventType: string, data)
	data = data or {}
	data.type = eventType
	table.insert(events, data)
end

local EFFECTS = {}

EFFECTS.PercentMaxHPLoss = function(session, def, events)
	local effect = def.Effect
	local percent = math.clamp(effect.Percent or 0, 0, 1)

	if effect.Targets == "BothActive" then
		for _, sideName in ipairs({ "player", "enemy" }) do
			local side = sideName == "player" and session.player or session.enemy
			local card = side.active
			if card and card.alive then
				-- Intentional floor: combat uses integer HP everywhere else too.
				local amount = math.floor(card.maxHP * percent)
				if amount > 0 then
					BattleRuntime.LoseHP(session, card, amount, "location", events)
				end
			end
		end
	end
end

function LocationRuntime.Apply(session, trigger: string, events)
	local def = LocationDefinitions.get(session.locationId)
	if not def or def.Trigger ~= trigger then
		return false
	end

	if def.TriggerRound and session.round ~= def.TriggerRound then
		return false
	end

	session.locationFired = session.locationFired or {}
	local key = def.id .. ":" .. trigger
	if def.Once and session.locationFired[key] then
		return false
	end

	local handler = def.Effect and EFFECTS[def.Effect.Kind]
	if not handler then
		warn("[Location] no handler for " .. tostring(def.Effect and def.Effect.Kind))
		return false
	end

	if def.Once then
		session.locationFired[key] = true
	end

	push(events, "LocationActivate", {
		locationId = def.id,
		locationName = def.Name,
		description = def.Description,
	})

	handler(session, def, events)
	return true
end

return LocationRuntime
