--!strict
-- The card pop-out: what opens when you press a card you own.
--
-- WHY IT EXISTS
-- Pressing a tile used to equip it immediately. That was unambiguous while
-- equipping was the only thing you could do with a card - it stopped being true
-- the moment Elder Essence arrived, because a press could now mean "put this in
-- my deck" or "pour essence into it". A click cannot mean two things, so it
-- means "open this card" and the actions sit beside it.
--
-- IT IS A POP-OUT, NOT A WINDOW.
-- Deliberately NOT a centred modal over a dimmed screen. It grows out of the
-- tile you pressed and parks next to it, so the collection stays visible and in
-- place behind it - you are still standing in your collection looking closer at
-- one card, rather than having been taken somewhere else. Card on one side,
-- actions on the other, and that is the whole layout.
--
-- THE BORDER CARRIES OVER. The card wears its own rarity frame, drawn by the
-- same Shine every card, tile and reward tile uses. That is the thread saying
-- "this is about THAT card" without a word of explanation.
--
-- ON LABELS AND "BOLD"
-- Labels are NOT set to Enum.FontWeight.Bold. The game's face is Fredoka One,
-- which ships one weight - asking Roblox for Bold makes it synthesise one by
-- smearing the outlines, and Theme.bind would overwrite the weight on its next
-- descendant pass anyway. Weight comes from size, a gradient fill and an ink
-- outline instead.
--
-- Every pill label is WHITE on an ink stroke, including the ones sitting on
-- pale buttons. Dark text plus a dark outline is what turned the USE button
-- into an unreadable black smear: at 18px the 2.6px stroke swallowed the
-- letterforms whole. Light-on-dark-outline is legible on every button colour
-- the tiers can produce, so it is the rule rather than a per-button decision.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local ElderEssence = require(ReplicatedStorage.Shared.UI.ElderEssence)
local BookDefinitions = require(ReplicatedStorage.Shared.Config.BookDefinitions)
local CardDefinitions = require(ReplicatedStorage.Shared.Config.CardDefinitions)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local CardActions = {}

local INK    = Color3.fromRGB(8, 8, 12)
local PANEL  = Color3.fromRGB(17, 17, 25)
local RAISED = Color3.fromRGB(30, 31, 44)
local SUNK   = Color3.fromRGB(11, 11, 16)
local LINE   = Color3.fromRGB(60, 62, 88)
local TEXT   = Color3.fromRGB(240, 242, 250)
local MUTED  = Color3.fromRGB(150, 154, 180)
local PURPLE = Color3.fromRGB(150, 92, 245)
local RED    = Color3.fromRGB(238, 76, 96)
local GOLD   = Color3.fromRGB(246, 196, 62)
local GOOD   = Color3.fromRGB(126, 240, 160)

local CARD_W = 206
local CARD_H = math.floor(CARD_W * 1.34)     -- 276
local COL_W  = 290
local GAP    = 14
local ROOT_W = CARD_W + GAP + COL_W
local ROOT_H = CARD_H

local DECK_H = 48
-- The deck row is the ADD pill plus a round REMOVE beside it. The remove
-- button is always there (greyed when this card is not in the line-up) so the
-- pill never changes width under the cursor as copies go in and out.
local REMOVE_W = DECK_H
local DECK_W = COL_W - REMOVE_W - 10
local LP_Y   = DECK_H + 10
local LP_H   = ROOT_H - LP_Y
local PAD    = 14
local INNER  = COL_W - PAD * 2                -- 262
local RIGHT_X = 100
local RIGHT_W = COL_W - RIGHT_X - PAD         -- 176

local gui: ScreenGui
local blocker: TextButton
local root: Frame
local rootScale: UIScale
local cardHolder: Frame
local card: any
local deckButton: TextButton
local deckLabel: TextLabel
local deckCount: Frame
local deckCountLabel: TextLabel
local removeButton: TextButton
local removeLabel: TextLabel
local deckScale: UIScale
local deckFlashToken = 0
local essenceButton: TextButton
local essenceHost: Frame
local essenceImage: ImageLabel? = nil
local essenceCount: TextLabel
local essenceBadge: TextLabel
local levelLabel: TextLabel
local levelRight: TextLabel
local levelFill: Frame
local gainLabel: TextLabel
local qtyLabel: TextLabel
local amountLabel: TextLabel
local sliderTrack: Frame
local sliderFill: Frame
local sliderKnob: Frame
local sliderHit: TextButton
local useButton: TextButton
local useLabel: TextLabel
local picker: Frame
local pickerNote: TextLabel
local pickerTiles: { any } = {}

local currentItem: any = nil
local currentProfile: any = nil
local handlers: any = nil
local selectedTier: string? = nil
local quantity = 1
local dragging = false
local openToken = 0

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = props.Parent
	for key, value in pairs(props) do
		if key ~= "Parent" and key ~= "Height" then (inst :: any)[key] = value end
	end
	if children then
		for _, child in ipairs(children) do child.Parent = inst end
	end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(r: number): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(colour: Color3, thickness: number, transparency: number?): UIStroke
	return new("UIStroke", {
		Color = colour, Thickness = thickness, Transparency = transparency or 0,
	})
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local d = {
		Parent = parent, BackgroundTransparency = 1, BorderSizePixel = 0,
		FontFace = Theme.font(), TextColor3 = TEXT, TextSize = 14,
	}
	for k, v in pairs(props) do d[k] = v end
	return new("TextLabel", d)
end

local function inked(label: TextLabel, thickness: number?): TextLabel
	new("UIStroke", {
		Parent = label, Color = INK, Thickness = thickness or 2.2,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
	return label
end

local function gradientFor(colour: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, colour:Lerp(Color3.new(1, 1, 1), 0.36)),
		ColorSequenceKeypoint.new(0.52, colour),
		ColorSequenceKeypoint.new(1, colour:Lerp(INK, 0.36)),
	})
end

-- The chunky action pill: a vertical gradient over the base colour, a heavy ink
-- outline, and a white inked label. Three cheap things that together read as a
-- moulded game button rather than a flat web rectangle.
local function pill(parent: Instance, props: { [string]: any }, colour: Color3)
	local h = props.Height or 46
	local button = new("TextButton", {
		Parent = parent, Name = props.Name or "Pill",
		Position = props.Position,
		Size = props.Size or UDim2.fromOffset(COL_W, h),
		BackgroundColor3 = colour, BorderSizePixel = 0,
		Text = "", AutoButtonColor = false, ZIndex = props.ZIndex or 6,
	}, { corner(math.floor(h / 2)) })

	new("UIGradient", { Parent = button, Rotation = 90, Color = gradientFor(colour) })
	local edge = stroke(INK, 3, 0.02)
	edge.Name = "Edge"
	edge.Parent = button

	local label = inked(text(button, {
		Name = "Label", Size = UDim2.fromScale(1, 1),
		Text = props.Text or "", TextSize = props.TextSize or 20,
		TextColor3 = Color3.new(1, 1, 1), ZIndex = (props.ZIndex or 6) + 1,
	}), 2.2)

	local scale = new("UIScale", { Parent = button, Scale = 1 })
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.025 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	return button, label
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------

local function ownedEntry()
	if not currentItem or not currentProfile then return nil end
	return (currentProfile.cards or {})[CardStats.key(currentItem.cardId, currentItem.variant)]
end

local function currentLevel(): number
	local entry = ownedEntry()
	return (entry and entry.level) or GameConfig.MinCardLevel
end

local function levelCap(): number
	if not currentItem then return GameConfig.MaxCardLevel end
	return CardDefinitions.maxLevel(currentItem.cardId)
end

local function ownedEssence(essenceId: string): number
	return ((currentProfile and currentProfile.books) or {})[essenceId] or 0
end

local function essenceIdForTier(tier: string?): string?
	if not tier then return nil end
	for _, id in ipairs(BookDefinitions.Order) do
		if BookDefinitions.get(id).tier == tier then return id end
	end
	return nil
end

-- How many of this essence can be poured in without overflowing the cap. The
-- slider is sized from this and the server clamps to the same function, so the
-- UI cannot offer a number the server would refuse.
local function usableCount(tier: string?): number
	local id = essenceIdForTier(tier)
	if not id then return 0 end
	return BookDefinitions.maxUsable(id, currentLevel(), levelCap(), ownedEssence(id))
end

local function gainFor(tier: string?, count: number): number
	local id = essenceIdForTier(tier)
	if not id then return 0 end
	local def = BookDefinitions.get(id)
	if def.toMax then return math.max(0, levelCap() - currentLevel()) end
	return def.levels * count
end

local function bestUsableTier(): string?
	for i = #BookDefinitions.Order, 1, -1 do
		local def = BookDefinitions.get(BookDefinitions.Order[i])
		if usableCount(def.tier) > 0 then return def.tier end
	end
	return nil
end

local function grantText(def: any): string
	if def.toMax then return "TO MAX" end
	return ("+%d"):format(def.levels)
end

----------------------------------------------------------------
-- PAINT
----------------------------------------------------------------

-- The vial is rebuilt rather than retinted: tier V is an animated sprite sheet
-- and I..IV are stills, so they are not the same kind of image.
local function setEssenceArt(tier: string?)
	if essenceImage then essenceImage:Destroy() end
	essenceImage = nil
	if not tier then return end
	essenceImage = ElderEssence.attach(essenceHost, tier, {
		Size = UDim2.fromScale(1, 1), ZIndex = 7,
	})
end

local function repaint()
	if not currentItem then return end
	local variant = VariantConfig.get(currentItem.variant)
	local level, cap = currentLevel(), levelCap()

	-- The deck row. A card can sit in the line-up several times now (up to the
	-- copies you own), so the pill ADDS another copy every press and a count
	-- says how many are in; the round button beside it takes one back out.
	local info = handlers and handlers.deckState and handlers.deckState(currentItem) or nil
	local deckColour, deckText, inDeck
	if info then
		inDeck = info.inDeck or 0
		if info.canAdd then
			deckText, deckColour = "ADD TO DECK", PURPLE
		else
			deckText, deckColour = info.reason or "CANNOT ADD", RAISED
		end
	else
		local equippedIndex = handlers and handlers.equippedIndex
			and handlers.equippedIndex(currentItem) or nil
		inDeck = equippedIndex and 1 or 0
		deckText = equippedIndex and "REMOVE FROM DECK" or "ADD TO DECK"
		deckColour = equippedIndex and RED or PURPLE
	end
	if deckFlashToken == 0 then
		deckLabel.Text = deckText
		deckLabel.TextColor3 = deckColour == RAISED and MUTED or Color3.new(1, 1, 1)
	end
	deckButton.BackgroundColor3 = deckColour
	local deckGrad = deckButton:FindFirstChildOfClass("UIGradient")
	if deckGrad then deckGrad.Color = gradientFor(deckColour) end
	deckCount.Visible = inDeck > 0
	deckCountLabel.Text = "x" .. tostring(inDeck)
	local canRemove = inDeck > 0
	removeButton.BackgroundColor3 = canRemove and RED or RAISED
	local removeGrad = removeButton:FindFirstChildOfClass("UIGradient")
	if removeGrad then removeGrad.Color = gradientFor(canRemove and RED or RAISED) end
	removeLabel.TextColor3 = canRemove and Color3.new(1, 1, 1) or MUTED

	levelLabel.Text = ("LEVEL %d"):format(level)
	levelRight.Text = ("%d / %d"):format(level, cap)
	levelFill.Size = UDim2.new(math.clamp(level / math.max(cap, 1), 0, 1), 0, 1, 0)
	levelFill.BackgroundColor3 = variant.color

	local id = essenceIdForTier(selectedTier)
	local def = id and BookDefinitions.get(id) or nil
	local tierVariant = def and VariantConfig.get(def.variant or "Standard") or nil
	local accent = tierVariant and tierVariant.color or LINE

	essenceCount.Text = id and ("x" .. Format.comma(ownedEssence(id))) or "NONE"
	essenceCount.TextColor3 = accent
	essenceBadge.Text = tierVariant and tierVariant.label or "-"
	essenceBadge.TextColor3 = accent
	local essEdge = essenceButton:FindFirstChildOfClass("UIStroke")
	if essEdge then essEdge.Color = INK end

	local usable = usableCount(selectedTier)
	quantity = math.clamp(quantity, 1, math.max(usable, 1))
	local spend = math.min(quantity, math.max(usable, 0))

	-- A to-max essence has no quantity to choose, so the row says what it does
	-- instead of showing a slider that can only sit at one end.
	local fills = def ~= nil and def.toMax == true
	amountLabel.Text = fills and "THIS ESSENCE" or "AMOUNT"
	qtyLabel.Text = fills and "FILLS TO MAX" or ("x%d"):format(spend)
	qtyLabel.TextColor3 = usable > 0 and TEXT or MUTED

	local ratio = 0
	if usable > 1 then ratio = (spend - 1) / (usable - 1)
	elseif usable == 1 then ratio = 1 end
	sliderFill.Size = UDim2.new(ratio, 0, 1, 0)
	sliderKnob.Position = UDim2.new(ratio, 0, 0.5, 0)
	sliderFill.BackgroundColor3 = accent
	sliderKnob.BackgroundColor3 = accent
	local ranged = usable > 1
	sliderKnob.Visible = ranged
	sliderTrack.Visible = ranged
	sliderHit.Visible = ranged

	local gain = gainFor(selectedTier, spend)
	if level >= cap then
		gainLabel.Text = "MAX LEVEL REACHED"
		gainLabel.TextColor3 = MUTED
	elseif not selectedTier then
		gainLabel.Text = "NO ESSENCE HELD"
		gainLabel.TextColor3 = MUTED
	elseif usable <= 0 then
		gainLabel.Text = ownedEssence(id or "") <= 0 and "NONE HELD" or "WOULD OVERFLOW"
		gainLabel.TextColor3 = RED
	else
		gainLabel.Text = ("+%d  \u{2192}  LEVEL %d"):format(gain, level + gain)
		gainLabel.TextColor3 = GOOD
	end

	local canLevel = level < cap and usable > 0
	local useColour = canLevel and accent or RAISED
	useButton.BackgroundColor3 = useColour
	local useGrad = useButton:FindFirstChildOfClass("UIGradient")
	if useGrad then useGrad.Color = gradientFor(useColour) end
	useLabel.TextColor3 = canLevel and Color3.new(1, 1, 1) or MUTED
	useLabel.Text = canLevel and (fills and "FILL TO MAX" or ("USE %d"):format(spend))
		or "USE"
end

local function selectTier(tier: string?)
	selectedTier = tier
	quantity = 1
	setEssenceArt(tier)
	repaint()
end

----------------------------------------------------------------
-- PICKER
----------------------------------------------------------------

-- Every essence you own, laid out at once.
--
-- This replaced a "tap to cycle" control. Cycling is fine for two or three
-- options you can hold in your head; with five tiers it means pressing a
-- button an unknown number of times to reach the one you want, and never
-- seeing what you have. A picker answers "what do I own" and "what does each
-- one do" in the same glance that selects one.
local function paintPicker()
	local level, cap = currentLevel(), levelCap()
	for _, entry in ipairs(pickerTiles) do
		local def = BookDefinitions.get(entry.essenceId)
		local owned = ownedEssence(entry.essenceId)
		local usable = usableCount(entry.tier)
		local selected = entry.tier == selectedTier

		entry.count.Text = "x" .. Format.comma(owned)
		entry.grant.Text = grantText(def)

		-- Dimmed, not hidden. Seeing the tier you cannot use yet is how you learn
		-- it exists; hiding it would just make the row change shape.
		local live = usable > 0
		entry.image.ImageTransparency = live and 0 or 0.62
		entry.count.TextTransparency = live and 0 or 0.45
		entry.grant.TextTransparency = live and 0 or 0.45
		entry.frame.BackgroundColor3 = selected and RAISED or SUNK
		entry.stroke.Color = selected and entry.colour or LINE
		entry.stroke.Thickness = selected and 2.4 or 1.2
		entry.stroke.Transparency = selected and 0 or 0.55
	end

	local id = essenceIdForTier(selectedTier)
	if not id then
		pickerNote.Text = "You have no essence yet"
		pickerNote.TextColor3 = MUTED
	else
		local def = BookDefinitions.get(id)
		local usable = usableCount(selectedTier)
		if level >= cap then
			pickerNote.Text = "This card is already at maximum level"
			pickerNote.TextColor3 = MUTED
		elseif usable <= 0 then
			pickerNote.Text = ("%s is too strong for the %d levels left")
				:format(def.name, cap - level)
			pickerNote.TextColor3 = RED
		else
			pickerNote.Text = ("%s  \u{2022}  up to %d at once"):format(def.name, usable)
			pickerNote.TextColor3 = MUTED
		end
	end
end

local function setPickerOpen(open: boolean)
	picker.Visible = open
	if open then paintPicker() end
end

----------------------------------------------------------------
-- SLIDER / ACTIONS
----------------------------------------------------------------

local function sliderValueFrom(x: number)
	local usable = usableCount(selectedTier)
	if usable <= 1 then return end
	local at = sliderTrack.AbsolutePosition.X
	local width = math.max(sliderTrack.AbsoluteSize.X, 1)
	local t = math.clamp((x - at) / width, 0, 1)
	quantity = math.clamp(1 + math.floor(t * (usable - 1) + 0.5), 1, usable)
	repaint()
end

local function applyLevelUp()
	if not currentItem or not selectedTier then return end
	local id = essenceIdForTier(selectedTier)
	if not id then return end
	local usable = usableCount(selectedTier)
	if usable <= 0 then return end
	local count = math.clamp(quantity, 1, usable)
	-- The server re-derives all of this from the profile. A request, not an
	-- instruction.
	Remotes.RequestLevelUp:FireServer(currentItem.cardId, currentItem.variant, id, count)
end

-- A press that did something gets a bump; a press that could not (line-up
-- full, every copy already placed) shakes the pill and says why for a moment,
-- so spamming E never feels like the key stopped working.
local function bumpDeck()
	deckScale.Scale = 1.07
	TweenService:Create(deckScale, TweenInfo.new(0.22, Enum.EasingStyle.Back,
		Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function refuseDeck(reason: string?)
	deckFlashToken += 1
	local mine = deckFlashToken
	deckLabel.Text = reason or "CANNOT ADD"
	deckLabel.TextColor3 = RED
	local home = deckButton.Position
	for i, dx in ipairs({ -7, 6, -4, 3, 0 }) do
		task.delay((i - 1) * 0.04, function()
			if mine == deckFlashToken then
				deckButton.Position = home + UDim2.fromOffset(dx, 0)
			end
		end)
	end
	task.delay(0.9, function()
		if mine ~= deckFlashToken then return end
		deckFlashToken = 0
		deckButton.Position = home
		repaint()
	end)
end

local function pressDeck()
	if not currentItem or not handlers then return end
	if handlers.add then
		-- STAYS OPEN. Pressing again adds another copy, so E, E, E fills the
		-- line-up with this card - up to the copies you own and the free slots.
		local ok, reason = handlers.add(currentItem)
		if ok then bumpDeck() else refuseDeck(reason) end
		repaint()
		return
	end
	local equippedIndex = handlers.equippedIndex and handlers.equippedIndex(currentItem)
	if equippedIndex then
		if handlers.unequip then handlers.unequip(currentItem, equippedIndex) end
	else
		if handlers.equip then handlers.equip(currentItem) end
	end
	CardActions.close()
end

local function pressRemove()
	if not currentItem or not handlers or not handlers.remove then return end
	if handlers.remove(currentItem) then
		removeButton.Size = UDim2.fromOffset(REMOVE_W - 6, DECK_H - 6)
		TweenService:Create(removeButton, TweenInfo.new(0.2, Enum.EasingStyle.Back,
			Enum.EasingDirection.Out), { Size = UDim2.fromOffset(REMOVE_W, DECK_H) }):Play()
	end
	repaint()
end

----------------------------------------------------------------
-- BUILD
----------------------------------------------------------------

local function build()
	-- `gui and gui.Parent`, not just `gui`. A destroyed instance is still truthy,
	-- so a bare nil check would keep handing back a reference to a ScreenGui no
	-- longer in PlayerGui and every later open() would silently do nothing.
	if gui and gui.Parent then return end
	table.clear(pickerTiles)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = new("ScreenGui", {
		Name = "CardActions", Parent = playerGui,
		ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 40, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})

	-- Full-screen but INVISIBLE. A dim would say "you have left the collection";
	-- the point of a pop-out is that you have not. It still swallows the click
	-- that closes it.
	blocker = new("TextButton", {
		Name = "Blocker", Parent = gui, Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Text = "", AutoButtonColor = false, ZIndex = 1,
	})

	root = new("Frame", {
		Name = "Root", Parent = gui, Size = UDim2.fromOffset(ROOT_W, ROOT_H),
		BackgroundTransparency = 1, Active = true, ZIndex = 2,
	})
	rootScale = new("UIScale", { Parent = root, Scale = 1 })

	cardHolder = new("Frame", {
		Name = "CardHolder", Parent = root,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 1, ZIndex = 3,
	})
	card = CardRenderer.create(cardHolder, CARD_W, 4)

	local column = new("Frame", {
		Name = "Column", Parent = root,
		Position = UDim2.fromOffset(CARD_W + GAP, 0),
		Size = UDim2.fromOffset(COL_W, ROOT_H),
		BackgroundTransparency = 1, ZIndex = 3,
	})

	deckButton, deckLabel = pill(column, {
		Name = "DeckButton", Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(DECK_W, DECK_H), Height = DECK_H,
		Text = "ADD TO DECK", TextSize = 18, ZIndex = 6,
	}, PURPLE)
	deckScale = deckButton:FindFirstChildOfClass("UIScale")
	-- Room for the keycap on the left and the count on the right.
	deckLabel.Position = UDim2.fromOffset(40, 0)
	deckLabel.Size = UDim2.new(1, -86, 1, 0)

	-- How many copies of this card are in the line-up right now.
	deckCount = new("Frame", {
		Name = "Count", Parent = deckButton, Visible = false,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(38, 26), BackgroundColor3 = INK,
		BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 8,
	}, { corner(13), stroke(Color3.new(1, 1, 1), 1, 0.7) })
	deckCountLabel = inked(text(deckCount, {
		Name = "Label", Size = UDim2.fromScale(1, 1), Text = "x1", TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1), ZIndex = 9,
	}), 1.6)

	-- Takes ONE copy back out: the highest slot holding this card.
	removeButton, removeLabel = pill(column, {
		Name = "RemoveButton", Position = UDim2.fromOffset(COL_W - REMOVE_W, 0),
		Size = UDim2.fromOffset(REMOVE_W, DECK_H), Height = DECK_H,
		Text = "\u{2212}", TextSize = 26, ZIndex = 6,
	}, RAISED)
	removeButton.AnchorPoint = Vector2.new(0, 0)

	-- The keybind chip is real: E performs this button while the pop-out is up.
	-- A chip showing a key that did nothing would be worse than no chip.
	new("Frame", {
		Name = "KeyPlate", Parent = deckButton,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(30, 30),
		BackgroundColor3 = INK, BackgroundTransparency = 0.18,
		BorderSizePixel = 0, ZIndex = 8,
	}, { corner(10), stroke(Color3.new(1, 1, 1), 1, 0.72) })
	inked(text(deckButton, {
		Name = "Key", AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(30, 30),
		Text = "E", TextSize = 16, TextColor3 = Color3.new(1, 1, 1), ZIndex = 9,
	}), 2)

	----------------------------------------------------------------
	-- levelling panel
	----------------------------------------------------------------
	local levelPanel = new("Frame", {
		Name = "LevelPanel", Parent = column,
		Position = UDim2.fromOffset(0, LP_Y),
		Size = UDim2.fromOffset(COL_W, LP_H),
		BackgroundColor3 = PANEL, BorderSizePixel = 0, ZIndex = 4,
	}, { corner(16), stroke(INK, 3, 0.02) })

	essenceButton = new("TextButton", {
		Name = "EssenceButton", Parent = levelPanel,
		Position = UDim2.fromOffset(PAD, 12), Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = SUNK, BorderSizePixel = 0,
		Text = "", AutoButtonColor = false, ZIndex = 6,
	}, { corner(14), stroke(INK, 2.5, 0.05) })
	essenceHost = new("Frame", {
		Name = "Host", Parent = essenceButton,
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 7,
	})
	new("Frame", {
		Name = "BadgePlate", Parent = essenceButton,
		Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(19, 19),
		BackgroundColor3 = INK, BackgroundTransparency = 0.08,
		BorderSizePixel = 0, ZIndex = 8,
	}, { corner(999) })
	essenceBadge = inked(text(essenceButton, {
		Name = "Badge", Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(19, 19), Text = "B", TextSize = 11, ZIndex = 9,
	}), 1.8)

	essenceCount = inked(text(levelPanel, {
		Name = "EssenceCount", Position = UDim2.fromOffset(PAD, 88),
		Size = UDim2.fromOffset(72, 16), Text = "x0", TextSize = 13, ZIndex = 6,
	}), 2)

	-- A real chip rather than loose grey words: it reads as something you press.
	local changeChip = new("Frame", {
		Name = "ChangeChip", Parent = levelPanel,
		Position = UDim2.fromOffset(PAD, 106), Size = UDim2.fromOffset(72, 18),
		BackgroundColor3 = RAISED, BorderSizePixel = 0, ZIndex = 6,
	}, { corner(9), stroke(LINE, 1, 0.5) })
	text(changeChip, {
		Name = "Label", Size = UDim2.fromScale(1, 1),
		Text = "CHANGE", TextSize = 9, TextColor3 = MUTED, ZIndex = 7,
	})

	text(levelPanel, {
		Name = "Rule", Position = UDim2.fromOffset(RIGHT_X, 12),
		Size = UDim2.fromOffset(RIGHT_W, 26),
		Text = ("Each level: +%s%% base HP and DMG")
			:format(tostring(GameConfig.StatBonusPerLevel * 100)),
		TextSize = 10, TextColor3 = MUTED, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6,
	})

	levelLabel = inked(text(levelPanel, {
		Name = "LevelLabel", Position = UDim2.fromOffset(RIGHT_X, 42),
		Size = UDim2.fromOffset(110, 20), Text = "LEVEL 0", TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6,
	}), 2)
	levelRight = text(levelPanel, {
		Name = "LevelRight", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 45), Size = UDim2.fromOffset(90, 16),
		Text = "0 / 100", TextSize = 12, TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6,
	})

	local levelTrack = new("Frame", {
		Name = "LevelTrack", Parent = levelPanel,
		Position = UDim2.fromOffset(RIGHT_X, 66), Size = UDim2.fromOffset(RIGHT_W, 11),
		BackgroundColor3 = SUNK, BorderSizePixel = 0, ZIndex = 6,
	}, { corner(6), stroke(INK, 2, 0.1) })
	levelFill = new("Frame", {
		Name = "Fill", Parent = levelTrack, Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = PURPLE, BorderSizePixel = 0, ZIndex = 7,
	}, { corner(6) })

	gainLabel = inked(text(levelPanel, {
		Name = "Gain", Position = UDim2.fromOffset(RIGHT_X, 82),
		Size = UDim2.fromOffset(RIGHT_W, 16), Text = "", TextSize = 12,
		TextColor3 = GOOD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6,
	}), 2)

	----------------------------------------------------------------
	-- amount row
	----------------------------------------------------------------
	amountLabel = text(levelPanel, {
		Name = "AmountLabel", Position = UDim2.fromOffset(PAD, 130),
		Size = UDim2.fromOffset(120, 15), Text = "AMOUNT", TextSize = 10,
		TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6,
	})
	qtyLabel = inked(text(levelPanel, {
		Name = "Qty", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, 128), Size = UDim2.fromOffset(150, 17),
		Text = "x1", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
	}), 2)

	sliderTrack = new("Frame", {
		Name = "SliderTrack", Parent = levelPanel,
		Position = UDim2.fromOffset(PAD, 152), Size = UDim2.fromOffset(INNER, 10),
		BackgroundColor3 = SUNK, BorderSizePixel = 0, ZIndex = 6,
	}, { corner(5), stroke(INK, 2, 0.1) })
	sliderFill = new("Frame", {
		Name = "Fill", Parent = sliderTrack, Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 7,
	}, { corner(5) })
	sliderKnob = new("Frame", {
		Name = "Knob", Parent = sliderTrack, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 8,
	}, { corner(999), stroke(INK, 2.5, 0.02) })

	-- A generous invisible hit area over the 10px track. Nobody should have to
	-- hit ten pixels to choose how much essence to spend.
	sliderHit = new("TextButton", {
		Name = "SliderHit", Parent = levelPanel,
		Position = UDim2.fromOffset(PAD - 6, 142), Size = UDim2.fromOffset(INNER + 12, 30),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 9,
	})

	useButton, useLabel = pill(levelPanel, {
		Name = "UseButton", Position = UDim2.fromOffset(PAD, 172),
		Size = UDim2.fromOffset(INNER, 44), Height = 44,
		Text = "USE", TextSize = 18, ZIndex = 6,
	}, GOLD)

	----------------------------------------------------------------
	-- the picker, laid over the panel
	----------------------------------------------------------------
	picker = new("Frame", {
		Name = "Picker", Parent = levelPanel,
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = PANEL,
		BorderSizePixel = 0, Visible = false, ZIndex = 12,
	}, { corner(16), stroke(INK, 3, 0.02) })

	text(picker, {
		Name = "Title", Position = UDim2.fromOffset(PAD, 12),
		Size = UDim2.fromOffset(INNER, 16), Text = "YOUR ESSENCE", TextSize = 11,
		TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13,
	})

	local TILE = math.floor((INNER - 4 * 6) / 5)
	for index, essenceId in ipairs(BookDefinitions.Order) do
		local def = BookDefinitions.get(essenceId)
		local tierVariant = VariantConfig.get(def.variant or "Standard")

		local frame = new("TextButton", {
			Name = "Pick" .. (def.tier or essenceId), Parent = picker,
			Position = UDim2.fromOffset(PAD + (index - 1) * (TILE + 6), 34),
			Size = UDim2.fromOffset(TILE, TILE + 30),
			BackgroundColor3 = SUNK, BorderSizePixel = 0,
			Text = "", AutoButtonColor = false, ZIndex = 13,
		}, { corner(11) })
		local edge = stroke(LINE, 1.2, 0.55)
		edge.Parent = frame

		local image = ElderEssence.attach(frame, def.tier or "I", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 2),
			Size = UDim2.fromOffset(TILE - 8, TILE - 8),
			ZIndex = 14,
		})
		local count = inked(text(frame, {
			Name = "Count", AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, TILE - 4),
			Size = UDim2.fromOffset(TILE, 14), Text = "x0", TextSize = 11,
			TextColor3 = tierVariant.color, ZIndex = 15,
		}), 2)
		local grant = text(frame, {
			Name = "Grant", AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, TILE + 10),
			Size = UDim2.fromOffset(TILE, 14), Text = "", TextSize = 9,
			TextColor3 = MUTED, ZIndex = 15,
		})

		table.insert(pickerTiles, {
			tier = def.tier, essenceId = essenceId, frame = frame, image = image,
			count = count, grant = grant, stroke = edge, colour = tierVariant.color,
		})
		frame.Activated:Connect(function()
			selectTier(def.tier)
			paintPicker()
			setPickerOpen(false)
		end)
		frame.MouseEnter:Connect(function()
			local owned = ownedEssence(essenceId)
			pickerNote.Text = ("%s  \u{2022}  %s levels  \u{2022}  x%s held")
				:format(def.name, def.toMax and "all remaining" or tostring(def.levels),
					Format.comma(owned))
			pickerNote.TextColor3 = MUTED
		end)
		frame.MouseLeave:Connect(paintPicker)
	end

	pickerNote = text(picker, {
		Name = "Note", Position = UDim2.fromOffset(PAD, 138),
		Size = UDim2.fromOffset(INNER, 26), Text = "", TextSize = 11,
		TextColor3 = MUTED, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13,
	})

	local backButton = pill(picker, {
		Name = "BackButton", Position = UDim2.fromOffset(PAD, 172),
		Size = UDim2.fromOffset(INNER, 44), Height = 44,
		Text = "DONE", TextSize = 17, ZIndex = 13,
	}, RAISED)

	----------------------------------------------------------------
	-- behaviour
	----------------------------------------------------------------

	blocker.Activated:Connect(function() CardActions.close() end)
	deckButton.Activated:Connect(pressDeck)
	removeButton.Activated:Connect(pressRemove)
	useButton.Activated:Connect(applyLevelUp)
	essenceButton.Activated:Connect(function() setPickerOpen(true) end)
	backButton.Activated:Connect(function() setPickerOpen(false) end)

	sliderHit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			sliderValueFrom(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			sliderValueFrom(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not CardActions.isOpen() then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			-- Escape backs out of the picker first, then the pop-out. One press
			-- should undo one layer.
			if picker.Visible then setPickerOpen(false) else CardActions.close() end
		elseif input.KeyCode == Enum.KeyCode.E and not picker.Visible then
			pressDeck()
		end
	end)

	Theme.bind(gui)
end

----------------------------------------------------------------
-- PLACEMENT
----------------------------------------------------------------

-- Park beside the tile that was pressed: to its right if there is room, its
-- left if not, clamped so no part leaves the screen. The pop-out belongs to the
-- card, so it follows the card rather than sitting in the middle of the screen
-- wherever the card happened to be.
local function placeNear(anchor: GuiObject?)
	local view = gui.AbsoluteSize
	if not anchor or anchor.AbsoluteSize.X <= 0 then
		root.Position = UDim2.fromOffset(
			math.floor((view.X - ROOT_W) / 2), math.floor((view.Y - ROOT_H) / 2))
		return
	end

	local at, size = anchor.AbsolutePosition, anchor.AbsoluteSize
	-- AbsolutePosition excludes the topbar inset but this ScreenGui ignores it,
	-- so the inset is added back or the pop-out sits high by the inset's height.
	local originY = at.Y + GuiService:GetGuiInset().Y

	local x = at.X + size.X + 16
	if x + ROOT_W > view.X - 10 then x = at.X - ROOT_W - 16 end
	x = math.clamp(x, 10, math.max(10, view.X - ROOT_W - 10))

	local y = originY + size.Y / 2 - ROOT_H / 2
	y = math.clamp(y, 10, math.max(10, view.Y - ROOT_H - 10))

	root.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

----------------------------------------------------------------
-- PUBLIC
----------------------------------------------------------------

function CardActions.isOpen(): boolean
	return gui ~= nil and gui.Parent ~= nil and gui.Enabled
end

function CardActions.close()
	if not gui or not gui.Enabled then return end
	openToken += 1
	currentItem = nil
	selectedTier = nil
	dragging = false
	quantity = 1
	if picker then picker.Visible = false end
	gui.Enabled = false
end

-- `item` is { cardId, variant, level, count } as the collection builds it.
-- `anchor` is the tile that was pressed; the pop-out parks beside it.
-- `handlers` supplies equip / unequip / equippedIndex, because who owns the
-- deck is the deck screen's business, not this pop-out's.
function CardActions.open(item: any, profile: any, incoming: any, anchor: GuiObject?)
	if not item then return end
	build()

	openToken += 1
	currentItem = item
	currentProfile = profile
	handlers = incoming
	quantity = 1
	setPickerOpen(false)

	-- Open on the largest essence that would actually do something, so the
	-- common case - "level this as far as I can right now" - is one press. The
	-- picker is there for every other case.
	selectedTier = bestUsableTier()
	setEssenceArt(selectedTier)

	CardRenderer.update(card, {
		cardId = item.cardId, variant = item.variant, level = item.level or 0 })

	-- THE BORDER CARRIES OVER: the card wears its own tier frame.
	Shine.apply(cardHolder, VariantConfig.get(item.variant).id, CARD_W)

	repaint()
	gui.Enabled = true
	placeNear(anchor)

	-- Pop in. The snap afterwards is not belt-and-braces for its own sake: if
	-- the tween never runs - a stalled render, a client that lost focus at the
	-- wrong moment - the pop-out would sit at 90% forever, which reads as a
	-- broken layout rather than a missing animation.
	rootScale.Scale = 0.9
	local token = openToken
	TweenService:Create(rootScale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
	task.delay(0.3, function()
		if token == openToken then rootScale.Scale = 1 end
	end)
end

-- Repaints against whatever the deck screen now predicts, without waiting for
-- the server: an E press changes the line-up locally at once, and the count
-- on the pill should move with it.
function CardActions.refresh()
	if CardActions.isOpen() and currentItem then repaint() end
end

-- Called when the profile replicates, so the level bar, the counts and the
-- slider follow a successful level-up without the pop-out being reopened.
function CardActions.setProfile(profile: any)
	currentProfile = profile
	if not CardActions.isOpen() or not currentItem then return end

	CardRenderer.update(card, {
		cardId = currentItem.cardId, variant = currentItem.variant,
		level = currentLevel() })

	-- If what was selected has run out or would now overflow, fall back to
	-- whatever still works rather than leaving a dead selection on screen.
	if usableCount(selectedTier) <= 0 then
		selectedTier = bestUsableTier()
		quantity = 1
		setEssenceArt(selectedTier)
	end
	repaint()
	if picker.Visible then paintPicker() end
end

return CardActions
