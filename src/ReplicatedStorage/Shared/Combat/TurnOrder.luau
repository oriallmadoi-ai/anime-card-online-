--!strict
-- Shared initiative for the live battle and the odds simulator.
local PassiveDefinitions = require(script.Parent.Parent.Config.PassiveDefinitions)
local TurnOrder = {}

local function baseTeam(match)
 local fallen = match.initiativeDefeats or {}
 if fallen.player and not fallen.enemy then return "player" end
 if fallen.enemy and not fallen.player then return "enemy" end
 -- A simultaneous knockout keeps the previous priority; new battles start player-first.
 return match.initiativeTeam or "player"
end

local function hasPriority(card)
 if not card or not card.alive or card.hp <= 0 then return false end
 for _, id in ipairs(card.passives or {}) do
  local passive = PassiveDefinitions.get(id)
  if passive and passive.alwaysFirst then return true end
 end
 return false
end

function TurnOrder.recordDefeat(match, team)
 match.initiativeDefeats = match.initiativeDefeats or {}
 match.initiativeDefeats[team] = true
end

function TurnOrder.peek(match, playerCard, enemyCard)
 local normal = baseTeam(match)
 local playerPriority, enemyPriority = hasPriority(playerCard), hasPriority(enemyCard)
 if playerPriority ~= enemyPriority then
  return playerPriority and "player" or "enemy", "Geass"
 end
 return normal, (playerPriority and enemyPriority) and "GeassTie" or "Normal"
end

function TurnOrder.beginRound(match, playerCard, enemyCard)
 match.initiativeTeam = baseTeam(match)
 match.initiativeDefeats = nil
 return TurnOrder.peek(match, playerCard, enemyCard)
end

return TurnOrder
