--!nonstrict
-- The Card Forge: the compact upgrade menu that opens at the forge, and the
-- forge's own reaction in the world.
--
-- THE MENU
-- A small panel, built as the Backpack's smaller sibling - same palette, rim,
-- corner brackets, header, close button, group fade and settle-in - docked to
-- the right so the forge itself stays in view behind it. It shows the core on
-- the forge, the tier it is, the tier it becomes, and one button: UPGRADE.
-- Opening cores is not done here; that is the Backpack's OPEN button.
--
-- WHO DECIDES
-- The server. UPGRADE asks SummonCoreService and the animation only plays once
-- the answer is back, so nothing on screen can run ahead of the saved profile.
--
-- WHAT IT COSTS
-- Each step spends forge items (SummonCoreConfig UPGRADE_COSTS): Elder Core
-- Essence for Basic I -> IV, an Elder Wrench for Basic IV -> Gilded I. The Cost
-- row shows have / need and the button names what is missing. A tier with no
-- cost yet is LOCKED ("Coming soon"); devs can still push it for free.
--
-- THE WORLD
-- While the menu is open the 3D core floating over the anvil wears the colours
-- of the core you have selected - your core, placed on the forge - and an
-- upgrade drives the forge itself: white arcs from the energy nodes, a pulse,
-- a flash, and the core changing colour. All client-side, so every player sees
-- their own core, and it returns to its resting Cosmic look when the menu
-- closes. The core also bobs gently at all times, again only on this client.
--
-- DEV
-- Owner / Studio only (SummonCoreConfig.isDev, re-checked by the server): two
-- rows of buttons along the foot of the panel that give test cores and forge
-- items.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local SummonCoreConfig = require(ReplicatedStorage.Shared.Config.SummonCoreConfig)
local VariantConfig = require(ReplicatedStorage.Shared.Config.VariantConfig)
local VfxAssets = require(ReplicatedStorage.Shared.Config.VfxAssets)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local ItemStage = require(ReplicatedStorage.Shared.UI.ItemStage)
local Sweep = require(ReplicatedStorage.Shared.UI.Sweep)
local TextShine = require(ReplicatedStorage.Shared.UI.TextShine)
local Sfx = require(ReplicatedStorage.Shared.UI.Sfx)

local player = Players.LocalPlayer

local CardForgeController = {}
CardForgeController.Name = "CardForgeController"

----------------------------------------------------------------------
-- palette (the Backpack's, so the two read as one family)
----------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TEXT = Color3.fromRGB(240, 242, 250)
local MUTED = Color3.fromRGB(156, 152, 182)
local DIM = Color3.fromRGB(110, 106, 138)
local INK = Color3.fromRGB(23, 26, 32)
local PANEL_TOP = Color3.fromRGB(27, 25, 40)
local PANEL_BOTTOM = Color3.fromRGB(11, 11, 17)
local SUNK = Color3.fromRGB(13, 12, 20)
local FIELD = Color3.fromRGB(30, 28, 44)
local LINE = Color3.fromRGB(66, 62, 96)
local ACCENT = Color3.fromRGB(150, 110, 255)
local ACCENT_HI = Color3.fromRGB(200, 176, 255)
local CLOSE_HOT = Color3.fromRGB(255, 112, 134)
local AMBER = Color3.fromRGB(255, 196, 92)
local GOOD = Color3.fromRGB(124, 224, 160)

local QUART = Enum.EasingStyle.Quart
local QUAD = Enum.EasingStyle.Quad
local BACK = Enum.EasingStyle.Back
local SINE = Enum.EasingStyle.Sine

-- Design size. One UIScale fits it to the screen.
local W = 640
local BASE_H = 482
local DEV_H = 76

-- How far the player can wander from the forge before the menu closes itself.
local WALK_AWAY = 26

-- Crackle, Thump and Switch are engine-shipped (rbxasset://), so they cannot
-- fail moderation. Upgrade is the game's own upload (ForgeUpgrade): it swells
-- through the charge and peaks at the flash, so it starts with the charge.
local SOUNDS = {
	Upgrade = { id = "rbxassetid://79551831226367", volume = 0.55 },
	Crackle = { id = "rbxasset://sounds/snap.mp3", volume = 0.22 },
	Thump = { id = "rbxasset://sounds/bass.wav", volume = 0.4 },
	Switch = { id = "rbxasset://sounds/switch.wav", volume = 0.3 },
}

----------------------------------------------------------------------
-- small builders (same vocabulary as InventoryPresentation)
----------------------------------------------------------------------

local function new(className, props, children)
	local object = Instance.new(className)
	if object:IsA("GuiObject") then object.BorderSizePixel = 0 end
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then object[key] = value end
	end
	for _, child in ipairs(children or {}) do child.Parent = object end
	if props and props.Parent then object.Parent = props.Parent end
	return object
end

local function corner(radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function round()
	return new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function outline(color, transparency, thickness)
	return new("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function text(parent, name, value, size, color, z, font)
	return new("TextLabel", { Parent = parent, Name = name, BackgroundTransparency = 1,
		Text = value, Font = font or Enum.Font.GothamMedium, TextSize = size, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = z or 1 })
end

local function tween(object, properties, duration, style, direction)
	local motion = TweenService:Create(object, TweenInfo.new(duration or 0.14,
		style or QUAD, direction or Enum.EasingDirection.Out), properties)
	motion:Play()
	return motion
end

local function fadeEnds(peak)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, peak),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function hairline(parent, name, color, peak, props)
	local line = new("Frame", { Parent = parent, Name = name, BackgroundColor3 = color, ZIndex = 2 })
	for key, value in pairs(props or {}) do line[key] = value end
	new("UIGradient", { Parent = line, Transparency = fadeEnds(peak) })
	return line
end

local function diamond(parent, name, size, color, transparency, position, z)
	return new("Frame", { Parent = parent, Name = name, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position or UDim2.new(), Size = UDim2.fromOffset(size, size), Rotation = 45,
		BackgroundColor3 = color, BackgroundTransparency = transparency or 0, ZIndex = z or 3 })
end

local function cross(parent, length, thickness, color)
	for _, angle in ipairs({ -45, 45 }) do
		new("Frame", { Parent = parent, Name = "Cross", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(length, thickness), Rotation = angle,
			BackgroundColor3 = color, ZIndex = (parent.ZIndex or 1) + 1 }, { round() })
	end
end

-- A ">" drawn from two bars; dir = 1 points right, -1 left.
local function chevron(parent, size, thickness, color, dir, z)
	local box = new("Frame", { Parent = parent, Name = "Chevron", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size, size), ZIndex = z or 3 })
	local bars = {}
	for _, sign in ipairs({ -1, 1 }) do
		table.insert(bars, new("Frame", { Parent = box, Name = "Bar", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, sign * size * 0.2), Size = UDim2.fromOffset(size * 0.62, thickness),
			Rotation = -45 * sign * dir, BackgroundColor3 = color, ZIndex = z or 3 }, { round() }))
	end
	return box, bars
end

local function bracket(parent, anchor, inset, arm, color, transparency, z)
	local box = new("Frame", { Parent = parent, Name = "Bracket", BackgroundTransparency = 1, AnchorPoint = anchor,
		Position = UDim2.new(anchor.X, anchor.X == 0 and inset or -inset, anchor.Y, anchor.Y == 0 and inset or -inset),
		Size = UDim2.fromOffset(arm, arm), ZIndex = z or 3 })
	new("Frame", { Parent = box, Name = "H", AnchorPoint = anchor, Position = UDim2.fromScale(anchor.X, anchor.Y),
		Size = UDim2.new(1, 0, 0, 1.5), BackgroundColor3 = color, BackgroundTransparency = transparency, ZIndex = z or 3 })
	new("Frame", { Parent = box, Name = "V", AnchorPoint = anchor, Position = UDim2.fromScale(anchor.X, anchor.Y),
		Size = UDim2.new(0, 1.5, 1, 0), BackgroundColor3 = color, BackgroundTransparency = transparency, ZIndex = z or 3 })
end

local function brackets(parent, inset, arm, color, transparency, z)
	for _, anchor in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		bracket(parent, anchor, inset, arm, color, transparency, z)
	end
end

local soundPool = {}
local function pooled(name)
	local spec = SOUNDS[name]
	if not spec then return nil end
	local s = soundPool[name]
	if not s or not s.Parent then
		s = Instance.new("Sound")
		s.Name = "Forge_" .. name
		s.SoundId = spec.id
		s.Volume = spec.volume
		s.Parent = SoundService
		soundPool[name] = s
	end
	return s
end

local function sound(name, pitch)
	local s = pooled(name)
	if not s then return end
	s.PlaybackSpeed = pitch or 1
	s.TimePosition = 0
	s:Play()
end

----------------------------------------------------------------------
-- group fade (the Backpack's: see InventoryPresentation FADES)
----------------------------------------------------------------------

local FADE_PROPS = {
	Frame = { "BackgroundTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	ImageButton = { "BackgroundTransparency", "ImageTransparency" },
	ViewportFrame = { "BackgroundTransparency", "ImageTransparency" },
	UIStroke = { "Transparency" },
}

local Fade = {}
Fade.__index = Fade

function Fade.new(root)
	return setmetatable({ root = root, entries = nil, conn = nil }, Fade)
end

function Fade:capture()
	local list = {}
	local root = self.root
	local function walk(object)
		if object ~= root and object:GetAttribute("NoFade") then return end
		local props = FADE_PROPS[object.ClassName]
		if props then
			for _, prop in ipairs(props) do
				local rest = object[prop]
				if rest < 0.999 then table.insert(list, { object, prop, rest, rest }) end
			end
		end
		for _, child in ipairs(object:GetChildren()) do walk(child) end
	end
	walk(root)
	return list
end

function Fade:apply(a)
	for _, e in ipairs(self.entries) do
		local object = e[1]
		if object.Parent then
			local value = e[3] + (1 - e[3]) * a
			object[e[2]] = value
			e[4] = value
		end
	end
end

function Fade:stop(restore)
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if restore and self.entries then
		for _, e in ipairs(self.entries) do
			local object = e[1]
			if object.Parent and math.abs(object[e[2]] - e[4]) < 0.002 then
				object[e[2]] = e[3]
			end
		end
		self.entries = nil
	end
end

function Fade:run(from, to, duration, onStep, onDone)
	self:stop(true)
	self.entries = self:capture()
	local start = os.clock()
	self:apply(from)
	if onStep then onStep(from) end
	self.conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / math.max(duration, 0.001), 0, 1)
		local k = TweenService:GetValue(t, QUAD, Enum.EasingDirection.Out)
		local a = from + (to - from) * k
		self:apply(a)
		if onStep then onStep(a) end
		if t >= 1 then
			if self.conn then
				self.conn:Disconnect()
				self.conn = nil
			end
			if to <= 0 then self:stop(true) end
			if onDone then onDone() end
		end
	end)
end

----------------------------------------------------------------------
-- the forge in the world (client-side only)
----------------------------------------------------------------------

local World = {}
local originals = {} -- [instance] = { prop = value }
local CORE_PARTS = { Frame = "frame", Trim = "trim", Glow = "glow" }

function World.forge()
	local lobby = workspace:FindFirstChild("Lobby")
	local section = lobby and lobby:FindFirstChild("ForgingSection")
	return section and section:FindFirstChild("CardForge")
end

function World.core()
	local forge = World.forge()
	return forge and forge:FindFirstChild("ForgeCore")
end

local function remember(object, props)
	local saved = originals[object]
	if not saved then
		saved = {}
		originals[object] = saved
	end
	for _, prop in ipairs(props) do
		if saved[prop] == nil then saved[prop] = object[prop] end
	end
end

local function coreLight(core)
	return core and core:FindFirstChildWhichIsA("PointLight", true)
end

local function forgeLights(forge)
	local lights = {}
	if not forge then return lights end
	for _, name in ipairs({ "Energy_Nodes", "Glow_Cradle", "Energy_Core" }) do
		local part = forge:FindFirstChild(name)
		if part then
			for _, d in ipairs(part:GetDescendants()) do
				if d:IsA("PointLight") then table.insert(lights, d) end
			end
		end
	end
	return lights
end

-- Colours the floating core like `stage`.
function World.paint(stage, duration)
	local core = World.core()
	if not core or not stage then return end
	local family = SummonCoreConfig.Families[stage.family]
	for name, key in pairs(CORE_PARTS) do
		local part = core:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			remember(part, { "Color" })
			if duration and duration > 0 then
				tween(part, { Color = family.model[key] }, duration)
			else
				part.Color = family.model[key]
			end
		end
	end
	local light = coreLight(core)
	if light then
		remember(light, { "Color", "Brightness" })
		tween(light, { Color = family.model.glow }, duration or 0)
	end
end

-- Hands every property this module changed back to how the place has it.
function World.restore(duration)
	for object, saved in pairs(originals) do
		if object.Parent then
			tween(object, saved, duration or 0.4)
		end
	end
	table.clear(originals)
end

-- A jagged white arc between two points, rebuilt every few frames.
local function newArc(folder, from, to, thickness)
	local arc = { from = from, to = to, parts = {}, thickness = thickness or 0.2 }
	for i = 1, 9 do
		local p = Instance.new("Part")
		p.Name = "Arc"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(235, 245, 255)
		p.Transparency = 0.05
		p.Size = Vector3.new(arc.thickness, arc.thickness, 1)
		p.Parent = folder
		arc.parts[i] = p
	end
	return arc
end

local function jitterArc(arc, amplitude)
	local n = #arc.parts
	local dir = arc.to - arc.from
	if dir.Magnitude < 0.01 then return end
	local up = math.abs(dir.Unit.Y) > 0.9 and Vector3.xAxis or Vector3.yAxis
	local s1 = dir:Cross(up).Unit
	local s2 = dir:Cross(s1).Unit
	local points = { arc.from }
	for i = 1, n - 1 do
		local t = i / n
		local envelope = math.sin(t * math.pi)
		local offset = (s1 * (math.random() * 2 - 1) + s2 * (math.random() * 2 - 1)) * amplitude * envelope
		points[i + 1] = arc.from + dir * t + offset
	end
	points[n + 1] = arc.to
	for i = 1, n do
		local p0, p1 = points[i], points[i + 1]
		local part = arc.parts[i]
		part.Size = Vector3.new(arc.thickness, arc.thickness, math.max(0.05, (p1 - p0).Magnitude))
		part.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
	end
end

local fxToken = 0

-- The forge powers up, pulses and flashes; the core comes out as `toStage`.
-- `onFlash` runs at the flash, which is when the UI swaps too.
function World.upgrade(toStage, familyChanged, charge)
	fxToken += 1
	local mine = fxToken
	local forge = World.forge()
	local core = World.core()
	if not forge or not core then return end
	local frame = core:FindFirstChild("Frame")
	local centre = frame and frame.Position or core:GetPivot().Position

	local folder = Instance.new("Folder")
	folder.Name = "ForgeUpgradeFx"
	folder.Parent = workspace

	local arcs = {}
	local nodes = forge:FindFirstChild("Energy_Nodes")
	for _, name in ipairs({ "NodeLightA", "NodeLightB" }) do
		local node = nodes and nodes:FindFirstChild(name)
		if node and node:IsA("Attachment") then
			table.insert(arcs, newArc(folder, node.WorldPosition, centre, 0.22))
		end
	end
	local cradle = forge:FindFirstChild("Glow_Cradle")
	if cradle then
		for _, side in ipairs({ -1, 1 }) do
			local base = cradle.Position + Vector3.new(0, 0.1, side * 1.4)
			table.insert(arcs, newArc(folder, base, centre + Vector3.new(0, -1.2, side * 0.6), 0.14))
		end
	end

	-- Charge: lights climb while the arcs crackle.
	local lights = forgeLights(forge)
	for _, light in ipairs(lights) do
		remember(light, { "Brightness", "Color" })
		tween(light, { Brightness = originals[light].Brightness * 2.6, Color = WHITE }, charge, QUAD, Enum.EasingDirection.In)
	end
	local cl = coreLight(core)
	if cl then
		remember(cl, { "Brightness", "Color" })
		tween(cl, { Brightness = 6, Color = WHITE }, charge, QUAD, Enum.EasingDirection.In)
	end
	local basePivot = core:GetPivot()

	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < charge and mine == fxToken do
			local k = (os.clock() - t0) / charge
			for _, arc in ipairs(arcs) do jitterArc(arc, 0.6 + 1.4 * k) end
			-- The core trembles as it fills.
			local j = 0.05 + 0.12 * k
			core:PivotTo(basePivot * CFrame.new((math.random() - 0.5) * j, (math.random() - 0.5) * j, (math.random() - 0.5) * j))
			task.wait(0.045)
		end
		if mine ~= fxToken then
			folder:Destroy()
			return
		end
		core:PivotTo(basePivot)

		-- Flash: the core takes its new colours inside a white burst.
		World.paint(toStage, 0)
		local family = SummonCoreConfig.Families[toStage.family]
		local ball = Instance.new("Part")
		ball.Name = "Flash"
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.CastShadow = false
		ball.Material = Enum.Material.Neon
		ball.Color = WHITE
		ball.Transparency = 0.05
		ball.Size = Vector3.one * 3
		ball.CFrame = CFrame.new(centre)
		ball.Parent = folder
		local flashLight = Instance.new("PointLight")
		flashLight.Color = family.model.glow
		flashLight.Brightness = familyChanged and 9 or 6
		flashLight.Range = familyChanged and 36 or 26
		flashLight.Parent = ball
		tween(ball, { Size = Vector3.one * (familyChanged and 19 or 13), Transparency = 1, Color = family.model.glow }, 0.55, QUART)
		tween(flashLight, { Brightness = 0 }, 0.7, QUAD)

		local ring = Instance.new("Part")
		ring.Name = "Pulse"
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.Neon
		ring.Color = family.model.glow
		ring.Transparency = 0.25
		ring.Size = Vector3.new(0.12, 4, 4)
		ring.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = folder
		tween(ring, { Size = Vector3.new(0.12, familyChanged and 40 or 28, familyChanged and 40 or 28), Transparency = 1 }, 0.7, QUART)

		for _, arc in ipairs(arcs) do
			for _, part in ipairs(arc.parts) do
				tween(part, { Transparency = 1 }, 0.18)
			end
		end
		-- Lights settle to the open-menu look: normal brightness, new colour.
		for _, light in ipairs(lights) do
			local saved = originals[light]
			if saved then tween(light, { Brightness = saved.Brightness, Color = saved.Color }, 0.6) end
		end
		if cl then
			local saved = originals[cl]
			tween(cl, { Brightness = saved and saved.Brightness or 1.6, Color = family.model.glow }, 0.6)
		end
		task.delay(0.8, function() folder:Destroy() end)
	end)
end

-- A gentle idle bob for the floating core, only while it is near the camera.
local bobConn = nil
local function startBob()
	if bobConn then return end
	local base, baseCore = nil, nil
	bobConn = RunService.RenderStepped:Connect(function()
		local core = World.core()
		if not core or not core.PrimaryPart then
			base, baseCore = nil, nil
			return
		end
		if core ~= baseCore then
			baseCore = core
			base = core:GetPivot()
		end
		if fxToken > 0 and core:FindFirstChild("Frame") and workspace:FindFirstChild("ForgeUpgradeFx") then
			return -- the upgrade owns the core while it plays
		end
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - base.Position).Magnitude > 220 then return end
		local t = os.clock()
		core:PivotTo(base * CFrame.new(0, 0.28 * math.sin(t * 1.3), 0) * CFrame.Angles(0, math.rad(9 * math.sin(t * 0.55)), 0))
	end)
end

----------------------------------------------------------------------
-- state
----------------------------------------------------------------------

local profile = nil
local gui, holder, scale
local ui = {}
local selectedId = nil
local isOpen = false
local animating = false
local pendingRefresh = false -- set while an upgrade animation owns the panel
local activePrompt = nil
local previewHandle = nil
local transition = 0
local panelFade = nil
local leaderboardGui, leaderboardWasEnabled = nil, nil
local menuDim = nil
local isDev = false

local function ownedList()
	return SummonCoreConfig.owned(profile)
end

-- The selected core if still owned; otherwise the highest one that can still
-- be upgraded, otherwise the highest one.
local function resolveSelection()
	local list = ownedList()
	if #list == 0 then
		selectedId = nil
		return list, nil
	end
	for i, entry in ipairs(list) do
		if entry.stage.id == selectedId then return list, i end
	end
	for i = #list, 1, -1 do
		if not list[i].stage.isMax then
			selectedId = list[i].stage.id
			return list, i
		end
	end
	selectedId = list[#list].stage.id
	return list, #list
end

local function coreItem(stage)
	local item = { id = "Forge_" .. stage.id, kind = "core", family = stage.family, level = stage.level,
		variant = stage.variant, name = stage.name }
	return item
end

----------------------------------------------------------------------
-- build
----------------------------------------------------------------------

local function build()
	local playerGui = player:WaitForChild("PlayerGui")
	gui = new("ScreenGui", { Name = "CardForge", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 4, Parent = playerGui })

	local H = BASE_H + (isDev and DEV_H or 0)
	holder = new("Frame", { Parent = gui, Name = "ForgeWindow", Visible = false, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -36, 0.5, 0), Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1, Active = true, ZIndex = 1 })
	scale = new("UIScale", { Parent = holder, Name = "WindowScale", Scale = 1 })
	holder:SetAttribute("PanelVisibility", 1)
	new("TextButton", { Parent = holder, Name = "InputBlocker", Text = "", AutoButtonColor = false,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Selectable = false, ZIndex = 0 })

	-- Shadow and a faint violet bloom (stacked strokes, as the Backpack).
	local shadow = new("Frame", { Parent = holder, Name = "Shadow", BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 1 }, { corner(18) })
	for i, spec in ipairs({ { 3, 0.8 }, { 7, 0.88 }, { 12, 0.93 }, { 18, 0.96 }, { 26, 0.978 } }) do
		new("UIStroke", { Parent = shadow, Name = "Shade" .. i, Color = BLACK, Thickness = spec[1],
			Transparency = spec[2], LineJoinMode = Enum.LineJoinMode.Round })
	end
	new("UIStroke", { Parent = shadow, Name = "Bloom", Color = ACCENT, Thickness = 5, Transparency = 0.93,
		LineJoinMode = Enum.LineJoinMode.Round })

	local panel = new("Frame", { Parent = holder, Name = "Panel", BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.06, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, {
		corner(18),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(PANEL_TOP, PANEL_BOTTOM) }),
	})
	local rim = new("UIStroke", { Parent = panel, Name = "Rim", Color = WHITE, Thickness = 1.2, Transparency = 0.25 })
	new("UIGradient", { Parent = rim, Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, ACCENT_HI:Lerp(LINE, 0.35)),
		ColorSequenceKeypoint.new(0.45, LINE),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 32, 50)),
	}) })
	new("Frame", { Parent = panel, Name = "InnerRim", BackgroundTransparency = 1, Position = UDim2.fromOffset(1, 1),
		Size = UDim2.new(1, -2, 1, -2), ZIndex = 1 }, { corner(17), new("UIStroke", { Color = WHITE, Transparency = 0.95 }) })
	new("Frame", { Parent = panel, Name = "TopSheen", BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 0, 110), ZIndex = 1 },
		{ corner(18), new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.955), NumberSequenceKeypoint.new(1, 1) }) }) })
	hairline(panel, "TopLight", ACCENT_HI, 0.3, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0.62, 0, 0, 1) })
	brackets(panel, 10, 14, ACCENT_HI, 0.62, 3)

	------------------------------------------------------------------
	-- header
	------------------------------------------------------------------
	local header = new("Frame", { Parent = panel, Name = "Header", BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 64), ZIndex = 4 })
	ui.header = header
	local badge = new("Frame", { Parent = header, Name = "IconBadge", BackgroundColor3 = WHITE,
		Position = UDim2.fromOffset(22, 12), Size = UDim2.fromOffset(40, 40), ZIndex = 1 }, {
		corner(11),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ACCENT:Lerp(PANEL_TOP, 0.52), PANEL_BOTTOM:Lerp(ACCENT, 0.1)) }),
		outline(ACCENT, 0.45),
	})
	new("ImageLabel", { Parent = badge, Name = "Icon", BackgroundTransparency = 1, Image = SummonCoreConfig.Families.Cosmic.image,
		ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.86), ZIndex = 2 })
	local title = text(header, "Title", "CARD FORGE", 24, TEXT, 2)
	title.Position = UDim2.fromOffset(74, 9)
	title.Size = UDim2.fromOffset(240, 28)
	new("UIStroke", { Parent = title, Thickness = 1.4, Color = BLACK, Transparency = 0.45 })
	local sub = text(header, "SectionLabel", "SUMMON CORE UPGRADES", 11, DIM, 2)
	sub.Position = UDim2.fromOffset(75, 36)
	sub.Size = UDim2.fromOffset(240, 14)

	local close = new("TextButton", { Parent = header, Name = "Close", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0, 32), Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = Color3.fromRGB(34, 31, 48), BackgroundTransparency = 0.08, ZIndex = 2 }, { corner(10) })
	local closeStroke = outline(LINE, 0.3)
	closeStroke.Parent = close
	cross(close, 14, 2, TEXT)
	local closeScale = new("UIScale", { Parent = close, Scale = 1 })
	local closeOver = false
	local function paintClose()
		tween(close, { BackgroundColor3 = closeOver and Color3.fromRGB(78, 32, 50) or Color3.fromRGB(34, 31, 48) })
		tween(closeStroke, { Color = closeOver and CLOSE_HOT or LINE, Transparency = closeOver and 0.1 or 0.3 })
		tween(closeScale, { Scale = closeOver and 1.06 or 1 }, 0.12)
	end
	close.MouseEnter:Connect(function() closeOver = true; paintClose() end)
	close.MouseLeave:Connect(function() closeOver = false; paintClose() end)
	close.MouseButton1Down:Connect(function() tween(closeScale, { Scale = 0.92 }, 0.06) end)
	close.Activated:Connect(function() CardForgeController:Close() end)
	Sfx.bindButton(close)

	-- Devs are told that locked tiers upgrade for them anyway, so a free upgrade
	-- while testing is never mistaken for what players get.
	if isDev and SummonCoreConfig.DevBypassLocked then
		local pill = new("Frame", { Parent = header, Name = "DevPill", AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -70, 0, 32), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = AMBER, BackgroundTransparency = 0.86, ZIndex = 2 },
			{ round(), outline(AMBER, 0.45), new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
		local pillText = text(pill, "Text", "DEV \u{00B7} LOCKED TIERS FREE", 11, AMBER, 3, Enum.Font.GothamBold)
		pillText.AutomaticSize = Enum.AutomaticSize.X
		pillText.Size = UDim2.fromOffset(0, 24)
	end

	hairline(panel, "HeaderDivider", ACCENT_HI, 0.62, { Position = UDim2.fromOffset(22, 64), Size = UDim2.new(1, -44, 0, 1) })
	diamond(panel, "DividerTipL", 5, ACCENT_HI, 0.45, UDim2.fromOffset(22, 64.5), 3)
	diamond(panel, "DividerTipR", 5, ACCENT_HI, 0.45, UDim2.new(1, -22, 0, 64.5), 3)

	------------------------------------------------------------------
	-- body
	------------------------------------------------------------------
	local BODY_Y = 78
	local BODY_H = BASE_H - BODY_Y - 18
	local STAGE_W = 248

	-- The stage: the core on its pedestal.
	local stage = new("Frame", { Parent = panel, Name = "Stage", BackgroundColor3 = WHITE, BackgroundTransparency = 0.02,
		Position = UDim2.fromOffset(22, BODY_Y), Size = UDim2.fromOffset(STAGE_W, BODY_H), ClipsDescendants = true, ZIndex = 4 }, {
		corner(12),
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(34, 28, 56), Color3.fromRGB(12, 11, 19)) }),
	})
	new("UIStroke", { Parent = stage, Color = WHITE, Transparency = 0.92, Thickness = 1 })
	ui.stage = stage
	ui.pedestal = ItemStage.platform(stage, { gate = holder, zIndex = 1, color = ACCENT })
	brackets(stage, 8, 12, ACCENT_HI, 0.55, 6)
	local stageCaption = text(stage, "Caption", "ON THE FORGE", 11, DIM, 6, Enum.Font.GothamBold)
	stageCaption.AnchorPoint = Vector2.new(0.5, 0)
	stageCaption.Position = UDim2.new(0.5, 0, 0, 12)
	stageCaption.Size = UDim2.new(1, -40, 0, 14)
	stageCaption.TextXAlignment = Enum.TextXAlignment.Center
	ui.previewSlot = new("Frame", { Parent = stage, Name = "Preview", BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromScale(0.78, 0.78), ZIndex = 4 },
		{ new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	ui.popScale = new("UIScale", { Parent = ui.previewSlot, Name = "PopScale", Scale = 1 })

	local countPill = new("Frame", { Parent = stage, Name = "Count", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 32), Size = UDim2.fromOffset(34, 20), BackgroundColor3 = WHITE, ZIndex = 7 }, { round() })
	ui.countPill = countPill
	ui.countText = text(countPill, "Value", "x0", 12, INK, 8, Enum.Font.GothamBold)
	ui.countText.Size = UDim2.fromScale(1, 1)
	ui.countText.TextXAlignment = Enum.TextXAlignment.Center

	-- Previous / next owned core.
	ui.arrows = {}
	for _, dir in ipairs({ -1, 1 }) do
		local button = new("TextButton", { Parent = stage, Name = dir < 0 and "Prev" or "Next", Text = "", AutoButtonColor = false,
			AnchorPoint = Vector2.new(dir < 0 and 0 or 1, 0.5), Position = UDim2.new(dir < 0 and 0 or 1, dir < 0 and 8 or -8, 0.47, 0),
			Size = UDim2.fromOffset(30, 30), BackgroundColor3 = FIELD, BackgroundTransparency = 0.15, ZIndex = 7 }, { round() })
		local stroke = outline(LINE, 0.3)
		stroke.Parent = button
		chevron(button, 14, 2.5, MUTED, dir, 8)
		local s = new("UIScale", { Parent = button, Scale = 1 })
		button.MouseEnter:Connect(function()
			tween(s, { Scale = 1.1 }, 0.12)
			tween(stroke, { Color = ACCENT_HI, Transparency = 0.1 }, 0.12)
		end)
		button.MouseLeave:Connect(function()
			tween(s, { Scale = 1 }, 0.12)
			tween(stroke, { Color = LINE, Transparency = 0.3 }, 0.12)
		end)
		button.MouseButton1Down:Connect(function() tween(s, { Scale = 0.9 }, 0.06) end)
		button.Activated:Connect(function() CardForgeController:Cycle(dir) end)
		ui.arrows[dir] = button
	end

	local empty = new("Frame", { Parent = stage, Name = "Empty", BackgroundTransparency = 1, Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.new(1, -30, 0, 110), ZIndex = 7 })
	ui.empty = empty
	new("ImageLabel", { Parent = empty, Name = "Ghost", BackgroundTransparency = 1, Image = SummonCoreConfig.Families.Basic.image,
		ImageTransparency = 0.82, ImageColor3 = Color3.fromRGB(120, 116, 150), ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(64, 64), ZIndex = 7 })
	local emptyTitle = text(empty, "Title", "No core to forge", 15, TEXT, 7, Enum.Font.GothamBold)
	emptyTitle.Position = UDim2.fromOffset(0, 68)
	emptyTitle.Size = UDim2.new(1, 0, 0, 18)
	emptyTitle.TextXAlignment = Enum.TextXAlignment.Center
	local emptyHint = text(empty, "Hint", "Every Pirate Shark win drops a Summon Core. Upgrade it here.", 11, DIM, 7)
	emptyHint.Position = UDim2.fromOffset(0, 88)
	emptyHint.Size = UDim2.new(1, 0, 0, 28)
	emptyHint.TextWrapped = true
	emptyHint.TextXAlignment = Enum.TextXAlignment.Center
	emptyHint.TextYAlignment = Enum.TextYAlignment.Top

	-- Effects layer for the upgrade: flash, pulse ring, bolts, sparks.
	local fx = new("Frame", { Parent = stage, Name = "Fx", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8 })
	fx:SetAttribute("NoFade", true)
	ui.fx = fx
	ui.flash = new("Frame", { Parent = fx, Name = "Flash", BackgroundColor3 = WHITE, BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1), ZIndex = 9 }, { corner(12) })
	ui.pulse = new("ImageLabel", { Parent = fx, Name = "Pulse", BackgroundTransparency = 1, Image = VfxAssets.Shock,
		ImageTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromScale(0.4, 0.4), ZIndex = 9 }, { new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	ui.bolts = new("Frame", { Parent = fx, Name = "Bolts", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 9 })
	ui.banner = text(fx, "Banner", "", 22, WHITE, 10, Enum.Font.GothamBold)
	ui.banner.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.banner.Position = UDim2.fromScale(0.5, 0.84)
	ui.banner.Size = UDim2.new(1, -20, 0, 28)
	ui.banner.TextXAlignment = Enum.TextXAlignment.Center
	ui.banner.TextTransparency = 1
	ui.bannerStroke = new("UIStroke", { Parent = ui.banner, Color = BLACK, Thickness = 1.6, Transparency = 1 })
	ui.bannerScale = new("UIScale", { Parent = ui.banner, Scale = 1 })

	-- Right column: what it is, what it becomes, and the button.
	local colX = 22 + STAGE_W + 20
	local colW = W - colX - 22
	local col = new("Frame", { Parent = panel, Name = "Info", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(colX, BODY_Y), Size = UDim2.fromOffset(colW, BODY_H), ZIndex = 4 })
	ui.col = col

	ui.name = text(col, "CoreName", "", 22, TEXT, 5, Enum.Font.GothamBold)
	ui.name.Size = UDim2.new(1, 0, 0, 28)
	ui.name.TextScaled = true
	new("UITextSizeConstraint", { Parent = ui.name, MaxTextSize = 22, MinTextSize = 14 })
	new("UIStroke", { Parent = ui.name, Color = BLACK, Thickness = 1.2, Transparency = 0.5 })

	local row = new("Frame", { Parent = col, Name = "TierRow", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 18), ZIndex = 5 },
		{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
	ui.family = text(row, "Family", "", 13, TEXT, 5, Enum.Font.GothamBold)
	ui.family.LayoutOrder = 1
	ui.family.AutomaticSize = Enum.AutomaticSize.X
	ui.family.Size = UDim2.fromOffset(0, 18)
	new("Frame", { Parent = row, Name = "Dot", LayoutOrder = 2, Size = UDim2.fromOffset(4, 4), BackgroundColor3 = DIM, ZIndex = 5 }, { round() })
	ui.tier = text(row, "Tier", "", 13, MUTED, 5)
	ui.tier.LayoutOrder = 3
	ui.tier.AutomaticSize = Enum.AutomaticSize.X
	ui.tier.Size = UDim2.fromOffset(0, 18)

	ui.divider = new("Frame", { Parent = col, Name = "Divider", BackgroundColor3 = ACCENT, Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 1), ZIndex = 5 },
		{ new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.65, 0.85), NumberSequenceKeypoint.new(1, 1) }) }) })

	-- Current -> next.
	local tiers = new("Frame", { Parent = col, Name = "Tiers", BackgroundColor3 = SUNK, BackgroundTransparency = 0.3,
		Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 0, 104), ZIndex = 5 }, { corner(10) })
	new("UIStroke", { Parent = tiers, Color = WHITE, Transparency = 0.94 })
	local function tierChip(name, x, caption)
		local chip = new("Frame", { Parent = tiers, Name = name, BackgroundTransparency = 1, Position = UDim2.new(x, x == 0 and 12 or 6, 0, 0),
			Size = UDim2.new(0.5, -30, 1, 0), ZIndex = 6 })
		local cap = text(chip, "Caption", caption, 10, DIM, 6, Enum.Font.GothamBold)
		cap.Position = UDim2.fromOffset(0, 10)
		cap.Size = UDim2.new(1, 0, 0, 12)
		local icon = new("ImageLabel", { Parent = chip, Name = "Icon", BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.fromOffset(-4, 28), Size = UDim2.fromOffset(52, 52), ZIndex = 6 })
		local numeral = text(chip, "Numeral", "", 26, TEXT, 6, Enum.Font.GothamBold)
		numeral.Position = UDim2.fromOffset(52, 30)
		numeral.Size = UDim2.new(1, -52, 0, 28)
		new("UIStroke", { Parent = numeral, Color = BLACK, Thickness = 1.2, Transparency = 0.5 })
		local short = text(chip, "Name", "", 11, MUTED, 6)
		short.Position = UDim2.fromOffset(53, 58)
		short.Size = UDim2.new(1, -53, 0, 14)
		local tag = new("Frame", { Parent = chip, Name = "Tag", Visible = false, Position = UDim2.fromOffset(0, 84),
			Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = WHITE, ZIndex = 6 },
			{ round(), new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
		local tagText = text(tag, "Text", "", 9, INK, 7, Enum.Font.GothamBold)
		tagText.AutomaticSize = Enum.AutomaticSize.X
		tagText.Size = UDim2.fromOffset(0, 14)
		return { chip = chip, caption = cap, icon = icon, numeral = numeral, short = short, tag = tag, tagText = tagText }
	end
	ui.current = tierChip("Current", 0, "CURRENT TIER")
	ui.next = tierChip("Next", 0.5, "NEXT TIER")
	local arrowBox = new("Frame", { Parent = tiers, Name = "Arrow", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, -6, 0, 54), Size = UDim2.fromOffset(28, 28), ZIndex = 6 })
	local _, arrowBars = chevron(arrowBox, 16, 3, ACCENT_HI, 1, 7)
	ui.arrowBars = arrowBars
	ui.arrowBox = arrowBox
	ui.maxLabel = text(tiers, "MaxTier", "MAX TIER", 16, AMBER, 7, Enum.Font.GothamBold)
	ui.maxLabel.AnchorPoint = Vector2.new(0, 0.5)
	ui.maxLabel.Position = UDim2.new(0.5, 10, 0.5, 0)
	ui.maxLabel.Size = UDim2.new(0.5, -20, 0, 20)
	ui.maxLabel.Visible = false

	-- Stats: 1 Luck Boost, 2 Cost, 3 Owned.
	local STAT_KEYS = { "Luck Boost", "Cost", "Owned" }
	local stats = new("Frame", { Parent = col, Name = "Stats", BackgroundColor3 = SUNK, BackgroundTransparency = 0.3,
		Position = UDim2.fromOffset(0, 186), Size = UDim2.new(1, 0, 0, 31 * #STAT_KEYS), ZIndex = 5 },
		{ corner(10), new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
			new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })
	new("UIStroke", { Parent = stats, Color = WHITE, Transparency = 0.94 })
	ui.rows = {}
	for i, key in ipairs(STAT_KEYS) do
		local r = new("Frame", { Parent = stats, Name = "Row" .. i, BackgroundTransparency = 1, LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 31), ZIndex = 6 })
		local k = text(r, "Label", key, 13, MUTED, 6)
		k.Size = UDim2.new(0.3, 0, 1, 0)
		local v = text(r, "Value", "", 14, TEXT, 6)
		v.AnchorPoint = Vector2.new(1, 0)
		v.Position = UDim2.fromScale(1, 0)
		v.Size = UDim2.new(0.7, 0, 1, 0)
		v.TextXAlignment = Enum.TextXAlignment.Right
		v.RichText = true
		if i < #STAT_KEYS then
			new("Frame", { Parent = r, Name = "Line", BackgroundColor3 = WHITE, BackgroundTransparency = 0.93,
				AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 6 })
		end
		ui.rows[i] = v
		if key == "Cost" then
			-- One chip per item the step costs: its icon, name and have / need.
			-- The row's own text is used instead for "Coming soon" and the like.
			local chips = new("Frame", { Parent = r, Name = "CostChips", BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0.7, 0, 1, 0), ZIndex = 6 },
				{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
					VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })
			ui.costChips = {}
			for c = 1, 2 do
				local chip = new("Frame", { Parent = chips, Name = "Chip" .. c, LayoutOrder = c, BackgroundTransparency = 1,
					Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Visible = false, ZIndex = 6 },
					{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }) })
				local icon = new("ImageLabel", { Parent = chip, Name = "Icon", LayoutOrder = 1, BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(24, 24), ZIndex = 7 })
				local label = text(chip, "Text", "", 14, TEXT, 7)
				label.LayoutOrder = 2
				label.AutomaticSize = Enum.AutomaticSize.X
				label.Size = UDim2.fromOffset(0, 24)
				label.RichText = true
				ui.costChips[c] = { frame = chip, icon = icon, label = label }
			end
		end
	end

	-- UPGRADE.
	local upgrade = new("TextButton", { Parent = col, Name = "Upgrade", Text = "", AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = WHITE, ZIndex = 6 }, { corner(12) })
	ui.upgrade = upgrade
	ui.upgradeGradient = new("UIGradient", { Parent = upgrade, Rotation = 90,
		Color = ColorSequence.new(ACCENT:Lerp(WHITE, 0.1), ACCENT:Lerp(BLACK, 0.42)) })
	ui.upgradeStroke = outline(ACCENT_HI, 0.3, 1.2)
	ui.upgradeStroke.Parent = upgrade
	ui.upgradeGlow = new("UIStroke", { Parent = upgrade, Name = "Glow", Color = ACCENT, Thickness = 6, Transparency = 0.84,
		LineJoinMode = Enum.LineJoinMode.Round, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	ui.upgradeScale = new("UIScale", { Parent = upgrade, Scale = 1 })
	ui.upgradeText = text(upgrade, "Caption", "UPGRADE", 19, WHITE, 8, Enum.Font.GothamBold)
	ui.upgradeText.AnchorPoint = Vector2.new(0.5, 0)
	ui.upgradeText.Position = UDim2.new(0.5, 0, 0, 8)
	ui.upgradeText.Size = UDim2.new(1, -20, 0, 22)
	ui.upgradeText.TextXAlignment = Enum.TextXAlignment.Center
	new("UIStroke", { Parent = ui.upgradeText, Color = BLACK, Thickness = 1.2, Transparency = 0.55 })
	ui.upgradeSub = text(upgrade, "Sub", "", 10, WHITE, 8, Enum.Font.GothamBold)
	ui.upgradeSub.AnchorPoint = Vector2.new(0.5, 0)
	ui.upgradeSub.Position = UDim2.new(0.5, 0, 0, 30)
	ui.upgradeSub.Size = UDim2.new(1, -20, 0, 12)
	ui.upgradeSub.TextXAlignment = Enum.TextXAlignment.Center
	ui.upgradeSub.TextTransparency = 0.3
	Sweep.attach(upgrade, { tint = WHITE, transparency = 0.84, width = 0.34, zIndex = 7 })
	local upgradeOver = false
	ui.paintUpgrade = function()
		local enabled = ui.canUpgrade and not animating
		tween(ui.upgradeScale, { Scale = animating and 0.98 or ((upgradeOver and enabled) and 1.025 or 1) }, 0.12)
		tween(ui.upgradeStroke, { Transparency = (upgradeOver and enabled) and 0.05 or 0.3 }, 0.12)
		tween(ui.upgradeGlow, { Transparency = (upgradeOver and enabled) and 0.7 or (enabled and 0.84 or 1) }, 0.16)
	end
	upgrade.MouseEnter:Connect(function() upgradeOver = true; ui.paintUpgrade() end)
	upgrade.MouseLeave:Connect(function() upgradeOver = false; ui.paintUpgrade() end)
	upgrade.MouseButton1Down:Connect(function()
		if ui.canUpgrade and not animating then tween(ui.upgradeScale, { Scale = 0.96 }, 0.06) end
	end)
	upgrade.Activated:Connect(function() CardForgeController:Upgrade() end)
	Sfx.bindButton(upgrade)

	local hint = new("Frame", { Parent = col, Name = "Hint", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 22), ZIndex = 5 })
	diamond(hint, "Tip", 5, ACCENT, 0.3, UDim2.fromOffset(3, 11), 6)
	ui.hint = text(hint, "Text", "", 11, DIM, 6)
	ui.hint.Position = UDim2.fromOffset(14, 0)
	ui.hint.Size = UDim2.new(1, -14, 1, 0)
	ui.hint.TextWrapped = true

	------------------------------------------------------------------
	-- dev strip
	------------------------------------------------------------------
	if isDev then
		local strip = new("Frame", { Parent = panel, Name = "Dev", BackgroundColor3 = SUNK, BackgroundTransparency = 0.25,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -44, 0, DEV_H - 14), ZIndex = 4 },
			{ corner(9), outline(AMBER, 0.75),
				new("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 4),
					VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
				new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
		local function devRow(order, label)
			local row = new("Frame", { Parent = strip, Name = "Row" .. order, LayoutOrder = order, BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 24), ZIndex = 4 },
				{ new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5),
					VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }) })
			local devLabel = text(row, "Label", label, 11, AMBER, 5, Enum.Font.GothamBold)
			devLabel.LayoutOrder = 0
			devLabel.Size = UDim2.fromOffset(52, 22)
			return row
		end
		local coreRow = devRow(1, "DEV CORES")
		local itemRow = devRow(2, "DEV ITEMS")
		local buttons = {}
		for i, stageId in ipairs(SummonCoreConfig.DevQuickGive) do
			local s = SummonCoreConfig.get(stageId)
			table.insert(buttons, { row = coreRow, label = "+" .. s.shortName, colour = s.colour, action = "give",
				args = { stageId = stageId, count = 1 }, order = i })
		end
		table.insert(buttons, { row = coreRow, label = "+ALL", colour = ACCENT_HI, action = "giveall", args = { count = 1 }, order = 90 })
		table.insert(buttons, { row = coreRow, label = "CLEAR", colour = CLOSE_HOT, action = "clear", args = {}, order = 91 })
		local essence = SummonCoreConfig.item("CoreEssenceBasic")
		local wrench = SummonCoreConfig.item("ElderWrench")
		if essence then
			table.insert(buttons, { row = itemRow, label = "+1 Essence", colour = essence.colour, action = "giveitem",
				args = { itemId = essence.id, count = 1 }, order = 1 })
			table.insert(buttons, { row = itemRow, label = "+5 Essence", colour = essence.colour, action = "giveitem",
				args = { itemId = essence.id, count = 5 }, order = 2 })
		end
		if wrench then
			table.insert(buttons, { row = itemRow, label = "+1 Wrench", colour = VariantConfig.get(wrench.variant).color,
				action = "giveitem", args = { itemId = wrench.id, count = 1 }, order = 3 })
		end
		for _, spec in ipairs(buttons) do
			local b = new("TextButton", { Parent = spec.row, Name = spec.label, LayoutOrder = spec.order, AutoButtonColor = false,
				Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = FIELD,
				Text = spec.label, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = spec.colour, ZIndex = 5 },
				{ corner(6), outline(spec.colour, 0.6), new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }) })
			b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = FIELD:Lerp(spec.colour, 0.18) }, 0.1) end)
			b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = FIELD }, 0.12) end)
			b.Activated:Connect(function() CardForgeController:Dev(spec.action, spec.args) end)
		end
	end

	panelFade = Fade.new(holder)
end

----------------------------------------------------------------------
-- fit
----------------------------------------------------------------------

local function fit()
	if not gui then return end
	local size = gui.AbsoluteSize
	if size.X < 2 or size.Y < 2 then return end
	local H = BASE_H + (isDev and DEV_H or 0)
	local s = math.clamp(math.min(size.X / 1500, size.Y / 860), 0.62, 1.08)
	s = math.max(0.3, math.min(s, (size.X - 32) / W, (size.Y - 32) / H))
	ui.baseScale = s
	scale.Scale = s
	-- Docked right, but never so far right that it clips.
	holder.Position = UDim2.new(1, -math.floor(math.clamp(size.X * 0.04, 16, 64)), 0.5, 0)
end

----------------------------------------------------------------------
-- paint
----------------------------------------------------------------------

local function mountPreview(stage, animate)
	if previewHandle then
		previewHandle:destroy()
		previewHandle = nil
	end
	ui.mountedId = stage and stage.id or nil
	if not stage then return end
	previewHandle = ItemStage.mount(ui.previewSlot, coreItem(stage), { size = "preview", gate = holder, phase = 0.21 })
	local family = SummonCoreConfig.Families[stage.family]
	ui.pedestal:setColor(family.colour, family.id == "Cosmic" and VariantConfig.get("Cosmic").border.glowColours or nil)
	if animate then
		ui.popScale.Scale = 0.86
		tween(ui.popScale, { Scale = 1 }, 0.34, QUART)
	end
end

local function boostText(stage)
	return "\u{00D7}" .. SummonCoreConfig.formatBoost(stage.luck)
end

local function paintChip(chip, stage, dim)
	chip.icon.Image = stage.image
	chip.icon.ImageTransparency = dim and 0.5 or 0
	chip.numeral.Text = stage.numeral
	chip.numeral.TextColor3 = stage.colour:Lerp(WHITE, 0.25)
	chip.short.Text = stage.shortName
end

-- The Cost row for upgrading FROM `stage`: one chip per item, "have/need",
-- the have in green when there is enough and red when not. Returns the first
-- item that is short, if any. A stage with no cost (locked, or the top) shows
-- no chips; the caller writes the row's text instead.
local function paintCost(stage)
	local list = stage and SummonCoreConfig.costList(stage.id) or {}
	local missing = nil
	for i, chip in ipairs(ui.costChips) do
		local entry = list[i]
		chip.frame.Visible = entry ~= nil
		if entry then
			local have = SummonCoreConfig.itemCount(profile, entry.item.id)
			local enough = have >= entry.amount
			if not enough and not missing then missing = { item = entry.item, amount = entry.amount, have = have } end
			chip.icon.Image = entry.item.image
			chip.label.Text = ("%s <font color=\"#%s\">%d</font><font color=\"#8C88AC\">/%d</font>"):format(
				entry.item.shortName, (enough and GOOD or CLOSE_HOT):ToHex(), have, entry.amount)
		end
	end
	return list, missing
end

local function greyButton()
	ui.upgradeGradient.Color = ColorSequence.new(Color3.fromRGB(58, 55, 78), Color3.fromRGB(30, 28, 42))
	ui.upgradeStroke.Color = LINE
end

local function refresh(animate)
	if not holder then return end
	local list, index = resolveSelection()
	local entry = index and list[index] or nil
	local stage = entry and entry.stage or nil

	ui.empty.Visible = stage == nil
	ui.countPill.Visible = stage ~= nil
	ui.col.Visible = true
	for _, arrow in pairs(ui.arrows) do arrow.Visible = #list > 1 end

	if not stage then
		mountPreview(nil)
		ui.pedestal:setColor(ACCENT, nil)
		ui.name.Text = "No Summon Core"
		ui.family.Text = "EMPTY"
		ui.family.TextColor3 = MUTED
		TextShine.apply(ui.family, "Standard")
		ui.family.TextColor3 = MUTED
		ui.tier.Text = ("TIER \u{2013} / %d"):format(SummonCoreConfig.MaxIndex)
		ui.current.chip.Visible = false
		ui.next.chip.Visible = false
		ui.arrowBox.Visible = false
		ui.maxLabel.Visible = false
		ui.rows[1].Text = "\u{2013}"
		paintCost(nil)
		ui.rows[2].Text = "\u{2013}"
		ui.rows[3].Text = "x0"
		ui.canUpgrade = false
		ui.upgradeText.Text = "NO CORE"
		ui.upgradeSub.Text = "COLLECT A SUMMON CORE FIRST"
		greyButton()
		ui.hint.Text = "Every Pirate Shark win drops a Summon Core."
		ui.hint.TextColor3 = DIM
		World.restore(0.3)
		ui.paintUpgrade()
		return
	end

	local family = SummonCoreConfig.Families[stage.family]
	local nextStage = SummonCoreConfig.nextOf(stage.id)

	-- A different core (or an explicit re-show) gets a fresh preview; the same
	-- core just has its numbers updated.
	if ui.mountedId ~= stage.id or animate == true then mountPreview(stage, animate == true) end
	ui.countText.Text = "x" .. entry.count
	ui.countPill.Size = UDim2.fromOffset(math.max(30, 14 + #ui.countText.Text * 8), 20)

	ui.name.Text = stage.name
	ui.family.Text = string.upper(family.display)
	ui.family.TextColor3 = stage.colour
	TextShine.apply(ui.family, stage.variant)
	ui.tier.Text = ("TIER %d / %d"):format(stage.index, SummonCoreConfig.MaxIndex)
	ui.divider.BackgroundColor3 = stage.colour

	ui.current.chip.Visible = true
	paintChip(ui.current, stage, false)
	ui.current.tag.Visible = false
	if nextStage then
		ui.next.chip.Visible = true
		ui.arrowBox.Visible = true
		ui.maxLabel.Visible = false
		paintChip(ui.next, nextStage, false)
		local newFamily = nextStage.family ~= stage.family
		ui.next.tag.Visible = newFamily
		if newFamily then
			ui.next.tag.BackgroundColor3 = nextStage.colour
			ui.next.tagText.Text = "NEW FAMILY"
		end
		ui.rows[1].Text = ("%s <font color=\"#8C88AC\">\u{2192}</font> <font color=\"#%s\">%s</font>"):format(
			boostText(stage), nextStage.colour:ToHex(), boostText(nextStage))

		local toName = string.upper(nextStage.shortName)
		local locked = stage.upgrade.locked
		local devFree = locked and isDev and SummonCoreConfig.DevBypassLocked
		local costs, missing = paintCost(stage)
		if locked then
			ui.rows[2].Text = devFree and ("<font color=\"#%s\">Free \u{00B7} dev only</font>"):format(AMBER:ToHex())
				or "<font color=\"#8C88AC\">Coming soon</font>"
		else
			ui.rows[2].Text = ""
		end

		if locked and not devFree then
			ui.canUpgrade = false
			ui.upgradeText.Text = "COMING SOON"
			ui.upgradeSub.Text = "THIS UPGRADE ISN'T OPEN YET"
			greyButton()
			ui.hint.Text = "This tier can't be upgraded yet. You can still open it from your Backpack."
		elseif devFree then
			ui.canUpgrade = true
			ui.upgradeText.Text = "UPGRADE"
			ui.upgradeSub.Text = "DEV \u{00B7} FREE \u{00B7} TO " .. toName
			ui.upgradeGradient.Color = ColorSequence.new(AMBER:Lerp(WHITE, 0.05), AMBER:Lerp(BLACK, 0.55))
			ui.upgradeStroke.Color = AMBER
			ui.hint.Text = "Players see Coming soon here. As a dev you upgrade it for free."
		elseif missing then
			ui.canUpgrade = false
			ui.upgradeText.Text = "NEED " .. string.upper(missing.item.shortName)
			ui.upgradeSub.Text = ("HAVE %d / %d \u{00B7} TO %s"):format(missing.have, missing.amount, toName)
			greyButton()
			ui.hint.Text = ("Get %s from %s wins."):format(missing.item.name, missing.item.source)
		else
			local uses = {}
			for _, c in ipairs(costs) do
				table.insert(uses, ("%d %s"):format(c.amount, string.upper(c.item.shortName)))
			end
			ui.canUpgrade = true
			ui.upgradeText.Text = "UPGRADE"
			ui.upgradeSub.Text = #uses > 0 and ("TO %s \u{00B7} USES %s"):format(toName, table.concat(uses, " + "))
				or ("TO " .. toName)
			ui.upgradeGradient.Color = ColorSequence.new(ACCENT:Lerp(WHITE, 0.1), ACCENT:Lerp(BLACK, 0.42))
			ui.upgradeStroke.Color = nextStage.colour:Lerp(WHITE, 0.25)
			ui.hint.Text = "Upgrading spends the cost shown above. It never fails."
		end
	else
		ui.next.chip.Visible = false
		ui.arrowBox.Visible = false
		ui.maxLabel.Visible = true
		ui.rows[1].Text = boostText(stage)
		paintCost(nil)
		ui.rows[2].Text = "\u{2013}"
		ui.canUpgrade = false
		ui.upgradeText.Text = "MAX TIER"
		ui.upgradeSub.Text = "THE TOP OF THE FORGE"
		ui.upgradeGradient.Color = ColorSequence.new(Color3.fromRGB(96, 70, 30), Color3.fromRGB(44, 32, 16))
		ui.upgradeStroke.Color = AMBER
		ui.hint.Text = "Cosmic V is the strongest core. Open it from your Backpack."
	end
	ui.hint.TextColor3 = DIM
	ui.rows[3].Text = "x" .. entry.count
	ui.paintUpgrade()

	if isOpen and not animating then World.paint(stage, 0.35) end
end

----------------------------------------------------------------------
-- upgrade animation (UI side)
----------------------------------------------------------------------

-- Short white bolts crackling around the core, rebuilt every few frames.
local function drawBolts(count, reach)
	local layer = ui.bolts
	for _, child in ipairs(layer:GetChildren()) do child:Destroy() end
	local size = layer.AbsoluteSize
	if size.X < 2 then return end
	local cx, cy = size.X * 0.5, size.Y * 0.47
	for _ = 1, count do
		local angle = math.random() * math.pi * 2
		local r1 = size.X * (0.17 + math.random() * 0.05)
		local r2 = size.X * (0.3 + math.random() * reach)
		local points = {}
		local n = 5
		for i = 0, n do
			local t = i / n
			local r = r2 + (r1 - r2) * t
			local a = angle + (math.random() - 0.5) * 0.5 * math.sin(t * math.pi)
			points[i + 1] = Vector2.new(cx + math.cos(a) * r, cy + math.sin(a) * r)
		end
		for i = 1, n do
			local p0, p1 = points[i], points[i + 1]
			local d = p1 - p0
			new("Frame", { Parent = layer, Name = "Bolt", AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((p0.X + p1.X) / 2, (p0.Y + p1.Y) / 2), Size = UDim2.fromOffset(d.Magnitude + 1, 2),
				Rotation = math.deg(math.atan2(d.Y, d.X)), BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.05 + math.random() * 0.25, ZIndex = 9 })
		end
	end
end

local function burstSparks(colour)
	local layer = ui.fx
	local size = layer.AbsoluteSize
	for i = 1, 12 do
		local angle = (i / 12) * math.pi * 2 + math.random() * 0.3
		local dist = size.X * (0.3 + math.random() * 0.2)
		local s = 8 + math.random() * 8
		local spark = new("ImageLabel", { Parent = layer, Name = "Spark", BackgroundTransparency = 1,
			Image = i % 3 == 0 and VfxAssets.Spark or VfxAssets.Mote, ImageColor3 = colour:Lerp(WHITE, 0.4),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.47, 0), Size = UDim2.fromOffset(s, s),
			ImageTransparency = 0.05, ZIndex = 10 })
		tween(spark, { Position = UDim2.new(0.5, math.cos(angle) * dist, 0.47, math.sin(angle) * dist),
			ImageTransparency = 1, Size = UDim2.fromOffset(s * 0.4, s * 0.4) }, 0.6 + math.random() * 0.3, QUART)
		task.delay(1, function() spark:Destroy() end)
	end
end

local CHARGE = 0.6

local function playUpgrade(fromStage, toStage)
	local familyChanged = fromStage.family ~= toStage.family
	local toFamily = SummonCoreConfig.Families[toStage.family]

	-- The world charges at the same moment, and the upgrade sound starts with
	-- the charge: it swells through it and peaks on the flash.
	World.upgrade(toStage, familyChanged, CHARGE)
	sound("Upgrade")

	-- 1. Charge: the core draws in and trembles; bolts crackle around it.
	if previewHandle then previewHandle:setBoost(1) end
	tween(ui.popScale, { Scale = 0.9 }, CHARGE, SINE, Enum.EasingDirection.In)
	local t0 = os.clock()
	local nextCrackle = 0
	while os.clock() - t0 < CHARGE do
		local k = (os.clock() - t0) / CHARGE
		drawBolts(2 + math.floor(k * 4), 0.08 + 0.1 * k)
		ui.previewSlot.Position = UDim2.new(0.5, (math.random() - 0.5) * 5 * k, 0.47, (math.random() - 0.5) * 5 * k)
		if os.clock() >= nextCrackle then
			sound("Crackle", 0.9 + math.random() * 0.5)
			nextCrackle = os.clock() + 0.09 + math.random() * 0.06
		end
		task.wait(0.04)
	end
	for _, child in ipairs(ui.bolts:GetChildren()) do child:Destroy() end
	ui.previewSlot.Position = UDim2.fromScale(0.5, 0.47)

	-- 2. Pulse + flash, and the core comes out as its new self. The upgrade
	-- sound peaks here by itself; a new family adds the thump under it.
	if familyChanged then sound("Thump", 1) end
	ui.flash.BackgroundColor3 = WHITE:Lerp(toFamily.colour, 0.25)
	ui.flash.BackgroundTransparency = familyChanged and 0 or 0.15
	tween(ui.flash, { BackgroundTransparency = 1 }, familyChanged and 0.55 or 0.4)
	ui.pulse.ImageColor3 = toFamily.colour:Lerp(WHITE, 0.3)
	ui.pulse.Size = UDim2.fromScale(0.3, 0.3)
	ui.pulse.ImageTransparency = 0.05
	tween(ui.pulse, { Size = UDim2.fromScale(1.5, 1.5), ImageTransparency = 1 }, 0.6, QUART)
	selectedId = toStage.id
	mountPreview(toStage, false)
	ui.popScale.Scale = 1.22
	tween(ui.popScale, { Scale = 1 }, 0.5, BACK)
	burstSparks(toFamily.colour)
	refresh(false)

	if familyChanged then
		ui.banner.Text = string.upper(toFamily.display) .. " CORE!"
		ui.banner.TextColor3 = toFamily.colour
		TextShine.apply(ui.banner, toStage.variant)
		ui.banner.TextTransparency = 0
		ui.bannerStroke.Transparency = 0.3
		ui.bannerScale.Scale = 0.6
		tween(ui.bannerScale, { Scale = 1 }, 0.4, BACK)
		task.delay(1.3, function()
			tween(ui.banner, { TextTransparency = 1 }, 0.3)
			tween(ui.bannerStroke, { Transparency = 1 }, 0.3)
		end)
	end
	task.wait(0.55)
	if previewHandle then previewHandle:setBoost(0) end
end

----------------------------------------------------------------------
-- public
----------------------------------------------------------------------

function CardForgeController:Cycle(dir)
	if animating then return end
	local list, index = resolveSelection()
	if #list < 2 or not index then return end
	local nextIndex = ((index - 1 + dir) % #list) + 1
	selectedId = list[nextIndex].stage.id
	sound("Switch", dir > 0 and 1.1 or 0.95)
	refresh(true)
end

function CardForgeController:Upgrade()
	if animating or not ui.canUpgrade or not selectedId then return end
	local fromStage = SummonCoreConfig.get(selectedId)
	if not fromStage then return end
	animating = true
	ui.upgradeText.Text = "FORGING\u{2026}"
	ui.paintUpgrade()

	local CoreRemotes = require(ReplicatedStorage.Shared.Net.SummonCoreRemotes)
	local okCall, ok, payload = pcall(function()
		return CoreRemotes.Action:InvokeServer("upgrade", { stageId = fromStage.id })
	end)
	if not okCall or not ok then
		animating = false
		refresh(false)
		ui.hint.Text = tostring(okCall and payload or "Couldn't reach the forge. Try again.")
		ui.hint.TextColor3 = CLOSE_HOT
		return
	end

	local toStage = SummonCoreConfig.get(payload.to)
	-- Apply the server's answer to our copy straight away, so the redraw at
	-- the flash cannot run ahead of the ProfileSync that carries the same.
	if profile and toStage then
		profile.summonCores = profile.summonCores or {}
		profile.summonCores[fromStage.id] = (payload.remaining or 0) > 0 and payload.remaining or nil
		profile.summonCores[toStage.id] = payload.owned
		-- The forge items left after paying, so the Cost row is right at once.
		if type(payload.items) == "table" then profile.forgeItems = payload.items end
	end
	if payload.failed or not toStage or toStage.id == fromStage.id then
		-- Only if a stage is given a successChance below 1: the cost is spent,
		-- the core stays.
		animating = false
		refresh(false)
		ui.hint.Text = "The upgrade failed. Your core is unchanged."
		ui.hint.TextColor3 = CLOSE_HOT
		return
	end

	local ran, err = pcall(playUpgrade, fromStage, toStage)
	if not ran then warn("[CardForge] upgrade animation: " .. tostring(err)) end
	animating = false
	pendingRefresh = false
	refresh(false)
	-- Closed mid-animation: hand the forge back now that it has finished.
	if not isOpen then World.restore(0.45) end
end

function CardForgeController:Dev(action, args)
	if not isDev then return end
	args = args or {}
	local CoreRemotes = require(ReplicatedStorage.Shared.Net.SummonCoreRemotes)
	task.spawn(function()
		local okCall, ok, message = pcall(function()
			return CoreRemotes.Action:InvokeServer(action, args)
		end)
		if okCall and ok then
			if action == "give" then selectedId = args.stageId end
			if action == "clear" then selectedId = nil end
			ui.hint.Text = "DEV: " .. tostring(message)
			ui.hint.TextColor3 = AMBER
		else
			ui.hint.Text = "DEV: " .. tostring(okCall and message or ok)
			ui.hint.TextColor3 = CLOSE_HOT
		end
	end)
end

local walkConn = nil

function CardForgeController:Open(prompt)
	if isOpen or not holder then return end
	isOpen = true
	transition += 1
	activePrompt = prompt
	if prompt then prompt.Enabled = false end

	-- One screen at a time.
	local controllers = self.Controllers or {}
	local menus = controllers.MenuController
	if menus and menus.CloseAll then pcall(menus.CloseAll, menus) end
	local deck = controllers.DeckController
	if deck and deck.Close then pcall(deck.Close, deck) end
	local tree = controllers.SkillTreeController
	if tree and tree.Close then pcall(tree.Close, tree) end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	leaderboardGui = playerGui and playerGui:FindFirstChild("BattlePowerLeaderboard")
	if leaderboardGui then
		leaderboardWasEnabled = leaderboardGui.Enabled
		leaderboardGui.Enabled = false
	end
	menuDim = menuDim or (playerGui and playerGui:FindFirstChild("MenuDim", true))

	if not profile then Remotes.RequestSync:FireServer() end
	fit()
	refresh(true)
	holder.Visible = true
	scale.Scale = (ui.baseScale or 1) * 0.97
	tween(scale, { Scale = ui.baseScale or 1 }, 0.3, QUART)
	panelFade:run(1, 0, 0.26, function(a) holder:SetAttribute("PanelVisibility", 1 - a) end)
	ui.col.Position = UDim2.fromOffset(22 + 248 + 20 + 12, 78)
	tween(ui.col, { Position = UDim2.fromOffset(22 + 248 + 20, 78) }, 0.32, QUART)
	sound("Switch", 0.9)

	-- Close when the player walks off, or another menu takes the screen.
	if walkConn then walkConn:Disconnect() end
	local accumulator = 0
	walkConn = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.25 then return end
		accumulator = 0
		if not isOpen then return end
		if menuDim and menuDim.Visible then
			self:Close()
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local anchor = activePrompt and activePrompt.Parent
		local position = anchor and (anchor:IsA("Attachment") and anchor.WorldPosition or (anchor:IsA("BasePart") and anchor.Position))
		if root and position and (root.Position - position).Magnitude > WALK_AWAY then
			self:Close()
		end
	end)
end

function CardForgeController:Close()
	if not isOpen then return end
	isOpen = false
	transition += 1
	local mine = transition
	if walkConn then
		walkConn:Disconnect()
		walkConn = nil
	end
	if activePrompt then activePrompt.Enabled = true end
	activePrompt = nil
	if leaderboardGui then
		leaderboardGui.Enabled = leaderboardWasEnabled ~= false
		leaderboardGui = nil
	end
	if not animating then World.restore(0.45) end
	tween(scale, { Scale = (ui.baseScale or 1) * 0.965 }, 0.14, QUAD, Enum.EasingDirection.In)
	panelFade:run(0, 1, 0.14, function(a) holder:SetAttribute("PanelVisibility", 1 - a) end, function()
		if mine ~= transition then return end
		holder.Visible = false
		panelFade:stop(true)
		holder:SetAttribute("PanelVisibility", 1)
		scale.Scale = ui.baseScale or 1
	end)
end

function CardForgeController:IsOpen()
	return isOpen
end

function CardForgeController:Init()
	isDev = SummonCoreConfig.isDev(player)
	-- Fetched now rather than on first use: an asset that is not cached yet
	-- plays late, by however long the download takes, and this one has to
	-- land on the flash.
	local upgradeSound = pooled("Upgrade")
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({ upgradeSound }) end)
	end)
	build()
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	Remotes.ProfileSync.OnClientEvent:Connect(function(data)
		profile = data
		if not isOpen then return end
		if animating then
			pendingRefresh = true
		else
			refresh(false)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt:GetAttribute("CardForge") then
			if isOpen then self:Close() else self:Open(prompt) end
		end
	end)
end

function CardForgeController:Start()
	startBob()
	if not profile then
		task.defer(function() Remotes.RequestSync:FireServer() end)
	end
end

return CardForgeController
