--!nonstrict
-- Anime Card Online
-- The Store window: GAME PASSES on top, BUNDLES underneath. No tabs.
--
-- LOOK (from the Figma "Store" frame)
-- Bright navy glass with a cyan rim and a faint grid. Every pass is a glowing
-- card in its own accent colour, with a green Robux button. MOST POPULAR and
-- HOT tags are "live" like the Divine/Secret borders: their colours travel
-- around them and they breathe.
--
-- BUYING
-- The button calls PromptGamePassPurchase. Roblox shows its own confirm; the
-- server (GamePassService) grants the pass on PromptGamePassPurchaseFinished and
-- sets the Pass_<key> attribute, which this window watches to flip the button
-- to OWNED. In a Studio playtest the purchase is a free test purchase.
--
-- BUNDLES have no developer products yet, so they are shown greyed out with a
-- COMING SOON button.
--
-- REDEEM A CODE sits in the header beside the title: a text box and a cyan
-- button (Enter works too). It asks CodeService through Remotes.RedeemCode and
-- the button itself reports the answer - CLAIMED!, INVALID CODE or ALREADY
-- USED - while the box lists what was paid.
--
-- MenuController still opens and closes the window; like the Settings record
-- this only describes how it enters and leaves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local GamePassConfig = require(ReplicatedStorage.Shared.Config.GamePassConfig)
local Theme = require(ReplicatedStorage.Shared.UI.Theme)
local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local StorePresentation = {}

local player = Players.LocalPlayer

----------------------------------------------------------------------
-- palette / sizes
----------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TEXT = Color3.fromRGB(240, 246, 255)
local MUTED = Color3.fromRGB(170, 190, 226)
local CYAN = Color3.fromRGB(63, 240, 255)
local CYAN_DEEP = Color3.fromRGB(30, 139, 255)
local PANEL_TOP = Color3.fromRGB(24, 48, 108)
local PANEL_BOTTOM = Color3.fromRGB(14, 28, 72)
local CARD_BOTTOM = Color3.fromRGB(16, 30, 74)
local CARD_MID = Color3.fromRGB(22, 40, 92)
local GREEN_TOP = Color3.fromRGB(92, 255, 168)
local GREEN_BOTTOM = Color3.fromRGB(18, 200, 98)
local GREEN_RIM = Color3.fromRGB(184, 255, 214)
local CLOSE_BG = Color3.fromRGB(58, 62, 74)
local CLOSE_BG_HOT = Color3.fromRGB(88, 40, 56)
local CLOSE_LINE = Color3.fromRGB(110, 116, 132)
local CLOSE_HOT = Color3.fromRGB(255, 112, 134)

local W, H = 1180, 690
local MARGIN = 26
local CARD_W, CARD_H, CARD_GAP = 360, 232, 24
local PASS_Y = 128
local BUNDLE_LABEL_Y = PASS_Y + CARD_H + 22
local BUNDLE_Y = BUNDLE_LABEL_Y + 44

local QUART = Enum.EasingStyle.Quart
local QUAD = Enum.EasingStyle.Quad
local BACK = Enum.EasingStyle.Back

local BUNDLES = {
	{ name = "STARTER PACK", accent = Color3.fromRGB(46, 123, 255), accent2 = Color3.fromRGB(127, 233, 255),
		items = { "2,500 Elder Coins", "2 Summon Cores", "100 Essence" }, old = "249", off = "-60%" },
	{ name = "MEGA BUNDLE", accent = Color3.fromRGB(255, 176, 32), accent2 = Color3.fromRGB(255, 241, 168),
		items = { "15,000 Elder Coins", "8 Summon Cores", "1,000 Essence" }, old = "1,499", off = "-53%", featured = true },
	{ name = "LEGEND CHEST", accent = Color3.fromRGB(180, 92, 255), accent2 = Color3.fromRGB(255, 124, 242),
		items = { "40,000 Elder Coins", "20 Summon Cores", "Legendary Card" }, old = "2,999", off = "-50%" },
}

----------------------------------------------------------------------
-- small builders
----------------------------------------------------------------------
local function new(className, props, children)
	local o = Instance.new(className)
	if o:IsA("GuiObject") then o.BorderSizePixel = 0 end
	local parent = nil
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if parent then o.Parent = parent end
	return o
end

local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function gradient(parent, a, b, rotation)
	return new("UIGradient", { Parent = parent, Rotation = rotation or 90, Color = ColorSequence.new(a, b) })
end

local function sequence(colours)
	local stops = {}
	for i, c in ipairs(colours) do
		stops[#stops + 1] = ColorSequenceKeypoint.new((i - 1) / (#colours - 1), c)
	end
	return ColorSequence.new(stops)
end

local function applyFont(o)
	pcall(function() o.FontFace = Theme.font() end)
end

local function label(parent, text, size, colour, props)
	local l = new("TextLabel", { Parent = parent, BackgroundTransparency = 1, Text = text, TextSize = size,
		TextColor3 = colour, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center })
	applyFont(l)
	for k, v in pairs(props or {}) do l[k] = v end
	return l
end

local function tween(o, props, t, style, dir)
	local tw = TweenService:Create(o, TweenInfo.new(t or 0.18, style or QUAD, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- Soft light around a card: stacked strokes, strongest at the edge.
local function glow(frame, colour, strength)
	strength = strength or 1
	local strokes = {}
	for i, spec in ipairs({ { 2, 0.15 }, { 5, 0.62 }, { 9, 0.8 }, { 14, 0.9 }, { 20, 0.95 } }) do
		local s = new("UIStroke", { Parent = frame, Name = "Glow" .. i, Color = colour, Thickness = spec[1],
			Transparency = 1 - (1 - spec[2]) * strength, LineJoinMode = Enum.LineJoinMode.Round,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		table.insert(strokes, s)
	end
	return strokes
end

local function outlineText(textLabel, colour, thickness, transparency)
	return new("UIStroke", { Parent = textLabel, Color = colour or BLACK, Thickness = thickness or 1.6,
		Transparency = transparency or 0.35, LineJoinMode = Enum.LineJoinMode.Round })
end

----------------------------------------------------------------------
-- live tags (the Divine/Secret treatment, in the pass's own colours)
----------------------------------------------------------------------
local liveTags = {}

local function liveTag(parent, text, colours, z)
	local pill = new("Frame", { Parent = parent, Name = "Tag", BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(40, 28), ZIndex = z }, { corner(14) })
	local fill = new("UIGradient", { Parent = pill, Color = sequence(colours), Rotation = 0 })
	local rim = new("UIStroke", { Parent = pill, Color = WHITE, Thickness = 2, Transparency = 0.05,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local rimGrad = new("UIGradient", { Parent = rim, Color = sequence({ WHITE, colours[2], WHITE, colours[4], WHITE }) })
	local halo = glow(pill, colours[1], 0.8)
	local caption = label(pill, text, 14, Color3.fromRGB(34, 8, 16), { Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 1 })
	caption.Position = UDim2.fromOffset(0, 0)
	-- Size the pill to its text.
	local width = math.max(40, caption.TextBounds.X + 26)
	pill.Size = UDim2.fromOffset(width, 28)
	caption:GetPropertyChangedSignal("TextBounds"):Connect(function()
		pill.Size = UDim2.fromOffset(math.max(40, caption.TextBounds.X + 26), 28)
	end)
	local scale = new("UIScale", { Parent = pill, Scale = 1 })
	table.insert(liveTags, { pill = pill, fill = fill, rimGrad = rimGrad, halo = halo, colours = colours, scale = scale,
		phase = #liveTags * 0.9 })
	return pill
end

local elapsed = 0
local function stepTags(dt)
	elapsed += dt
	for i = #liveTags, 1, -1 do
		local t = liveTags[i]
		if not t.pill.Parent then
			table.remove(liveTags, i)
		else
			local e = elapsed + t.phase
			-- Colours travel across the fill, the rim sweeps the other way.
			t.fill.Offset = Vector2.new(math.sin(e * 1.6) * 0.55, 0)
			t.fill.Rotation = (e * 40) % 360
			t.rimGrad.Rotation = (-e * 120) % 360
			-- Breathing, and the glow shifting through the tag's colours.
			t.scale.Scale = 1 + math.sin(e * 3.2) * 0.04
			local k = (math.sin(e * 1.3) + 1) / 2
			local a = t.colours[1]:Lerp(t.colours[2], k)
			for _, s in ipairs(t.halo) do s.Color = a end
		end
	end
end

----------------------------------------------------------------------
-- pieces
----------------------------------------------------------------------
local function closeButton(parent, onClose, z)
	local close = new("TextButton", { Parent = parent, Name = "Close", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0, 42), Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = CLOSE_BG, ZIndex = z }, { corner(12) })
	local rim = new("UIStroke", { Parent = close, Color = CLOSE_LINE, Thickness = 1.5, Transparency = 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	for _, rot in ipairs({ 45, -45 }) do
		new("Frame", { Parent = close, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(20, 3), Rotation = rot, BackgroundColor3 = Color3.fromRGB(222, 226, 236), ZIndex = z + 1 },
			{ corner(2) })
	end
	local scale = new("UIScale", { Parent = close, Scale = 1 })
	close.MouseEnter:Connect(function()
		tween(close, { BackgroundColor3 = CLOSE_BG_HOT }, 0.12)
		tween(rim, { Color = CLOSE_HOT, Transparency = 0.05 }, 0.12)
		tween(scale, { Scale = 1.06 }, 0.12)
	end)
	close.MouseLeave:Connect(function()
		tween(close, { BackgroundColor3 = CLOSE_BG }, 0.14)
		tween(rim, { Color = CLOSE_LINE, Transparency = 0.2 }, 0.14)
		tween(scale, { Scale = 1 }, 0.14)
	end)
	close.MouseButton1Down:Connect(function() tween(scale, { Scale = 0.92 }, 0.06) end)
	close.Activated:Connect(onClose)
	return close
end

local function sectionLabel(parent, text, y, z)
	local bar = new("Frame", { Parent = parent, Name = text .. "Bar", Position = UDim2.fromOffset(MARGIN + 2, y + 6),
		Size = UDim2.fromOffset(5, 24), BackgroundColor3 = WHITE, ZIndex = z }, { corner(3) })
	gradient(bar, CYAN, CYAN_DEEP)
	glow(bar, CYAN, 0.6)
	local l = label(parent, text, 26, TEXT, { Name = text .. "Label", Position = UDim2.fromOffset(MARGIN + 18, y),
		Size = UDim2.fromOffset(400, 36), ZIndex = z })
	outlineText(l, BLACK, 1.6, 0.5)
	return l
end

local function buyButton(parent, x, y, w, h, z)
	local button = new("TextButton", { Parent = parent, Name = "BuyButton", Text = "", AutoButtonColor = false,
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = WHITE, ZIndex = z },
		{ corner(14) })
	local grad = gradient(button, GREEN_TOP, GREEN_BOTTOM)
	local rim = new("UIStroke", { Parent = button, Color = GREEN_RIM, Thickness = 2, Transparency = 0.1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local halo = glow(button, Color3.fromRGB(43, 255, 138), 0.55)
	-- the glossy top half
	new("Frame", { Parent = button, Name = "Gloss", BackgroundColor3 = WHITE, BackgroundTransparency = 0.78,
		Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0.42, 0), ZIndex = z + 1 }, { corner(10) })
	local caption = label(button, "R$ ...", 24, WHITE, { Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = z + 2 })
	outlineText(caption, Color3.fromRGB(0, 70, 30), 2, 0.2)
	local scale = new("UIScale", { Parent = button, Scale = 1 })
	return { button = button, grad = grad, rim = rim, halo = halo, caption = caption, scale = scale }
end

----------------------------------------------------------------------
-- window
----------------------------------------------------------------------
function StorePresentation.createWindow(root, onClose)
	local holder = new("Frame", { Parent = root, Name = "ShopWindow", Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, Active = true, ZIndex = 82 })
	local scale = new("UIScale", { Parent = holder, Name = "WindowScale", Scale = 1 })
	-- Clicks on empty parts of the panel must not reach MenuDim (which closes
	-- every menu), so a transparent button sits under everything.
	new("TextButton", { Parent = holder, Name = "InputBlocker", Text = "", AutoButtonColor = false,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Selectable = false, ZIndex = 0 })

	-- shadow + cyan bloom
	local shadow = new("Frame", { Parent = holder, Name = "Shadow", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 1 }, { corner(24) })
	for i, spec in ipairs({ { 4, 0.78 }, { 9, 0.87 }, { 16, 0.93 }, { 26, 0.965 } }) do
		new("UIStroke", { Parent = shadow, Name = "Shade" .. i, Color = BLACK, Thickness = spec[1], Transparency = spec[2],
			LineJoinMode = Enum.LineJoinMode.Round })
	end
	new("UIStroke", { Parent = shadow, Name = "Bloom", Color = CYAN, Thickness = 7, Transparency = 0.9,
		LineJoinMode = Enum.LineJoinMode.Round })

	local panel = new("Frame", { Parent = holder, Name = "Panel", BackgroundColor3 = WHITE, Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true, ZIndex = 2 }, { corner(24) })
	gradient(panel, PANEL_TOP, PANEL_BOTTOM)
	local rim = new("UIStroke", { Parent = panel, Color = WHITE, Thickness = 2, Transparency = 0.05 })
	new("UIGradient", { Parent = rim, Rotation = 90, Color = sequence({ CYAN, Color3.fromRGB(58, 110, 200), Color3.fromRGB(40, 70, 140) }) })

	-- ambient light and the faint grid
	for _, spec in ipairs({
		{ UDim2.fromOffset(-160, -220), UDim2.fromOffset(760, 560), Color3.fromRGB(40, 120, 255), 0.55 },
		{ UDim2.fromOffset(820, 300), UDim2.fromOffset(640, 560), CYAN, 0.7 },
		{ UDim2.fromOffset(360, 420), UDim2.fromOffset(520, 380), Color3.fromRGB(120, 80, 255), 0.78 },
	}) do
		new("ImageLabel", { Parent = panel, Name = "Ambient", BackgroundTransparency = 1, Image = VfxAssets.Glow,
			Position = spec[1], Size = spec[2], ImageColor3 = spec[3], ImageTransparency = spec[4], ZIndex = 2 })
	end
	local grid = new("Frame", { Parent = panel, Name = "Grid", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	for x = 64, W - 1, 64 do
		new("Frame", { Parent = grid, BackgroundColor3 = CYAN, BackgroundTransparency = 0.94,
			Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 2 })
	end
	for y = 64, H - 1, 64 do
		new("Frame", { Parent = grid, BackgroundColor3 = CYAN, BackgroundTransparency = 0.94,
			Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), ZIndex = 2 })
	end

	------------------------------------------------------------------
	-- header
	------------------------------------------------------------------
	local header = new("Frame", { Parent = panel, Name = "Header", BackgroundColor3 = WHITE, BackgroundTransparency = 0.15,
		Size = UDim2.new(1, 0, 0, 84), ZIndex = 3 })
	gradient(header, Color3.fromRGB(30, 58, 128), Color3.fromRGB(22, 44, 102))
	local line = new("Frame", { Parent = header, Name = "Line", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = CYAN, ZIndex = 4 })
	new("UIGradient", { Parent = line, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) })
	local title = label(header, "STORE", 48, WHITE, { Name = "Title", Position = UDim2.fromOffset(MARGIN + 8, 14),
		Size = UDim2.fromOffset(300, 56), ZIndex = 5 })
	new("UIGradient", { Parent = title, Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(127, 233, 255)) })
	new("UIStroke", { Parent = title, Color = Color3.fromRGB(0, 150, 255), Thickness = 2.4, Transparency = 0.35,
		LineJoinMode = Enum.LineJoinMode.Round })
	closeButton(header, onClose, 6)

	------------------------------------------------------------------
	-- redeem a code (header, beside the title)
	------------------------------------------------------------------
	local CODE_X, CODE_Y, CODE_H = 222, 15, 54
	local BOX_W, BTN_W, CODE_GAP = 450, 340, 14
	local PLACEHOLDER = Color3.fromRGB(112, 146, 204)
	local RED_TOP, RED_BOTTOM = Color3.fromRGB(255, 122, 142), Color3.fromRGB(214, 40, 72)

	local codeHome = UDim2.fromOffset(CODE_X, CODE_Y)
	local codeBox = new("Frame", { Parent = header, Name = "CodeBox", BackgroundColor3 = WHITE,
		Position = codeHome, Size = UDim2.fromOffset(BOX_W, CODE_H), ZIndex = 5 }, { corner(14) })
	gradient(codeBox, Color3.fromRGB(9, 20, 54), Color3.fromRGB(14, 30, 74))
	local boxRim = new("UIStroke", { Parent = codeBox, Color = CYAN, Thickness = 2, Transparency = 0.45,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	local codeInput = new("TextBox", { Parent = codeBox, Name = "CodeInput", BackgroundTransparency = 1,
		ClearTextOnFocus = false, Text = "", PlaceholderText = "ENTER CODE", PlaceholderColor3 = PLACEHOLDER,
		TextColor3 = WHITE, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -40, 1, 0),
		ZIndex = 6 })
	applyFont(codeInput)

	local redeem = new("TextButton", { Parent = header, Name = "RedeemButton", Text = "", AutoButtonColor = false,
		Position = UDim2.fromOffset(CODE_X + BOX_W + CODE_GAP, CODE_Y), Size = UDim2.fromOffset(BTN_W, CODE_H),
		BackgroundColor3 = WHITE, ZIndex = 5 }, { corner(14) })
	local redeemGrad = gradient(redeem, CYAN, CYAN_DEEP)
	new("UIStroke", { Parent = redeem, Color = Color3.fromRGB(196, 250, 255), Thickness = 2, Transparency = 0.1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	glow(redeem, CYAN, 0.45)
	new("Frame", { Parent = redeem, Name = "Gloss", BackgroundColor3 = WHITE, BackgroundTransparency = 0.78,
		Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0.42, 0), ZIndex = 6 }, { corner(10) })
	local redeemText = label(redeem, "REDEEM A CODE", 28, WHITE, { Name = "Caption", Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })
	local redeemOutline = outlineText(redeemText, Color3.fromRGB(0, 52, 128), 2, 0.15)
	local redeemScale = new("UIScale", { Parent = redeem, Scale = 1 })

	local CODE_STATES = {
		idle = { CYAN, CYAN_DEEP, "REDEEM A CODE", Color3.fromRGB(0, 52, 128) },
		busy = { Color3.fromRGB(128, 176, 232), Color3.fromRGB(62, 100, 178), "CHECKING...", Color3.fromRGB(20, 40, 96) },
		claimed = { GREEN_TOP, GREEN_BOTTOM, "CLAIMED!", Color3.fromRGB(0, 70, 30) },
		bad = { RED_TOP, RED_BOTTOM, "INVALID CODE", Color3.fromRGB(96, 0, 24) },
	}
	local function paintRedeem(state, text)
		local s = CODE_STATES[state]
		redeemGrad.Color = ColorSequence.new(s[1], s[2])
		redeemText.Text = text or s[3]
		redeemOutline.Color = s[4]
	end

	local function shakeBox()
		task.spawn(function()
			for _, dx in ipairs({ -9, 9, -6, 6, -3, 3, 0 }) do
				codeBox.Position = codeHome + UDim2.fromOffset(dx, 0)
				task.wait(0.03)
			end
			codeBox.Position = codeHome
		end)
	end

	local codeBusy, codeShowing, codeToken = false, false, 0
	local function resetRedeem()
		codeShowing = false
		paintRedeem("idle")
		codeInput.PlaceholderText = "ENTER CODE"
		codeInput.PlaceholderColor3 = PLACEHOLDER
		codeInput.TextSize = 28
		tween(boxRim, { Color = CYAN, Transparency = codeInput:IsFocused() and 0.05 or 0.45 }, 0.2)
	end

	local function submitCode()
		if codeBusy then return end
		local code = (codeInput.Text:gsub("^%s+", ""):gsub("%s+$", ""))
		if code == "" then
			shakeBox()
			tween(boxRim, { Transparency = 0.05 }, 0.1)
			return
		end
		codeBusy = true
		codeToken += 1
		local token = codeToken
		paintRedeem("busy")
		task.spawn(function()
			local ok, result = pcall(function()
				return Remotes.RedeemCode:InvokeServer(code)
			end)
			codeBusy = false
			if token ~= codeToken then return end
			codeShowing = true
			if ok and type(result) == "table" and result.ok then
				paintRedeem("claimed")
				codeInput.Text = ""
				codeInput.PlaceholderText = result.summary or "CLAIMED!"
				codeInput.PlaceholderColor3 = GREEN_TOP
				codeInput.TextSize = 20
				tween(boxRim, { Color = GREEN_TOP, Transparency = 0.05 }, 0.15)
				redeemScale.Scale = 1.12
				tween(redeemScale, { Scale = 1 }, 0.4, BACK)
			else
				local status = if ok and type(result) == "table" then result.status else "error"
				paintRedeem("bad", if status == "used" then "ALREADY USED"
					elseif status == "invalid" then "INVALID CODE" else "TRY AGAIN")
				tween(boxRim, { Color = RED_TOP, Transparency = 0.05 }, 0.1)
				shakeBox()
			end
			task.delay(if ok and type(result) == "table" and result.ok then 4 else 2.2, function()
				if token == codeToken and codeShowing then resetRedeem() end
			end)
		end)
	end

	redeem.Activated:Connect(submitCode)
	codeInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitCode()
		elseif not codeShowing then
			tween(boxRim, { Transparency = 0.45 }, 0.15)
		end
	end)
	codeInput.Focused:Connect(function()
		if codeShowing and not codeBusy then
			codeToken += 1
			resetRedeem()
		end
		tween(boxRim, { Transparency = 0.05 }, 0.12)
	end)
	redeem.MouseEnter:Connect(function() tween(redeemScale, { Scale = 1.04 }, 0.12) end)
	redeem.MouseLeave:Connect(function() tween(redeemScale, { Scale = 1 }, 0.14) end)
	redeem.MouseButton1Down:Connect(function() tween(redeemScale, { Scale = 0.94 }, 0.06) end)
	redeem.MouseButton1Up:Connect(function() tween(redeemScale, { Scale = 1.04 }, 0.1) end)

	------------------------------------------------------------------
	-- game passes
	------------------------------------------------------------------
	sectionLabel(panel, "GAME PASSES", PASS_Y - 42, 4)
	local passCards = {}
	for i, key in ipairs(GamePassConfig.Order) do
		local pass = GamePassConfig.Passes[key]
		local x = MARGIN + (i - 1) * (CARD_W + CARD_GAP)
		local card = new("Frame", { Parent = panel, Name = "Pass_" .. key, BackgroundColor3 = WHITE,
			Position = UDim2.fromOffset(x, PASS_Y), Size = UDim2.fromOffset(CARD_W, CARD_H), ZIndex = 4 }, { corner(22) })
		new("UIGradient", { Parent = card, Rotation = 90, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, pass.accent:Lerp(CARD_MID, 0.45)),
			ColorSequenceKeypoint.new(0.55, CARD_MID),
			ColorSequenceKeypoint.new(1, CARD_BOTTOM),
		}) })
		local cardRim = new("UIStroke", { Parent = card, Color = pass.accent, Thickness = 2.2, Transparency = 0.1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		local cardGlow = glow(card, pass.accent, 0.55)
		local topLine = new("Frame", { Parent = card, Name = "TopLine", Position = UDim2.fromOffset(22, 0),
			Size = UDim2.new(1, -44, 0, 3), BackgroundColor3 = pass.accent2, ZIndex = 5 })
		new("UIGradient", { Parent = topLine, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) })

		new("ImageLabel", { Parent = card, Name = "IconGlow", BackgroundTransparency = 1, Image = VfxAssets.Glow,
			ImageColor3 = pass.accent, ImageTransparency = 0.25, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(92, 118), Size = UDim2.fromOffset(230, 230), ZIndex = 5 })
		local icon = new("ImageLabel", { Parent = card, Name = "Icon", BackgroundTransparency = 1, Image = pass.icon,
			ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(92, 120),
			Size = UDim2.fromOffset(156, 156), ZIndex = 6 })
		local iconScale = new("UIScale", { Parent = icon, Scale = 1 })

		local name = label(card, string.upper(pass.name), 26, WHITE, { Name = "PassName",
			Position = UDim2.fromOffset(180, 34), Size = UDim2.fromOffset(CARD_W - 196, 34), ZIndex = 6,
			TextScaled = true })
		new("UITextSizeConstraint", { Parent = name, MaxTextSize = 26 })
		new("UIGradient", { Parent = name, Rotation = 90, Color = ColorSequence.new(WHITE, pass.accent2) })
		outlineText(name, pass.accent:Lerp(BLACK, 0.5), 1.8, 0.2)
		label(card, pass.description, 15, MUTED, { Name = "Description", Position = UDim2.fromOffset(180, 72),
			Size = UDim2.fromOffset(CARD_W - 196, 80), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 6 })

		local buy = buyButton(card, 180, CARD_H - 70, CARD_W - 196, 52, 7)
		if pass.tag then
			liveTag(card, pass.tag, pass.tagColours, 8)
		end

		local cardScale = new("UIScale", { Parent = card, Scale = 1 })
		local entry = { key = key, pass = pass, card = card, rim = cardRim, glow = cardGlow, buy = buy,
			scale = cardScale, iconScale = iconScale, price = nil, home = card.Position }
		passCards[i] = entry

		local function hover(on)
			tween(cardScale, { Scale = on and 1.025 or 1 }, 0.16)
			tween(iconScale, { Scale = on and 1.08 or 1 }, 0.2, on and BACK or QUAD)
			tween(cardRim, { Thickness = on and 3 or 2.2 }, 0.16)
		end
		card.MouseEnter:Connect(function() hover(true) end)
		card.MouseLeave:Connect(function() hover(false) end)
		buy.button.MouseEnter:Connect(function()
			hover(true)
			if not GamePassConfig.owns(player, key) then tween(buy.scale, { Scale = 1.05 }, 0.12) end
		end)
		buy.button.MouseLeave:Connect(function() tween(buy.scale, { Scale = 1 }, 0.14) end)
		buy.button.MouseButton1Down:Connect(function()
			if not GamePassConfig.owns(player, key) then tween(buy.scale, { Scale = 0.94 }, 0.06) end
		end)
		buy.button.Activated:Connect(function()
			if GamePassConfig.owns(player, key) then return end
			tween(buy.scale, { Scale = 1 }, 0.12, BACK)
			pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, pass.id)
			end)
		end)
	end

	local function paintPass(entry)
		local buy = entry.buy
		if GamePassConfig.owns(player, entry.key) then
			buy.caption.Text = "OWNED \u{2713}"
			buy.grad.Color = ColorSequence.new(Color3.fromRGB(70, 96, 150), Color3.fromRGB(44, 64, 110))
			buy.rim.Color = Color3.fromRGB(150, 180, 230)
			for _, s in ipairs(buy.halo) do s.Enabled = false end
			buy.button.AutoButtonColor = false
		else
			buy.caption.Text = if entry.price then ("R$ %d"):format(entry.price) else "BUY"
			buy.grad.Color = ColorSequence.new(GREEN_TOP, GREEN_BOTTOM)
			buy.rim.Color = GREEN_RIM
			for _, s in ipairs(buy.halo) do s.Enabled = true end
		end
	end

	local function fetchPrices()
		for _, entry in ipairs(passCards) do
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(entry.pass.id, Enum.InfoType.GamePass)
				end)
				if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
					entry.price = info.PriceInRobux
				end
				paintPass(entry)
			end)
		end
	end

	for _, entry in ipairs(passCards) do
		paintPass(entry)
		player:GetAttributeChangedSignal(GamePassConfig.attribute(entry.key)):Connect(function()
			paintPass(entry)
			if GamePassConfig.owns(player, entry.key) and holder.Visible then
				-- a little celebration on the card that was just bought
				entry.scale.Scale = 1.08
				tween(entry.scale, { Scale = 1 }, 0.5, BACK)
				local flash = new("Frame", { Parent = entry.card, BackgroundColor3 = WHITE, BackgroundTransparency = 0.3,
					Size = UDim2.fromScale(1, 1), ZIndex = 20 }, { corner(22) })
				tween(flash, { BackgroundTransparency = 1 }, 0.6)
				task.delay(0.65, function() flash:Destroy() end)
			end
		end)
	end

	------------------------------------------------------------------
	-- bundles (coming soon)
	------------------------------------------------------------------
	sectionLabel(panel, "BUNDLES", BUNDLE_LABEL_Y, 4)
	local bundleCards = {}
	local bundleHomes = {}
	for i, b in ipairs(BUNDLES) do
		local x = MARGIN + (i - 1) * (CARD_W + CARD_GAP)
		local card = new("Frame", { Parent = panel, Name = "Bundle_" .. b.name, BackgroundColor3 = WHITE,
			Position = UDim2.fromOffset(x, BUNDLE_Y), Size = UDim2.fromOffset(CARD_W, CARD_H), ZIndex = 4 }, { corner(22) })
		local accent = b.accent:Lerp(Color3.fromRGB(120, 130, 160), 0.45)
		new("UIGradient", { Parent = card, Rotation = 90, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, accent:Lerp(CARD_MID, 0.55)),
			ColorSequenceKeypoint.new(0.55, CARD_MID),
			ColorSequenceKeypoint.new(1, CARD_BOTTOM),
		}) })
		new("UIStroke", { Parent = card, Color = accent, Thickness = b.featured and 2.6 or 2, Transparency = 0.25,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		glow(card, accent, b.featured and 0.4 or 0.25)
		local nameLabel = label(card, b.name, 24, WHITE, { Position = UDim2.fromOffset(20, 14), Size = UDim2.fromOffset(240, 32),
			ZIndex = 6 })
		new("UIGradient", { Parent = nameLabel, Rotation = 90, Color = ColorSequence.new(WHITE, b.accent2) })
		outlineText(nameLabel, BLACK, 1.4, 0.5)
		local off = new("Frame", { Parent = card, Name = "Discount", AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 16), Size = UDim2.fromOffset(68, 28), BackgroundColor3 = Color3.fromRGB(200, 60, 80),
			ZIndex = 6 }, { corner(9) })
		label(off, b.off, 17, WHITE, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 })

		-- art placeholder: three fanned cards
		for k, spec in ipairs({ { -14, 20, Color3.fromRGB(40, 110, 255) }, { 0, 44, Color3.fromRGB(106, 60, 255) }, { 14, 68, b.accent } }) do
			local c = new("Frame", { Parent = card, Name = "Pack" .. k, BackgroundColor3 = WHITE,
				Position = UDim2.fromOffset(spec[2] + 8, 64 + math.abs(spec[1]) * 0.35), Size = UDim2.fromOffset(62, 90),
				Rotation = -spec[1], ZIndex = 5 + k }, { corner(10) })
			gradient(c, spec[3]:Lerp(Color3.fromRGB(150, 150, 170), 0.35), Color3.fromRGB(18, 26, 56))
			new("UIStroke", { Parent = c, Color = b.accent2, Thickness = 1.6, Transparency = 0.35 })
			new("Frame", { Parent = c, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45),
				Size = UDim2.fromOffset(20, 20), BackgroundColor3 = WHITE, BackgroundTransparency = 0.25, ZIndex = 6 + k },
				{ new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		end

		for j, item in ipairs(b.items) do
			local y = 62 + (j - 1) * 34
			local dot = new("Frame", { Parent = card, Position = UDim2.fromOffset(176, y + 4), Size = UDim2.fromOffset(18, 18),
				BackgroundColor3 = j == 1 and Color3.fromRGB(245, 190, 60) or j == 2 and Color3.fromRGB(160, 100, 255)
					or Color3.fromRGB(80, 190, 255), ZIndex = 6 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			dot.BackgroundTransparency = 0.15
			label(card, item, 16, Color3.fromRGB(214, 224, 244), { Position = UDim2.fromOffset(202, y), Size = UDim2.fromOffset(150, 26),
				ZIndex = 6 })
		end

		local old = label(card, "<s>R$ " .. b.old .. "</s>", 17, Color3.fromRGB(130, 146, 180), { RichText = true,
			Position = UDim2.fromOffset(22, CARD_H - 56), Size = UDim2.fromOffset(140, 30), ZIndex = 6 })
		old.Name = "OldPrice"
		local soon = new("Frame", { Parent = card, Name = "ComingSoon", Position = UDim2.fromOffset(180, CARD_H - 70),
			Size = UDim2.fromOffset(CARD_W - 196, 52), BackgroundColor3 = WHITE, ZIndex = 7 }, { corner(14) })
		gradient(soon, Color3.fromRGB(96, 104, 126), Color3.fromRGB(64, 70, 90))
		new("UIStroke", { Parent = soon, Color = Color3.fromRGB(150, 158, 180), Thickness = 1.6, Transparency = 0.3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		local soonText = label(soon, "COMING SOON", 20, Color3.fromRGB(226, 230, 240), { Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 8 })
		outlineText(soonText, BLACK, 1.4, 0.55)

		-- dim veil so the section reads as not available yet
		new("Frame", { Parent = card, Name = "Veil", BackgroundColor3 = Color3.fromRGB(10, 18, 44), BackgroundTransparency = 0.45,
			Size = UDim2.fromScale(1, 1), ZIndex = 6 }, { corner(22) })
		soon.ZIndex = 9
		soonText.ZIndex = 10
		bundleCards[i] = card
		bundleHomes[i] = card.Position
	end
	-- MEGA's ribbon rides over the card's top edge
	do
		local mega = bundleCards[2]
		local ribbon = new("Frame", { Parent = panel, Name = "BestValue", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(mega.Position.X.Offset + CARD_W / 2, BUNDLE_Y), Size = UDim2.fromOffset(170, 30),
			BackgroundColor3 = WHITE, ZIndex = 11 }, { corner(15) })
		gradient(ribbon, Color3.fromRGB(230, 220, 170), Color3.fromRGB(200, 160, 70))
		new("UIStroke", { Parent = ribbon, Color = WHITE, Thickness = 1.4, Transparency = 0.4,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		label(ribbon, "\u{2605} BEST VALUE \u{2605}", 15, Color3.fromRGB(58, 28, 0), { Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12 })
	end

	------------------------------------------------------------------
	-- record, sizing, animation loop, entrance and exit
	------------------------------------------------------------------
	local record = { name = "Shop", holder = holder, scale = scale, tabButtons = {}, selectedTab = nil,
		baseScale = 1, motion = nil, transition = 0, openFrom = 0.95,
		openTween = TweenInfo.new(0.32, BACK, Enum.EasingDirection.Out) }

	local function fit()
		local size = root.AbsoluteSize
		if size.X < 2 or size.Y < 2 then return end
		local s = math.min((size.X - 40) / W, (size.Y - 40) / H, 1.15)
		s = math.max(0.3, s)
		if record.motion then
			record.motion:Cancel()
			record.motion = nil
		end
		record.baseScale = s
		scale.Scale = s
	end

	local loop = nil
	local function startLoop()
		if loop then return end
		loop = RunService.RenderStepped:Connect(stepTags)
	end
	local function stopLoop()
		if loop then loop:Disconnect(); loop = nil end
	end

	function record.onOpen()
		startLoop()
		fetchPrices()
		-- cards rise in one after another
		for i, entry in ipairs(passCards) do
			local target = entry.home
			entry.card.Position = target + UDim2.fromOffset(0, 18)
			entry.scale.Scale = 0.94
			task.delay(0.04 * i, function()
				tween(entry.card, { Position = target }, 0.36, QUART)
				tween(entry.scale, { Scale = 1 }, 0.4, BACK)
			end)
		end
		for i, card in ipairs(bundleCards) do
			local target = bundleHomes[i]
			card.Position = target + UDim2.fromOffset(0, 18)
			task.delay(0.12 + 0.04 * i, function()
				tween(card, { Position = target }, 0.36, QUART)
			end)
		end
	end

	function record.onClose()
		task.delay(0.2, function()
			if not holder.Visible then stopLoop() end
		end)
	end

	holder:GetPropertyChangedSignal("Visible"):Connect(function()
		if holder.Visible then startLoop() else stopLoop() end
	end)

	local resize = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	holder.Destroying:Connect(function()
		resize:Disconnect()
		stopLoop()
	end)
	fit()

	return record
end

return StorePresentation
