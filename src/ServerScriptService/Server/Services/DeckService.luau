--!strict
-- Owns the player's deck presets. The counts are GameConfig.DeckPresets
-- lineups of GameConfig.AttackSlots attack + GameConfig.SupportSlots support
-- slots - today 8 lineups of 5 and 5. They are named rather than written out
-- because this comment previously said 4 and 4 and had been wrong since the
-- slot counts changed.
--
-- A slot stores ONLY { cardId, variant }. The level is read live from the
-- inventory whenever the deck is used, so levelling a card immediately
-- strengthens the equipped copy instead of leaving a stale snapshot behind.
--
-- Everything is validated server-side against real ownership. A client that
-- could write its own deck could equip cards it never rolled, and the deck
-- feeds straight into combat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local DeckService = {}
DeckService.Name = "DeckService"

local function slotCount(slotType: string): number
	return slotType == "attack" and GameConfig.AttackSlots or GameConfig.SupportSlots
end

-- EVERY LINE-UP IS STORED DENSE: exactly slotCount entries, an empty slot
-- being `false` rather than nil.
--
-- A line-up with a hole in it is a SPARSE array, and sparse arrays do not
-- survive the trip anywhere. Sent through a RemoteEvent, { [1] = a, [3] = b }
-- arrives as just { a } - slot 3 silently gone - and { [2] = a } arrives with
-- the STRING key "2", which no `lineup[2]` lookup ever finds; a DataStore write
-- does the same to it. Both used to happen whenever a slot was cleared or a
-- copy moved out of one, which is how a deck could show up with cards
-- missing. `false` keeps every index occupied, so the array stays an array.
local function densify(list, n: number)
	local out = table.create(n, false)
	if type(list) == "table" then
		for key, slot in pairs(list) do
			local i = tonumber(key)
			if i and i % 1 == 0 and i >= 1 and i <= n and type(slot) == "table"
				and type(slot.cardId) == "string" and type(slot.variant) == "string" then
				out[i] = { cardId = slot.cardId, variant = slot.variant }
			end
		end
	end
	return out
end

-- Repairs the shape on demand: a profile that predates presets, one whose
-- active index points at a preset that no longer exists, or one whose line-ups
-- went sparse (see densify) still works.
local function decksOf(profile)
	profile.decks = profile.decks or { active = 1, presets = {} }
	local presets = profile.decks.presets or {}
	profile.decks.presets = presets
	for i = 1, GameConfig.DeckPresets do
		local preset = presets[i] or presets[tostring(i)] or {}
		presets[tostring(i)] = nil
		preset.attack = densify(preset.attack, GameConfig.AttackSlots)
		preset.support = densify(preset.support, GameConfig.SupportSlots)
		presets[i] = preset
	end
	local active = profile.decks.active
	if typeof(active) ~= "number" or active < 1 or active > GameConfig.DeckPresets then
		profile.decks.active = 1
	end
	return profile.decks
end

DeckService.densify = densify

function DeckService:ActivePreset(profile)
	local decks = decksOf(profile)
	return decks.presets[decks.active]
end

function DeckService:SetActive(player: Player, index: number)
	local profile = self.Services.DataService:Get(player)
	if not profile then return false, "no profile" end
	if typeof(index) ~= "number" or index % 1 ~= 0 then return false, "bad index" end
	if index < 1 or index > GameConfig.DeckPresets then return false, "preset out of range" end

	decksOf(profile).active = index
	self.Services.DataService:Sync(player)
	return true, "switched to deck " .. index
end

-- Returns ok, reason
function DeckService:Equip(player: Player, slotType: string, index: number, cardId: string?, variant: string?)
	local profile = self.Services.DataService:Get(player)
	if not profile then return false, "no profile" end

	if slotType ~= "attack" and slotType ~= "support" then return false, "bad slot type" end
	if typeof(index) ~= "number" or index % 1 ~= 0 then return false, "bad index" end
	if index < 1 or index > slotCount(slotType) then return false, "index out of range" end

	local preset = self:ActivePreset(profile)
	local lineup = preset[slotType]

	-- Clearing is always allowed. `false`, never nil - see densify.
	if cardId == nil then
		lineup[index] = false
		self.Services.DataService:Sync(player)
		return true, "cleared"
	end

	if typeof(cardId) ~= "string" or typeof(variant) ~= "string" then return false, "bad args" end
	if not VariantConfig.Data[variant] then return false, "unknown variant" end

	-- The card must go in the matching column: attack cards fight, supports
	-- assist from off-field, and they are not interchangeable.
	local isSupport = SupportDefinitions.get(cardId) ~= nil
	local isAttack = CardDefinitions.get(cardId) ~= nil
	if slotType == "attack" and not isAttack then return false, "that is not an attack card" end
	if slotType == "support" and not isSupport then return false, "that is not a support card" end

	-- Ownership checked against the real inventory, never trusted from the client.
	local entry = profile.cards[CardStats.key(cardId, variant)]
	if not entry or (entry.count or 0) < 1 then return false, "you do not own that copy" end

	local current = lineup[index]
	if current and current.cardId == cardId and current.variant == variant then
		return true, "already there"
	end

	-- DUPLICATES: one copy can fill several slots, as many as you OWN of it.
	-- Five Franky copies can be five Frankys; one copy is one slot. Once every
	-- owned copy is placed, putting it somewhere else MOVES the copy there from
	-- the highest slot holding it - the same rule the client predicts with, so
	-- the line-up it draws before the sync lands is the one that comes back.
	local owned = entry.count or 0
	local used = 0
	for i = 1, slotCount(slotType) do
		local slot = lineup[i]
		if i ~= index and slot and slot.cardId == cardId and slot.variant == variant then
			used += 1
		end
	end
	if used >= owned then
		for i = slotCount(slotType), 1, -1 do
			local slot = lineup[i]
			if i ~= index and slot and slot.cardId == cardId and slot.variant == variant then
				lineup[i] = false
				break
			end
		end
	end

	lineup[index] = { cardId = cardId, variant = variant }
	self.Services.DataService:Sync(player)
	return true, "equipped"
end

-- Builds the active lineup in the shape CombatEngine expects, resolving levels live.
function DeckService:BuildCombatDeck(player: Player)
	local profile = self.Services.DataService:Get(player)
	if not profile then return nil end
	local preset = self:ActivePreset(profile)

	local out = { attack = {}, support = {} }
	for _, slotType in ipairs({ "attack", "support" }) do
		for i = 1, slotCount(slotType) do
			local slot = preset[slotType] and preset[slotType][i]
			if slot then
				local entry = profile.cards[CardStats.key(slot.cardId, slot.variant)]
				out[slotType][i] = {
					cardId = slot.cardId,
					variant = slot.variant,
					level = entry and entry.level or GameConfig.MinCardLevel,
				}
			end
		end
	end
	return out
end

function DeckService:IsEmpty(player: Player): boolean
	local deck = self:BuildCombatDeck(player)
	if not deck then return true end
	for _ in pairs(deck.attack) do return false end
	return true
end

function DeckService:Init()
	Remotes.RequestSetDeck.OnServerEvent:Connect(function(player, slotType, index, cardId, variant)
		local ok, reason = self:Equip(player, slotType, index, cardId, variant)
		if not ok then
			warn(("[DeckService] %s: %s"):format(player.Name, tostring(reason)))
		end
	end)

	Remotes.RequestSetActiveDeck.OnServerEvent:Connect(function(player, index)
		local ok, reason = self:SetActive(player, index)
		if not ok then
			warn(("[DeckService] %s: %s"):format(player.Name, tostring(reason)))
		end
	end)
end

return DeckService
