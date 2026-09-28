--!strict
-- Anime Card Online
-- Redeem codes: the REDEEM A CODE box in the Store header calls
-- Remotes.RedeemCode, which lands here. The code list is CodeConfig (server
-- only). A code is marked as used BEFORE its rewards are paid, so double
-- clicks or a spammed remote can never pay twice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)
local CodeConfig = require(script.Parent.Parent.CodeConfig)

local CodeService = {}
CodeService.Name = "CodeService"

local COOLDOWN = 1 -- seconds between attempts, per player
local MAX_LENGTH = 40

local lastAttempt: { [Player]: number } = {}

local function short(n: number): string
	if n >= 1e6 and n % 1e5 == 0 then return ("%gM"):format(n / 1e6) end
	if n >= 1e3 and n % 100 == 0 then return ("%gK"):format(n / 1e3) end
	return tostring(n)
end

-- One line for the input box, e.g. "+4 CORES · +1 WRENCH · +500K COINS".
local function summarise(entry): string
	local parts = {}
	for _, pair in ipairs(entry.cores or {}) do
		table.insert(parts, ("+%d CORE%s"):format(pair[2], pair[2] == 1 and "" or "S"))
	end
	for _, pair in ipairs(entry.items or {}) do
		local item = SummonCoreConfig.item(pair[1])
		local name = item and item.name or pair[1]
		name = string.upper((name:gsub("^Elder%s+", "")))
		table.insert(parts, ("+%d %s%s"):format(pair[2], name, pair[2] == 1 and "" or "S"))
	end
	if entry.coins and entry.coins > 0 then
		table.insert(parts, "+" .. short(entry.coins) .. " COINS")
	end
	return table.concat(parts, " \u{00B7} ")
end

local function give(service, method: string, player: Player, id: string, count: number)
	local left = math.max(0, math.floor(count))
	while left > 0 do
		local n = math.min(left, SummonCoreConfig.DevGiveMax)
		local ok, message = service[method](service, player, id, n)
		if not ok then warn(("[Codes] %s %s x%d failed: %s"):format(method, id, n, tostring(message))) end
		left -= n
	end
end

function CodeService:Redeem(player: Player, raw: any)
	if type(raw) ~= "string" or #raw == 0 or #raw > MAX_LENGTH then
		return { ok = false, status = "invalid" }
	end
	local now = os.clock()
	if lastAttempt[player] and now - lastAttempt[player] < COOLDOWN then
		return { ok = false, status = "busy" }
	end
	lastAttempt[player] = now

	local code = (raw:gsub("^%s+", ""):gsub("%s+$", "")) -- case is kept: codes are exact
	local entry = CodeConfig.Codes[code]
	if not entry or entry.disabled or (entry.expires and os.time() > entry.expires) then
		return { ok = false, status = "invalid" }
	end

	local DataService = self.Services.DataService
	local profile = DataService:Get(player)
	if not profile then
		return { ok = false, status = "busy" }
	end
	profile.redeemedCodes = profile.redeemedCodes or {}
	if profile.redeemedCodes[code] then
		return { ok = false, status = "used" }
	end
	profile.redeemedCodes[code] = os.time()

	local cores = self.Services.SummonCoreService
	for _, pair in ipairs(entry.cores or {}) do
		give(cores, "Give", player, pair[1], pair[2])
	end
	for _, pair in ipairs(entry.items or {}) do
		give(cores, "GiveItem", player, pair[1], pair[2])
	end
	if entry.coins and entry.coins > 0 then
		profile.currency = profile.currency or {}
		profile.currency.elderCoins = (profile.currency.elderCoins or 0) + math.floor(entry.coins)
	end
	DataService:Sync(player)

	print(("[Codes] %s redeemed %s"):format(player.Name, code))
	return { ok = true, status = "claimed", summary = summarise(entry) }
end

function CodeService:Init()
	Remotes.RedeemCode.OnServerInvoke = function(player: Player, code: any)
		local ok, result = pcall(self.Redeem, self, player, code)
		if ok then return result end
		warn("[Codes] " .. tostring(result))
		return { ok = false, status = "error" }
	end
	Players.PlayerRemoving:Connect(function(player)
		lastAttempt[player] = nil
	end)
end

return CodeService
