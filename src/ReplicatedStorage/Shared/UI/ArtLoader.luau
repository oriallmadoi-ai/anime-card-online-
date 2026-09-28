--!strict
-- Anime Card Online - resilient artwork assignment.
--
-- ReplicatedStorage > Shared > UI > ArtLoader
--
-- WHY THIS EXISTS
--
-- Every card art id in the game is valid and owned; a sweep of all 69 image
-- assets referenced by Shared.Config found none that are permanently broken.
-- What actually happens is that the FIRST fetch of a cold asset sometimes
-- fails, and an ImageLabel whose fetch failed stays blank forever - Roblox
-- does not retry on its own, and nothing in the game re-assigned the property.
-- That is why the missing pictures moved around: it was never the same cards
-- twice, it was whichever ones lost the race on that session's cold cache.
--
-- Two defences, in order of importance:
--   1. warm() downloads the whole art set once at boot, off the critical path,
--      so by the time a grid or a battle board is drawn the cache is hot.
--   2. set() watches each assignment and, if the asset has not been confirmed
--      downloaded this session, retries with backoff and re-assigns the label
--      once the bytes are actually there.
--
-- Cost is bounded: each asset is probed at most once per session (the result
-- is cached in `verified`), and every label sharing that asset is repaired by
-- the single probe rather than starting one of its own.

local ContentProvider = game:GetService("ContentProvider")

local ArtLoader = {}

-- Backoff between retries. The first one is quick because most cold-cache
-- failures clear immediately; the long tail covers a genuinely slow CDN.
local RETRY_DELAYS = { 0.4, 1.2, 3, 7, 15 }

-- Assets confirmed downloaded during this session. Never re-probed.
local verified: { [string]: boolean } = {}
-- Assets with a probe in flight, mapped to the labels waiting on them.
local waiting: { [string]: { ImageLabel } } = {}

-- Fetches through a throwaway label so the caller's label is never blanked by
-- the probe itself. Returns true only on a confirmed Success.
local function probe(assetId: string): boolean
	local scratch = Instance.new("ImageLabel")
	scratch.Image = assetId
	local ok = false
	local ran = pcall(function()
		ContentProvider:PreloadAsync({ scratch }, function(_, status)
			ok = status == Enum.AssetFetchStatus.Success
		end)
	end)
	scratch:Destroy()
	return ran and ok
end

local function ensure(assetId: string)
	if verified[assetId] or waiting[assetId] then
		return
	end
	waiting[assetId] = {}

	task.spawn(function()
		for attempt = 0, #RETRY_DELAYS do
			if attempt > 0 then
				task.wait(RETRY_DELAYS[attempt])
			end

			if probe(assetId) then
				verified[assetId] = true
				local labels = waiting[assetId] or {}
				waiting[assetId] = nil
				-- A label whose own fetch failed while the asset was cold will not
				-- redraw by itself. Re-assigning the property makes it read the
				-- bytes that are now cached.
				for _, label in ipairs(labels) do
					if label.Parent and label.Image == assetId and not label.IsLoaded then
						label.Image = ""
						label.Image = assetId
					end
				end
				return
			end
		end

		waiting[assetId] = nil
		warn(("[ArtLoader] %s did not resolve after %d attempts")
			:format(assetId, #RETRY_DELAYS + 1))
	end)
end

-- Assign artwork to a label. Use this instead of writing `.Image` directly
-- anywhere the asset comes from a definition table.
function ArtLoader.set(label: ImageLabel, assetId: string?)
	if not assetId or assetId == "" then
		label.Image = ""
		return
	end

	label.Image = assetId
	if verified[assetId] then
		return
	end

	ensure(assetId)
	local queue = waiting[assetId]
	if queue then
		table.insert(queue, label)
	end
end

-- Download a set of assets ahead of time. Call this in a spawned thread: it
-- yields until every asset resolves or gives up.
function ArtLoader.warm(assetIds: { string })
	local scratch = Instance.new("Folder")
	local objects = {}
	local byContent: { [string]: string } = {}

	for _, assetId in ipairs(assetIds) do
		if assetId ~= "" and not verified[assetId] then
			local label = Instance.new("ImageLabel")
			label.Image = assetId
			label.Parent = scratch
			table.insert(objects, label)
			byContent[assetId] = assetId
		end
	end

	if #objects == 0 then
		scratch:Destroy()
		return
	end

	local failed: { string } = {}
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(objects, function(contentId, status)
			local assetId = byContent[contentId] or contentId
			if status == Enum.AssetFetchStatus.Success then
				verified[assetId] = true
			else
				table.insert(failed, assetId)
			end
		end)
	end)
	scratch:Destroy()

	if not ok then
		warn(("[ArtLoader] warm failed: %s"):format(tostring(err)))
		return
	end

	-- Anything that lost the cold-cache race gets the same retry treatment a
	-- live label would get, so it is hot before a player ever opens the tab.
	for _, assetId in ipairs(failed) do
		ensure(assetId)
	end
end

-- Every artwork id referenced by the card and support tables, which is what a
-- collection grid, a deck slot and a battle board all draw from.
function ArtLoader.cardArtIds(): { string }
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}

	local function collect(moduleName: string)
		local moduleScript = ReplicatedStorage.Shared.Config:FindFirstChild(moduleName)
		if not moduleScript then
			return
		end
		local ok, defs = pcall(require, moduleScript)
		if not ok or type(defs) ~= "table" then
			return
		end
		-- Both definition tables expose their entries as `.Data`.
		local list = defs.Data
		if type(list) ~= "table" then
			return
		end
		for _, def in pairs(list) do
			if type(def) == "table" and type(def.art) == "string" and def.art ~= "" and not seen[def.art] then
				seen[def.art] = true
				table.insert(ids, def.art)
			end
		end
	end

	collect("CardDefinitions")
	collect("SupportDefinitions")
	return ids
end

return ArtLoader
