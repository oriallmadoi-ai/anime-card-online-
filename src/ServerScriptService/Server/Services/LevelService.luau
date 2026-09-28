--!strict
-- Card levelling via Elder Essence.
--
-- Essence is consumed server-side and the level is written server-side. The
-- client only ever asks. Levelling directly raises combat stats, so a client
-- that could set its own level could set its own damage.
--
-- Overflow is refused rather than wasted: spending a 50-level vial on a card
-- three levels from its cap would silently burn it, so the request is rejected
-- and the player keeps the vial. Essence V is the deliberate exception - it
-- fills to whatever is left, so it can never be wasted and stays ahead of IV
-- on a part-levelled card.
--
-- THE CAP IS PER CARD, not global. Bosses run past 100 (Pirate Shark to 120),
-- so every check below asks CardDefinitions.maxLevel rather than reading
-- GameConfig.MaxCardLevel directly - otherwise a boss would be refused the
-- levels it is entitled to.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BookDefinitions = require(ReplicatedStorage.Shared.Config.BookDefinitions)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local LevelService = {}
LevelService.Name = "LevelService"

-- Kept named GrantBooks: profile.books is the save key these live under, and
-- DebugService already calls this. The item is Elder Essence now; the storage
-- is not renamed, for the reason BookDefinitions spells out.
function LevelService:GrantBooks(player: Player, bookId: string, count: number)
	local profile = self.Services.DataService:Get(player)
	if not profile or not BookDefinitions.get(bookId) then return false end
	profile.books = profile.books or {}
	profile.books[bookId] = (profile.books[bookId] or 0) + count
	self.Services.DataService:Sync(player)
	return true
end

-- Returns success, reason.
--
-- `count` is how many vials to pour in at once. It is CLAMPED, not trusted: the
-- client sends what its stepper showed, and this recomputes the legal maximum
-- from the profile and the card's own cap. A tampered client asking for 999
-- gets the same answer as one asking for what it could see.
function LevelService:UseBook(player: Player, cardId: string, variant: string,
	bookId: string, count: number?)
	local profile = self.Services.DataService:Get(player)
	if not profile then return false, "no profile" end

	-- Validate every part of the request against real definitions; never trust
	-- ids that arrived over a remote.
	local book = BookDefinitions.get(bookId)
	if not book then return false, "unknown book" end
	if not CardDefinitions.exists(cardId) then return false, "unknown card" end
	if not VariantConfig.Data[variant] then return false, "unknown variant" end

	profile.books = profile.books or {}
	local owned = profile.books[bookId] or 0
	if owned < 1 then return false, "you do not have that essence" end

	local key = CardStats.key(cardId, variant)
	local entry = profile.cards[key]
	if not entry then return false, "you do not own that card" end

	local cap = CardDefinitions.maxLevel(cardId)
	local current = entry.level or GameConfig.MinCardLevel
	if current >= cap then return false, "already max level" end

	local usable = BookDefinitions.maxUsable(bookId, current, cap, owned)
	if usable <= 0 then
		return false, ("%s would overflow (only %d levels needed)")
			:format(book.name or bookId, cap - current)
	end

	local want = math.floor(tonumber(count) or 1)
	if want < 1 then want = 1 end
	local spend = math.min(want, usable)

	local gain = book.toMax and (cap - current) or (book.levels * spend)
	if gain <= 0 then return false, "that essence would grant nothing" end

	profile.books[bookId] = owned - spend
	if profile.books[bookId] <= 0 then profile.books[bookId] = nil end
	entry.level = current + gain

	self.Services.DataService:Sync(player)
	return true, ("%s is now level %d/%d (spent %dx %s)")
		:format(cardId, entry.level, cap, spend, book.name or bookId)
end

function LevelService:Init()
	Remotes.RequestLevelUp.OnServerEvent:Connect(function(player, cardId, variant, bookId, count)
		if typeof(cardId) ~= "string" or typeof(variant) ~= "string" or typeof(bookId) ~= "string" then
			return
		end
		-- count is optional and arrives from the client, so anything that is not a
		-- sane number becomes 1 rather than being rejected outright - an older
		-- client that sends nothing still levels one vial's worth.
		if typeof(count) ~= "number" or count ~= count or count < 1 then count = 1 end
		local ok, reason = self:UseBook(player, cardId, variant, bookId, count)
		if not ok then
			warn(("[LevelService] %s: %s"):format(player.Name, tostring(reason)))
		end
	end)
end

return LevelService
