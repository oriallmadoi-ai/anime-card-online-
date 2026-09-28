--!strict
-- Server-authoritative skill tree.
--
-- THE CLIENT SENDS A SKILL ID. That is the entire payload. It never sends a
-- cost, a rank, an effect or a coin balance, so there is nothing in the request
-- worth forging - the worst a modified client can do is ask to buy a skill it
-- cannot afford, and be told no.
--
-- HOW EFFECTS REACH THE GAME
-- Not through hooks scattered across other services. The tree recomputes a small
-- stat table from the player's ranks and writes the two values RollService
-- already reads into `profile.upgrades`. RollService and UIController are
-- therefore COMPLETELY UNCHANGED by the skill tree - they keep reading the field
-- they always read, and it simply has a real number in it now.
--
-- Battle stats (DMG, HP, crit) cannot work that way because they are per-card,
-- so BattleService asks this service for them when it builds a deck.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local SkillDefinitions = require(ReplicatedStorage.Shared.Config.SkillDefinitions)
local SkillEffects = require(ReplicatedStorage.Shared.Config.SkillEffects)
local SkillRemotes = require(ReplicatedStorage.Shared.Net.SkillRemotes)

local SkillTreeService = {}
SkillTreeService.Name = "SkillTreeService"

-- One purchase per player per this many seconds. A RemoteFunction invoked in a
-- tight loop would otherwise run the full validate-and-save path as fast as the
-- network allows; every call is cheap, but the DataStore write behind Sync is
-- not. This is a throttle, not a security boundary - the validation is.
local PURCHASE_COOLDOWN = 0.15
local lastPurchase: { [Player]: number } = {}

local function ranksOf(profile)
	return (profile and profile.skills) or {}
end

----------------------------------------------------------------------
-- READING
----------------------------------------------------------------------

-- The player's full derived stat table. Computed through the SHARED registry, so
-- it is the same maths the client uses to preview a purchase.
function SkillTreeService:Totals(player: Player)
	local profile = self.Services.DataService:Get(player)
	return SkillEffects.Totals(SkillDefinitions, ranksOf(profile))
end

-- One stat, with the registry's identity value as the fallback. Callers outside
-- this service should use this rather than reading the totals table directly, so
-- a missing profile yields "no bonus" instead of nil arithmetic.
function SkillTreeService:GetStat(player: Player, stat: string): number
	local totals = self:Totals(player)
	if totals[stat] ~= nil then
		return totals[stat]
	end
	for _, effect in pairs(SkillEffects.Registry) do
		if effect.stat == stat then
			return effect.base
		end
	end
	return 0
end

function SkillTreeService:Coins(player: Player): number
	local profile = self.Services.DataService:Get(player)
	return (profile and profile.currency and profile.currency.elderCoins) or 0
end

----------------------------------------------------------------------
-- APPLYING
----------------------------------------------------------------------

-- Writes the derived stats into the fields the rest of the game already reads.
--
-- RollService computes luck as `1 + upgrades.luck * LuckPerLevel`, so to express
-- a total multiplier M the stored level is (M - 1) / LuckPerLevel. It is a
-- fractional "level", which is fine - nothing rounds it - and it means the skill
-- tree speaks RollService's units instead of RollService learning the tree's.
function SkillTreeService:Recompute(player: Player)
	local profile = self.Services.DataService:Get(player)
	if not profile then
		return
	end

	local totals = SkillEffects.Totals(SkillDefinitions, ranksOf(profile))
	profile.upgrades = profile.upgrades or {}

	-- RollService reads luck as `1 + upgrades.luck * LuckPerLevel`, so the stored
	-- "level" is whatever produces the multiplier the tree adds up to.
	--
	-- Two sources feed it and they combine differently: luckMultiplier is a
	-- proportional bonus (1.10 = +10%), while luckFlat is an absolute number added
	-- straight on (+0.25 per Luck Boost rank). Converting the pair once here is
	-- what lets RollService stay completely unaware of any of it.
	local luckMultiplier = totals.luckMultiplier or 1
	local luckFlat = totals.luckFlat or 0
	profile.upgrades.luck = ((luckMultiplier - 1) + luckFlat) / GameConfig.LuckPerLevel

	-- Clamped BEFORE the division, so the cap stays expressed in the units it is
	-- written in. A reduction of 1.0 would otherwise produce a zero or negative
	-- cooldown before RollService's own floor is ever consulted.
	local reduction = math.clamp(
		totals.rollSpeedReduction or 0,
		0,
		GameConfig.MaxSkillRollSpeedReduction
	)
	profile.upgrades.rollSpeed = reduction / GameConfig.RollSpeedPerLevel

	-- Kept for symmetry and for anything that later wants a flat read; battle
	-- damage is actually applied per-card by BattleService via GetStat.
	profile.upgrades.damage = (totals.damageMultiplier or 1) - 1
end

----------------------------------------------------------------------
-- EARNING
----------------------------------------------------------------------

-- Awarded on a battle WIN. The coin multiplier from the tree is applied here, so
-- CoinGain skills compound the reward that funds the tree itself.
function SkillTreeService:GrantCoins(player: Player, amount: number, reason: string?)
	local profile = self.Services.DataService:Get(player)
	if not profile or amount <= 0 then
		return 0
	end

	local multiplier = self:GetStat(player, "coinMultiplier")
	local granted = math.max(1, math.floor(amount * multiplier))

	profile.currency = profile.currency or {}
	profile.currency.elderCoins = (profile.currency.elderCoins or 0) + granted

	self.Services.DataService:Sync(player)
	SkillRemotes.Result:FireClient(player, {
		type = "Coins",
		amount = granted,
		total = profile.currency.elderCoins,
		reason = reason or "victory",
	})
	return granted
end

----------------------------------------------------------------------
-- PURCHASING
----------------------------------------------------------------------

-- Returns ok, reason. Every branch below is a thing a modified client WILL try.
--
-- `deferSync` exists purely for PurchaseMax: recomputing and replicating the
-- whole profile after EVERY rank would mean up to 3000 remote fires and 3000
-- dirty-save marks for one button press. The caller passes true and syncs once
-- at the end instead. Nothing else should use it - a purchase the client never
-- hears about is a purchase the UI cannot draw.
function SkillTreeService:Purchase(player: Player, skillId: any, deferSync: boolean?)
	-- Type check first. A table or nil arriving here would otherwise reach the
	-- definitions lookup and index something that is not a string.
	if typeof(skillId) ~= "string" then
		return false, "invalid request"
	end

	local profile = self.Services.DataService:Get(player)
	if not profile then
		return false, "your save is not loaded yet"
	end

	local def = SkillDefinitions.get(skillId)
	if not def then
		return false, "unknown skill"
	end

	profile.skills = profile.skills or {}
	local current = profile.skills[skillId] or 0

	if current >= def.MaxRank then
		return false, "already at max rank"
	end

	-- Prerequisites, INCLUDING the required rank - "owns it at all" is not the
	-- same test as "owns it at rank 2", and several nodes rely on the difference.
	--
	-- EVERY unmet requirement is collected and the list is sorted, rather than
	-- returning at the first failure found. Requirements is a hash table, so
	-- pairs() visits it in arbitrary order: bailing early would name a DIFFERENT
	-- missing prerequisite on each attempt, which reads as a broken tree to the
	-- player and makes the message untestable. Sorting also means the capstone
	-- tells you all three things you still need, not one of them at random.
	local missing = {}
	for reqId, reqRank in pairs(def.Requirements or {}) do
		if (profile.skills[reqId] or 0) < reqRank then
			local reqDef = SkillDefinitions.get(reqId)
			table.insert(missing, {
				id = reqId,
				text = ("%s rank %d"):format(reqDef and reqDef.Name or reqId, reqRank),
			})
		end
	end

	if #missing > 0 then
		table.sort(missing, function(a, b) return a.id < b.id end)
		local parts = {}
		for _, entry in ipairs(missing) do
			table.insert(parts, entry.text)
		end
		return false, "requires " .. table.concat(parts, ", ")
	end

	local cost = def.Cost(current + 1)
	if type(cost) ~= "number" then
		-- SkillDefinitions probes both ends of every curve at require time, so this
		-- is belt and braces - but a nil cost comparing as free would be the worst
		-- possible failure, so it is refused explicitly.
		return false, "that rank has no cost defined"
	end

	profile.currency = profile.currency or {}
	local coins = profile.currency.elderCoins or 0
	if coins < cost then
		return false, ("needs %d Elder Coins, you have %d"):format(cost, coins)
	end

	-- Everything validated; commit. Track the EXACT price actually paid so Reset
	-- can refund correctly even after future balance changes.
	profile.currency.elderCoins = coins - cost
	profile.skills[skillId] = current + 1
	profile.skillTreeSpent = math.max(0, profile.skillTreeSpent or 0) + cost

	if not deferSync then
		self:Recompute(player)
		self.Services.DataService:Sync(player)
	end

	return true, ("%s is now rank %d/%d"):format(def.Name, current + 1, def.MaxRank)
end

-- Buys as many ranks of one skill as the player can afford, in a single call.
--
-- The loop re-runs the FULL Purchase check every iteration rather than
-- calculating how many ranks the balance covers and granting them in one go.
-- That is deliberate: Purchase is the only place the rules live, so max-buying
-- cannot drift from single-buying, and a prerequisite or max-rank boundary is
-- respected mid-run. The iteration cap is a safety net against a future cost
-- curve that returns zero and would otherwise spin forever.
function SkillTreeService:PurchaseMax(player: Player, skillId: any)
	if typeof(skillId) ~= "string" then
		return false, "invalid request"
	end

	local def = SkillDefinitions.get(skillId)
	if not def then
		return false, "unknown skill"
	end

	local bought = 0
	local lastReason = nil

	for _ = 1, def.MaxRank do
		local ok, reason = self:Purchase(player, skillId, true)
		if not ok then
			lastReason = reason
			break
		end
		bought += 1
	end

	if bought == 0 then
		return false, lastReason or "could not buy any ranks"
	end

	-- One recompute and one replication for the whole run.
	self:Recompute(player)
	self.Services.DataService:Sync(player)

	local profile = self.Services.DataService:Get(player)
	local rank = profile and (profile.skills[skillId] or 0) or 0
	return true, ("%s +%d ranks, now %d/%d"):format(def.Name, bought, rank, def.MaxRank)
end

-- Buys EXACTLY `amount` ranks of one skill, or none at all - the panel's
-- amount picker. A request for more ranks than are left is trimmed to what is
-- left; a request the balance cannot cover buys nothing, rather than some
-- arbitrary part of what was asked for.
--
-- Like PurchaseMax, every rank still goes through Purchase, so the rules live
-- in one place. The whole run is priced first only so a short balance is
-- refused up front instead of stopping part-way.
function SkillTreeService:PurchaseAmount(player: Player, skillId: any, amount: any)
	if typeof(skillId) ~= "string" then
		return false, "invalid request"
	end
	-- A whole number of at least one. NaN fails `amount == amount`.
	if typeof(amount) ~= "number" or amount ~= amount or amount < 1 or amount % 1 ~= 0 then
		return false, "invalid amount"
	end

	local def = SkillDefinitions.get(skillId)
	if not def then
		return false, "unknown skill"
	end

	local profile = self.Services.DataService:Get(player)
	if not profile then
		return false, "your save is not loaded yet"
	end

	local current = (profile.skills and profile.skills[skillId]) or 0
	if current >= def.MaxRank then
		return false, "already at max rank"
	end
	amount = math.min(amount, def.MaxRank - current)

	-- An unmet prerequisite is Purchase's refusal to word (it lists every
	-- missing one). It fails before touching anything, so asking it is free.
	for reqId, reqRank in pairs(def.Requirements or {}) do
		if ((profile.skills and profile.skills[reqId]) or 0) < reqRank then
			return self:Purchase(player, skillId, true)
		end
	end

	local total = 0
	for rank = current + 1, current + amount do
		local cost = def.Cost(rank)
		if type(cost) ~= "number" then
			return false, "that rank has no cost defined"
		end
		total += cost
	end
	local coins = (profile.currency and profile.currency.elderCoins) or 0
	if coins < total then
		return false, ("needs %d Elder Coins, you have %d"):format(total, coins)
	end

	local bought = 0
	local lastReason = nil
	for _ = 1, amount do
		local ok, reason = self:Purchase(player, skillId, true)
		if not ok then
			lastReason = reason
			break
		end
		bought += 1
	end

	if bought == 0 then
		return false, lastReason or "could not buy any ranks"
	end

	-- One recompute and one replication for the whole run.
	self:Recompute(player)
	self.Services.DataService:Sync(player)

	local rank = profile.skills[skillId] or 0
	if bought == 1 then
		return true, ("%s is now rank %d/%d"):format(def.Name, rank, def.MaxRank)
	end
	return true, ("%s +%d ranks, now %d/%d"):format(def.Name, bought, rank, def.MaxRank)
end

-- Wipes every rank and hands back every Elder Coin ACTUALLY spent.
--
-- We store exact spend instead of recomputing from today's cost curves. That is
-- essential now that the tree is being rebalanced: a player who bought ranks at
-- old prices must not receive the new, much larger prices as a refund.
function SkillTreeService:Reset(player: Player)
	local profile = self.Services.DataService:Get(player)
	if not profile then
		return false, "your save is not loaded yet"
	end

	profile.skills = profile.skills or {}

	local hasSkills = false
	for _, rank in pairs(profile.skills) do
		if type(rank) == "number" and rank > 0 then
			hasSkills = true
			break
		end
	end

	if not hasSkills then
		return false, "you have no skills to reset"
	end

	local refund = math.max(0, math.floor(profile.skillTreeSpent or 0))

	profile.skills = {}
	profile.skillTreeSpent = 0
	profile.currency = profile.currency or {}
	profile.currency.elderCoins = (profile.currency.elderCoins or 0) + refund

	self:Recompute(player)
	self.Services.DataService:Sync(player)

	return true, ("Skill tree reset. %d Elder Coins refunded."):format(refund)
end

----------------------------------------------------------------------
-- LIFECYCLE
----------------------------------------------------------------------

function SkillTreeService:Init()
	local HANDLERS = {
		Purchase = function(p, payload) return self:Purchase(p, payload) end,
		PurchaseMax = function(p, payload) return self:PurchaseMax(p, payload) end,
		PurchaseAmount = function(p, payload, amount) return self:PurchaseAmount(p, payload, amount) end,
		Reset = function(p) return self:Reset(p) end,
	}

	SkillRemotes.Action.OnServerInvoke = function(player: Player, action: any, payload: any, amount: any)
		local handler = typeof(action) == "string" and HANDLERS[action]
		if not handler then
			return false, "unknown action"
		end

		local now = os.clock()
		if lastPurchase[player] and (now - lastPurchase[player]) < PURCHASE_COOLDOWN then
			return false, "slow down"
		end
		lastPurchase[player] = now

		-- pcall so a malformed payload can never take down the remote handler and
		-- leave every later purchase silently unanswered.
		local ok, result, reason = pcall(function()
			return handler(player, payload, amount)
		end)
		if not ok then
			warn(("[SkillTreeService] purchase error for %s: %s"):format(player.Name, tostring(result)))
			return false, "something went wrong"
		end
		return result, reason
	end

	Players.PlayerRemoving:Connect(function(player)
		lastPurchase[player] = nil
	end)
end

function SkillTreeService:Start()
	-- Derived stats have to exist before the player's first roll, so recompute as
	-- soon as the profile lands. Await yields, which is why this is in Start:
	-- Bootstrap runs every Init sequentially on ONE thread, so yielding there
	-- would stall every service queued behind this one.
	local function onJoin(player: Player)
		task.spawn(function()
			if self.Services.DataService:Await(player, 20) then
				self:Recompute(player)
				self.Services.DataService:Sync(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(onJoin)
	for _, player in ipairs(Players:GetPlayers()) do
		onJoin(player)
	end

	print(("[SkillTreeService] online - %d skills"):format(#SkillDefinitions.Order))
end

return SkillTreeService
