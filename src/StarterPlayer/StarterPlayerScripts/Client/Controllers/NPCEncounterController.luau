--!strict
-- The Arlong Park encounter panel: pick a stage, see who you will face, fight.
--
-- The world card carries only a card id on its prompt; everything below is
-- client presentation built from shared config. The panel can therefore show a
-- lineup and a stat multiplier without any new remote - EncounterModes is the
-- same table BattleService builds the real fight from, so the preview cannot
-- drift from what actually spawns.
--
-- THE ACCENT IS THE DIFFICULTY. Every coloured thing in this panel - frame,
-- glow, tab, button, stat figures - reads from the selected stage's accent, so
-- switching stage repaints the whole window. That is the main feedback that a
-- selection happened, which matters more here than any animation.
--
-- WHAT THE PANEL CANNOT DO. It sends a card id and a difficulty NAME. The
-- lineup it draws is advisory; the server re-derives the real one. Nothing here
-- is trusted.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local SupportDefinitions = require(ReplicatedStorage.Shared.Config.SupportDefinitions)
local EncounterModes = require(ReplicatedStorage.Shared.Config.EncounterModes)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local ElderCoin = require(ReplicatedStorage.Shared.UI.ElderCoin)
local RarityBands = require(ReplicatedStorage.Shared.Config.RarityBands)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local ArtLoader = require(ReplicatedStorage.Shared.UI.ArtLoader)
local MountDefinitions = require(ReplicatedStorage.Shared.Config.MountDefinitions)
local UITheme = require(ReplicatedStorage.Shared.UI.UITheme)
local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)
local EncounterController = {}
EncounterController.Name = "NPCEncounterController"

local player = Players.LocalPlayer

-- Grown to fit two reward rows. The card grew with it rather than leaving a
-- taller panel with the same small card floating in it.
-- 668, not 648: the footer hint is anchored to the bottom edge, and at 648 it
-- sat on top of the fight button.
local PANEL_W, PANEL_H = 820, 668
local CARD_W = 244
local TAB_H = 38
local REWARD_H = 76

local C = {
	Ink    = Color3.fromRGB(5, 5, 9),
	Panel  = Color3.fromRGB(11, 11, 17),
	Raised = Color3.fromRGB(19, 19, 28),
	Line   = Color3.fromRGB(44, 44, 60),
	-- One text colour across every menu, from UITheme. See MenuController.
	Text   = UITheme.Text,
	Muted  = UITheme.TextMuted,
	Bad    = Color3.fromRGB(255, 96, 112),
}

local gui: ScreenGui
local dim: TextButton
local panel: CanvasGroup
local panelScale: UIScale
local panelStroke: UIStroke
local glowImage: ImageLabel
local eyebrow: TextLabel
local title: TextLabel
local subtitle: TextLabel
local cardHost: Frame
local card: any
local tabButtons: { any } = {}
local statsLabel: TextLabel
local lineupRow: Frame
local lineupSlots: { any } = {}
local firstRow: Frame
local repeatRow: Frame
local firstSlots: { any } = {}
local repeatSlots: { any } = {}
local repeatLabel: TextLabel? = nil
-- Summon Core drops: one wide tile standing in for repeat slots 2 and 3.
local dropsTile: any = nil
local fightButton: TextButton
local fightLabel: TextLabel
local statusLabel: TextLabel
local headerAccent: Frame
local stageProgress: TextLabel
local stageSegments: { Frame } = {}

local currentCardId: string? = nil
local currentNpc: Model? = nil
local currentDifficulty: string = "Easy"
local openToken = 0
local starting = false

-- The prompt that opened the panel. It is switched OFF for as long as the panel
-- is up, which is what frees the E key to mean "fight" instead of re-triggering
-- the prompt underneath and resetting the panel back to Easy.
local activePrompt: ProximityPrompt? = nil

local beginFight: () -> ()

-- profile.encounters, replicated by DataService:Sync. Used only to say whether a
-- stage's unlock has already been earned; nothing here is authoritative.
local clears: { [string]: number } = {}
-- Which mounts the player already owns, so an earned mount reads as UNLOCKED on
-- the reward row instead of dangling as a prize they have already claimed.
local ownedMounts: { [string]: boolean } = {}

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for key, value in pairs(props) do
		if key ~= "Parent" then (inst :: any)[key] = value end
	end
	if children then
		for _, child in ipairs(children) do child.Parent = inst end
	end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(radius: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color: Color3, thickness: number, transparency: number?): UIStroke
	return new("UIStroke", {
		Color = color, Thickness = thickness, Transparency = transparency or 0,
	})
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local d = {
		Parent = parent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = Theme.font(),
		TextColor3 = C.Text,
		TextSize = 15,
	}
	for k, v in pairs(props) do d[k] = v end
	return new("TextLabel", d)
end

local function viewportScale(): number
	if not gui then return 1 end
	local size = gui.AbsoluteSize
	if size.X < 10 or size.Y < 10 then return 1 end
	return math.max(0.1, math.min(1, (size.X - 32) / PANEL_W, (size.Y - 32) / PANEL_H))
end

local function defOf(cardId: string)
	return CardDefinitions.get(cardId) or SupportDefinitions.get(cardId)
end

-- The same rule CardRenderer uses, so a thumbnail's edge matches the border the
-- real card would wear.
local function rarityColour(cardId: string): Color3
	local d = defOf(cardId)
	if not d then return C.Line end
	return RarityBands.forDenominator(d.baseRarity).color
end

----------------------------------------------------------------
-- REPAINT
----------------------------------------------------------------

local function stageOpen(id: string): boolean
	return currentCardId ~= nil
		and EncounterModes.isStageUnlocked(currentCardId, id, clears)
end

local function paintTabs(accent: Color3)
	for _, tab in ipairs(tabButtons) do
		local selected = tab.id == currentDifficulty
		local open = stageOpen(tab.id)
		TweenService:Create(tab.button, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {
			BackgroundColor3 = selected and accent or C.Raised,
			BackgroundTransparency = selected and 0 or (open and 0.35 or 0.62),
		}):Play()
		tab.indicator.Visible = selected
		tab.indicator.BackgroundColor3 = accent
		tab.label.TextColor3 = selected and C.Ink
			or (open and C.Muted or Color3.fromRGB(88, 88, 104))
		tab.stroke.Color = selected and accent or C.Line
		tab.stroke.Transparency = selected and 0 or (open and 0.45 or 0.75)
		-- A padlock rather than a hidden tab: seeing Cosmic sitting there locked is
		-- the thing that tells you there is a ladder to climb at all.
		tab.lock.Visible = not open
	end
end

local function paintLineup(lineup: { string })
	for index, slot in ipairs(lineupSlots) do
		local cardId = lineup[index]
		if cardId then
			local d = defOf(cardId)
			slot.frame.Visible = true
			ArtLoader.set(slot.art, d and d.art or "")
			slot.name.Text = d and d.name or cardId
			slot.stroke.Color = rarityColour(cardId)
			-- The encounter's own card is the one you came for; the rest are
			-- backup, and dimming them says so without needing a label.
			slot.frame.BackgroundTransparency = index == 1 and 0 or 0.25
			slot.art.ImageTransparency = index == 1 and 0 or 0.12
		else
			slot.frame.Visible = false
		end
	end
end

-- What a stage pays, split into the two rows.
--
-- The rule the panel has to make obvious: FIRST TIME is always strictly better
-- than REPEAT, and any card unlock only ever appears in the first-time row -
-- an unlock cannot happen twice, so showing it under repeat would be a lie.
local function fillSlot(slot, opts)
	slot.frame.Visible = true
	slot.art.Visible = opts.art ~= nil
	slot.coin.Visible = opts.coin == true
	slot.glyph.Visible = opts.glyph ~= nil and opts.coin ~= true
	if opts.art then ArtLoader.set(slot.art, opts.art) end
	if opts.coin then
		-- Claimed still shows the coin - it is the thing the row is about - but
		-- faded, so "already had this" reads at a glance without hiding it.
		slot.coin.ImageTransparency = opts.dim and 0.5 or 0
	end
	if opts.glyph then
		slot.glyph.Text = opts.glyph
		slot.glyph.TextColor3 = opts.accent
	end
	slot.name.Text = opts.name
	slot.name.TextColor3 = opts.nameColour or C.Text
	slot.tag.Text = opts.tag
	slot.tag.TextColor3 = opts.tagInk and C.Ink or C.Muted
	slot.tagBg.BackgroundColor3 = opts.tagInk and opts.accent or C.Raised
	slot.tagBg.BackgroundTransparency = opts.tagInk and 0 or 0.3
	slot.stroke.Color = opts.accent
	slot.stroke.Transparency = opts.dim and 0.55 or 0.12
	slot.frame.BackgroundTransparency = opts.dim and 0.45 or 0.1

	-- THE RARITY BORDER. This is the same Shine the deck, the roll reveal and the
	-- results screen draw, given the tile's own width so the falloff scales the
	-- way it does on a card. Without this call an Elder Coin tile wore a flat
	-- 1.4px outline and none of the Cosmic tier was visible anywhere in the panel.
	--
	-- Slots are reused between repaints, so a tile that stops being Cosmic has to
	-- be told to drop the border - Shine.remove also re-enables the plain stroke
	-- it parked when it took over.
	if opts.variant then
		Shine.apply(slot.frame, opts.variant, slot.width)
	else
		Shine.remove(slot.frame)
		slot.stroke.Color = opts.accent
		slot.stroke.Transparency = opts.dim and 0.55 or 0.12
	end
end

-- Summon Core drops for the selected stage, read from SummonCoreConfig.dropsFor
-- - the table SummonCoreService pays from - so the preview cannot drift from
-- what a win actually hands over.
local function paintDrops(drops: { any })
	local tile = dropsTile
	if not tile then return end
	local shown = math.min(#drops, #tile.entries)
	local listW = tile.frame.Size.X.Offset - 16
	local entryW = math.floor((listW - 6 * (shown - 1)) / math.max(shown, 1))
	local best = VariantConfig.get("Standard")
	for index, entry in ipairs(tile.entries) do
		local drop = if index <= shown then drops[index] else nil
		entry.frame.Visible = drop ~= nil
		if drop then
			local stage = if drop.kind == "core" then SummonCoreConfig.get(drop.id) else nil
			local item = if drop.kind == "item" then SummonCoreConfig.item(drop.id) else nil
			entry.frame.Size = UDim2.fromOffset(entryW, 48)
			entry.amount.Size = UDim2.fromOffset(entryW - 48, 18)
			entry.name.Size = UDim2.fromOffset(entryW - 48, 22)
			ArtLoader.set(entry.art, drop.image)
			-- A core's art is shared by its whole family, so its name carries the
			-- level ("Basic Core IV").
			entry.amount.Text = "x" .. Format.comma(drop.amount)
			entry.name.Text = if stage then ("%s Core %s"):format(stage.family, stage.numeral)
				elseif item then item.shortName
				else tostring(drop.name)
			local variant = VariantConfig.get(drop.variant)
			if variant.rank > best.rank then best = variant end
		end
	end
	tile.frame.Visible = true
	tile.tagBg.BackgroundColor3 = best.color
	Shine.apply(tile.frame, best.id, tile.frame.Size.X.Offset)
end

local function paintRewards(accent: Color3)
	for _, slot in ipairs(firstSlots) do slot.frame.Visible = false end
	for _, slot in ipairs(repeatSlots) do slot.frame.Visible = false end
	if dropsTile then dropsTile.frame.Visible = false end
	if not currentCardId then return end

	local cosmicAccent = VariantConfig.get("Cosmic").color
	local rank = EncounterModes.rank(currentDifficulty)

	----------------------------------------------------------------
	-- first time
	----------------------------------------------------------------
	local firstCoins = EncounterModes.coins(currentCardId, currentDifficulty, true)
	local cleared = (clears[currentCardId] or 0) >= rank
	local n = 0

	n += 1
	fillSlot(firstSlots[n], {
		coin = true,
		variant = "Cosmic",
		accent = cosmicAccent,
		name = Format.comma(firstCoins),
		tag = cleared and "ALREADY CLAIMED" or "ELDER COINS",
		tagInk = not cleared,
		dim = cleared,
	})

	-- Every unlock this stage grants, always on the first-time row.
	local granted = {}
	for unlockId, req in pairs(EncounterModes.Unlocks) do
		if req.encounter == currentCardId and EncounterModes.rank(req.difficulty) == rank then
			table.insert(granted, unlockId)
		end
	end
	table.sort(granted)

	for _, unlockId in ipairs(granted) do
		if n >= #firstSlots then break end
		n += 1
		local def = defOf(unlockId)
		local req = EncounterModes.requirement(unlockId)
		local earned = req ~= nil
			and (clears[req.encounter] or 0) >= EncounterModes.rank(req.difficulty)
		fillSlot(firstSlots[n], {
			art = def and def.art or "",
			accent = rarityColour(unlockId),
			name = def and def.name or unlockId,
			tag = earned and "UNLOCKED" or "UNLOCK ROLL",
			tagInk = not earned,
			dim = earned,
		})
	end

	-- Mounts this stage hands over, on the first-time row beside the card
	-- unlocks. A mount is the rarest thing the route pays out, so it is worth
	-- advertising before the fight rather than only announcing after it.
	for _, mountId in ipairs(MountDefinitions.Order) do
		if n >= #firstSlots then break end
		local req = MountDefinitions.requirement(mountId)
		if req and req.encounter == currentCardId
			and EncounterModes.rank(req.difficulty) == rank then
			n += 1
			local def = MountDefinitions.get(mountId)
			local owned = ownedMounts[mountId] == true
			fillSlot(firstSlots[n], {
				art = (def and def.icon ~= "") and def.icon or nil,
				glyph = (not def or def.icon == "") and "\u{25C9}" or nil,
				accent = cosmicAccent,
				name = def and def.name or mountId,
				tag = owned and "UNLOCKED" or "MOUNT",
				tagInk = not owned,
				dim = owned,
			})
		end
	end

	----------------------------------------------------------------
	-- repeat
	----------------------------------------------------------------
	local repeatCoins = EncounterModes.coins(currentCardId, currentDifficulty, false)
	fillSlot(repeatSlots[1], {
		coin = true,
		variant = "Cosmic",
		accent = cosmicAccent,
		name = Format.comma(repeatCoins),
		tag = "ELDER COINS",
		tagInk = true,
	})

	-- Summon Core drops (Pirate Shark today) take the rest of the row. They pay
	-- on EVERY win, the first one included, which the section label spells out.
	local drops = SummonCoreConfig.dropsFor(currentCardId, currentDifficulty)
	if #drops > 0 and dropsTile then
		paintDrops(drops)
		if repeatLabel then
			repeatLabel.Text = "REPEAT REWARDS   \u{2022}   CORE DROPS ON EVERY WIN, FIRST ONE TOO"
		end
	else
		if repeatLabel then repeatLabel.Text = "REPEAT REWARDS" end
		fillSlot(repeatSlots[2], {
			glyph = "\u{2014}",
			accent = C.Line,
			name = "No unlocks",
			nameColour = C.Muted,
			tag = "EVERY CLEAR",
			dim = true,
		})
	end
end

local function repaint()
	if not currentCardId then return end
	local mode = EncounterModes.get(currentDifficulty)
	local accent = mode.accent

	panelStroke.Color = accent
	glowImage.ImageColor3 = accent
	eyebrow.TextColor3 = accent
	headerAccent.BackgroundColor3 = accent
	stageProgress.Text = ("STAGE %d / %d"):format(EncounterModes.rank(currentDifficulty), #EncounterModes.Order)
	stageProgress.TextColor3 = accent
	local completed = clears[currentCardId] or 0
	for index, segment in ipairs(stageSegments) do
		segment.BackgroundColor3 = index <= completed and Color3.fromRGB(123, 215, 178) or accent
		segment.BackgroundTransparency = index <= completed and 0.05
			or (index == EncounterModes.rank(currentDifficulty) and 0.12 or 0.82)
	end

	paintTabs(accent)

	local lineup = EncounterModes.lineup(currentCardId, currentDifficulty)
	local count = #lineup
	statsLabel.Text = ("%dx STATS   \u{2022}   %d ENEM%s")
		:format(EncounterModes.statMultiplier(currentDifficulty, currentCardId), count, count == 1 and "Y" or "IES")
	statsLabel.TextColor3 = accent

	subtitle.Text = EncounterModes.blurb(currentCardId, currentDifficulty)

	paintLineup(lineup)
	paintRewards(accent)

	fightButton.BackgroundColor3 = accent
	fightLabel.TextColor3 = C.Ink
	local d = currentCardId and defOf(currentCardId)
	-- The key is on the button itself, not only in the footer: the button is
	-- where the eye already is when deciding to commit.
	fightLabel.Text = ("[E]   FIGHT ON %s"):format(mode.display)
	local _ = d
end

local function selectDifficulty(id: string)
	if not EncounterModes.exists(id) or currentDifficulty == id then return end

	if not stageOpen(id) then
		-- Say WHICH stage is in the way rather than just refusing. The tab stays
		-- visible and clickable precisely so this message can be shown.
		local previous = EncounterModes.previousStage(id)
		statusLabel.Text = ("Beat %s first"):format(EncounterModes.get(previous).display)
		statusLabel.TextColor3 = C.Bad
		return
	end

	currentDifficulty = id
	statusLabel.Text = "[E] to fight    \u{2022}    X to close"
	statusLabel.TextColor3 = C.Muted
	repaint()
end

----------------------------------------------------------------
-- OPEN / CLOSE
----------------------------------------------------------------

local function close()
	if not dim.Visible then return end
	openToken += 1
	local closingToken = openToken
	currentCardId = nil
	currentNpc = nil
	starting = false

	-- Hand E back to the world card. Guarded because the card can be destroyed
	-- while its panel is open (streaming, a respawn), and re-enabling a prompt
	-- that no longer exists would throw inside a close path.
	if activePrompt then
		pcall(function()
			if activePrompt.Parent then activePrompt.Enabled = true end
		end)
		activePrompt = nil
	end
	TweenService:Create(panelScale, TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
		Scale = viewportScale() * 0.96,
	}):Play()
	local fade = TweenService:Create(panel, TweenInfo.new(0.12), { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Once(function()
		if openToken == closingToken then dim.Visible = false end
	end)
end

-- Assigned in Init; nil until then.
local controllers: any = nil

-- The panel proper. `prompt` is optional: it is how the world card opens this,
-- but the panel does not depend on one existing, which is what lets Open() below
-- summon it for a card id alone.
local function openFor(cardId: string, model: Model?, prompt: ProximityPrompt?)
	if typeof(cardId) ~= "string" then return end
	local def = CardDefinitions.get(cardId)
	if not def then return end

	-- Never open on top of a fight. The card you just challenged is a few studs
	-- away, so its prompt is still in range while the battle plays out.
	local battle = controllers and controllers.BattleController
	if battle and type(battle.IsBattleOpen) == "function" and battle:IsBattleOpen() then
		return
	end

	openToken += 1
	currentCardId = cardId
	currentNpc = model
	starting = false

	-- Take E off the world card for as long as the panel is up. Without this,
	-- pressing E to fight would ALSO re-trigger the prompt behind the panel,
	-- which calls show() again and snaps the stage back to Easy - so the fight
	-- you launched would never be the one you selected.
	if activePrompt and activePrompt ~= prompt then
		pcall(function()
			if activePrompt.Parent then activePrompt.Enabled = true end
		end)
	end
	activePrompt = prompt
	if prompt then prompt.Enabled = false end
	-- Always reopen on Easy. Landing on whatever stage was picked last time is
	-- how someone walks into a Cosmic fight by accident.
	currentDifficulty = "Easy"

	title.Text = string.upper(def.name)
	CardRenderer.update(card, { cardId = cardId, variant = "Standard", level = 0 })
	if card.levelPill then card.levelPill.Visible = false end

	statusLabel.Text = "[E] to fight    \u{2022}    X to close"
	statusLabel.TextColor3 = C.Muted
	repaint()

	dim.Visible = true
	panel.GroupTransparency = 1
	local fittedScale = viewportScale()
	panelScale.Scale = fittedScale * 0.96
	TweenService:Create(panel, TweenInfo.new(0.18), { GroupTransparency = 0 }):Play()
	TweenService:Create(panelScale, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = fittedScale,
	}):Play()
end

local function show(prompt: ProximityPrompt)
	local cardId = prompt:GetAttribute("EncounterCardId")
	if typeof(cardId) ~= "string" then return end
	openFor(cardId, prompt:FindFirstAncestorOfClass("Model"), prompt)
end

local function fitToViewport()
	if not gui or not panelScale then return end
	panelScale.Scale = viewportScale()
end

----------------------------------------------------------------
-- BUILD
----------------------------------------------------------------

function EncounterController:Init()
	controllers = self.Controllers

	-- Idempotent on purpose. Bootstrap calls this once, but the slot tables are
	-- MODULE state: a second Init appends a second set of frames to them, and the
	-- paint functions then write into slots belonging to a panel that is no longer
	-- on screen - so the window renders empty with no error to explain why.
	if gui then gui:Destroy() end
	table.clear(tabButtons)
	table.clear(lineupSlots)
	table.clear(firstSlots)
	table.clear(repeatSlots)
	table.clear(stageSegments)

	gui = new("ScreenGui", {
		Name = "NPCEncounterScreen",
		Parent = player:WaitForChild("PlayerGui"),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 55,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	dim = new("TextButton", {
		Name = "Dim", Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0, Text = "", AutoButtonColor = false, Visible = false,
	})

	panel = new("CanvasGroup", {
		Name = "EncounterPanel", Parent = dim,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_W, PANEL_H),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0, Active = true, GroupTransparency = 1,
	}, { corner(22) })
	panelScale = new("UIScale", { Parent = panel, Scale = 1 })
	panelStroke = stroke(C.Line, 1.5, 0.1)
	panelStroke.Parent = panel

	-- Grain and accent glow sit under the content and never take input.
	new("ImageLabel", {
		Parent = panel, Name = "Grain",
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Image = EncounterModes.UI.Grain, ImageTransparency = 0.955,
		ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(256, 256),
		ZIndex = 0,
	})

	glowImage = new("ImageLabel", {
		Parent = panel, Name = "AccentGlow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -180),
		Size = UDim2.fromOffset(900, 520),
		BackgroundTransparency = 1,
		Image = EncounterModes.UI.Glow,
		ImageTransparency = 0.86,
		ZIndex = 0,
	})

	local headerSurface = new("Frame", {
		Parent = panel, Name = "HeaderSurface",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 99),
		BackgroundColor3 = Color3.fromRGB(27, 36, 56),
		BackgroundTransparency = 0.12, BorderSizePixel = 0, ZIndex = 1,
	}, { corner(16) })
	new("UIGradient", {
		Parent = headerSurface,
		Color = ColorSequence.new(Color3.fromRGB(216, 231, 255), Color3.fromRGB(76, 85, 110)),
		Rotation = 10,
	})
	headerAccent = new("Frame", {
		Parent = panel, Name = "HeaderAccent",
		Position = UDim2.fromOffset(30, 13),
		Size = UDim2.fromOffset(64, 3),
		BackgroundColor3 = C.Text, BorderSizePixel = 0, ZIndex = 2,
	}, { corner(2) })

	local closeButton = new("TextButton", {
		Name = "Close", Parent = panel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -26, 0, 27),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = C.Raised, BackgroundTransparency = 0.25,
		-- The cross uses geometry so it stays centered in every display font.
		BorderSizePixel = 0, Text = "",
		FontFace = Theme.font(), TextSize = 16, TextColor3 = C.Muted,
		AutoButtonColor = false, ZIndex = 9,
	}, { corner(12), stroke(Color3.fromRGB(126, 147, 178), 1, 0.35) })
	for _, rotation in ipairs({ 45, -45 }) do
		new("Frame", {
			Parent = closeButton, Name = "Cross",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(17, 2), Rotation = rotation,
			BackgroundColor3 = Color3.fromRGB(234, 242, 255),
			BorderSizePixel = 0, ZIndex = 10,
		}, { corner(1) })
	end

	eyebrow = text(panel, {
		Position = UDim2.fromOffset(30, 26),
		Size = UDim2.new(1, -90, 0, 16),
		Text = "ARLONG PARK ENCOUNTER",
		TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
	})
	title = text(panel, {
		Position = UDim2.fromOffset(30, 44),
		Size = UDim2.new(1, -90, 0, 42),
		Text = "", TextSize = 32, TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
	})
	subtitle = text(panel, {
		Position = UDim2.fromOffset(30, 86),
		Size = UDim2.new(1, -90, 0, 18),
		Text = "", TextSize = 13, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
	})

	-- the enemy, rendered as an actual card by the game's own renderer
	cardHost = new("Frame", {
		Parent = panel, Name = "CardHost",
		Position = UDim2.fromOffset(30, 120),
		Size = UDim2.fromOffset(CARD_W, math.floor(CARD_W * 1.34)),
		BackgroundTransparency = 1, ZIndex = 3,
	})
	card = CardRenderer.create(cardHost, CARD_W, 4)

	local progressCard = new("Frame", {
		Parent = panel, Name = "StageProgress",
		Position = UDim2.fromOffset(30, 481),
		Size = UDim2.fromOffset(CARD_W, 151),
		BackgroundColor3 = Color3.fromRGB(20, 27, 41), BorderSizePixel = 0,
		BackgroundTransparency = 0.12, ZIndex = 3,
	}, { corner(13), stroke(Color3.fromRGB(70, 90, 121), 1, 0.55) })
	text(progressCard, {
		Position = UDim2.fromOffset(16, 14), Size = UDim2.new(1, -32, 0, 14),
		Text = "CHALLENGE PROGRESS", TextSize = 10, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	})
	stageProgress = text(progressCard, {
		Position = UDim2.fromOffset(16, 33), Size = UDim2.new(1, -32, 0, 23),
		Text = "", TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	})
	local segmentWidth = (CARD_W - 32 - (#EncounterModes.Order - 1) * 5) / #EncounterModes.Order
	for index = 1, #EncounterModes.Order do
		stageSegments[index] = new("Frame", {
			Parent = progressCard, Name = "Stage" .. index,
			Position = UDim2.fromOffset(16 + (index - 1) * (segmentWidth + 5), 67),
			Size = UDim2.fromOffset(segmentWidth, 5), BorderSizePixel = 0, ZIndex = 4,
		}, { corner(3) })
	end
	text(progressCard, {
		Position = UDim2.fromOffset(16, 85), Size = UDim2.new(1, -32, 0, 49),
		Text = "First clears advance the ladder.\nRepeat clears earn more coins.",
		TextSize = 12, TextColor3 = C.Muted, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
	})

	local RIGHT_X = 30 + CARD_W + 26
	local RIGHT_W = PANEL_W - RIGHT_X - 30

	local function sectionLabel(y: number, str: string): TextLabel
		return text(panel, {
			Position = UDim2.fromOffset(RIGHT_X, y),
			Size = UDim2.fromOffset(RIGHT_W, 14),
			Text = str, TextSize = 11, TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
		})
	end

	sectionLabel(120, "DIFFICULTY")

	-- stage tabs
	local tabRow = new("Frame", {
		Parent = panel, Name = "Tabs",
		Position = UDim2.fromOffset(RIGHT_X, 140),
		Size = UDim2.fromOffset(RIGHT_W, TAB_H),
		BackgroundTransparency = 1, ZIndex = 3,
	})
	local gap = 5
	local tabW = (RIGHT_W - gap * (#EncounterModes.Order - 1)) / #EncounterModes.Order
	for index, id in ipairs(EncounterModes.Order) do
		local mode = EncounterModes.Data[id]
		local button = new("TextButton", {
			Parent = tabRow, Name = id,
			Position = UDim2.fromOffset((index - 1) * (tabW + gap), 0),
			Size = UDim2.fromOffset(tabW, TAB_H),
			BackgroundColor3 = C.Raised, BackgroundTransparency = 0.35,
			BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 4,
		}, { corner(9) })
		local st = stroke(C.Line, 1, 0.45)
		st.Parent = button
		local lbl = text(button, {
			Size = UDim2.fromScale(1, 1),
			Text = mode.display, TextSize = 11,
			TextColor3 = C.Muted, ZIndex = 5,
		})
		lbl.TextScaled = true
		new("UITextSizeConstraint", { Parent = lbl, MaxTextSize = 12, MinTextSize = 8 })

		local lock = new("Frame", {
			Parent = button, Name = "Lock",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -5, 0, 3),
			Size = UDim2.fromOffset(9, 11),
			BackgroundTransparency = 1, BorderSizePixel = 0,
			Visible = false, ZIndex = 6,
		})
		new("Frame", {
			Parent = lock, Position = UDim2.fromOffset(2, 0),
			Size = UDim2.fromOffset(5, 7),
			BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6,
		}, { corner(3), stroke(Color3.fromRGB(120, 130, 151), 1.2, 0) })
		new("Frame", {
			Parent = lock, Position = UDim2.fromOffset(0, 4),
			Size = UDim2.fromOffset(9, 7),
			BackgroundColor3 = Color3.fromRGB(120, 130, 151),
			BorderSizePixel = 0, ZIndex = 7,
		}, { corner(2) })

		local indicator = new("Frame", {
			Parent = button, Name = "SelectedIndicator",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 3),
			Size = UDim2.new(0.5, 0, 0, 2),
			BackgroundColor3 = C.Text, BorderSizePixel = 0, Visible = false, ZIndex = 5,
		}, { corner(2) })
		local entry = { id = id, button = button, label = lbl, stroke = st, lock = lock, indicator = indicator }
		table.insert(tabButtons, entry)

		button.Activated:Connect(function() selectDifficulty(id) end)
		button.MouseEnter:Connect(function()
			if currentDifficulty ~= id and stageOpen(id) then
				TweenService:Create(button, TweenInfo.new(0.12), { BackgroundTransparency = 0.1 }):Play()
				lbl.TextColor3 = C.Text
			end
		end)
		button.MouseLeave:Connect(function()
			if currentDifficulty ~= id then
				local open = stageOpen(id)
				TweenService:Create(button, TweenInfo.new(0.15), { BackgroundTransparency = open and 0.35 or 0.62 }):Play()
				lbl.TextColor3 = open and C.Muted or Color3.fromRGB(88, 88, 104)
			end
		end)
	end

	statsLabel = text(panel, {
		Position = UDim2.fromOffset(RIGHT_X, 188),
		Size = UDim2.fromOffset(RIGHT_W, 20),
		Text = "", TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
	})

	sectionLabel(218, "YOU WILL FACE")

	lineupRow = new("Frame", {
		Parent = panel, Name = "Lineup",
		Position = UDim2.fromOffset(RIGHT_X, 236),
		Size = UDim2.fromOffset(RIGHT_W, 100),
		BackgroundTransparency = 1, ZIndex = 3,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
	})
	for i = 1, EncounterModes.MaxEnemies do
		local frame = new("Frame", {
			Parent = lineupRow, LayoutOrder = i,
			Size = UDim2.fromOffset(56, 100),
			BackgroundColor3 = C.Raised, BackgroundTransparency = 0,
			BorderSizePixel = 0, Visible = false, ZIndex = 4,
		}, { corner(8) })
		local st = stroke(C.Line, 1.4, 0.1)
		st.Parent = frame
		local art = new("ImageLabel", {
			Parent = frame,
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.fromOffset(50, 68),
			BackgroundColor3 = C.Ink, BorderSizePixel = 0,
			ScaleType = Enum.ScaleType.Crop, ZIndex = 5,
		}, { corner(6) })
		local nameLabel = text(frame, {
			Position = UDim2.fromOffset(2, 73),
			Size = UDim2.fromOffset(52, 24),
			Text = "", TextSize = 9, TextColor3 = C.Muted,
			TextWrapped = true, ZIndex = 5,
		})
		table.insert(lineupSlots, { frame = frame, art = art, name = nameLabel, stroke = st })
	end

	-- Two reward rows rather than one. Seeing what a stage pays the FIRST time
	-- next to what it pays forever after is the whole decision a player is making
	-- when they pick a stage, and it cannot be made from one row.
	local function rewardRowAt(y: number, count: number, slots: { any }): Frame
		local row = new("Frame", {
			Parent = panel,
			Position = UDim2.fromOffset(RIGHT_X, y),
			Size = UDim2.fromOffset(RIGHT_W, REWARD_H),
			BackgroundTransparency = 1, ZIndex = 3,
		}, {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				-- 16, not 8. The Cosmic border throws ~9px of glow past the tile edge,
				-- and at 8px the next tile's opaque background drew straight over it -
				-- so the coin tile lost its border on exactly the side you look at.
				Padding = UDim.new(0, 16),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local tileW = math.floor((RIGHT_W - 16 * (count - 1)) / count)
		for i = 1, count do
			local frame = new("Frame", {
				Parent = row, LayoutOrder = i,
				Size = UDim2.fromOffset(tileW, REWARD_H),
				BackgroundColor3 = C.Raised, BackgroundTransparency = 0.1,
				BorderSizePixel = 0, Visible = false, ZIndex = 4,
				ClipsDescendants = true,
			}, { corner(10) })
			local st = stroke(C.Line, 1.4, 0.2)
			st.Parent = frame

			-- Centred in the same 68px left column the coin uses, so a card tile and
			-- a currency tile line their text up at the same x.
			local art = new("ImageLabel", {
				Parent = frame,
				Position = UDim2.fromOffset(11, 7),
				Size = UDim2.fromOffset(46, 62),
				BackgroundColor3 = C.Ink, BorderSizePixel = 0,
				ScaleType = Enum.ScaleType.Crop, ZIndex = 5,
			}, { corner(7) })
			local glyph = text(frame, {
				Name = "Glyph",
				Position = UDim2.fromOffset(11, 7),
				Size = UDim2.fromOffset(46, 62),
				Text = "", TextSize = 26, Visible = false, ZIndex = 6,
			})

			-- The real coin, square because the render is - a coin squeezed into the
			-- 46x62 card slot would read as an oval.
			local coin = ElderCoin.attach(frame, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 4, 0.5, 0),
				Size = UDim2.fromOffset(62, 62),
				Visible = false, ZIndex = 6,
			})
			local nameLabel = text(frame, {
				Name = "RewardName",
				Position = UDim2.fromOffset(68, 13),
				Size = UDim2.fromOffset(tileW - 76, 22),
				Text = "", TextSize = 14, TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6,
			})
			new("UITextSizeConstraint", { Parent = nameLabel, MinTextSize = 9, MaxTextSize = 14 })
			local tagBg = new("Frame", {
				Parent = frame,
				Position = UDim2.fromOffset(68, 39),
				Size = UDim2.fromOffset(0, 20),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = C.Raised, BorderSizePixel = 0, ZIndex = 6,
			}, { corner(6) })
			new("UIPadding", { Parent = tagBg,
				PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })
			local tag = text(tagBg, {
				Size = UDim2.fromOffset(0, 20),
				AutomaticSize = Enum.AutomaticSize.X,
				Text = "", TextSize = 10, TextColor3 = C.Ink, ZIndex = 7,
			})
			table.insert(slots, {
				frame = frame, art = art, glyph = glyph, coin = coin,
				name = nameLabel, tag = tag, tagBg = tagBg, stroke = st,
				width = tileW,
			})
		end
		return row
	end

	sectionLabel(352, "FIRST TIME REWARDS")
	firstRow = rewardRowAt(370, 3, firstSlots)
	firstRow.Name = "FirstTimeRewards"

	repeatLabel = sectionLabel(462, "REPEAT REWARDS")
	repeatRow = rewardRowAt(480, 3, repeatSlots)
	repeatRow.Name = "RepeatRewards"

	-- FORGE DROPS. One wide tile standing in for repeat slots 2 and 3: a Cosmic
	-- win pays a core, essence AND a wrench, which would not fit as a slot each
	-- beside the coins. paintDrops fills it.
	do
		local slotW = repeatSlots[1].width
		local frame = new("Frame", {
			Parent = repeatRow, Name = "ForgeDrops", LayoutOrder = 2,
			Size = UDim2.fromOffset(slotW * 2 + 16, REWARD_H),
			BackgroundColor3 = C.Raised, BackgroundTransparency = 0.1,
			BorderSizePixel = 0, Visible = false, ZIndex = 4,
			ClipsDescendants = true,
		}, { corner(10) })
		local st = stroke(C.Line, 1.4, 0.12)
		st.Parent = frame
		local tagBg = new("Frame", {
			Parent = frame,
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.Raised, BorderSizePixel = 0, ZIndex = 6,
		}, { corner(5) })
		new("UIPadding", { Parent = tagBg,
			PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) })
		local tag = text(tagBg, {
			Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "EVERY WIN", TextSize = 10, TextColor3 = C.Ink, ZIndex = 7,
		})
		local list = new("Frame", {
			Parent = frame, Name = "Entries",
			Position = UDim2.fromOffset(8, 25),
			Size = UDim2.new(1, -16, 0, 48),
			BackgroundTransparency = 1, ZIndex = 5,
		}, {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local entries = {}
		for i = 1, 3 do
			local entry = new("Frame", {
				Parent = list, Name = "Drop" .. i, LayoutOrder = i,
				Size = UDim2.fromOffset(96, 48),
				BackgroundTransparency = 1, Visible = false, ZIndex = 5,
			})
			local art = new("ImageLabel", {
				Parent = entry, Name = "Art",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(44, 44),
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Fit, ZIndex = 6,
			})
			local amount = text(entry, {
				Name = "Amount",
				Position = UDim2.fromOffset(48, 3),
				Size = UDim2.fromOffset(48, 18),
				Text = "", TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6,
			})
			local dropName = text(entry, {
				Name = "DropName",
				Position = UDim2.fromOffset(48, 23),
				Size = UDim2.fromOffset(48, 22),
				Text = "", TextSize = 11, TextScaled = true, TextWrapped = true,
				TextColor3 = C.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 6,
			})
			new("UITextSizeConstraint", { Parent = dropName, MinTextSize = 8, MaxTextSize = 11 })
			entries[i] = { frame = entry, art = art, amount = amount, name = dropName }
		end
		dropsTile = { frame = frame, stroke = st, tagBg = tagBg, tag = tag, entries = entries }
	end

	fightButton = new("TextButton", {
		Name = "Fight", Parent = panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(RIGHT_X + RIGHT_W / 2, 605),
		Size = UDim2.fromOffset(RIGHT_W, 54),
		BackgroundColor3 = C.Text, BorderSizePixel = 0,
		Text = "", AutoButtonColor = false, ZIndex = 4,
	}, { corner(12), stroke(Color3.fromRGB(232, 244, 255), 1.4, 0.36) })
	new("UIGradient", {
		Parent = fightButton,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(205, 217, 235)),
			ColorSequenceKeypoint.new(0.42, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(191, 209, 237)),
		}),
		Rotation = 18,
	})
	fightLabel = text(fightButton, {
		Size = UDim2.fromScale(1, 1),
		Text = "FIGHT", TextSize = 19, TextColor3 = C.Ink, ZIndex = 5,
	})

	statusLabel = text(panel, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -60, 0, 18),
		Text = "[E] to fight    \u{2022}    X to close",
		TextSize = 12, TextColor3 = C.Muted, ZIndex = 3,
	})

	----------------------------------------------------------------
	-- behaviour
	----------------------------------------------------------------

	closeButton.Activated:Connect(close)
	dim.Activated:Connect(close)
	local closeScale = new("UIScale", { Parent = closeButton, Scale = 1 })
	closeButton.MouseEnter:Connect(function()
		TweenService:Create(closeButton, TweenInfo.new(0.14), {
			BackgroundColor3 = Color3.fromRGB(154, 54, 77), BackgroundTransparency = 0,
		}):Play()
		TweenService:Create(closeScale, TweenInfo.new(0.14), { Scale = 1.04 }):Play()
	end)
	closeButton.MouseLeave:Connect(function()
		TweenService:Create(closeButton, TweenInfo.new(0.16), {
			BackgroundColor3 = C.Raised, BackgroundTransparency = 0.25,
		}):Play()
		TweenService:Create(closeScale, TweenInfo.new(0.16), { Scale = 1 }):Play()
	end)

	local fightScale = new("UIScale", { Parent = fightButton, Scale = 1 })
	fightButton.MouseEnter:Connect(function()
		TweenService:Create(fightScale, TweenInfo.new(0.12), { Scale = 1.02 }):Play()
	end)
	fightButton.MouseLeave:Connect(function()
		TweenService:Create(fightScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)

	fightButton.MouseButton1Down:Connect(function()
		TweenService:Create(fightScale, TweenInfo.new(0.08), { Scale = 0.98 }):Play()
	end)
	fightButton.MouseButton1Up:Connect(function()
		TweenService:Create(fightScale, TweenInfo.new(0.13), { Scale = 1 }):Play()
	end)

	beginFight = function()
		if starting or not currentCardId then return end
		if not stageOpen(currentDifficulty) then
			local previous = EncounterModes.previousStage(currentDifficulty)
			statusLabel.Text = ("Beat %s first"):format(EncounterModes.get(previous).display)
			statusLabel.TextColor3 = C.Bad
			return
		end
		starting = true
		fightButton.Active = false
		fightLabel.Text = "PREPARING BATTLE..."
		statusLabel.Text = "Loading your active deck"
		statusLabel.TextColor3 = EncounterModes.get(currentDifficulty).accent

		local world = self.Controllers and self.Controllers.EncounterWorldController
		if world and type(world.PlayChallenge) == "function" then
			pcall(function() world:PlayChallenge(currentCardId) end)
		end

		local battle = self.Controllers and self.Controllers.BattleController
		if not battle or type(battle.StartEncounter) ~= "function" then
			starting = false
			fightButton.Active = true
			fightLabel.Text = "TRY AGAIN"
			statusLabel.Text = "Battle controller is unavailable"
			statusLabel.TextColor3 = C.Bad
			return
		end

		local ok, reason = battle:StartEncounter(currentCardId, currentDifficulty)
		if ok then
			close()
		else
			starting = false
			fightButton.Active = true
			repaint()
			statusLabel.Text = tostring(reason or "Could not start battle")
			statusLabel.TextColor3 = C.Bad
		end
	end

	fightButton.Activated:Connect(function() beginFight() end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not dim.Visible then return end

		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			close()

		-- E opened this panel and E starts the fight. The prompt underneath is
		-- switched off while the panel is up (see show), so this cannot race with
		-- it re-triggering and resetting the stage back to Easy.
		elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonA then
			beginFight()

		-- Left/right walk the stage ladder, so the whole panel is reachable from
		-- the keyboard without going back to the mouse.
		elseif input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
			local rank = EncounterModes.rank(currentDifficulty)
			if rank > 1 then selectDifficulty(EncounterModes.Order[rank - 1]) end
		elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
			local rank = EncounterModes.rank(currentDifficulty)
			local nextId = EncounterModes.Order[rank + 1]
			if nextId then selectDifficulty(nextId) end
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("EncounterCardId") then
			show(prompt)
		end
	end)

	Remotes.ProfileSync.OnClientEvent:Connect(function(data)
		if typeof(data) == "table" and typeof(data.encounters) == "table" then
			clears = data.encounters
			ownedMounts = (typeof(data.mounts) == "table") and data.mounts or {}
			if dim.Visible then repaint() end
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not dim.Visible or not currentNpc then return end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		-- Encounter cards have no HumanoidRootPart; their body IS the PrimaryPart.
		local npcRoot = currentNpc:FindFirstChild("HumanoidRootPart") or currentNpc.PrimaryPart
		if root and npcRoot and npcRoot:IsA("BasePart") then
			if (root.Position - npcRoot.Position).Magnitude > 20 then
				close()
			end
		end
	end)

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToViewport)
	task.defer(fitToViewport)
	Theme.bind(gui)
end

-- Open the panel for an encounter without needing its world prompt. Pairs with
-- SetDifficulty below: together they let anything - a menu entry, a teleport, a
-- debug command - put the player in front of an encounter, and they are how this
-- panel is testable without synthesising proximity input.
function EncounterController:Open(cardId: string): boolean
	local folder = Workspace:FindFirstChild("EncounterCards")
	local model = folder and folder:FindFirstChild("Encounter_" .. cardId)
	local prompt = model and model.PrimaryPart
		and model.PrimaryPart:FindFirstChildOfClass("ProximityPrompt")
	openFor(cardId, model, prompt)
	return dim ~= nil and dim.Visible
end

-- Preselect a stage on the open panel. Exists so another system - or a debug
-- command - can drop the player straight onto a stage, and so the selector can
-- be driven without synthesising a click.
function EncounterController:SetDifficulty(id: string): boolean
	if not dim or not dim.Visible then return false end
	selectDifficulty(id)
	return currentDifficulty == id
end

function EncounterController:Start()
	print("[NPCEncounterController] encounter panel online - 5 stages")
end

return EncounterController
