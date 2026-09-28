--!strict
-- Anime Card Online - polished battle UI controller.
--
-- IMPORTANT:
-- This is a COMPLETE replacement for the existing BattleController only.
-- It does NOT replace or duplicate battle logic, damage, HP, abilities,
-- enemy AI, deck data, card rendering, rarity visuals, location mechanics, remotes,
-- player saves, rolling, or leaderboard logic.
--
-- Put this ModuleScript at:
-- StarterPlayer > StarterPlayerScripts > Client > Controllers > BattleController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local BattleRemotes = require(ReplicatedStorage.Shared.Net.BattleRemotes)
local CardRenderer = require(ReplicatedStorage.Shared.UI.CardRenderer)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local LocationDefinitions = require(ReplicatedStorage.Shared.Config.LocationDefinitions)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CardStats = require(ReplicatedStorage.Shared.Util.CardStats)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local RewardPopup = require(ReplicatedStorage.Shared.UI.RewardPopup)

local BattleController = {}
BattleController.Name = "BattleController"

local player = Players.LocalPlayer

local function getExistingUISound(soundName: string): Sound?
	-- Reuse the exact UI sounds already used by the game's deck UI.
	-- No new SoundIds are introduced here.
	local found = SoundService:FindFirstChild(soundName, true)
	if found and found:IsA("Sound") then
		return found
	end
	return nil
end

local function playExistingUISound(soundName: string)
	local template = getExistingUISound(soundName)
	if not template then
		-- Fail silently so a missing cosmetic sound can never break battle UI.
		return
	end

	-- Clone the existing Sound so rapid UI interactions don't cut each other off.
	-- Cloning preserves its SoundId, volume, playback speed and SoundGroup.
	local sound = template:Clone()
	sound.Name = "Battle_" .. soundName
	sound.Parent = SoundService
	sound.TimePosition = 0
	sound:Play()
	Debris:AddItem(sound, math.max(sound.TimeLength + 1, 3))
end

local function playHoverSound()
	playExistingUISound("UIHover")
end

local function playClickSound()
	playExistingUISound("UIClick")
end

local function playRewardSound()
	-- Reward / victory sound requested for the battle reward popup.
	-- This is cosmetic only and does not affect rewards or battle logic.
	local sound = Instance.new("Sound")
	sound.Name = "BattleRewardSound"
	sound.SoundId = "rbxassetid://92895758368760"
	sound.Volume = 1
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 6)
end

local function wireButtonSounds(button: GuiButton)
	button.MouseEnter:Connect(playHoverSound)
	button.Activated:Connect(playClickSound)
end

-- ZIndex language used by this battle UI.
local Z = {
	Background = 1,
	Decoration = 2,
	Panel = 5,
	Slot = 10,
	Location = 15,
	Card = 20,
	Hover = 30,
	Drag = 50,
	Effect = 60,
	Notice = 100,
	Modal = 140,
	Test = 150,
}

local COLORS = {
	Panel = Color3.fromRGB(10, 11, 22),
	Panel2 = Color3.fromRGB(15, 13, 27),
	PanelStroke = Color3.fromRGB(84, 73, 128),
	Text = Color3.fromRGB(245, 245, 255),
	Muted = Color3.fromRGB(184, 186, 208),
	Gold = Color3.fromRGB(255, 220, 104),
	Enemy = Color3.fromRGB(255, 91, 108),
	EnemySoft = Color3.fromRGB(255, 147, 158),
	Player = Color3.fromRGB(142, 106, 255),
	PlayerSoft = Color3.fromRGB(201, 188, 255),
	Green = Color3.fromRGB(88, 255, 157),
	GreenSoft = Color3.fromRGB(211, 255, 226),
	Location = Color3.fromRGB(65, 172, 255),
	LocationSoft = Color3.fromRGB(218, 241, 255),
	Damage = Color3.fromRGB(255, 91, 91),
	Heal = Color3.fromRGB(112, 255, 150),
}

local gui: ScreenGui
local overlay: Frame
local stage: Frame
local dragLayer: Frame
local effectsLayer: Frame
local testButton: TextButton
local closeButton: TextButton
local roundLabel: TextLabel
local enemyNameLabel: TextLabel

local enemyHandPanel: Frame
local enemyHand: Frame
local enemyHandTitle: TextLabel
local enemyActiveHolder: Frame
local enemySlotText: TextLabel
local playerShowcaseHolder: Frame
local enemyShowcaseHolder: Frame

local locationHolder: Frame
local locationDiamond: Frame
local locationStroke: UIStroke
local locationImage: ImageLabel
local locationName: TextLabel
local locationDescriptionPanel: Frame
local locationInfoStroke: UIStroke
local locationDescription: TextLabel
local locationHint: TextLabel

local playerActiveHolder: Frame
local playerDropStroke: UIStroke
local playerSlotText: TextLabel
local playerSlotGlow: Frame

local playerHandPanel: Frame
local playerHand: Frame
local playerHandTitle: TextLabel

local playerBattlePowerValue: TextLabel
local enemyBattlePowerValue: TextLabel
local victoryChanceValue: TextLabel

local playerEffectsPanel: Frame
local playerEffectsList: ScrollingFrame
local enemyEffectsPanel: Frame
local enemyEffectsList: ScrollingFrame

local effectTooltip: Frame
local effectTooltipStroke: UIStroke
local effectTooltipIcon: TextLabel
local effectTooltipTitle: TextLabel
local effectTooltipAmount: TextLabel
local effectTooltipDescription: TextLabel
local effectTooltipSource: TextLabel
local effectTooltipTiming: TextLabel
local effectTooltipScale: UIScale

local noticeLabel: TextLabel
local resultPanel: Frame
local resultText: TextLabel
local resultSubText: TextLabel

local currentSnapshot = nil
local pendingSnapshot = nil
local dragging = nil
local cardRefs = {
	player = {},
	enemy = {},
}
local activeRefs = {
	player = nil,
	enemy = nil,
}
local showcaseRefs = {
	player = nil,
	enemy = nil,
}
local showcaseKeys = {
	player = nil,
	enemy = nil,
}
local outcomeToken = 0

-- Diameter of an effect chip. Chips are icon-only, so this is the whole chip,
-- and the effects panel's grid cell is sized from it.
local EFFECT_ICON_SIZE = 34

local effectChipRefs = {
	player = {},
	enemy = {},
}
local effectSequence = 0
local hoveredEffectRef = nil

local lobbyHudPreviousEnabled: boolean? = nil
local lastBattleId: string? = nil

local function new(className: string, props)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		(instance :: any)[key] = value
	end
	return instance
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	return new("UIStroke", {
		Parent = parent,
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		LineJoinMode = Enum.LineJoinMode.Round,
	}) :: UIStroke
end

local function corner(parent: Instance, radius: number)
	new("UICorner", {
		Parent = parent,
		CornerRadius = UDim.new(0, radius),
	})
end

local function pad(parent: Instance, top: number, bottom: number, left: number, right: number)
	new("UIPadding", {
		Parent = parent,
		PaddingTop = UDim.new(0, top),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
		PaddingRight = UDim.new(0, right),
	})
end

local function addTextConstraint(parent: TextLabel | TextButton, minSize: number, maxSize: number)
	new("UITextSizeConstraint", {
		Parent = parent,
		MinTextSize = minSize,
		MaxTextSize = maxSize,
	})
end

local function label(
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2,
	textSize: number,
	zIndex: number?
)
	local l = new("TextLabel", {
		Parent = parent,
		Size = size,
		Position = position,
		BackgroundTransparency = 1,
		Text = text,
		FontFace = Theme.font(),
		TextSize = textSize,
		TextColor3 = COLORS.Text,
		TextStrokeColor3 = Color3.fromRGB(8, 8, 15),
		TextStrokeTransparency = 0.48,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = zIndex or Z.Card,
	}) :: TextLabel
	return l
end


local function comma(value: number): string
	local n = math.floor(math.max(0, value))
	local s = tostring(n)
	local sign, digits = s:match("^([%-]?)(%d+)$")
	if not digits then
		return s
	end
	local reversed = digits:reverse():gsub("(%d%d%d)", "%1,")
	reversed = reversed:gsub(",$", "")
	return (sign or "") .. reversed:reverse()
end

local function addMovingPowerGradient(textObject: TextLabel)
	-- Matches the moving red -> orange -> gold Battle Power treatment used
	-- by the custom leaderboard.
	textObject.TextColor3 = Color3.new(1, 1, 1)
	local gradient = new("UIGradient", {
		Parent = textObject,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 55, 35)),
			ColorSequenceKeypoint.new(0.28, Color3.fromRGB(255, 104, 35)),
			ColorSequenceKeypoint.new(0.52, Color3.fromRGB(255, 178, 48)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 92, 28)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(230, 42, 28)),
		}),
		Offset = Vector2.new(-0.45, 0),
		Rotation = 0,
	}) :: UIGradient

	local tween = TweenService:Create(
		gradient,
		TweenInfo.new(1.55, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true),
		{ Offset = Vector2.new(0.45, 0) }
	)
	tween:Play()
	return gradient, tween
end

local function entryBattlePower(entry): number
	if not entry or not entry.cardId then
		return 0
	end

	local total = 0
	local def = CardStats.definition(entry.cardId)
	if def and def.baseRarity then
		local variant = VariantConfig.get(entry.variant or "Standard")
		total += VariantConfig.effectiveRarity(def.baseRarity, variant.id)
	end

	-- Supports are NOT counted. They have no combat stats, they are Standard-only,
	-- and including them let a player pad their party power with cards that never
	-- take the field. This matches LeaderboardService, so the number on the
	-- battle screen and the number on the leaderboard are computed the same way.

	return total
end

local function sideBattlePower(sideSnapshot): number
	if not sideSnapshot then
		return 0
	end
	local total = 0
	for _, card in ipairs(sideSnapshot.hand or {}) do
		total += entryBattlePower(card)
	end
	if sideSnapshot.active then
		total += entryBattlePower(sideSnapshot.active)
	end
	return total
end

local function updateBattleMetrics(snapshot)
	if not snapshot or not snapshot.player or not snapshot.enemy then
		return
	end

	local playerPower = sideBattlePower(snapshot.player)
	local enemyPower = sideBattlePower(snapshot.enemy)
	local combined = playerPower + enemyPower

	local victoryChance = 50
	if combined > 0 then
		victoryChance = math.floor((playerPower / combined) * 100 + 0.5)
	end
	victoryChance = math.clamp(victoryChance, 0, 100)

	if playerBattlePowerValue then
		playerBattlePowerValue.Text = comma(playerPower)
	end
	if enemyBattlePowerValue then
		enemyBattlePowerValue.Text = comma(enemyPower)
	end
	if victoryChanceValue then
		victoryChanceValue.Text = tostring(victoryChance) .. "%"
		if victoryChance >= 60 then
			victoryChanceValue.TextColor3 = COLORS.Green
		elseif victoryChance <= 40 then
			victoryChanceValue.TextColor3 = COLORS.Enemy
		else
			victoryChanceValue.TextColor3 = COLORS.Gold
		end
	end
end

local function scaledLabel(
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2,
	minText: number,
	maxText: number,
	zIndex: number?
)
	local l = label(parent, text, size, position, maxText, zIndex)
	l.TextScaled = true
	addTextConstraint(l, minText, maxText)
	return l
end

local function clearCards(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:GetAttribute("BattleCardSlot") or child:GetAttribute("BattleGenerated") then
			child:Destroy()
		end
	end
end

-- âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
-- Battle effect presentation
--
-- The server remains the source of truth. These tables only decide how a real
-- effect is NAMED and COLORED on screen. Amounts, stacks, duration, source and
-- applied round all come from BattleRuntime snapshots/events.
-- âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

local EFFECT_VISUALS = {
	Burn = { name = "Burn", icon = "BRN", color = Color3.fromRGB(255, 113, 54) },
	Bleed = { name = "Bleed", icon = "BLD", color = Color3.fromRGB(235, 65, 80) },
	Brand = { name = "Brand", icon = "BRD", color = Color3.fromRGB(220, 73, 106) },
	Freeze = { name = "Stun", icon = "STN", color = Color3.fromRGB(109, 164, 255) },
	TimeStop = { name = "Time Stop", icon = "TIME", color = Color3.fromRGB(156, 121, 255) },
	Shield = { name = "Shield", icon = "SH", color = Color3.fromRGB(77, 174, 255) },
	DmgUp = { name = "DMG Buff", icon = "DMG", color = Color3.fromRGB(255, 177, 58) },
	CritUp = { name = "Crit Buff", icon = "CRT", color = Color3.fromRGB(255, 219, 72) },
	DmgReduction = { name = "DMG Reduction", icon = "RES", color = Color3.fromRGB(69, 203, 218) },
	Chained = { name = "Chained", icon = "LOCK", color = Color3.fromRGB(175, 91, 211) },
	ExtraAttackChance = { name = "Double Strike", icon = "2X", color = Color3.fromRGB(255, 196, 66) },
	AbilityActivation = { name = "Ability", icon = "ABL", color = Color3.fromRGB(247, 206, 82) },
}

local function roundPercent(value: number): number
	return math.floor((value * 100) + 0.5)
end

local function effectVisual(effect)
	if effect.abilityActivation then
		return EFFECT_VISUALS.AbilityActivation
	end
	local visual = EFFECT_VISUALS[effect.effectType or effect.id]
	if visual then
		return visual
	end
	if effect.isDebuff then
		return { name = effect.displayName or "Debuff", icon = "DB", color = Color3.fromRGB(230, 77, 96) }
	end
	return { name = effect.displayName or "Buff", icon = "BF", color = Color3.fromRGB(83, 211, 139) }
end

local function effectDisplayName(effect): string
	if effect.abilityActivation then
		return effect.displayName or "Ability"
	end
	local visual = effectVisual(effect)
	return visual.name or effect.displayName or effect.effectType or effect.id or "Effect"
end

local function effectAmountText(effect): string
	if effect.abilityActivation then
		return "ABILITY ACTIVATED"
	end

	local id = effect.effectType or effect.id
	local stacks = math.max(1, effect.stacks or 1)
	local potency = effect.potency or 0
	local sourceDmg = effect.sourceDmg or 0

	if id == "Burn" or id == "Bleed" then
		local amount = math.floor(sourceDmg * potency * stacks)
		return amount > 0 and (tostring(amount) .. " Damage / Round") or "Damage over time"
	elseif id == "DmgUp" then
		return "+" .. tostring(roundPercent(potency * stacks)) .. "% Damage"
	elseif id == "CritUp" then
		return "+" .. tostring(roundPercent(potency * stacks)) .. "% Crit Chance"
	elseif id == "DmgReduction" then
		local effectiveReduction = math.min(GameConfig.MaxDamageReduction, potency * stacks)
		return tostring(roundPercent(effectiveReduction)) .. "% Damage Reduction"
	elseif id == "Shield" then
		local shield = math.floor((effect.maxHP or 0) * potency * stacks)
		return shield > 0 and (tostring(shield) .. " Shield") or "Damage Shield"
	elseif id == "Freeze" then
		return "Cannot act"
	elseif id == "TimeStop" then
		return "Enemies cannot act"
	elseif id == "Brand" then
		return stacks > 1 and (tostring(stacks) .. " Brand Stacks") or "Takes bonus damage"
	elseif id == "Chained" then
		return "Cannot be swapped"
	elseif id == "ExtraAttackChance" then
		return "+" .. tostring(roundPercent(effect.value or 0)) .. "% Double Strike Chance"
	end

	if effect.valueType == "Chance" then
		return "+" .. tostring(roundPercent(effect.value or 0)) .. "% Chance"
	end
	if effect.value and effect.value ~= 0 then
		return tostring(effect.value)
	end
	return effect.description ~= "" and effect.description or "Active effect"
end

local function effectDescriptionText(effect): string
	if effect.abilityActivation then
		return effect.description ~= "" and effect.description or "This ability triggered during combat."
	end

	local id = effect.effectType or effect.id
	if id == "Burn" then
		return "Takes damage at the end of each round."
	elseif id == "Bleed" then
		return "Takes damage at the end of each round, based on the hit that applied it."
	elseif id == "DmgUp" then
		return "Increases this card's outgoing damage."
	elseif id == "CritUp" then
		return "Increases this card's critical hit chance."
	elseif id == "DmgReduction" then
		return "Reduces incoming damage before HP is lost."
	elseif id == "Shield" then
		return "Absorbs incoming damage before HP is lost."
	end
	return effect.description ~= "" and effect.description or "This effect is currently active."
end

local function effectTimingText(effect): string
	local appliedRound = effect.appliedRound or (currentSnapshot and currentSnapshot.round) or 1
	local duration = effect.duration or 0
	local timing = "Applied: Round " .. tostring(appliedRound)
	if effect.abilityActivation then
		-- Repeat activations pulse one chip rather than adding more, so this count is
		-- the only place the repetition is visible.
		local count = effect.triggerCount or 1
		if count > 1 then
			return ("Triggered %dx, last Round %s"):format(count, tostring(appliedRound))
		end
		return "Triggered: Round " .. tostring(appliedRound)
	elseif duration <= 0 then
		return timing .. "\nDuration: Until battle ends"
	elseif duration == 1 then
		return timing .. "\nRemaining: 1 round"
	end
	return timing .. "\nRemaining: " .. tostring(duration) .. " rounds"
end

local function effectSourceText(effect): string
	local sourceAbility = effect.sourceAbility
	local sourceCard = effect.sourceCard
	if sourceAbility and sourceCard then
		return sourceAbility .. "\nFrom: " .. sourceCard
	elseif sourceAbility then
		return "Source: " .. sourceAbility
	elseif sourceCard then
		return "From: " .. sourceCard
	end
	return "Source: Battle effect"
end

local function hideEffectTooltip()
	hoveredEffectRef = nil
	if not effectTooltip or not effectTooltip.Parent then
		return
	end

	local token = os.clock()
	effectTooltip:SetAttribute("HideToken", token)
	TweenService:Create(effectTooltipScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 0.96,
	}):Play()
	TweenService:Create(effectTooltip, TweenInfo.new(0.12), {
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(effectTooltipStroke, TweenInfo.new(0.12), {
		Transparency = 1,
	}):Play()
	for _, descendant in ipairs(effectTooltip:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, TweenInfo.new(0.12), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end
	end
	task.delay(0.13, function()
		if effectTooltip and effectTooltip:GetAttribute("HideToken") == token then
			effectTooltip.Visible = false
		end
	end)
end

local function showEffectTooltip(side: string, effect, ref)
	if not effectTooltip or not effectTooltip.Parent then
		return
	end

	hoveredEffectRef = ref
	effectTooltip:SetAttribute("HideToken", 0)
	local visual = effectVisual(effect)
	local leftSide = side == "player"

	-- Keep the tooltip in the outer lane and line it up vertically with the
	-- hovered effect. A taller fixed-height layout prevents amount/description/
	-- source/timing text from ever drawing on top of each other.
	effectTooltip.AnchorPoint = leftSide and Vector2.new(0, 0) or Vector2.new(1, 0)
	local stageSize = stage.AbsoluteSize
	local tooltipWidth = math.clamp(stageSize.X * 0.145, 225, 285)
	local tooltipHeight = math.clamp(stageSize.Y * 0.30, 245, 270)
	local chipCenterY = (ref.root.AbsolutePosition.Y - stage.AbsolutePosition.Y) + (ref.root.AbsoluteSize.Y * 0.5)
	local tooltipTop = math.clamp(chipCenterY - (tooltipHeight * 0.28), 8, math.max(8, stageSize.Y - tooltipHeight - 8))
	effectTooltip.Position = leftSide and UDim2.fromOffset(8, tooltipTop) or UDim2.new(1, -8, 0, tooltipTop)
	effectTooltip.Size = UDim2.fromOffset(tooltipWidth, tooltipHeight)
	effectTooltip.BackgroundColor3 = Color3.fromRGB(11, 13, 23)
	effectTooltip.BackgroundTransparency = 0.08
	effectTooltipStroke.Color = visual.color
	effectTooltipStroke.Transparency = 0.18
	effectTooltip.Visible = true

	effectTooltipIcon.Text = visual.icon
	effectTooltipIcon.TextColor3 = visual.color
	-- The chip carries no visible text, so the tooltip is the only place the player
	-- can tell an expired effect from a live one.
	local expired = ref ~= nil and ref.expired == true
	effectTooltipTitle.Text = string.upper(effectDisplayName(effect)) .. (expired and "  (ENDED)" or "")
	effectTooltipTitle.TextColor3 = expired and Color3.fromRGB(150, 152, 170) or COLORS.Text
	effectTooltipAmount.Text = effectAmountText(effect)
	effectTooltipAmount.TextColor3 = visual.color
	effectTooltipDescription.Text = effectDescriptionText(effect)
	effectTooltipSource.Text = effectSourceText(effect)
	effectTooltipTiming.Text = effectTimingText(effect)

	for _, descendant in ipairs(effectTooltip:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			descendant.TextTransparency = 0
			descendant.TextStrokeTransparency = math.min(descendant.TextStrokeTransparency, 0.78)
		end
	end

	effectTooltipScale.Scale = 0.95
	TweenService:Create(effectTooltipScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

-- Effects are never deleted mid-battle now, so "no longer active" has to be
-- shown rather than removed. An expired chip fades back and desaturates: the
-- record stays readable without competing with what is actually running.
local function setChipExpired(ref, expired: boolean)
	if not ref or not ref.root or not ref.root.Parent then
		return
	end
	if ref.expired == expired then
		return
	end
	ref.expired = expired

	local visual = effectVisual(ref.effect)
	local target = expired and visual.color:Lerp(Color3.fromRGB(70, 72, 88), 0.68) or visual.color
	TweenService:Create(ref.iconBackground, TweenInfo.new(0.22), {
		BackgroundColor3 = target,
		BackgroundTransparency = expired and 0.42 or 0.06,
	}):Play()
	TweenService:Create(ref.stroke, TweenInfo.new(0.22), {
		Transparency = expired and 0.72 or 0.32,
	}):Play()
	TweenService:Create(ref.icon, TweenInfo.new(0.22), {
		TextTransparency = expired and 0.45 or 0,
	}):Play()
end

local function updateEffectChip(ref, effect)
	ref.effect = effect
	local visual = effectVisual(effect)
	ref.stroke.Color = visual.color
	-- Only repaint the disc while the chip is live; an expired chip keeps the
	-- muted colour setChipExpired gave it.
	if not ref.expired then
		ref.iconBackground.BackgroundColor3 = visual.color
	end
	ref.icon.Text = visual.icon
	ref.icon.TextColor3 = Color3.fromRGB(255, 255, 255)
	ref.name.Text = effectDisplayName(effect)

	local stacks = math.max(1, effect.stacks or 1)
	local duration = effect.duration or 0
	if effect.abilityActivation then
		ref.counter.Text = "!"
	elseif stacks > 1 then
		ref.counter.Text = "Ã" .. tostring(stacks)
	elseif duration > 0 then
		ref.counter.Text = tostring(duration)
	else
		ref.counter.Text = "â"
	end
	ref.counter.TextColor3 = visual.color

	if hoveredEffectRef == ref then
		showEffectTooltip(ref.side, effect, ref)
	end
end

local function removeEffectChip(side: string, id: string, animate: boolean?)
	local ref = effectChipRefs[side][id]
	if not ref then
		return
	end
	effectChipRefs[side][id] = nil
	if hoveredEffectRef == ref then
		hideEffectTooltip()
	end

	if not ref.root or not ref.root.Parent then
		return
	end
	if animate == false then
		ref.root:Destroy()
		return
	end

	TweenService:Create(ref.scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Scale = 0.86,
	}):Play()
	TweenService:Create(ref.root, TweenInfo.new(0.18), {
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(ref.stroke, TweenInfo.new(0.18), {
		Transparency = 1,
	}):Play()
	for _, descendant in ipairs(ref.root:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, TweenInfo.new(0.18), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		elseif descendant:IsA("Frame") then
			TweenService:Create(descendant, TweenInfo.new(0.18), {
				BackgroundTransparency = 1,
			}):Play()
		end
	end
	task.delay(0.19, function()
		if ref.root and ref.root.Parent then
			ref.root:Destroy()
		end
	end)
end

local function createEffectChip(side: string, effect, transient: boolean?)
	local container = side == "player" and playerEffectsList or enemyEffectsList
	if not container then
		return nil
	end

	effectSequence += 1
	local id = effect.id or ("Effect_" .. tostring(effectSequence))
	local root = new("Frame", {
		Name = "Effect_" .. tostring(id),
		Parent = container,
		-- ICON ONLY. This was a 42-tall row carrying the effect's name and a
		-- stack/duration counter. Effects persist for the whole battle now, so
		-- named rows would run off the panel within a couple of rounds; the name,
		-- stacks and duration all live in the hover tooltip instead.
		Size = UDim2.fromOffset(EFFECT_ICON_SIZE, EFFECT_ICON_SIZE),
		BackgroundColor3 = Color3.fromRGB(17, 18, 30),
		BackgroundTransparency = 0.14,
		BorderSizePixel = 0,
		LayoutOrder = effectSequence,
		Active = true,
		ZIndex = Z.Hover,
	}) :: Frame
	corner(root, math.floor(EFFECT_ICON_SIZE / 2))
	local chipStroke = stroke(root, Color3.fromRGB(110, 110, 140), 1.25, 0.32)
	new("UIGradient", {
		Parent = root,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(31, 30, 49)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 13, 24)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.10),
			NumberSequenceKeypoint.new(1, 0.36),
		}),
	})
	local chipScale = new("UIScale", { Parent = root, Scale = 0.90, Name = "EffectScale" }) :: UIScale

	local iconBackground = new("Frame", {
		Parent = root,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(EFFECT_ICON_SIZE - 4, EFFECT_ICON_SIZE - 4),
		BackgroundColor3 = COLORS.Green,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		ZIndex = Z.Hover + 1,
	}) :: Frame
	corner(iconBackground, math.floor((EFFECT_ICON_SIZE - 4) / 2))
	stroke(iconBackground, Color3.fromRGB(255, 255, 255), 1, 0.64)

	local icon = scaledLabel(iconBackground, "FX", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 9, 13, Z.Hover + 2)
	icon.TextStrokeTransparency = 0.72

	local nameLabel = scaledLabel(root, "EFFECT", UDim2.new(1, -74, 1, 0), UDim2.fromOffset(41, 0), 9, 13, Z.Hover + 1)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = COLORS.Text
	nameLabel.TextStrokeTransparency = 0.62
	nameLabel.TextWrapped = false
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	-- Kept as an instance but never shown: updateEffectChip still writes to it,
	-- and hiding it here is what makes the chip read as a bare icon.
	nameLabel.Visible = false

	local counter = scaledLabel(root, "", UDim2.fromOffset(28, 26), UDim2.new(1, -33, 0.5, -13), 9, 12, Z.Hover + 1)
	counter.TextStrokeTransparency = 0.72
	counter.Visible = false

	local ref = {
		id = id,
		side = side,
		root = root,
		stroke = chipStroke,
		scale = chipScale,
		iconBackground = iconBackground,
		icon = icon,
		name = nameLabel,
		counter = counter,
		effect = effect,
		transient = transient == true,
		expired = false,
		triggerCount = 1,
	}
	effectChipRefs[side][id] = ref
	updateEffectChip(ref, effect)

	root.MouseEnter:Connect(function()
		if not root.Parent then
			return
		end
		playHoverSound()
		TweenService:Create(chipScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1.04,
		}):Play()
		showEffectTooltip(side, ref.effect, ref)
	end)
	root.MouseLeave:Connect(function()
		if root.Parent then
			TweenService:Create(chipScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
		hideEffectTooltip()
	end)

	root.BackgroundTransparency = 1
	chipStroke.Transparency = 1
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			descendant.TextTransparency = 1
			descendant.TextStrokeTransparency = 1
		end
	end
	task.defer(function()
		if not root.Parent then
			return
		end
		TweenService:Create(root, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.14,
		}):Play()
		TweenService:Create(chipStroke, TweenInfo.new(0.22), { Transparency = 0.32 }):Play()
		TweenService:Create(chipScale, TweenInfo.new(0.23, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("TextLabel") then
				TweenService:Create(descendant, TweenInfo.new(0.20), {
					TextTransparency = 0,
					TextStrokeTransparency = 0.68,
				}):Play()
			end
		end
	end)

	return ref
end

local function upsertEffect(side: string, effect)
	if not effect or not effect.id then
		return
	end
	local ref = effectChipRefs[side][effect.id]
	if ref and ref.root and ref.root.Parent then
		updateEffectChip(ref, effect)
		ref.scale.Scale = 1.07
		TweenService:Create(ref.scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		return
	end
	createEffectChip(side, effect, false)
end

local function clearEffects(side: string, animate: boolean?)
	local ids = {}
	for id in pairs(effectChipRefs[side]) do
		table.insert(ids, id)
	end
	for _, id in ipairs(ids) do
		removeEffectChip(side, id, animate)
	end
end

local function reconcileEffects(side: string, effects)
	local wanted = {}
	for _, effect in ipairs(effects or {}) do
		if effect.id then
			wanted[effect.id] = true
			upsertEffect(side, effect)
		end
	end

	-- An effect that dropped out of the snapshot has EXPIRED, not vanished. It used
	-- to be deleted here, which is why buffs disappeared seconds after landing. The
	-- chip now stays for the rest of the battle and just dims, so the panel is a
	-- running record of everything that happened.
	for id, ref in pairs(effectChipRefs[side]) do
		if not ref.transient then
			setChipExpired(ref, not wanted[id])
		end
	end
end

local function showAbilityActivation(event)
	local side = event.side
	if side ~= "player" and side ~= "enemy" then
		return
	end
	local activeRef = activeRefs[side]
	if activeRef and event.slot and activeRef.data.slot ~= event.slot then
		return
	end

	-- Keyed by the ability itself, not a running counter. A passive that fires ten
	-- times must pulse ONE chip ten times, not stack ten identical discs down the
	-- panel now that nothing is ever removed.
	local abilityName = event.passiveName or event.passive or "Ability"
	local id = "Ability_" .. abilityName
	local existing = effectChipRefs[side][id]
	if existing and existing.root and existing.root.Parent then
		existing.triggerCount = (existing.triggerCount or 1) + 1
		existing.effect.triggerCount = existing.triggerCount
		existing.effect.appliedRound = event.round or existing.effect.appliedRound
		setChipExpired(existing, false)
		existing.scale.Scale = 1.14
		TweenService:Create(existing.scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		if hoveredEffectRef == existing then
			showEffectTooltip(side, existing.effect, existing)
		end
		return
	end

	local effect = {
		id = id,
		triggerCount = 1,
		effectType = "AbilityActivation",
		displayName = event.passiveName or event.passive or "Ability",
		description = event.passiveDescription or "This ability triggered during combat.",
		abilityActivation = true,
		isDebuff = false,
		sourceCard = event.sourceCardName or event.cardName,
		sourceAbility = event.passiveName or event.passive,
		appliedRound = event.round or (currentSnapshot and currentSnapshot.round) or 1,
	}
	-- Part of the permanent record too. transient = true only marks it exempt from
	-- the expiry sweep (it is never in the status snapshot); it is not removed.
	local ref = createEffectChip(side, effect, false)
	if ref then
		ref.transient = true
	end
end

local function makeEffectsPanel(parent: Frame, side: string)
	local playerSide = side == "player"
	local accent = playerSide and COLORS.Player or COLORS.Enemy
	local panel = new("Frame", {
		Name = playerSide and "PlayerEffects" or "EnemyEffects",
		Parent = parent,
		AnchorPoint = playerSide and Vector2.new(0, 0.5) or Vector2.new(1, 0.5),
		Position = playerSide and UDim2.fromScale(0.006, 0.54) or UDim2.fromScale(0.994, 0.54),
		Size = UDim2.fromScale(0.095, 0.42),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = Z.Panel,
	}) :: Frame

	local title = scaledLabel(panel, playerSide and "PLAYER EFFECTS" or "ENEMY EFFECTS", UDim2.fromScale(1, 0.10), UDim2.fromScale(0, 0), 9, 13, Z.Hover)
	title.TextColor3 = playerSide and COLORS.PlayerSoft or COLORS.EnemySoft
	title.TextStrokeTransparency = 0.60

	local accentLine = new("Frame", {
		Parent = panel,
		Position = playerSide and UDim2.fromScale(0.99, 0.13) or UDim2.fromScale(0, 0.13),
		Size = UDim2.new(0, 2, 0.82, 0),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = Z.Panel,
	}) :: Frame
	corner(accentLine, 2)

	local list = new("ScrollingFrame", {
		Name = "EffectList",
		Parent = panel,
		Position = UDim2.fromScale(0, 0.13),
		Size = UDim2.fromScale(0.96, 0.84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = accent,
		ScrollBarImageTransparency = 0.45,
		ClipsDescendants = true,
		ZIndex = Z.Panel,
	}) :: ScrollingFrame
	-- A grid, not a column: icon-only chips are small and a battle can end with a
	-- dozen of them, so they wrap instead of running off the bottom.
	new("UIGridLayout", {
		Parent = list,
		CellSize = UDim2.fromOffset(EFFECT_ICON_SIZE, EFFECT_ICON_SIZE),
		CellPadding = UDim2.fromOffset(6, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	pad(list, 4, 4, 2, 2)

	return panel, list
end

local function pointInside(guiObject: GuiObject, point: Vector2): boolean
	local pos = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	return point.X >= pos.X and point.X <= pos.X + size.X
		and point.Y >= pos.Y and point.Y <= pos.Y + size.Y
end

local function localPoint(container: GuiObject, absolute: Vector2): Vector2
	return absolute - container.AbsolutePosition
end

local function changeZRecursive(root: Instance, delta: number)
	if root:IsA("GuiObject") then
		root.ZIndex += delta
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex += delta
		end
	end
end

local function setLobbyHudVisible(visible: boolean)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local lobbyHud = playerGui:FindFirstChild("CardClashHUD")
	if lobbyHud and lobbyHud:IsA("ScreenGui") then
		if not visible then
			if lobbyHudPreviousEnabled == nil then
				lobbyHudPreviousEnabled = lobbyHud.Enabled
			end
			lobbyHud.Enabled = false
		else
			if lobbyHudPreviousEnabled ~= nil then
				lobbyHud.Enabled = lobbyHudPreviousEnabled
				lobbyHudPreviousEnabled = nil
			end
		end
	end
end

local function setBattleVisible(visible: boolean)
	overlay.Visible = visible
	setLobbyHudVisible(not visible)

	if RunService:IsStudio() then
		testButton.Visible = not visible
	end
end

local function fitRenderedCard(card, holder: GuiObject, fillPercent: number?)
	local scale = card.root:FindFirstChild("BattleFitScale") :: UIScale?
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "BattleFitScale"
		scale.Parent = card.root
	end

	local function update()
		local holderSize = holder.AbsoluteSize
		if holderSize.X <= 0 or holderSize.Y <= 0 then
			return
		end
		local fill = fillPercent or 0.94
		scale.Scale = math.max(0.1, math.min(
			(holderSize.X * fill) / card.width,
			(holderSize.Y * fill) / card.height
			))
	end

	update()
	local connection = holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	card.root.Destroying:Connect(function()
		connection:Disconnect()
	end)
	return scale
end

local function setBattleHP(ref, hp: number, maxHP: number)
	if not ref then
		return
	end
	maxHP = math.max(1, maxHP)
	hp = math.clamp(hp, 0, maxHP)
	if ref.card and ref.card.hp then
		ref.card.hp.Text = ("HP %d/%d"):format(hp, maxHP)
	end
	if ref.hpFill then
		TweenService:Create(
			ref.hpFill,
			TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(hp / maxHP, 1) }
		):Play()
	end
	if ref.hpText then
		ref.hpText.Text = ("%d / %d"):format(hp, maxHP)
	end
end

-- The DMG figure on the card face, and the counterpart to setBattleHP above.
--
-- The server sends the EFFECTIVE number (the card's DMG with any DmgUp buff
-- already folded in), so there is nothing to compute here. It is also written
-- back into ref.data so that a later re-render of the same card - a state
-- snapshot, a hover, a re-layout - keeps the buffed figure instead of snapping
-- back to the printed base stat.
local function setBattleDMG(ref, dmg: number?)
	if not ref or not dmg then
		return
	end
	ref.data.dmg = dmg
	if ref.card and ref.card.dmg then
		ref.card.dmg.Text = "DMG " .. Format.short(dmg)
	end
end

-- Every rendered copy of one card: it can be the active fighter, the enlarged
-- showcase, and a hand tile at the same time, and a stat change has to reach all
-- three or the same card shows two different numbers at once.
local function refsForSlot(side: string, slot: number)
	local out = {}
	for _, ref in ipairs({ activeRefs[side], showcaseRefs[side], (cardRefs[side] or {})[slot] }) do
		if ref and ref.data and ref.data.slot == slot then
			table.insert(out, ref)
		end
	end
	return out
end

local function makeHealthBar(holder: Frame, data)
	local bar = new("Frame", {
		Parent = holder,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(0.76, 0, 0, 8),
		BackgroundColor3 = Color3.fromRGB(31, 33, 45),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ZIndex = Z.Hover + 2,
	}) :: Frame
	bar:SetAttribute("BattleGenerated", true)
	corner(bar, 5)
	stroke(bar, Color3.fromRGB(6, 7, 12), 1, 0.15)

	local fill = new("Frame", {
		Parent = bar,
		Size = UDim2.fromScale(math.clamp((data.currentHP or data.maxHP) / math.max(1, data.maxHP), 0, 1), 1),
		BackgroundColor3 = Color3.fromRGB(86, 235, 118),
		BorderSizePixel = 0,
		ZIndex = Z.Hover + 3,
	}) :: Frame
	corner(fill, 5)
	new("UIGradient", {
		Parent = fill,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(65, 205, 102)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(122, 255, 151)),
		}),
	})

	local hpText = label(holder, "", UDim2.new(0.76, 0, 0, 18), UDim2.new(0.12, 0, 1, 4), 12, Z.Hover + 3)
	hpText:SetAttribute("BattleGenerated", true)
	hpText.TextColor3 = Color3.fromRGB(224, 255, 230)
	hpText.TextYAlignment = Enum.TextYAlignment.Top

	return fill, hpText
end

local function setEnemyStatLayout(card)
	card.hp.AnchorPoint = Vector2.new(0, 1)
	card.hp.Position = UDim2.new(0, 10, 1, -6)
	card.hp.Size = UDim2.new(0.5, -12, 0, 22)
	card.hp.TextXAlignment = Enum.TextXAlignment.Left

	card.dmg.AnchorPoint = Vector2.new(1, 1)
	card.dmg.Position = UDim2.new(1, -10, 1, -6)
	card.dmg.Size = UDim2.new(0.5, -12, 0, 22)
	card.dmg.TextXAlignment = Enum.TextXAlignment.Right
end

local function simplifyHandCard(card)
	for _, item in ipairs({
		card.rarityPill,
		card.rarityText,
		card.levelPill,
		card.levelText,
		card.name,
		card.denom,
		card.abilityName,
		card.abilityDesc,
		card.dmg,
		card.hp,
		}) do
		if item then
			item.Visible = false
		end
	end
end


local function animateShowcaseEntrance(ref, side: string)
	if not ref or not ref.root or not ref.root.Parent or not ref.fitScale then
		return
	end

	local root = ref.root
	local finalScale = ref.fitScale.Scale
	local fromX = side == "player" and 0.30 or 0.70
	local startRotation = side == "player" and -5 or 5

	root.Position = UDim2.fromScale(fromX, 0.52)
	root.Rotation = startRotation
	ref.fitScale.Scale = finalScale * 0.76
	changeZRecursive(root, Z.Hover - Z.Card)

	task.spawn(function()
		local move = TweenService:Create(
			root,
			TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(0.5, 0.5), Rotation = 0 }
		)
		local scaleTween = TweenService:Create(
			ref.fitScale,
			TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = finalScale }
		)
		move:Play()
		scaleTween:Play()
		move.Completed:Wait()
		if root.Parent then
			changeZRecursive(root, -(Z.Hover - Z.Card))
		end
	end)
end

local function animateRefDeath(ref)
	if not ref or not ref.root or not ref.root.Parent then
		return
	end

	local root = ref.root
	local scale = ref.fitScale
	local originalScale = scale and scale.Scale or 1

	-- Stop this dead card from being interacted with while its exit animation plays.
	root.Active = false

	task.spawn(function()
		-- Small readable hit/shake first.
		local shakeOut = TweenService:Create(
			root,
			TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Rotation = 3.5 }
		)
		shakeOut:Play()
		shakeOut.Completed:Wait()

		if not root.Parent then
			return
		end

		local shakeBack = TweenService:Create(
			root,
			TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Rotation = -2 }
		)
		shakeBack:Play()
		shakeBack.Completed:Wait()

		if not root.Parent then
			return
		end

		-- Fade while only shrinking a little. The old animation shrank to ~18%,
		-- which left a tiny bordered "ghost card" on screen until the next
		-- server snapshot arrived. This keeps the card readable while fading
		-- and removes it completely before that gap can become visible.
		local exitTween = TweenService:Create(
			root,
			TweenInfo.new(0.36, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				Rotation = -4,
				Position = UDim2.new(
					root.Position.X.Scale,
					root.Position.X.Offset,
					root.Position.Y.Scale + 0.025,
					root.Position.Y.Offset
				),
			}
		)
		exitTween:Play()

		if scale then
			TweenService:Create(
				scale,
				TweenInfo.new(0.36, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Scale = originalScale * 0.72 }
			):Play()
		end

		-- Fade every visual class used by CardRenderer, including UIStroke.
		-- Fading UIStroke is what prevents the tiny border remnant seen before.
		local fadeInfo = TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		local function fadeObject(obj)
			if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
				TweenService:Create(obj, fadeInfo, {
					ImageTransparency = 1,
					BackgroundTransparency = 1,
				}):Play()
			elseif obj:IsA("TextLabel") or obj:IsA("TextButton") then
				TweenService:Create(obj, fadeInfo, {
					TextTransparency = 1,
					TextStrokeTransparency = 1,
					BackgroundTransparency = 1,
				}):Play()
			elseif obj:IsA("Frame") or obj:IsA("ScrollingFrame") then
				TweenService:Create(obj, fadeInfo, {
					BackgroundTransparency = 1,
				}):Play()
			elseif obj:IsA("UIStroke") then
				TweenService:Create(obj, fadeInfo, {
					Transparency = 1,
				}):Play()
			elseif obj:IsA("CanvasGroup") then
				TweenService:Create(obj, fadeInfo, {
					GroupTransparency = 1,
					BackgroundTransparency = 1,
				}):Play()
			end
		end

		fadeObject(root)
		for _, descendant in ipairs(root:GetDescendants()) do
			fadeObject(descendant)
		end

		-- Hide/destroy the visual before BattleService's Death event delay ends.
		-- The following state snapshot will rebuild the correct empty/replacement slot.
		task.wait(0.38)
		if root.Parent then
			root.Visible = false
			root:Destroy()
		end
	end)
end

local function createRenderedCard(holder: Frame, data, width: number, side: string, kind: string)
	local isHand = kind == "hand"
	local card = CardRenderer.create(holder, width, Z.Card)
	-- Pass the snapshot's LIVE dmg/maxHP through. BattleRuntime.SnapshotCard sends
	-- card.dmg, which already includes anything gained mid-fight; without this the
	-- renderer falls back to CardStats and the card shows its printed base stat
	-- for the whole battle no matter what it is actually hitting for.
	CardRenderer.update(card, {
		cardId = data.cardId,
		variant = data.variant,
		level = data.level,
		dmg = data.dmg,
		maxHP = data.maxHP,
	})
	card.root:SetAttribute("BattleGenerated", true)
	card.root.AnchorPoint = Vector2.new(0.5, 0.5)
	card.root.Position = UDim2.fromScale(0.5, 0.5)
	card.root.Active = true
	card.root.ClipsDescendants = true

	if isHand then
		simplifyHandCard(card)
	elseif side == "enemy" then
		setEnemyStatLayout(card)
	end

	local fill = isHand and 0.985 or (kind == "showcase" and 0.95 or 0.87)
	local fitScale = fitRenderedCard(card, holder, fill)

	local ref = {
		card = card,
		root = card.root,
		holder = holder,
		data = data,
		fitScale = fitScale,
		hpFill = nil,
		hpText = nil,
		hovered = false,
		hoverBaseScale = 0,
	}

	if kind == "active" then
		local hpFill, hpText = makeHealthBar(holder, data)
		ref.hpFill = hpFill
		ref.hpText = hpText
		setBattleHP(ref, data.currentHP or data.maxHP, data.maxHP)
	elseif kind == "showcase" then
		setBattleHP(ref, data.currentHP or data.maxHP, data.maxHP)
	end

	if kind == "hand" then
		cardRefs[side][data.slot] = ref
	elseif kind == "active" then
		activeRefs[side] = ref
	elseif kind == "showcase" then
		showcaseRefs[side] = ref
	end

	return ref
end

local function makeSlot(parent: Frame, name: string)
	local slot = new("Frame", {
		Name = name,
		Parent = parent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
	}) :: Frame
	slot:SetAttribute("BattleCardSlot", true)
	return slot
end

local function showNotice(text: string, color: Color3?)
	noticeLabel.Text = text
	noticeLabel.TextColor3 = color or Color3.fromRGB(255, 225, 135)
	noticeLabel.TextTransparency = 0
	noticeLabel.Visible = true

	local noticeScale = noticeLabel:FindFirstChild("NoticeScale") :: UIScale?
	if noticeScale then
		noticeScale.Scale = 0.92
		TweenService:Create(noticeScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end

	task.delay(1.7, function()
		if noticeLabel.Text == text then
			local tween = TweenService:Create(noticeLabel, TweenInfo.new(0.30), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			})
			tween:Play()
			tween.Completed:Once(function()
				if noticeLabel.Text == text then
					noticeLabel.Visible = false
					noticeLabel.TextStrokeTransparency = 0.48
				end
			end)
		end
	end)
end

local function setDropHighlight(active: boolean)
	playerDropStroke.Color = active and COLORS.Green or COLORS.Player
	playerDropStroke.Thickness = active and 3.2 or 1.8
	playerDropStroke.Transparency = active and 0.02 or 0.38
	playerSlotGlow.BackgroundTransparency = active and 0.78 or 0.93
	playerSlotText.TextColor3 = active and Color3.fromRGB(224, 255, 235) or COLORS.PlayerSoft

	local scale = playerActiveHolder:FindFirstChild("DropPulseScale") :: UIScale?
	if scale then
		TweenService:Create(scale, TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = active and 1.025 or 1,
		}):Play()
	end
end

-- Leaves the battle presentation without sending another server action.
-- Used after a legitimate BattleEnd win. The server has already finished the
-- battle, so calling "Forfeit" here would be wrong.
local function closeBattlePresentation()
	if dragging and dragging.ref and dragging.ref.root and dragging.ref.root.Parent then
		dragging.ref.root:Destroy()
	end
	dragging = nil

	setDropHighlight(false)
	hideEffectTooltip()
	clearEffects("player", false)
	clearEffects("enemy", false)
	setBattleVisible(false)

	if resultPanel then
		resultPanel.Visible = false
	end

	currentSnapshot = nil
	pendingSnapshot = nil
	lastBattleId = nil
	showcaseKeys.player = nil
	showcaseKeys.enemy = nil

	-- Invalidates any delayed outcome-banner hide from the battle we just left.
	outcomeToken += 1
end

local function animateFloatingText(side: string, text: string, color: Color3, slot: number?)
	local ref = slot and cardRefs[side] and cardRefs[side][slot] or nil
	local targetHolder = ref and ref.holder or (side == "player" and playerActiveHolder or enemyActiveHolder)
	if not targetHolder then
		return
	end

	local absoluteCenter = targetHolder.AbsolutePosition + targetHolder.AbsoluteSize / 2
	local localCenter = localPoint(effectsLayer, absoluteCenter)

	local floating = label(effectsLayer, text, UDim2.fromOffset(150, 38), UDim2.fromOffset(localCenter.X - 75, localCenter.Y - 12), 25, Z.Effect)
	floating.AnchorPoint = Vector2.new(0, 0.5)
	floating.TextColor3 = color
	floating.TextStrokeTransparency = 0.22
	floating.TextScaled = true
	addTextConstraint(floating, 18, 28)

	local tween = TweenService:Create(
		floating,
		TweenInfo.new(0.62, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromOffset(localCenter.X - 75, localCenter.Y - 64),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)
	tween:Play()
	tween.Completed:Once(function()
		floating:Destroy()
	end)
end

local function animateAttack(side: string)
	local ref = activeRefs[side]
	if not ref or not ref.root.Parent then
		return
	end

	local root = ref.root
	local direction = side == "player" and -1 or 1
	local base = UDim2.fromScale(0.5, 0.5)

	task.spawn(function()
		local anticipation = TweenService:Create(
			root,
			TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0.5, -direction * 7), Rotation = direction * 1.3 }
		)
		anticipation:Play()
		anticipation.Completed:Wait()

		local strike = TweenService:Create(
			root,
			TweenInfo.new(0.19, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0.5, direction * 46), Rotation = -direction * 1.8 }
		)
		strike:Play()
		strike.Completed:Wait()

		local back = TweenService:Create(
			root,
			TweenInfo.new(0.19, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = base, Rotation = 0 }
		)
		back:Play()
	end)
end

local function animateHit(side: string, slot: number, amount: number, tag: string?)
	for _, ref in ipairs({ activeRefs[side], showcaseRefs[side] }) do
		if ref and ref.root.Parent and ref.data.slot == slot then
			task.spawn(function()
				local root = ref.root
				local baseRotation = root.Rotation
				for _, rotation in ipairs({ -2.5, 2.5, -1.5, 0 }) do
					local tween = TweenService:Create(root, TweenInfo.new(0.05), { Rotation = rotation })
					tween:Play()
					tween.Completed:Wait()
				end
				root.Rotation = baseRotation == 0 and 0 or baseRotation
			end)
		end
	end

	local color = tag == "location" and COLORS.Location or COLORS.Damage
	animateFloatingText(side, "-" .. tostring(amount), color, slot)
end

local function animateDeath(side: string)
	animateRefDeath(activeRefs[side])
	animateRefDeath(showcaseRefs[side])
end

local function animateLocation()
	local scale = locationHolder:FindFirstChild("PulseScale") :: UIScale?
	if not scale then
		return
	end

	locationStroke.Transparency = 0
	locationStroke.Thickness = 4.5

	task.spawn(function()
		local up = TweenService:Create(scale, TweenInfo.new(0.17, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1.075,
		})
		up:Play()
		up.Completed:Wait()
		local down = TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		down:Play()
		down.Completed:Wait()
		TweenService:Create(locationStroke, TweenInfo.new(0.32), {
			Transparency = 0.18,
			Thickness = 2.5,
		}):Play()
	end)

	showNotice("LOCATION ACTIVATED", COLORS.Location)
end

local function refreshLocation(snapshot)
	if not snapshot.location then
		return
	end

	local def = LocationDefinitions.get(snapshot.location.id)

	-- IMPORTANT: The location name is intentionally NOT drawn over the artwork.
	-- It only exists inside the hover tooltip.
	locationName.Text = string.upper(snapshot.location.name or "LOCATION")
	locationDescription.Text = snapshot.location.description or ""

	if def then
		local artwork = def.Artwork
		if type(artwork) == "string" and artwork ~= "" then
			if not string.find(artwork, "rbxassetid://", 1, true) then
				artwork = "rbxassetid://" .. artwork
			end
			locationImage.Image = artwork
			locationImage.Visible = true
		else
			locationImage.Image = ""
			locationImage.Visible = false
		end

		if def.Colors then
			locationDiamond.BackgroundColor3 = def.Colors.Base
			locationStroke.Color = def.Colors.Highlight
			locationInfoStroke.Color = def.Colors.Highlight
			locationDescriptionPanel.BackgroundColor3 = def.Colors.Outer
			locationName.TextColor3 = def.Colors.Text
			locationDescription.TextColor3 = def.Colors.Text:Lerp(Color3.fromRGB(185, 220, 255), 0.35)
			locationHint.TextColor3 = def.Colors.Highlight:Lerp(Color3.new(1, 1, 1), 0.28)
		end
	end
end

local function setHover(ref, hovering: boolean)
	if dragging or not ref or not ref.root or not ref.root.Parent then
		return
	end
	if ref.hovered == hovering then
		return
	end
	ref.hovered = hovering

	if hovering then
		changeZRecursive(ref.root, Z.Hover - Z.Card)
	else
		changeZRecursive(ref.root, -(Z.Hover - Z.Card))
	end

	-- Capture the true fitted scale when hover begins. This avoids stale values
	-- if Roblox completed a responsive layout pass after the card was created.
	if hovering then
		ref.hoverBaseScale = ref.fitScale.Scale
	elseif ref.hoverBaseScale <= 0 then
		ref.hoverBaseScale = ref.fitScale.Scale
	end
	local targetScale = hovering and ref.hoverBaseScale * 1.06 or ref.hoverBaseScale

	TweenService:Create(ref.fitScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = targetScale,
	}):Play()
	TweenService:Create(ref.root, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = hovering and UDim2.fromScale(0.5, 0.43) or UDim2.fromScale(0.5, 0.5),
	}):Play()
end

local function handSlotWidth(count: number, enemy: boolean): number
	if count <= 0 then
		return 0.18
	end
	-- The hand now uses only the left portion of its panel. Cards are intentionally
	-- larger and left-aligned; five cards still fit without overlapping.
	local maxWidth = enemy and 0.185 or 0.19
	local room = 0.91
	return math.min(maxWidth, room / count)
end

local function introTween(panel: GuiObject, yOffset: number, delayTime: number)
	local finalPosition = panel.Position
	panel.Position = UDim2.new(
		finalPosition.X.Scale,
		finalPosition.X.Offset,
		finalPosition.Y.Scale,
		finalPosition.Y.Offset + yOffset
	)
	local scale = panel:FindFirstChild("IntroScale") :: UIScale?
	if not scale then
		scale = new("UIScale", { Parent = panel, Name = "IntroScale", Scale = 0.97 }) :: UIScale
	else
		scale.Scale = 0.97
	end

	task.delay(delayTime, function()
		if not panel.Parent then
			return
		end
		TweenService:Create(panel, TweenInfo.new(0.30, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = finalPosition,
		}):Play()
		TweenService:Create(scale, TweenInfo.new(0.30, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end)
end

local function playBattleIntro()
	introTween(enemyHandPanel, -14, 0.00)
	introTween(enemyActiveHolder, -10, 0.06)
	introTween(locationHolder, 0, 0.11)
	introTween(playerActiveHolder, 10, 0.15)
	introTween(playerHandPanel, 14, 0.20)
end

local function renderSnapshot(snapshot)
	if dragging then
		pendingSnapshot = snapshot
		return
	end

	local isNewBattle = lastBattleId ~= snapshot.battleId
	lastBattleId = snapshot.battleId
	currentSnapshot = snapshot
	if isNewBattle then
		hideEffectTooltip()
		clearEffects("player", false)
		clearEffects("enemy", false)
		showcaseKeys.player = nil
		showcaseKeys.enemy = nil
		outcomeToken += 1
	end
	pendingSnapshot = nil
	setBattleVisible(true)
	resultPanel.Visible = false
	roundLabel.Text = "ROUND " .. tostring(snapshot.round or 1)
	enemyNameLabel.Text = string.upper(snapshot.enemyName or "TEST ENEMY")
	refreshLocation(snapshot)
	updateBattleMetrics(snapshot)

	cardRefs.player = {}
	cardRefs.enemy = {}
	activeRefs.player = nil
	activeRefs.enemy = nil
	showcaseRefs.player = nil
	showcaseRefs.enemy = nil

	clearCards(playerHand)
	clearCards(enemyHand)
	clearCards(playerActiveHolder)
	clearCards(enemyActiveHolder)
	clearCards(playerShowcaseHolder)
	clearCards(enemyShowcaseHolder)

	local playerHandData = snapshot.player.hand or {}
	local enemyHandData = snapshot.enemy.hand or {}
	local playerWidth = handSlotWidth(#playerHandData, false)
	local enemyWidth = handSlotWidth(#enemyHandData, true)

	for order, data in ipairs(playerHandData) do
		local slot = makeSlot(playerHand, "PlayerHand_" .. tostring(data.slot))
		slot.LayoutOrder = order
		slot.Size = UDim2.fromScale(playerWidth, 0.94)
		local ref = createRenderedCard(slot, data, 150, "player", "hand")

		ref.root.MouseEnter:Connect(function()
			playHoverSound()
			setHover(ref, true)
		end)
		ref.root.MouseLeave:Connect(function()
			setHover(ref, false)
		end)
		ref.root.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				playClickSound()
				BattleController:_beginDrag(ref, input)
			end
		end)
	end

	for order, data in ipairs(enemyHandData) do
		local slot = makeSlot(enemyHand, "EnemyHand_" .. tostring(data.slot))
		slot.LayoutOrder = order
		slot.Size = UDim2.fromScale(enemyWidth, 0.92)
		createRenderedCard(slot, data, 135, "enemy", "hand")
	end

	local function showcaseKey(data)
		if not data then
			return nil
		end
		return table.concat({
			tostring(data.slot or 0),
			tostring(data.cardId or ""),
			tostring(data.variant or "Standard"),
		}, "|")
	end

	local newPlayerShowcaseKey = showcaseKey(snapshot.player.active)
	local newEnemyShowcaseKey = showcaseKey(snapshot.enemy.active)
	local animatePlayerShowcase = newPlayerShowcaseKey ~= nil and newPlayerShowcaseKey ~= showcaseKeys.player
	local animateEnemyShowcase = newEnemyShowcaseKey ~= nil and newEnemyShowcaseKey ~= showcaseKeys.enemy

	if snapshot.player.active then
		createRenderedCard(playerActiveHolder, snapshot.player.active, 190, "player", "active")
		local showcase = createRenderedCard(playerShowcaseHolder, snapshot.player.active, 220, "player", "showcase")
		if animatePlayerShowcase then
			animateShowcaseEntrance(showcase, "player")
		end
	end
	if snapshot.enemy.active then
		createRenderedCard(enemyActiveHolder, snapshot.enemy.active, 190, "enemy", "active")
		local showcase = createRenderedCard(enemyShowcaseHolder, snapshot.enemy.active, 220, "enemy", "showcase")
		if animateEnemyShowcase then
			animateShowcaseEntrance(showcase, "enemy")
		end
	end

	showcaseKeys.player = newPlayerShowcaseKey
	showcaseKeys.enemy = newEnemyShowcaseKey

	local playerEffects = snapshot.player.active and (snapshot.player.active.effects or snapshot.player.active.statuses) or {}
	local enemyEffects = snapshot.enemy.active and (snapshot.enemy.active.effects or snapshot.enemy.active.statuses) or {}
	reconcileEffects("player", playerEffects)
	reconcileEffects("enemy", enemyEffects)

	local canDrop = snapshot.player.active == nil and #playerHandData > 0
	playerActiveHolder:SetAttribute("CanDrop", canDrop)
	playerSlotText.Visible = snapshot.player.active == nil
	enemySlotText.Visible = snapshot.enemy.active == nil
	setDropHighlight(false)

	if isNewBattle then
		playBattleIntro()
	end
end

function BattleController:_beginDrag(ref, input)
	if dragging or not currentSnapshot then
		return
	end
	if currentSnapshot.player.active then
		showNotice("Your active slot is already occupied")
		return
	end

	local root = ref.root
	local pointer = Vector2.new(input.Position.X, input.Position.Y)
	local absoluteSize = root.AbsoluteSize

	local extraZ = ref.hovered and (Z.Drag - Z.Hover) or (Z.Drag - Z.Card)
	changeZRecursive(root, extraZ)

	dragging = {
		ref = ref,
		slot = ref.data.slot,
		target = pointer,
		current = pointer,
		inputType = input.UserInputType,
		startAbsolute = root.AbsolutePosition + absoluteSize / 2,
		originalScale = ref.hoverBaseScale > 0 and ref.hoverBaseScale or ref.fitScale.Scale,
	}

	root.Parent = dragLayer
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromOffset(pointer.X, pointer.Y)
	root.Rotation = -1.5
	ref.fitScale.Scale = dragging.originalScale * 1.08

	setDropHighlight(pointInside(playerActiveHolder, pointer))
end

local function finishDrag(valid: boolean)
	local drag = dragging
	if not drag then
		return
	end
	dragging = nil
	setDropHighlight(false)

	local root = drag.ref.root
	if not root or not root.Parent then
		if pendingSnapshot then
			renderSnapshot(pendingSnapshot)
		end
		return
	end

	if valid then
		local ok, reason, snapshot = BattleRemotes.Action:InvokeServer("PlayCard", { slot = drag.slot })
		if not ok then
			showNotice(reason or "That card cannot be played", Color3.fromRGB(255, 125, 125))
			local target = localPoint(dragLayer, drag.startAbsolute)
			local tween = TweenService:Create(root, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(target.X, target.Y),
				Rotation = 0,
			})
			tween:Play()
			tween.Completed:Once(function()
				if root.Parent then
					root:Destroy()
				end
				renderSnapshot(pendingSnapshot or currentSnapshot)
			end)
			return
		end

		local activeCenter = playerActiveHolder.AbsolutePosition + playerActiveHolder.AbsoluteSize / 2
		local localCenter = localPoint(dragLayer, activeCenter)
		local desiredScale = math.max(0.1, math.min(
			(playerActiveHolder.AbsoluteSize.X * 0.87) / drag.ref.card.width,
			(playerActiveHolder.AbsoluteSize.Y * 0.87) / drag.ref.card.height
			))
		local move = TweenService:Create(root, TweenInfo.new(0.23, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(localCenter.X, localCenter.Y),
			Rotation = 0,
		})
		local grow = TweenService:Create(drag.ref.fitScale, TweenInfo.new(0.23, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = desiredScale,
		})
		move:Play()
		grow:Play()
		move.Completed:Once(function()
			if root.Parent then
				root:Destroy()
			end
			renderSnapshot(snapshot or pendingSnapshot or currentSnapshot)
		end)
	else
		local target = localPoint(dragLayer, drag.startAbsolute)
		local move = TweenService:Create(root, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(target.X, target.Y),
			Rotation = 0,
		})
		local shrink = TweenService:Create(drag.ref.fitScale, TweenInfo.new(0.22), {
			Scale = drag.originalScale,
		})
		move:Play()
		shrink:Play()
		move.Completed:Once(function()
			if root.Parent then
				root:Destroy()
			end
			renderSnapshot(pendingSnapshot or currentSnapshot)
		end)
	end
end

local function animateEnemyPlay(event)
	local ref = cardRefs.enemy[event.slot]
	if not ref or not ref.root.Parent then
		return
	end

	local root = ref.root
	changeZRecursive(root, Z.Drag - Z.Card)
	root.Parent = dragLayer
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	local start = ref.holder.AbsolutePosition + ref.holder.AbsoluteSize / 2
	local finish = enemyActiveHolder.AbsolutePosition + enemyActiveHolder.AbsoluteSize / 2
	local localStart = localPoint(dragLayer, start)
	local localFinish = localPoint(dragLayer, finish)
	root.Position = UDim2.fromOffset(localStart.X, localStart.Y)

	local desiredScale = math.max(0.1, math.min(
		(enemyActiveHolder.AbsoluteSize.X * 0.87) / ref.card.width,
		(enemyActiveHolder.AbsoluteSize.Y * 0.87) / ref.card.height
		))
	local move = TweenService:Create(root, TweenInfo.new(0.30, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(localFinish.X, localFinish.Y),
	})
	local scaleTween = TweenService:Create(ref.fitScale, TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = desiredScale,
	})
	move:Play()
	scaleTween:Play()
	move.Completed:Once(function()
		if root.Parent then
			root:Destroy()
		end
	end)
end


local function showBattleOutcome(event)
	if not resultPanel or not resultText or not resultSubText then
		return
	end

	outcomeToken += 1
	local token = outcomeToken
	local enemyName = (currentSnapshot and currentSnapshot.enemyName) or enemyNameLabel.Text or "ENEMY"
	enemyName = string.upper(enemyName)

	if event.reason == "draw" then
		resultText.Text = "BATTLE ENDED IN A DRAW"
		resultSubText.Text = ""
		resultText.TextColor3 = COLORS.Gold
	elseif event.won then
		resultText.Text = "YOU BEAT " .. enemyName .. "!"

		-- BattleService sends the final, multiplier-adjusted Elder Coin amount.
		-- Show it in the outcome banner immediately instead of the old "none yet"
		-- placeholder. RewardPopup.Show(event) below still draws the full Secret-
		-- rarity reward tile, so the player gets both instant feedback and the
		-- collectible-style reward presentation.
		local elderCoins = tonumber(event.elderCoins) or 0
		if elderCoins > 0 then
			resultSubText.Text = ("+%s ELDER COINS"):format(Format.comma(elderCoins))
		else
			resultSubText.Text = "Rewards deposited into your inventory"
		end

		resultText.TextColor3 = COLORS.Green
		playRewardSound()
	else
		resultText.Text = enemyName .. " DEFEATED YOU!"
		resultSubText.Text = ""
		resultText.TextColor3 = COLORS.Enemy
	end

	resultPanel.Visible = true
	resultPanel.Position = UDim2.fromScale(0.5, -0.10)
	resultPanel.BackgroundTransparency = 0.10
	resultText.TextTransparency = 0
	resultText.TextStrokeTransparency = 0.34
	resultSubText.TextTransparency = 0
	resultSubText.TextStrokeTransparency = 0.70

	local bannerScale = resultPanel:FindFirstChild("OutcomeScale") :: UIScale?
	if bannerScale then
		bannerScale.Scale = 0.92
		TweenService:Create(
			bannerScale,
			TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
	end

	TweenService:Create(
		resultPanel,
		TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.012) }
	):Play()

	task.delay(3.6, function()
		if outcomeToken ~= token or not resultPanel.Visible then
			return
		end
		local out = TweenService:Create(
			resultPanel,
			TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.fromScale(0.5, -0.10), BackgroundTransparency = 1 }
		)
		TweenService:Create(resultText, TweenInfo.new(0.22), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		TweenService:Create(resultSubText, TweenInfo.new(0.22), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		out:Play()
		out.Completed:Once(function()
			if outcomeToken == token then
				resultPanel.Visible = false
			end
		end)
	end)
end

local function handleBattleEvent(event)
	if not event or type(event) ~= "table" then
		return
	end

	if event.type == "RoundStart" then
		roundLabel.Text = "ROUND " .. tostring(event.round)
		local roundScale = roundLabel:FindFirstChild("RoundScale") :: UIScale?
		if roundScale then
			roundScale.Scale = 1.12
			TweenService:Create(roundScale, TweenInfo.new(0.20, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end

	elseif event.type == "EnemyPlay" then
		animateEnemyPlay(event)

	elseif event.type == "Attack" then
		animateAttack(event.side)

	elseif event.type == "Damage" then
		for _, ref in ipairs({ activeRefs[event.side], showcaseRefs[event.side] }) do
			if ref and ref.data.slot == event.slot then
				setBattleHP(ref, event.hp or 0, event.maxHP or 1)
			end
		end
		animateHit(event.side, event.slot, event.amount or 0, event.tag)

	elseif event.type == "Heal" then
		for _, ref in ipairs({ activeRefs[event.side], showcaseRefs[event.side] }) do
			if ref and ref.data.slot == event.slot then
				setBattleHP(ref, event.hp or 0, event.maxHP or 1)
			end
		end
		animateFloatingText(event.side, "+" .. tostring(event.amount or 0), COLORS.Heal, event.slot)

	elseif event.type == "Death" then
		animateDeath(event.side)
		-- The card's effects all end with it, but the chips STAY: the panel is a
		-- record of the whole battle, not just of the card currently standing.
		task.delay(0.28, function()
			for _, ref in pairs(effectChipRefs[event.side]) do
				setChipExpired(ref, true)
			end
		end)

	elseif event.type == "Passive" then
		-- One-time ability activations become short-lived chips on the correct side
		-- instead of covering the center of the battlefield.
		showAbilityActivation(event)

	elseif event.type == "Status" then
		if event.effect then
			local activeRef = activeRefs[event.side]
			if not activeRef or activeRef.data.slot == event.slot then
				upsertEffect(event.side, event.effect)
				print(("[BattleEffects] %s gained %s (%s)"):format(
					event.side == "player" and "Player" or "Enemy",
					effectDisplayName(event.effect),
					effectAmountText(event.effect)
					))
			end
		end

	elseif event.type == "StatusEnd" then
		if event.side and event.status then
			removeEffectChip(event.side, event.status, true)
			print(("[BattleEffects] %s %s expired"):format(
				event.side == "player" and "Player" or "Enemy",
				event.statusName or event.status
				))
		end

	elseif event.type == "Stat" then
		-- A buff landed or fell off, or a card permanently stole DMG. The number on
		-- the card face updates right now, the way HP already does off a Damage
		-- event, instead of waiting a full round for the next state snapshot.
		for _, ref in ipairs(refsForSlot(event.side, event.slot)) do
			setBattleDMG(ref, event.dmg)
			if event.maxHP then
				setBattleHP(ref, event.hp or 0, event.maxHP)
			end
		end

	elseif event.type == "Skip" then
		showNotice((event.cardName or "Card") .. " cannot act!", Color3.fromRGB(150, 210, 255))

	elseif event.type == "LocationActivate" then
		animateLocation()

	elseif event.type == "BattleEnd" then
		if event.won == true then
			-- A win now ENDS the battle presentation immediately. The old
			-- "YOU BEAT <ENEMY>" banner is deliberately skipped so the player never
			-- sees two different victory messages competing with the reward popup.
			playRewardSound()
			closeBattlePresentation()
			RewardPopup.Show(event)
		else
			-- Draws/defeats can still use the compact battle outcome banner because
			-- there is no victory reward presentation to replace it.
			showBattleOutcome(event)
		end
	end
end

local function makeHandPanel(parent: Frame, name: string, titleText: string, enemy: boolean)
	local accent = enemy and COLORS.Enemy or COLORS.Player
	local panel = new("Frame", {
		Name = name .. "Panel",
		Parent = parent,
		AnchorPoint = enemy and Vector2.new(0.5, 0) or Vector2.new(0.5, 1),
		Position = enemy and UDim2.fromScale(0.5, 0.090) or UDim2.fromScale(0.5, 0.985),
		Size = enemy and UDim2.fromScale(0.66, 0.17) or UDim2.fromScale(0.76, 0.205),
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.46,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = Z.Panel,
	}) :: Frame
	corner(panel, 18)
	stroke(panel, accent, 1.35, 0.62)
	new("UIGradient", {
		Parent = panel,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 22, 42)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 9, 18)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 0.55),
		}),
	})

	-- LEFT: the actual available cards.
	local title = scaledLabel(panel, titleText, UDim2.fromScale(0.60, 0.16), UDim2.fromScale(0.025, 0.018), 10, 15, Z.Slot)
	title.TextColor3 = enemy and COLORS.EnemySoft or Color3.fromRGB(188, 255, 207)
	title.TextXAlignment = Enum.TextXAlignment.Center

	local container = new("Frame", {
		Name = name,
		Parent = panel,
		Position = UDim2.fromScale(0.025, 0.19),
		Size = UDim2.fromScale(0.60, 0.77),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = Z.Slot,
	}) :: Frame
	new("UIListLayout", {
		Parent = container,
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0.008, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	new("UIPadding", {
		Parent = container,
		PaddingLeft = UDim.new(0.012, 0),
		PaddingRight = UDim.new(0.008, 0),
	})

	-- CENTER: short divider that deliberately does not touch the panel edges.
	new("Frame", {
		Name = "InfoDivider",
		Parent = panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.65, 0.55),
		Size = UDim2.new(0, 1, 0.68, 0),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = Z.Slot,
	})

	-- RIGHT: battle overview.
	local info = new("Frame", {
		Name = "BattleInfo",
		Parent = panel,
		Position = UDim2.fromScale(0.68, 0.15),
		Size = UDim2.fromScale(0.29, 0.70),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = Z.Slot,
	}) :: Frame

	if enemy then
		local powerTitle = scaledLabel(info, "ENEMY BATTLE POWER", UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0.05), 9, 13, Z.Slot + 1)
		powerTitle.TextColor3 = COLORS.EnemySoft
		powerTitle.TextStrokeTransparency = 0.70

		enemyBattlePowerValue = scaledLabel(info, "0", UDim2.fromScale(1, 0.34), UDim2.fromScale(0, 0.27), 16, 25, Z.Slot + 2)
		enemyBattlePowerValue.TextStrokeTransparency = 0.36
		addMovingPowerGradient(enemyBattlePowerValue)

		local helper = scaledLabel(info, "CURRENT CARDS STILL IN THE FIGHT", UDim2.fromScale(1, 0.20), UDim2.fromScale(0, 0.70), 7, 10, Z.Slot + 1)
		helper.TextColor3 = COLORS.Muted
		helper.TextStrokeTransparency = 0.84
	else
		local chanceTitle = scaledLabel(info, "VICTORY CHANCE", UDim2.fromScale(0.46, 0.22), UDim2.fromScale(0, 0.03), 9, 13, Z.Slot + 1)
		chanceTitle.TextColor3 = COLORS.Gold
		chanceTitle.TextStrokeTransparency = 0.66

		victoryChanceValue = scaledLabel(info, "50%", UDim2.fromScale(0.46, 0.38), UDim2.fromScale(0, 0.24), 19, 30, Z.Slot + 2)
		victoryChanceValue.TextColor3 = COLORS.Gold
		victoryChanceValue.TextStrokeTransparency = 0.28

		local miniDivider = new("Frame", {
			Parent = info,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.50, 0.49),
			Size = UDim2.new(0, 1, 0.70, 0),
			BackgroundColor3 = COLORS.Player,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			ZIndex = Z.Slot,
		})
		miniDivider.Name = "MetricDivider"

		local powerTitle = scaledLabel(info, "PARTY BATTLE POWER", UDim2.fromScale(0.46, 0.22), UDim2.fromScale(0.54, 0.03), 9, 13, Z.Slot + 1)
		powerTitle.TextColor3 = COLORS.PlayerSoft
		powerTitle.TextStrokeTransparency = 0.66

		playerBattlePowerValue = scaledLabel(info, "0", UDim2.fromScale(0.46, 0.38), UDim2.fromScale(0.54, 0.24), 15, 24, Z.Slot + 2)
		playerBattlePowerValue.TextStrokeTransparency = 0.34
		addMovingPowerGradient(playerBattlePowerValue)

		local helper = scaledLabel(info, "BASED ON CURRENT CARDS", UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0.75), 7, 10, Z.Slot + 1)
		helper.TextColor3 = COLORS.Muted
		helper.TextStrokeTransparency = 0.86
	end

	return panel, container, title
end

local function makeActiveSlot(parent: Frame, name: string, enemy: boolean)
	local accent = enemy and COLORS.Enemy or COLORS.Player
	local holder = new("Frame", {
		Name = name,
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = enemy and UDim2.fromScale(0.5, 0.355) or UDim2.fromScale(0.5, 0.68),
		Size = UDim2.fromScale(0.14, 0.185),
		BackgroundColor3 = COLORS.Panel2,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = Z.Slot,
	}) :: Frame
	corner(holder, 18)
	local holderStroke = stroke(holder, accent, 1.8, 0.45)

	local inner = new("Frame", {
		Parent = holder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.88),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.96,
		BorderSizePixel = 0,
		ZIndex = Z.Slot,
	}) :: Frame
	corner(inner, 14)
	stroke(inner, accent, 1, 0.78)

	-- Soft slot shadow/depth without making another giant outlined box.
	new("UIGradient", {
		Parent = holder,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(32, 25, 50)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 8, 15)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0.62),
		}),
	})

	local slotText = scaledLabel(holder, enemy and "ENEMY SLOT" or "DRAG CARD HERE", UDim2.fromScale(0.84, 0.20), UDim2.fromScale(0.08, 0.40), 10, 14, Z.Slot + 1)
	slotText.TextColor3 = enemy and COLORS.EnemySoft or COLORS.PlayerSoft

	return holder, holderStroke, slotText
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")

	local old = playerGui:FindFirstChild("AnimeCardBattleGui")
	if old then
		old:Destroy()
	end

	gui = new("ScreenGui", {
		Name = "AnimeCardBattleGui",
		Parent = playerGui,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 90,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	overlay = new("Frame", {
		Name = "BattleOverlay",
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(6, 7, 16),
		BackgroundTransparency = 0.42,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Z.Background,
	}) :: Frame

	new("UIGradient", {
		Parent = overlay,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 16, 42)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(7, 12, 19)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 10, 30)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.18),
			NumberSequenceKeypoint.new(0.5, 0.40),
			NumberSequenceKeypoint.new(1, 0.18),
		}),
	})

	-- Safe-area stage. All important battle UI lives inside this 96% x 96% area.
	stage = new("Frame", {
		Name = "Stage",
		Parent = overlay,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.96, 0.96),
		BackgroundTransparency = 1,
		ZIndex = Z.Decoration,
	}) :: Frame

	dragLayer = new("Frame", {
		Name = "DragLayer",
		Parent = overlay,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = Z.Drag,
	}) :: Frame

	effectsLayer = new("Frame", {
		Name = "EffectsLayer",
		Parent = overlay,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = Z.Effect,
	}) :: Frame

	-- Compact top information; no giant box.
	roundLabel = scaledLabel(stage, "ROUND 1", UDim2.fromScale(0.19, 0.052), UDim2.fromScale(0.405, 0.006), 18, 30, Z.Notice)
	roundLabel.TextColor3 = COLORS.Gold
	roundLabel.TextStrokeTransparency = 0.32
	new("UIScale", { Parent = roundLabel, Name = "RoundScale", Scale = 1 })

	enemyNameLabel = scaledLabel(stage, "TEST ENEMY", UDim2.fromScale(0.22, 0.032), UDim2.fromScale(0.39, 0.055), 11, 17, Z.Notice)
	enemyNameLabel.TextColor3 = COLORS.Enemy
	enemyNameLabel.TextStrokeTransparency = 0.40

	enemyHandPanel, enemyHand, enemyHandTitle = makeHandPanel(stage, "EnemyHand", "ENEMY AVAILABLE CARDS", true)

	enemyActiveHolder, _, enemySlotText = makeActiveSlot(stage, "EnemyActive", true)

	local function makeShowcaseHolder(name: string, side: string, xScale: number)
		local accent = side == "player" and COLORS.Player or COLORS.Enemy
		local holder = new("Frame", {
			Name = name,
			Parent = stage,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(xScale, 0.52),
			Size = UDim2.fromScale(0.18, 0.46),
			BackgroundColor3 = COLORS.Panel2,
			BackgroundTransparency = 0.68,
			BorderSizePixel = 0,
			ClipsDescendants = false,
			ZIndex = Z.Panel,
		}) :: Frame
		corner(holder, 22)
		stroke(holder, accent, 1.6, 0.55)
		new("UIGradient", {
			Parent = holder,
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 22, 40)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 9, 17)),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.30),
				NumberSequenceKeypoint.new(1, 0.55),
			}),
		})
		local title = scaledLabel(holder, side == "player" and "YOUR PLAYED CARD" or "ENEMY PLAYED CARD", UDim2.fromScale(0.92, 0.10), UDim2.fromScale(0.04, 0.02), 11, 16, Z.Slot)
		title.TextColor3 = side == "player" and COLORS.PlayerSoft or COLORS.EnemySoft
		local cardZone = new("Frame", {
			Name = "CardZone",
			Parent = holder,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.13),
			Size = UDim2.fromScale(0.94, 0.84),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = false,
			ZIndex = Z.Card,
		}) :: Frame
		return cardZone
	end

	playerEffectsPanel, playerEffectsList = makeEffectsPanel(stage, "player")
	enemyEffectsPanel, enemyEffectsList = makeEffectsPanel(stage, "enemy")

	playerShowcaseHolder = makeShowcaseHolder("PlayerShowcase", "player", 0.245)
	enemyShowcaseHolder = makeShowcaseHolder("EnemyShowcase", "enemy", 0.755)

	-- One shared, high-Z tooltip. It appears only while an effect is hovered.
	-- The content uses dedicated vertical rows instead of overlapping scaled
	-- regions, so every effect tooltip stays readable even with two-line text.
	effectTooltip = new("Frame", {
		Name = "EffectTooltip",
		Parent = stage,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(245, 255),
		BackgroundColor3 = Color3.fromRGB(11, 13, 23),
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Z.Modal + 5,
	}) :: Frame
	corner(effectTooltip, 16)
	effectTooltipStroke = stroke(effectTooltip, COLORS.Green, 1.6, 0.18)
	new("UIGradient", {
		Parent = effectTooltip,
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 27, 45)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(9, 10, 19)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 0.22),
		}),
	})
	effectTooltipScale = new("UIScale", { Parent = effectTooltip, Scale = 0.95, Name = "TooltipScale" }) :: UIScale

	local tooltipIconBack = new("Frame", {
		Parent = effectTooltip,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Color3.fromRGB(30, 31, 48),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ZIndex = Z.Modal + 6,
	}) :: Frame
	corner(tooltipIconBack, 17)
	stroke(tooltipIconBack, Color3.fromRGB(255, 255, 255), 1, 0.72)
	effectTooltipIcon = scaledLabel(tooltipIconBack, "FX", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 8, 12, Z.Modal + 7)
	effectTooltipIcon.TextStrokeTransparency = 0.76

	effectTooltipTitle = scaledLabel(effectTooltip, "EFFECT", UDim2.new(1, -62, 0, 34), UDim2.fromOffset(54, 11), 11, 17, Z.Modal + 7)
	effectTooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
	effectTooltipTitle.TextStrokeTransparency = 0.62
	effectTooltipTitle.TextWrapped = false
	effectTooltipTitle.TextTruncate = Enum.TextTruncate.AtEnd

	effectTooltipAmount = scaledLabel(effectTooltip, "", UDim2.new(1, -24, 0, 38), UDim2.fromOffset(12, 54), 10, 16, Z.Modal + 7)
	effectTooltipAmount.TextXAlignment = Enum.TextXAlignment.Left
	effectTooltipAmount.TextYAlignment = Enum.TextYAlignment.Center
	effectTooltipAmount.TextWrapped = true
	effectTooltipAmount.TextStrokeTransparency = 0.58

	local dividerTop = new("Frame", {
		Parent = effectTooltip,
		Position = UDim2.fromOffset(12, 96),
		Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.87,
		BorderSizePixel = 0,
		ZIndex = Z.Modal + 6,
	}) :: Frame

	effectTooltipDescription = label(effectTooltip, "", UDim2.new(1, -24, 0, 44), UDim2.fromOffset(12, 104), 11, Z.Modal + 7)
	effectTooltipDescription.TextXAlignment = Enum.TextXAlignment.Left
	effectTooltipDescription.TextYAlignment = Enum.TextYAlignment.Top
	effectTooltipDescription.TextWrapped = true
	effectTooltipDescription.TextColor3 = Color3.fromRGB(220, 221, 236)
	effectTooltipDescription.TextStrokeTransparency = 0.82

	effectTooltipSource = label(effectTooltip, "", UDim2.new(1, -24, 0, 43), UDim2.fromOffset(12, 153), 11, Z.Modal + 7)
	effectTooltipSource.TextXAlignment = Enum.TextXAlignment.Left
	effectTooltipSource.TextYAlignment = Enum.TextYAlignment.Top
	effectTooltipSource.TextWrapped = true
	effectTooltipSource.TextColor3 = Color3.fromRGB(194, 196, 216)
	effectTooltipSource.TextStrokeTransparency = 0.84

	local dividerBottom = new("Frame", {
		Parent = effectTooltip,
		Position = UDim2.fromOffset(12, 201),
		Size = UDim2.new(1, -24, 0, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.90,
		BorderSizePixel = 0,
		ZIndex = Z.Modal + 6,
	}) :: Frame

	effectTooltipTiming = label(effectTooltip, "", UDim2.new(1, -24, 0, 40), UDim2.fromOffset(12, 208), 10, Z.Modal + 7)
	effectTooltipTiming.TextXAlignment = Enum.TextXAlignment.Left
	effectTooltipTiming.TextYAlignment = Enum.TextYAlignment.Top
	effectTooltipTiming.TextWrapped = true
	effectTooltipTiming.TextColor3 = Color3.fromRGB(165, 168, 192)
	effectTooltipTiming.TextStrokeTransparency = 0.88

	-- Central location zone.
	-- The artwork itself stays completely clean: NO location name is drawn over it.
	-- Hovering the location reveals a blue information box containing the name
	-- and mechanic.
	locationHolder = new("Frame", {
		Name = "Location",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.515),
		Size = UDim2.fromScale(0.28, 0.115),
		BackgroundTransparency = 1,
		ZIndex = Z.Location,
	}) :: Frame
	new("UIScale", { Parent = locationHolder, Name = "PulseScale", Scale = 1 })

	-- Diamond backing/border.
	locationDiamond = new("Frame", {
		Name = "LocationVisual",
		Parent = locationHolder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.50, 0.50),
		Size = UDim2.fromScale(0.12, 0.84),
		BackgroundColor3 = Color3.fromRGB(12, 55, 100),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Rotation = 45,
		ZIndex = Z.Location,
	}) :: Frame
	new("UIAspectRatioConstraint", {
		Parent = locationDiamond,
		AspectRatio = 1,
		DominantAxis = Enum.DominantAxis.Height,
	})
	corner(locationDiamond, 17)
	locationStroke = stroke(locationDiamond, COLORS.Location, 2.5, 0.14)
	new("UIGradient", {
		Parent = locationDiamond,
		Rotation = 45,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(5, 24, 52)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(16, 79, 137)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 47, 92)),
		}),
	})

	-- Location artwork.
	-- The parent is rotated +45 degrees to make the diamond, so the image is
	-- counter-rotated -45 degrees. This keeps the uploaded artwork upright.
	locationImage = new("ImageLabel", {
		Name = "LocationArtwork",
		Parent = locationDiamond,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.22, 1.22),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = "rbxassetid://84676003250303",
		ScaleType = Enum.ScaleType.Fit,
		Rotation = -45,
		ZIndex = Z.Location + 1,
	}) :: ImageLabel

	-- Blue hover information panel.
	locationDescriptionPanel = new("Frame", {
		Name = "LocationInfo",
		Parent = locationHolder,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.86, 0.50),
		Size = UDim2.fromScale(0.92, 1.55),
		BackgroundColor3 = Color3.fromRGB(5, 20, 42),
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ZIndex = Z.Modal,
		Visible = false,
	}) :: Frame
	corner(locationDescriptionPanel, 12)
	locationInfoStroke = stroke(locationDescriptionPanel, COLORS.Location, 1.4, 0.30)
	pad(locationDescriptionPanel, 8, 8, 11, 11)

	-- The location name ONLY exists in this hover box.
	locationName = scaledLabel(
		locationDescriptionPanel,
		"ARLONG PARK",
		UDim2.new(1, 0, 0.28, 0),
		UDim2.fromScale(0, 0),
		12,
		20,
		Z.Modal + 2
	)
	locationName.TextXAlignment = Enum.TextXAlignment.Left
	locationName.TextColor3 = COLORS.LocationSoft
	locationName.TextStrokeTransparency = 0.48

	local locationDivider = new("Frame", {
		Parent = locationDescriptionPanel,
		Position = UDim2.fromScale(0, 0.31),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = COLORS.Location,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = Z.Modal + 2,
	}) :: Frame

	locationDescription = scaledLabel(
		locationDescriptionPanel,
		"Round 6: All remaining cards lose HP equal to 15% of their Max HP.",
		UDim2.new(1, 0, 0.62, 0),
		UDim2.fromScale(0, 0.36),
		10,
		17,
		Z.Modal + 2
	)
	locationDescription.TextXAlignment = Enum.TextXAlignment.Left
	locationDescription.TextYAlignment = Enum.TextYAlignment.Top
	locationDescription.TextWrapped = true
	locationDescription.TextColor3 = Color3.fromRGB(213, 235, 255)
	locationDescription.TextStrokeTransparency = 0.74

	locationHint = scaledLabel(
		locationHolder,
		"HOVER FOR INFO",
		UDim2.fromScale(0.62, 0.16),
		UDim2.fromScale(0.19, 0.89),
		8,
		11,
		Z.Location + 1
	)
	locationHint.TextColor3 = Color3.fromRGB(153, 211, 255)
	locationHint.TextStrokeTransparency = 0.78

	local locationHoverScale = new("UIScale", { Parent = locationDescriptionPanel, Name = "HoverScale", Scale = 0.95 }) :: UIScale
	locationHolder.Active = true
	locationDiamond.Active = true
	local hoveringLocation = false

	local function setLocationTooltip(open: boolean)
		if hoveringLocation == open then
			return
		end

		hoveringLocation = open
		locationDescriptionPanel.Visible = true

		if open then
			locationDescriptionPanel.BackgroundTransparency = 0.12
			locationDescriptionPanel.Position = UDim2.fromScale(0.86, 0.50)
			locationDescriptionPanel.Size = UDim2.fromScale(0.92, 1.55)
			locationDescriptionPanel.ZIndex = Z.Modal
			locationHoverScale.Scale = 0.95

			TweenService:Create(
				locationHoverScale,
				TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()

			for _, obj in ipairs(locationDescriptionPanel:GetDescendants()) do
				if obj:IsA("TextLabel") then
					obj.TextTransparency = 0
					obj.TextStrokeTransparency = obj == locationName and 0.48 or 0.74
				end
			end
		else
			local tween = TweenService:Create(
				locationHoverScale,
				TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = 0.96 }
			)
			tween:Play()

			TweenService:Create(
				locationDescriptionPanel,
				TweenInfo.new(0.14),
				{ BackgroundTransparency = 1 }
			):Play()

			for _, obj in ipairs(locationDescriptionPanel:GetDescendants()) do
				if obj:IsA("TextLabel") then
					TweenService:Create(
						obj,
						TweenInfo.new(0.14),
						{ TextTransparency = 1, TextStrokeTransparency = 1 }
					):Play()
				end
			end

			task.delay(0.15, function()
				if not hoveringLocation and locationDescriptionPanel then
					locationDescriptionPanel.Visible = false
				end
			end)
		end
	end

	locationHolder.MouseEnter:Connect(function()
		playHoverSound()
		setLocationTooltip(true)
	end)

	locationHolder.MouseLeave:Connect(function()
		setLocationTooltip(false)
	end)

	playerActiveHolder, playerDropStroke, playerSlotText = makeActiveSlot(stage, "PlayerActive", false)
	new("UIScale", { Parent = playerActiveHolder, Name = "DropPulseScale", Scale = 1 })

	playerSlotGlow = new("Frame", {
		Parent = playerActiveHolder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.04, 1.04),
		BackgroundColor3 = COLORS.Player,
		BackgroundTransparency = 0.93,
		BorderSizePixel = 0,
		ZIndex = Z.Slot,
	}) :: Frame
	corner(playerSlotGlow, 20)

	playerHandPanel, playerHand, playerHandTitle = makeHandPanel(stage, "PlayerHand", "YOUR AVAILABLE CARDS", false)

	-- Notice sits in open horizontal space, not through the location description.
	noticeLabel = scaledLabel(stage, "", UDim2.fromScale(0.28, 0.050), UDim2.fromScale(0.07, 0.485), 13, 21, Z.Notice)
	noticeLabel.Visible = false
	new("UIScale", { Parent = noticeLabel, Name = "NoticeScale", Scale = 1 })

	-- Exit sits top-left so it never fights with the existing top-right leaderboard.
	closeButton = new("TextButton", {
		Name = "ExitBattle",
		Parent = stage,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(74, 34),
		BackgroundColor3 = Color3.fromRGB(25, 22, 38),
		BackgroundTransparency = 0.26,
		BorderSizePixel = 0,
		Text = "EXIT",
		FontFace = Theme.font(),
		TextSize = 13,
		TextColor3 = Color3.fromRGB(224, 224, 238),
		ZIndex = Z.Notice,
	}) :: TextButton
	corner(closeButton, 10)
	stroke(closeButton, Color3.fromRGB(104, 92, 138), 1.2, 0.45)
	wireButtonSounds(closeButton)
	closeButton.Activated:Connect(function()
		BattleRemotes.Action:InvokeServer("Forfeit")
		closeBattlePresentation()
	end)

	resultPanel = new("Frame", {
		Name = "BattleOutcomeBanner",
		Parent = stage,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, -0.10),
		Size = UDim2.fromScale(0.42, 0.085),
		BackgroundColor3 = Color3.fromRGB(9, 10, 20),
		BackgroundTransparency = 0.10,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Z.Modal,
	}) :: Frame
	corner(resultPanel, 16)
	stroke(resultPanel, Color3.fromRGB(138, 118, 210), 1.6, 0.30)
	new("UIScale", { Parent = resultPanel, Name = "OutcomeScale", Scale = 1 })
	new("UIGradient", {
		Parent = resultPanel,
		Rotation = 0,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(19, 17, 34)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 12, 22)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(19, 17, 34)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.12),
			NumberSequenceKeypoint.new(0.5, 0.02),
			NumberSequenceKeypoint.new(1, 0.12),
		}),
	})

	resultText = scaledLabel(resultPanel, "", UDim2.fromScale(0.94, 0.55), UDim2.fromScale(0.03, 0.05), 15, 24, Z.Modal + 1)
	resultText.TextStrokeTransparency = 0.34

	resultSubText = scaledLabel(resultPanel, "", UDim2.fromScale(0.94, 0.28), UDim2.fromScale(0.03, 0.62), 9, 13, Z.Modal + 1)
	resultSubText.TextColor3 = Color3.fromRGB(205, 206, 224)
	resultSubText.TextStrokeTransparency = 0.70

	-- Studio-only start button. It stays outside the actual battle screen.
	testButton = new("TextButton", {
		Name = "TestBattleButton",
		Parent = gui,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -22, 1, -22),
		Size = UDim2.fromOffset(165, 48),
		BackgroundColor3 = Color3.fromRGB(60, 42, 105),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Text = "TEST BATTLE",
		FontFace = Theme.font(),
		TextSize = 18,
		TextColor3 = COLORS.Text,
		Visible = RunService:IsStudio(),
		ZIndex = Z.Test,
	}) :: TextButton
	corner(testButton, 15)
	stroke(testButton, Color3.fromRGB(160, 120, 255), 2, 0.15)
	wireButtonSounds(testButton)

	local function startTest()
		testButton.Active = false
		testButton.Text = "LOADING..."
		local ok, reason, snapshot = BattleRemotes.Action:InvokeServer("StartTest")
		testButton.Active = true
		testButton.Text = "TEST BATTLE"
		if ok and snapshot then
			renderSnapshot(snapshot)
		else
			local message = reason or "Could not start test battle"
			warn("[Battle] " .. message)
			testButton.Text = "CAN'T START"
			task.delay(1.8, function()
				if testButton and testButton.Parent and not overlay.Visible then
					testButton.Text = "TEST BATTLE"
				end
			end)
		end
	end

	testButton.Activated:Connect(startTest)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragging.target = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local point = dragging.target
			local valid = playerActiveHolder:GetAttribute("CanDrop") == true and pointInside(playerActiveHolder, point)
			finishDrag(valid)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if not dragging then
			return
		end
		local alpha = 1 - math.exp(-20 * dt)
		dragging.current = dragging.current:Lerp(dragging.target, alpha)
		local p = localPoint(dragLayer, dragging.current)
		dragging.ref.root.Position = UDim2.fromOffset(p.X, p.Y)
		setDropHighlight(playerActiveHolder:GetAttribute("CanDrop") == true and pointInside(playerActiveHolder, dragging.current))
	end)
end

function BattleController:Init()
	buildGui()

	BattleRemotes.State.OnClientEvent:Connect(function(snapshot)
		if snapshot then
			renderSnapshot(snapshot)
		end
	end)

	BattleRemotes.Event.OnClientEvent:Connect(handleBattleEvent)
end

function BattleController:Start()
	print("[BattleController] battle effects + party power HUD online")
end

return BattleController