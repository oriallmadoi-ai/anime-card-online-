--!strict
-- Anime Card Online - battle victory reward presentation.
--
-- COMPLETE replacement:
-- ReplicatedStorage > Shared > UI > RewardPopup
--
-- The battle itself closes before this opens. This module intentionally has NO
-- filled modal background: it lives at the top of the screen, replacing the old
-- "YOU BEAT <ENEMY>" message instead of stacking another window over battle UI.
--
-- The BATTLE WON header uses an animated rainbow Shine border. Reward tiles
-- still use the exact rarity border from VariantConfig, so Elder Coins keep the
-- same Secret border as Secret cards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local Shine = require(ReplicatedStorage.Shared.UI.Shine)
local TextShine = require(ReplicatedStorage.Shared.UI.TextShine)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local ElderCoin = require(ReplicatedStorage.Shared.UI.ElderCoin)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local ArtLoader = require(ReplicatedStorage.Shared.UI.ArtLoader)
local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)

local RewardPopup = {}

local TILE = 132
local INK = Color3.fromRGB(10, 10, 16)
local TEXT = Color3.fromRGB(248, 248, 255)
local MUTED = Color3.fromRGB(205, 207, 226)

-- Custom animated border built by the SAME Shine system used throughout the
-- game. The rotating gradient is what makes colour travel around the outline.
local RAINBOW_BORDER = {
	baseColour = Color3.fromRGB(255, 255, 255),
	baseThickness = 1.4,
	baseTransparency = 0.72,
	corner = 18,
	glowScale = 1.0,
	glowColours = {
		Color3.fromRGB(255, 75, 90),
		Color3.fromRGB(255, 166, 65),
		Color3.fromRGB(255, 235, 80),
		Color3.fromRGB(89, 255, 150),
		Color3.fromRGB(75, 225, 255),
		Color3.fromRGB(92, 125, 255),
		Color3.fromRGB(190, 90, 255),
		Color3.fromRGB(255, 75, 190),
		Color3.fromRGB(255, 75, 90),
	},
}

local gui: ScreenGui? = nil
local root: Frame? = nil
local titleFrame: Frame? = nil
local titleLabel: TextLabel
local subtitleLabel: TextLabel
local tileRow: Frame
local hideToken = 0

-- Hard deadline for the banner, in os.clock() seconds. The five-second
-- task.delay below is the NICE way out (it plays the slide-up); this is the one
-- that cannot be skipped. Anything that re-enables the ScreenGui behind this
-- module's back - and BattleController's suppressOtherGuis used to do exactly
-- that, restoring a banner it had hidden when the next battle opened - leaves
-- the banner on screen forever, because the hide timer for that showing has
-- already run. The watchdog below re-checks every frame, so a banner past its
-- deadline is switched off no matter who switched it on.
local visibleUntil = 0
local watchdog: RBXScriptConnection? = nil

local function new(class: string, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function build()
	if gui then
		return
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = new("ScreenGui", {
		Name = "BattleRewards",
		Parent = playerGui,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 110,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}) :: ScreenGui

	if not watchdog then
		watchdog = RunService.Heartbeat:Connect(function()
			local g = gui
			if g and g.Enabled and os.clock() > visibleUntil then
				g.Enabled = false
			end
		end)
	end

	-- Layout container only. There is deliberately NO modal rectangle behind it.
	root = new("Frame", {
		Parent = gui,
		Name = "RewardPresentation",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.022),
		Size = UDim2.fromOffset(900, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = 2,
	}) :: Frame

	new("UIScale", {
		Parent = root,
		Name = "PopScale",
		Scale = 1,
	})

	-- Only the header gets the rainbow frame. This keeps the presentation light
	-- instead of rebuilding another giant modal in the middle of the screen.
	titleFrame = new("Frame", {
		Parent = root,
		Name = "BattleWonHeader",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(700, 82),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = 3,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 18) }),
	}) :: Frame

	Shine.applySpec(titleFrame, RAINBOW_BORDER, 700, "BattleWonRainbow")

	titleLabel = new("TextLabel", {
		Parent = titleFrame,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 7),
		Size = UDim2.new(1, 0, 0, 42),
		Text = "BATTLE WON",
		FontFace = Theme.font(),
		TextSize = 36,
		TextColor3 = TEXT,
		ZIndex = 5,
	}, {
		new("UIStroke", {
			Color = INK,
			Thickness = 3.5,
			LineJoinMode = Enum.LineJoinMode.Round,
		}),
	}) :: TextLabel

	subtitleLabel = new("TextLabel", {
		Parent = titleFrame,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 49),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		FontFace = Theme.font(),
		TextSize = 17,
		-- Scaled down (never up) when a win pays several kinds of thing and the
		-- line would otherwise run past the header.
		TextScaled = true,
		TextColor3 = MUTED,
		ZIndex = 5,
	}, {
		new("UIStroke", {
			Color = INK,
			Thickness = 2,
			Transparency = 0.25,
			LineJoinMode = Enum.LineJoinMode.Round,
		}),
		new("UITextSizeConstraint", {
			MinTextSize = 10,
			MaxTextSize = 17,
		}),
	}) :: TextLabel

	tileRow = new("Frame", {
		Parent = root,
		Name = "Tiles",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 101),
		Size = UDim2.new(1, -28, 0, TILE + 16),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = 3,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 18),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame
end

local function makeTile(reward, order: number)
	local variant = VariantConfig.get(reward.variant or "Standard")

	local tile = new("Frame", {
		Parent = tileRow,
		Name = reward.kind or "Reward",
		LayoutOrder = order,
		Size = UDim2.fromOffset(TILE, TILE),
		BackgroundColor3 = Color3.fromRGB(14, 14, 23),
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = 4,
	}, {
		new("UICorner", { CornerRadius = UDim.new(0, 15) }),
	}) :: Frame

	-- Same renderer and same rarity data as actual cards.
	Shine.apply(tile, variant.id, TILE)

	local glyph = new("TextLabel", {
		Parent = tile,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.62, 0.5),
		Text = reward.glyph or "\u{25C9}",
		FontFace = Theme.font(),
		TextScaled = true,
		TextColor3 = variant.color,
		ZIndex = 6,
	}) :: TextLabel

	-- Elder Coins get the modelled coin instead of the glyph they used to wear.
	-- The kind is what decides it, not the glyph string, so the server can keep
	-- sending its fallback character for any client running older code.
	if reward.kind == "ElderCoins" then
		glyph.Visible = false
		ElderCoin.attach(tile, {
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromScale(0.66, 0.66),
			ZIndex = 6,
		})
	end

	if reward.icon and reward.icon ~= "" then
		glyph.Visible = false

		-- An unlock is announcing a CARD, so it gets the card's own proportions and
		-- fills the tile, rather than the small centred pictogram a currency uses.
		local isUnlock = reward.unlockLabel ~= nil
		local art = new("ImageLabel", {
			Parent = tile,
			Name = "Art",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, isUnlock and 0.5 or 0.45),
			Size = isUnlock and UDim2.fromScale(1, 1) or UDim2.fromScale(0.72, 0.6),
			ScaleType = isUnlock and Enum.ScaleType.Crop or Enum.ScaleType.Fit,
			ZIndex = 6,
		}, {
			new("UICorner", { CornerRadius = UDim.new(0, 15) }),
		}) :: ImageLabel

		-- Assigned through ArtLoader rather than in the property table above: an
		-- unlock banner announcing a card with a blank face is the worst place
		-- for a cold-cache fetch failure to land.
		ArtLoader.set(art, reward.icon)

		-- A Summon Core's art is shared by every level of its family, so the
		-- level is drawn on top of it, the same way the Backpack does.
		local stage = if reward.kind == "SummonCore" then SummonCoreConfig.get(reward.id) else nil
		if stage then
			new("TextLabel", {
				Parent = tile,
				Name = "CoreLevel",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(0.84, 0, 0.77, 0),
				Size = UDim2.fromOffset(56, 30),
				Text = stage.numeral,
				FontFace = Theme.font(),
				TextSize = 28,
				TextColor3 = stage.colour,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 8,
			}, {
				new("UIStroke", {
					Color = INK,
					Thickness = 3,
					LineJoinMode = Enum.LineJoinMode.Round,
				}),
			})
		end

		if isUnlock then
			-- The banner sits ON the artwork, which is what makes the tile read as
			-- "this card is now rollable" rather than as one more currency payout.
			-- Scrimmed, because card art is busy and white text alone would be lost
			-- against a bright illustration.
			local band = new("Frame", {
				Parent = tile,
				Name = "UnlockBand",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.53),
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundColor3 = INK,
				BackgroundTransparency = 0.14,
				BorderSizePixel = 0,
				ZIndex = 8,
			}) :: Frame
			new("UIGradient", {
				Parent = band,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.14, 0),
					NumberSequenceKeypoint.new(0.86, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			})

			local unlockText = new("TextLabel", {
				Parent = band,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Text = reward.unlockLabel,
				FontFace = Theme.font(),
				TextSize = 17,
				TextColor3 = Color3.new(1, 1, 1),
				ZIndex = 9,
			}, {
				new("UIStroke", {
					Color = INK, Thickness = 2.5,
					LineJoinMode = Enum.LineJoinMode.Round,
				}),
			}) :: TextLabel
			-- Same travelling palette the rarity tiers use, so the words read as part
			-- of the game's own language rather than as a system message.
			TextShine.apply(unlockText, "Transcendent")

			local _ = art
		end
	end

	local badge = new("TextLabel", {
		Parent = tile,
		BackgroundColor3 = Color3.fromRGB(12, 12, 20),
		BackgroundTransparency = 0.12,
		Position = UDim2.fromOffset(7, 7),
		Size = UDim2.fromOffset(22, 22),
		Text = variant.label,
		FontFace = Theme.font(),
		TextSize = 12,
		TextColor3 = variant.color,
		ZIndex = 7,
	}, {
		new("UICorner", { CornerRadius = UDim.new(1, 0) }),
		new("UIStroke", {
			Color = variant.color,
			Thickness = 1,
			Transparency = 0.28,
		}),
	}) :: TextLabel
	TextShine.apply(badge, variant.id)

	-- An unlock is not a quantity, so it does not wear a count. "x1" beside a
	-- card that just became rollable reads as "you received one copy", which is
	-- the opposite of what happened.
	new("TextLabel", {
		Parent = tile,
		BackgroundTransparency = 1,
		Visible = reward.unlockLabel == nil,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -9, 0, 7),
		Size = UDim2.fromOffset(82, 22),
		Text = "x" .. Format.comma(reward.amount or 1),
		FontFace = Theme.font(),
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 7,
	}, {
		new("UIStroke", {
			Color = INK,
			Thickness = 2.5,
			LineJoinMode = Enum.LineJoinMode.Round,
		}),
	})

	new("TextLabel", {
		Parent = tile,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -7),
		Size = UDim2.new(1, -12, 0, 18),
		Text = reward.name or "Reward",
		FontFace = Theme.font(),
		TextSize = 13,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(232, 234, 248),
		ZIndex = 7,
	}, {
		new("UITextSizeConstraint", {
			MinTextSize = 9,
			MaxTextSize = 14,
		}),
		new("UIStroke", {
			Color = INK,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Round,
		}),
	})

	return tile
end

function RewardPopup.Show(event)
	if not event or event.won ~= true then
		return
	end

	local rewards = event.rewards
	if type(rewards) ~= "table" or #rewards == 0 then
		return
	end

	build()

	for _, child in ipairs(tileRow:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	-- Coins are summed; everything else that is not an unlock (Summon Cores,
	-- forge items) is listed by name. Adding a coin count to a core count used
	-- to produce "20,002 rewards".
	local coinsTotal = 0
	local unlocked = {}
	local items = {}
	for index, reward in ipairs(rewards) do
		if reward.unlockLabel then
			table.insert(unlocked, reward.name or "a card")
		elseif reward.kind == "ElderCoins" then
			coinsTotal += reward.amount or 0
		else
			table.insert(items, ("+%s %s"):format(Format.comma(reward.amount or 1),
				string.upper(reward.name or "reward")))
		end
		makeTile(reward, index)
	end

	-- More tiles than the row is wide (a first clear on a high stage can pay
	-- coins, a core, essence, a wrench and unlocks at once): shrink the row to
	-- fit rather than letting it run off both edges. Recreated every showing,
	-- because the loop above clears the row.
	local needed = #rewards * TILE + math.max(0, #rewards - 1) * 18
	new("UIScale", {
		Parent = tileRow,
		Name = "RowScale",
		Scale = math.min(1, (900 - 28) / math.max(needed, 1)),
	})

	titleLabel.Text = "BATTLE WON"
	if #unlocked > 0 then
		-- An unlock is the headline whenever there is one: it is the rarest thing
		-- that can come out of a battle, and burying it under a coin count would
		-- waste the moment.
		subtitleLabel.Text = ("%s  \u{2022}  NOW AVAILABLE FROM ROLLS")
			:format(string.upper(table.concat(unlocked, "  \u{2022}  ")))
	else
		local parts = {}
		if coinsTotal > 0 then
			table.insert(parts, ("+%s ELDER COINS"):format(Format.comma(coinsTotal)))
		end
		for _, part in ipairs(items) do
			table.insert(parts, part)
		end
		if #parts == 0 then
			subtitleLabel.Text = "REWARDS DEPOSITED INTO BACKPACK"
		elseif #parts == 1 then
			subtitleLabel.Text = parts[1] .. "  \u{2022}  DEPOSITED INTO BACKPACK"
		else
			subtitleLabel.Text = table.concat(parts, "  \u{2022}  ")
		end
	end

	-- Set BEFORE the ScreenGui goes up, so the watchdog never sees an enabled
	-- banner with a stale deadline. The extra 0.4s covers the slide-out tween.
	visibleUntil = os.clock() + 5.4
	gui.Enabled = true

	local scale = root:FindFirstChild("PopScale") :: UIScale
	scale.Scale = 0.88
	TweenService:Create(
		scale,
		TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	-- A tiny downward settle makes the top banner feel like it replaces the
	-- battle result instead of abruptly spawning.
	root.Position = UDim2.fromScale(0.5, -0.035)
	TweenService:Create(
		root,
		TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.022) }
	):Play()

	hideToken += 1
	local token = hideToken
	task.delay(5, function()
		if hideToken ~= token or not gui or not root then
			return
		end

		local out = TweenService:Create(
			root,
			TweenInfo.new(0.23, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.fromScale(0.5, -0.06) }
		)
		out:Play()
		out.Completed:Once(function()
			if hideToken == token and gui then
				gui.Enabled = false
			end
		end)
	end)
end

function RewardPopup.Hide()
	hideToken += 1
	visibleUntil = 0
	if gui then
		gui.Enabled = false
	end
end

return RewardPopup
