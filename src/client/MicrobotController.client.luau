--[[
	MICROBOTS  (Big Hero 6 style swarm)
	E  = link / scatter        Q = switch form (Snake / Spider / Megabot), or click the form buttons
	Snake:   the head follows your mouse.
	Spider:  an army of spiders (one more for every SPIDER_BOTS_EACH bots). They walk to your mouse,
	         each leg stepping on its own, and climb walls, ladders, stairs and ceilings: point at a
	         wall to climb it, then at the ceiling to crawl onto it. Point at the floor under them to drop.
	Megabot: big microbots built from microbots. Every MEGA_BOTS_EACH bots form one more
	         megabot; they gather around your mouse as a crowd.
	Slider / number box = swarm size.
	Bot model: ReplicatedStorage.Microbot (a single part or a Model - edit it freely).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

---------------------------------------------------------------- SETTINGS
local MIN_BOTS = 1
local MAX_BOTS = 20000
local START_BOTS = 1000
local TOGGLE_KEY = Enum.KeyCode.E
local FORM_KEY = Enum.KeyCode.Q
local START_FORM = "snake"      -- "snake", "spider" or "megabot"
local BOT_SCALE = 0.5           -- bot size: 1 = ~0.5 studs long, 0.5 = ~0.26 studs (smaller bots = smaller forms)

-- snake
local HEAD_HEIGHT = 3           -- head hovers this high above the mouse point
local HEAD_SPEED = 70
local HEAD_RESPONSE = 7
local RING_SPACING = 0.32
local NECK_LENGTH = 7
local SLITHER_AMP = 0.7
local SLITHER_FREQ = 6
local TWIST_SPEED = 1.6

-- spider
local SPIDER_BOTS_EACH = 200    -- bots per spider: fewer = more (and smaller) spiders in the army
local MAX_SPIDERS = 100
local SPIDER_COVERAGE = 1.3     -- higher = bots packed tighter (smaller, denser spider)
local SPIDER_MIN_SIZE = 0.35
local SPIDER_SPEED = 10          -- base walk speed (studs/s)
local SPIDER_SPEED_PER_SIZE = 4 -- bigger spiders walk faster
local SPIDER_TURN = 6
local STEP_DIST = 0.85          -- how far a foot may lag before it steps (x spider size)
local IDLE_STEP_DIST = 0.3

-- megabot (big microbots built out of microbots)
local MEGA_BOTS_EACH = 400      -- bots per megabot: more bots = more megabots
local MAX_MEGABOTS = 60
local MEGA_COVERAGE = 1.3
local MEGA_MIN_SIZE = 0.5
local MEGA_SPEED = 9

-- shared
local MAX_REACH = 150           -- how far from you the swarm may go
local SPAWN_PER_FRAME = 200
local ACCENT = Color3.fromRGB(230, 57, 70)
local GOLDEN = math.pi * (3 - math.sqrt(5))
----------------------------------------------------------------

---------------------------------------------------------------- BOT TEMPLATE
local templateParts = {}
local BOT_LEN, BOT_THICK = 0.52, 0.18
do
	local src = ReplicatedStorage:WaitForChild("Microbot", 10)
	if src then
		src = src:Clone()
		if src:IsA("BasePart") then
			src.Size = src.Size * BOT_SCALE
			templateParts[1] = { part = src, offset = CFrame.identity }
			BOT_LEN, BOT_THICK = src.Size.X, math.min(src.Size.Y, src.Size.Z)
		elseif src:IsA("Model") then
			if BOT_SCALE ~= 1 then
				src:ScaleTo(src:GetScale() * BOT_SCALE)
			end
			local pivot = src:GetPivot()
			for _, d in src:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(templateParts, { part = d, offset = pivot:ToObjectSpace(d.CFrame) })
				end
			end
			local ext = src:GetExtentsSize()
			BOT_LEN, BOT_THICK = ext.X, math.min(ext.Y, ext.Z)
		end
	end
	if #templateParts == 0 then
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(0.18, 0.18, 0.18) * BOT_SCALE
		p.Color = Color3.fromRGB(10, 10, 12)
		p.Material = Enum.Material.SmoothPlastic
		templateParts[1] = { part = p, offset = CFrame.identity }
		BOT_LEN, BOT_THICK = p.Size.X, p.Size.Y
	end
	for _, tp in templateParts do
		local p = tp.part
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
end

local nParts = #templateParts
local offsets = {}
for k, tp in templateParts do
	offsets[k] = tp.offset
end
local singlePart = nParts == 1 and offsets[1] == CFrame.identity

local folder = Instance.new("Folder")
folder.Name = "Microbots_" .. player.Name
folder.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshFilter()
	local list = { folder }
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end
refreshFilter()

---------------------------------------------------------------- STATE
local bots = {}
local mode = "scatter" -- "scatter" | "linked"
local form = START_FORM
local targetCount = START_BOTS
local now = os.clock()
local lastGroundY = 0
local lastMouseHit = Vector3.zero
local lastMouseNormal = Vector3.yAxis

---------------------------------------------------------------- UI
local gui = Instance.new("ScreenGui")
gui.Name = "MicrobotUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function round(inst, px)
	local c = Instance.new("UICorner")
	c.CornerRadius = px and UDim.new(0, px) or UDim.new(1, 0)
	c.Parent = inst
end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -16)
panel.Size = UDim2.fromOffset(272, 162)
panel.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
panel.BackgroundTransparency = 0.08
panel.Parent = gui
round(panel, 12)
do
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(70, 70, 78)
	s.Transparency = 0.4
	s.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.Parent = panel
end

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Size = UDim2.new(0.5, 0, 0, 16)
title.Font = Enum.Font.GothamBlack
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(240, 240, 245)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "MICROBOTS"
title.Parent = panel

local modeBtn = Instance.new("TextButton")
modeBtn.Name = "ModeButton"
modeBtn.AnchorPoint = Vector2.new(1, 0)
modeBtn.Position = UDim2.new(1, 0, 0, -2)
modeBtn.Size = UDim2.fromOffset(92, 20)
modeBtn.AutoButtonColor = false
modeBtn.Font = Enum.Font.GothamBold
modeBtn.TextSize = 11
modeBtn.Parent = panel
round(modeBtn, 6)

local row = Instance.new("Frame")
row.Name = "CountRow"
row.BackgroundTransparency = 1
row.Position = UDim2.fromOffset(0, 22)
row.Size = UDim2.new(1, 0, 0, 34)
row.Parent = panel
do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.VerticalAlignment = Enum.VerticalAlignment.Bottom
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = row
end

local countBox = Instance.new("TextBox")
countBox.Name = "CountBox"
countBox.BackgroundTransparency = 1
countBox.Size = UDim2.new(0, 20, 1, 0)
countBox.AutomaticSize = Enum.AutomaticSize.X
countBox.Font = Enum.Font.GothamBold
countBox.TextSize = 30
countBox.TextColor3 = Color3.new(1, 1, 1)
countBox.TextXAlignment = Enum.TextXAlignment.Left
countBox.ClearTextOnFocus = false
countBox.Text = tostring(START_BOTS)
countBox.LayoutOrder = 1
countBox.Parent = row

local units = Instance.new("TextLabel")
units.BackgroundTransparency = 1
units.Size = UDim2.new(0, 0, 0, 30)
units.AutomaticSize = Enum.AutomaticSize.X
units.Font = Enum.Font.GothamMedium
units.TextSize = 13
units.TextColor3 = Color3.fromRGB(140, 140, 150)
units.TextYAlignment = Enum.TextYAlignment.Bottom
units.Text = "/ " .. MAX_BOTS .. " units"
units.LayoutOrder = 2
units.Parent = row

local sliderHit = Instance.new("TextButton")
sliderHit.Name = "Slider"
sliderHit.BackgroundTransparency = 1
sliderHit.Text = ""
sliderHit.AutoButtonColor = false
sliderHit.Position = UDim2.fromOffset(0, 62)
sliderHit.Size = UDim2.new(1, 0, 0, 20)
sliderHit.Parent = panel

local track = Instance.new("Frame")
track.AnchorPoint = Vector2.new(0, 0.5)
track.Position = UDim2.new(0, 0, 0.5, 0)
track.Size = UDim2.new(1, 0, 0, 6)
track.BackgroundColor3 = Color3.fromRGB(42, 42, 48)
track.Parent = sliderHit
round(track)

local fill = Instance.new("Frame")
fill.BackgroundColor3 = ACCENT
fill.Size = UDim2.new(0, 0, 1, 0)
fill.Parent = track
round(fill)

local knob = Instance.new("Frame")
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Size = UDim2.fromOffset(16, 16)
knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
knob.ZIndex = 2
knob.Parent = track
round(knob)
do
	local s = Instance.new("UIStroke")
	s.Color = ACCENT
	s.Thickness = 2
	s.Parent = knob
end

local formRow = Instance.new("Frame")
formRow.Name = "FormRow"
formRow.BackgroundTransparency = 1
formRow.Position = UDim2.fromOffset(0, 92)
formRow.Size = UDim2.new(1, 0, 0, 24)
formRow.Parent = panel

local function formButton(name, text, idx)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.Position = UDim2.new((idx - 1) / 3, (idx - 1) * 2, 0, 0)
	b.Size = UDim2.new(1 / 3, -4, 1, 0)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.Text = text
	b.Parent = formRow
	round(b, 6)
	return b
end
local snakeBtn = formButton("SnakeButton", "SNAKE", 1)
local spiderBtn = formButton("SpiderButton", "SPIDER", 2)
local megaBtn = formButton("MegabotButton", "MEGABOT", 3)

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Position = UDim2.fromOffset(0, 122)
hint.Size = UDim2.new(1, 0, 0, 12)
hint.Font = Enum.Font.Gotham
hint.TextSize = 11
hint.TextColor3 = Color3.fromRGB(130, 130, 140)
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = "[E] link / scatter   [Q] form   |   mouse steers"
hint.Parent = panel

local function refreshCountUI()
	-- slider is curved so small counts are still easy to pick
	local p = math.sqrt((targetCount - MIN_BOTS) / (MAX_BOTS - MIN_BOTS))
	fill.Size = UDim2.new(p, 0, 1, 0)
	knob.Position = UDim2.new(p, 0, 0.5, 0)
	if not countBox:IsFocused() then
		countBox.Text = tostring(targetCount)
	end
end

local function setTarget(n)
	targetCount = math.clamp(math.floor(n + 0.5), MIN_BOTS, MAX_BOTS)
	refreshCountUI()
end

local function updateModeUI()
	if mode == "linked" then
		modeBtn.Text = "LINKED"
		modeBtn.BackgroundColor3 = ACCENT
		modeBtn.TextColor3 = Color3.new(1, 1, 1)
	else
		modeBtn.Text = "SCATTERED"
		modeBtn.BackgroundColor3 = Color3.fromRGB(34, 34, 40)
		modeBtn.TextColor3 = Color3.fromRGB(170, 170, 180)
	end
end

local function updateFormUI()
	for _, pair in { { snakeBtn, "snake" }, { spiderBtn, "spider" }, { megaBtn, "megabot" } } do
		local b, f = pair[1], pair[2]
		if form == f then
			b.BackgroundColor3 = Color3.fromRGB(235, 235, 240)
			b.TextColor3 = Color3.fromRGB(12, 12, 14)
		else
			b.BackgroundColor3 = Color3.fromRGB(34, 34, 40)
			b.TextColor3 = Color3.fromRGB(150, 150, 160)
		end
	end
end
refreshCountUI()
updateModeUI()
updateFormUI()

---------------------------------------------------------------- HELPERS
-- Bots that have settled into a spider are welded to one of its invisible joints, so moving
-- the joint moves them all at once (far cheaper than moving every bot every frame).
local function attachBot(b, joint, world)
	b.cf = world
	local welds = table.create(nParts)
	for k = 1, nParts do
		local p = b.parts[k]
		p.CFrame = world * offsets[k]
		local w = Instance.new("WeldConstraint")
		w.Part0 = joint
		w.Part1 = p
		w.Parent = p
		p.Anchored = false
		welds[k] = w
	end
	b.welds = welds
	b.lcf = nil
end

local function detachBot(b)
	local welds = b.welds
	if welds then
		for k = 1, nParts do
			b.parts[k].Anchored = true
		end
		for _, w in welds do
			w:Destroy()
		end
		b.welds = nil
		b.cf = b.parts[1].CFrame * offsets[1]:Inverse()
	end
	b.lcf = nil
	b.locked = false
end

local function detachAll()
	for _, b in bots do
		detachBot(b)
	end
end
local function getRoot()
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- surface under a point, searching from a little above it
local function groundAt(p)
	local r = workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -300, 0), rayParams)
	if r then
		return r.Position, r.Normal
	end
	return Vector3.new(p.X, lastGroundY, p.Z), Vector3.yAxis
end

-- surface straight below a point (never above it)
local function groundBelow(p)
	local r = workspace:Raycast(p, Vector3.new(0, -400, 0), rayParams)
	if r then
		return r.Position, r.Normal
	end
	return Vector3.new(p.X, lastGroundY, p.Z), Vector3.yAxis
end

local function sphere(origin, radius, dir)
	if dir.Magnitude < 1e-3 then
		return nil
	end
	return workspace:Spherecast(origin, radius, dir, rayParams)
end

-- a bot lying flat on a surface with a random heading
local function lyingCF(pos, normal)
	local ref = math.abs(normal.Y) < 0.95 and Vector3.yAxis or Vector3.xAxis
	local a = normal:Cross(ref).Unit
	local b = normal:Cross(a).Unit
	local yaw = math.random() * math.pi * 2
	local x = a * math.cos(yaw) + b * math.sin(yaw)
	return CFrame.fromMatrix(pos + normal * (BOT_THICK * 0.5), x, normal)
end

local function groundSpot(center, rMin, rMax)
	local ang = math.random() * math.pi * 2
	local d = rMin + (rMax - rMin) * math.sqrt(math.random())
	return lyingCF(groundAt(center + Vector3.new(math.cos(ang) * d, 0, math.sin(ang) * d)))
end

local function scatterRadius(n)
	return 4 + math.sqrt(n) * 0.65
end

-- point under the mouse (clamped to MAX_REACH from the player)
local function getMouseHit()
	local m = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(m.X, m.Y)
	local r = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	local hit
	lastMouseNormal = r and r.Normal or Vector3.yAxis
	if r then
		hit = r.Position
	elseif ray.Direction.Y < -1e-3 then
		hit = ray.Origin + ray.Direction * ((lastGroundY - ray.Origin.Y) / ray.Direction.Y)
	else
		hit = lastMouseHit
	end
	local root = getRoot()
	if root then
		local rp = root.Position
		local flat = Vector3.new(hit.X - rp.X, 0, hit.Z - rp.Z)
		if flat.Magnitude > MAX_REACH then
			flat = flat.Unit * MAX_REACH
			hit = Vector3.new(rp.X + flat.X, hit.Y, rp.Z + flat.Z)
		end
	end
	lastMouseHit = hit
	return hit
end

---------------------------------------------------------------- SNAKE
local nodes = {}
local ringSize, rings, baseRadius, slotStep, spacing = 1, 1, 0, 0, RING_SPACING
local ringRadius, liftProfile = {}, {}
local ringCenter, ringT, ringR, ringU, ringTwist = {}, {}, {}, {}, {}
local headDir = Vector3.new(0, 0, -1)
local headSpeed = 0

local function taper(i, n)
	local head = math.min(1, 0.7 + 0.1 * i)
	local tail = 1
	local tailStart = n * 0.6
	if n > 4 and i > tailStart then
		tail = 1 - 0.7 * ((i - tailStart) / (n - tailStart))
	end
	return math.min(head, tail)
end

local function snakeLayout()
	local n = math.max(#bots, 1)
	ringSize = math.clamp(math.floor(math.sqrt(n) / 3 + 0.5), 1, 60)
	rings = math.max(1, math.ceil(n / ringSize))
	baseRadius = ringSize > 1 and ringSize * BOT_LEN * 0.62 / (2 * math.pi) or 0
	slotStep = 2 * math.pi / ringSize
	spacing = ringSize == 1 and BOT_LEN * 0.85 or RING_SPACING * BOT_SCALE
	local neckRings = math.max(1, NECK_LENGTH / spacing)
	for i = 1, rings do
		ringRadius[i] = baseRadius * taper(i, rings)
		local k = 1 - (i - 1) / neckRings
		liftProfile[i] = k > 0 and HEAD_HEIGHT * k ^ 1.6 or 0
	end
end

local function snakeInit()
	table.clear(nodes)
	local c = Vector3.zero
	for _, b in bots do
		c += b.cf.Position
	end
	c /= math.max(#bots, 1)
	local tgt = getMouseHit()
	local dir = Vector3.new(tgt.X - c.X, 0, tgt.Z - c.Z)
	if dir.Magnitude < 0.1 then
		dir = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(0, 0, -1)
	headDir = dir
	local g = groundAt(c)
	local start = Vector3.new(c.X, g.Y + 1, c.Z)
	for i = 1, rings do
		nodes[i] = start - dir * ((i - 1) * spacing)
	end
end

local function snakeResize()
	local old = #nodes
	if old == 0 then
		snakeInit()
		return
	end
	if rings > old then
		local last = nodes[old]
		local dir = old > 1 and (nodes[old] - nodes[old - 1]) or -headDir
		dir = dir.Magnitude > 1e-4 and dir.Unit or -headDir
		for i = old + 1, rings do
			nodes[i] = last + dir * ((i - old) * spacing)
		end
	else
		for i = old, rings + 1, -1 do
			nodes[i] = nil
		end
	end
end

local function snakeUpdate(dt)
	-- head chases the mouse
	local target = getMouseHit() + Vector3.new(0, HEAD_HEIGHT, 0)
	local head = nodes[1]
	local step = (target - head) * (1 - math.exp(-HEAD_RESPONSE * dt))
	local sm = step.Magnitude
	local maxStep = HEAD_SPEED * dt
	if sm > maxStep then
		step = step * (maxStep / sm)
		sm = maxStep
	end
	nodes[1] = head + step
	headSpeed += (sm / dt - headSpeed) * math.min(1, dt * 5)
	if rings == 1 and sm > 1e-3 then
		headDir = step / sm
	end

	-- body follows like a rope, settling onto the ground behind the raised neck
	local yAlpha = 1 - math.exp(-10 * dt)
	local halfT = BOT_THICK * 0.5
	for i = 2, rings do
		local prev = nodes[i - 1]
		local d = nodes[i] - prev
		local m = d.Magnitude
		local p = if m > 1e-4 then prev + d * (spacing / m) else prev - headDir * spacing
		local g = groundAt(p)
		local desired = g.Y + ringRadius[i] + halfT + liftProfile[i]
		nodes[i] = Vector3.new(p.X, p.Y + (desired - p.Y) * yAlpha, p.Z)
	end

	-- ring frames + slither
	local wavePhase = now * SLITHER_FREQ
	local moveF = math.clamp(headSpeed / 20, 0.15, 1)
	for i = 1, rings do
		local t
		if rings == 1 then
			t = headDir
		elseif i == 1 then
			t = nodes[1] - nodes[2]
		else
			t = nodes[i - 1] - nodes[i]
		end
		local tm = t.Magnitude
		t = if tm > 1e-4 then t / tm else headDir
		if i == 1 then
			headDir = t
		end
		local right = t:Cross(Vector3.yAxis)
		if right.Magnitude < 0.05 then
			right = t:Cross(Vector3.xAxis)
		end
		right = right.Unit
		local up = right:Cross(t)
		local env = math.min(1, (i - 1) / 6)
		ringCenter[i] = nodes[i] + right * (math.sin(wavePhase - i * 0.22) * SLITHER_AMP * moveF * env)
		ringT[i] = t
		ringR[i] = right
		ringU[i] = up
		ringTwist[i] = now * TWIST_SPEED + i * 0.37
	end
end

local function snakeTarget(j, b, shimmerT)
	local ring = math.floor((j - 1) / ringSize) + 1
	local c = ringCenter[ring]
	local t = ringT[ring]
	if ringSize == 1 then
		b.radial = ringU[ring]
		return CFrame.fromMatrix(c, t, ringU[ring])
	end
	local a = ringTwist[ring] + ((j - 1) % ringSize) * slotStep
	local ca, sa = math.cos(a), math.sin(a)
	local R, U = ringR[ring], ringU[ring]
	local radial = R * ca + U * sa
	local tang = U * ca - R * sa
	local r = ringRadius[ring] * (1 + 0.1 * math.sin(shimmerT + b.phase))
	local x = (tang + t * ((ring % 2 == 0) and 0.5 or -0.5)).Unit
	b.radial = radial
	return CFrame.fromMatrix(c + radial * r, x, radial)
end

---------------------------------------------------------------- SPIDER
-- An army of spiders: every SPIDER_BOTS_EACH bots form one more spider. Each spider walks,
-- climbs and steps on its own. Body space: X = right, Y = up, -Z = forward.
-- All sizes below are x spider size.
local FEMUR, TIBIA, REACH, BODY_H = 2.3, 2.7, 3.0, 1.3

local LEG_DEFS = {}
local function legIndex(s, k)
	return (s - 1) * 4 + k
end
do
	local hipZ = { -0.55, -0.2, 0.15, 0.5 }
	local ang = { 55, 20, -15, -50 } -- foot direction, degrees toward the front
	for s = 1, 2 do
		local side = s == 1 and -1 or 1
		for k = 1, 4 do
			LEG_DEFS[legIndex(s, k)] = {
				side = side,
				hip = Vector3.new(side * 0.75, 0.05, hipZ[k]),
				ang = math.rad(ang[k]),
			}
		end
	end
end

-- a leg won't lift while a neighbour (front/back on the same side, or its mirror) is in the air
local LEG_NEIGHBORS = {}
for s = 1, 2 do
	for k = 1, 4 do
		local list = { legIndex(3 - s, k) }
		if k > 1 then
			table.insert(list, legIndex(s, k - 1))
		end
		if k < 4 then
			table.insert(list, legIndex(s, k + 1))
		end
		LEG_NEIGHBORS[legIndex(s, k)] = list
	end
end

-- body parts every spider is made of
local SP_DEFS = {
	{ kind = "ell", off = CFrame.new(0, 0, 0), radii = Vector3.new(0.95, 0.6, 1.05) }, -- thorax
	{ kind = "ell", off = CFrame.new(0, 0.05, -1.25), radii = Vector3.new(0.55, 0.45, 0.5) }, -- head
	{ kind = "ell", off = CFrame.new(0, 0.4, 1.75) * CFrame.Angles(math.rad(-14), 0, 0), radii = Vector3.new(1.2, 0.95, 1.5) }, -- abdomen
}
for i = 1, 8 do
	table.insert(SP_DEFS, { kind = "tube", leg = i, seg = 1, r0 = 0.24, r1 = 0.2, len = FEMUR })
	table.insert(SP_DEFS, { kind = "knee", leg = i, radii = Vector3.new(0.3, 0.3, 0.3) })
	table.insert(SP_DEFS, { kind = "tube", leg = i, seg = 2, r0 = 0.2, r1 = 0.07, len = TIBIA })
end

local function ellArea(r)
	local p = 1.6
	local ab, ac, bc = (r.X * r.Y) ^ p, (r.X * r.Z) ^ p, (r.Y * r.Z) ^ p
	return 4 * math.pi * ((ab + ac + bc) / 3) ^ (1 / p)
end

local function allocate(weights, n)
	local total = 0
	for _, w in weights do
		total += w
	end
	local counts, rems, order, used = {}, {}, {}, 0
	for i, w in weights do
		local exact = n * w / total
		counts[i] = math.floor(exact)
		rems[i] = exact - counts[i]
		used += counts[i]
		order[i] = i
	end
	table.sort(order, function(a, b)
		return rems[a] > rems[b]
	end)
	for k = 1, n - used do
		counts[order[k]] += 1
	end
	return counts
end

local SP_WEIGHTS, SP_UNIT_AREA = {}, 0
for i, d in SP_DEFS do
	local a = d.kind == "tube" and (math.pi * (d.r0 + d.r1) * d.len) or ellArea(d.radii)
	SP_WEIGHTS[i] = a
	SP_UNIT_AREA += a
end

local spiders = {}
local spiderFrame = 0
local botSpider, botPart, botLCF, botSFrac = {}, {}, {}, {}
local spAllocCache, spAllocCount = {}, 0

local function spiderSizeFor(count)
	local botArea = BOT_LEN * BOT_THICK * 1.15
	return math.max(SPIDER_MIN_SIZE * BOT_SCALE, math.sqrt(count * botArea / (SP_UNIT_AREA * SPIDER_COVERAGE)))
end

-- where each bot sits on a spider built from `count` bots, as a CFrame relative to its body part.
-- Precomputed once per count, so placing a bot each frame is a single CFrame multiply.
local function spAlloc(count)
	local cached = spAllocCache[count]
	if cached then
		return cached
	end
	if spAllocCount > 64 then
		table.clear(spAllocCache)
		spAllocCount = 0
	end
	local S = spiderSizeFor(count)
	local counts = allocate(SP_WEIGHTS, count)
	local list = { S = S, part = {}, cf = {} }
	local k = 0
	for i, d in SP_DEFS do
		local c = counts[i]
		for q = 1, c do
			k += 1
			list.part[k] = i
			local th = q * GOLDEN
			local ca, sa = math.cos(th), math.sin(th)
			if d.kind == "tube" then
				-- along the leg segment (local X), bots lying lengthwise like fibres
				local t = (q - 0.5) / c
				local r = (d.r0 + (d.r1 - d.r0) * t) * S
				list.cf[k] = CFrame.fromMatrix(Vector3.new(d.len * S * t, r * ca, -r * sa), Vector3.xAxis, Vector3.new(0, ca, -sa))
			else
				-- on the surface of an ellipsoid, facing outward
				local y = 1 - 2 * (q - 0.5) / c
				local rr = math.sqrt(math.max(0, 1 - y * y))
				local dir = Vector3.new(ca * rr, y, sa * rr)
				local R = d.radii * S
				local n = Vector3.new(dir.X / R.X, dir.Y / R.Y, dir.Z / R.Z).Unit
				local ref = Vector3.new(0, 0, -1)
				local x = ref - n * n:Dot(ref)
				if x.Magnitude < 0.15 then
					ref = Vector3.xAxis
					x = ref - n * n:Dot(ref)
				end
				list.cf[k] = CFrame.fromMatrix(Vector3.new(dir.X * R.X, dir.Y * R.Y, dir.Z * R.Z), x.Unit, n)
			end
		end
	end
	spAllocCache[count] = list
	spAllocCount += 1
	return list
end

local function newSpider()
	local sp = {
		S = 1, H = BODY_H, P = Vector3.zero, U = Vector3.yAxis, F = Vector3.new(0, 0, -1),
		vel = Vector3.zero, fall = Vector3.zero, airborne = false, cf = CFrame.identity,
		parts = {}, legs = {}, fresh = true, first = 1, count = 0, active = true,
		scanP = Vector3.zero, scanF = Vector3.zAxis, scanT = 0,
		prevP = Vector3.zero, prevU = Vector3.yAxis, prevF = Vector3.zAxis,
	}
	for i = 1, 8 do
		sp.legs[i] = {
			planted = Vector3.zero, foot = Vector3.zero, footVis = Vector3.zero, knee = Vector3.zero,
			hipW = Vector3.zero, target = Vector3.zero, from = Vector3.zero,
			hipLocal = Vector3.zero, restLocal = Vector3.zero,
			stepping = false, t = 0,
		}
	end
	for i, d in SP_DEFS do
		sp.parts[i] = { kind = d.kind, leg = d.leg, seg = d.seg, frame = CFrame.identity, off = CFrame.identity }
	end
	-- invisible joints the settled bots are welded to (one per body part / leg segment)
	sp.roots = {}
	for i = 1, #SP_DEFS do
		local r = Instance.new("Part")
		r.Name = "SpiderJoint"
		r.Size = Vector3.new(0.05, 0.05, 0.05)
		r.Transparency = 1
		r.Anchored = true
		r.CanCollide = false
		r.CanQuery = false
		r.CanTouch = false
		r.CastShadow = false
		r.Parent = folder
		sp.roots[i] = r
	end
	return sp
end

-- size everything on one spider for its current scale
local function spiderScale(sp)
	local S = sp.S
	sp.H = BODY_H * S
	for i, d in SP_DEFS do
		if d.off then
			sp.parts[i].off = CFrame.new(d.off.Position * S) * d.off.Rotation
		end
	end
	for i, def in LEG_DEFS do
		local leg = sp.legs[i]
		leg.hipLocal = def.hip * S
		leg.restLocal = Vector3.new(
			def.hip.X + def.side * math.cos(def.ang) * REACH,
			-BODY_H,
			def.hip.Z - math.sin(def.ang) * REACH
		) * S
	end
end

local function spiderLayout()
	local n = math.max(#bots, 1)
	local k = math.clamp(math.floor(n / SPIDER_BOTS_EACH), 1, MAX_SPIDERS)
	for i = #spiders + 1, k do
		spiders[i] = newSpider()
	end
	for i = #spiders, k + 1, -1 do
		for _, r in spiders[i].roots do
			r:Destroy()
		end
		spiders[i] = nil
	end
	local base, extra = math.floor(n / k), n % k
	local j = 0
	for i, sp in spiders do
		local c = base + (i <= extra and 1 or 0)
		sp.count, sp.first = c, j + 1
		local list = spAlloc(c)
		sp.S = list.S
		spiderScale(sp)
		sp.active = true
		for q = 1, c do
			j += 1
			botSpider[j] = i
			botPart[j] = list.part[q]
			botLCF[j] = list.cf[q]
			botSFrac[j] = c > 1 and (q - 1) / (c - 1) or 0
		end
	end
end

local function buildSpiderCF(sp)
	local U = sp.U
	local right = sp.F:Cross(U)
	if right.Magnitude < 1e-3 then
		right = U:Cross(Vector3.zAxis)
		if right.Magnitude < 1e-3 then
			right = U:Cross(Vector3.xAxis)
		end
	end
	right = right.Unit
	sp.F = U:Cross(right)
	sp.cf = CFrame.fromMatrix(sp.P, right, U)
end

-- find where a foot should go: toward its rest spot, or around an edge, or dangle
local function findFoot(sp, hipW, restW)
	local S, H, U = sp.S, sp.H, sp.U
	local r = math.max(0.04, 0.1 * S)
	local aimEnd = restW - U * (0.4 * S)
	local hit = sphere(hipW, r, (aimEnd - hipW) * 1.25)
	if hit then
		return hit.Position
	end
	hit = sphere(restW + U * H, r, -U * (H * 2.6))
	if hit then
		return hit.Position
	end
	local under = sp.P - U * H
	local o = restW - U * (H * 0.8)
	hit = sphere(o, r, (under - o) * 1.3)
	if hit then
		return hit.Position
	end
	return restW
end

-- two-bone IK: returns knee position and the (reachable) foot position
local function solveKnee(sp, hip, foot, a, b, pole)
	local d = foot - hip
	local dist = d.Magnitude
	local axis = dist > 1e-4 and d / dist or -sp.U
	dist = math.clamp(dist, math.abs(a - b) + 1e-3, a + b - 1e-3)
	local footVis = hip + axis * dist
	local x = (a * a - b * b + dist * dist) / (2 * dist)
	local h = math.sqrt(math.max(a * a - x * x, 0))
	local pp = pole - axis * pole:Dot(axis)
	if pp.Magnitude < 1e-3 then
		pp = sp.F - axis * sp.F:Dot(axis)
	end
	return hip + axis * x + pp.Unit * h, footVis
end

-- world frames of every body part (bots are placed relative to these)
local function spiderFrames(sp)
	local cf, U, F, legs = sp.cf, sp.U, sp.F, sp.legs
	for _, p in sp.parts do
		if p.kind == "ell" then
			p.frame = cf * p.off
		elseif p.kind == "knee" then
			p.frame = CFrame.new(legs[p.leg].knee) * cf.Rotation
		else
			local leg = legs[p.leg]
			local A, B
			if p.seg == 1 then
				A, B = leg.hipW, leg.knee
			else
				A, B = leg.knee, leg.footVis
			end
			local d = B - A
			local L = d.Magnitude
			local axis = L > 1e-4 and d / L or -U
			local u = axis:Cross(U)
			if u.Magnitude < 0.05 then
				u = axis:Cross(F)
			end
			p.frame = CFrame.fromMatrix(A, axis, u.Unit)
		end
	end
end

-- drop a spider where its own bots currently are, facing the cursor
local function spiderPlace(sp)
	local c, cnt = Vector3.zero, 0
	for j = sp.first, sp.first + sp.count - 1 do
		local b = bots[j]
		if b then
			c += b.cf.Position
			cnt += 1
		end
	end
	c /= math.max(cnt, 1)
	local g, n = groundBelow(c + Vector3.new(0, 2, 0))
	sp.U = n
	sp.P = g + n * sp.H
	local d = getMouseHit() - sp.P
	d -= sp.U * d:Dot(sp.U)
	if d.Magnitude < 0.1 then
		local look = camera.CFrame.LookVector
		d = look - sp.U * look:Dot(sp.U)
	end
	sp.F = d.Magnitude > 1e-3 and d.Unit or Vector3.new(0, 0, -1)
	sp.vel, sp.fall, sp.airborne = Vector3.zero, Vector3.zero, false
	buildSpiderCF(sp)
	for _, leg in sp.legs do
		leg.hipW = sp.cf * leg.hipLocal
		local p = findFoot(sp, leg.hipW, sp.cf * leg.restLocal)
		leg.planted, leg.foot, leg.target = p, p, p
		leg.stepping = false
		local outward = leg.hipW - sp.P
		outward -= sp.U * outward:Dot(sp.U)
		local pole = sp.U + (outward.Magnitude > 1e-3 and outward.Unit * 0.5 or Vector3.zero)
		leg.knee, leg.footVis = solveKnee(sp, leg.hipW, p, FEMUR * sp.S, TIBIA * sp.S, pole)
	end
	spiderFrames(sp)
	sp.scanP, sp.scanF, sp.scanT = sp.P, sp.F, now
	sp.active = true
	sp.fresh = false
end

local function spiderInit()
	for _, sp in spiders do
		spiderPlace(sp)
	end
end

-- move one spider toward its target point (tgt on a surface with normal tgtN)
local function spiderStep(sp, dt, tgt, tgtN, push, idx)
	local S, H = sp.S, sp.H
	local P, U, F = sp.P, sp.U, sp.F
	-- big enough to bridge ladder rungs, even for small spiders
	local probeR = math.max(0.4, 0.35 * S)
	local speed = SPIDER_SPEED + SPIDER_SPEED_PER_SIZE * S

	-- aim for where our body would sit on that surface (helps us go over edges toward it)
	local toT = (tgt + tgtN * (H * 1.5)) - P
	local planar = toT - U * toT:Dot(U)
	local dist = planar.Magnitude
	local full = toT.Magnitude

	-- let go and drop when walking can't get us closer:
	-- hanging from a ceiling above the target, or clinging to a wall/edge that faces it
	if not sp.airborne then
		local ceilingDrop = U.Y < -0.5 and tgtN.Y > 0.5 and tgt.Y < P.Y - H and dist < 1.5 * S + 1
		local stuckDrop = U.Y < 0.5 and dist < 0.3 * S and full > 3 * S and toT:Dot(U) > 0.7 * full
		if ceilingDrop or stuckDrop then
			sp.airborne = true
			sp.fall = Vector3.zero
		end
	end

	-- keep going while the target is still far away, even if it's "behind" our surface
	local stopR = 0.6 * S + 0.4
	local desiredVel = Vector3.zero
	if dist > 0.15 * S and (dist > stopR or full > stopR * 2.5) then
		desiredVel = planar * (math.min(speed, math.max(dist, full) * 3) / dist)
	end
	desiredVel += push - U * push:Dot(U) -- make room for the others
	if desiredVel.Magnitude > speed then
		desiredVel = desiredVel.Unit * speed
	end
	local vel = sp.vel:Lerp(desiredVel, 1 - math.exp(-6 * dt))
	vel -= U * vel:Dot(U)
	if vel.Magnitude < 0.01 * S then
		vel = Vector3.zero
	end
	local spd = vel.Magnitude
	local moveDir = spd > 0.05 * S and vel / spd or nil

	local upGoal = nil
	if not sp.airborne then
		local move = vel * dt
		-- wall / ladder / ceiling ahead: climb onto it (only surfaces that face us)
		if moveDir then
			local reach = H + 1.2 * S + spd * dt * 2
			local fw = sphere(P, probeR, moveDir * reach)
			local facing = fw and fw.Normal:Dot(U)
			if not (fw and facing < 0.6 and facing > -0.3) then
				-- also look up-and-ahead: catches ladder rungs and ledges above a small spider
				fw = sphere(P, probeR, (moveDir + U * 0.8).Unit * (reach * 1.2))
				facing = fw and fw.Normal:Dot(U)
				if fw and fw.Normal:Dot(moveDir) > -0.2 then
					fw = nil
				end
			end
			if fw and facing < 0.6 and facing > -0.3 then
				upGoal = fw.Normal
				sp.climbN, sp.climbT = fw.Normal, now
				local into = move:Dot(fw.Normal)
				if into < 0 and fw.Distance < H + spd * dt then
					move -= fw.Normal * into
				end
			end
		end
		P += move
		-- surface under the body (start the probe high enough that it never begins inside it)
		local downOff = math.max(0.5 * S, probeR - H + 0.05)
		local down = sphere(P + U * downOff, probeR, -U * (H * 2.5 + downOff))
		if down then
			-- keep turning onto a surface we just started climbing, even if the probe flickers
			upGoal = upGoal or (sp.climbT and now - sp.climbT < 0.12 and sp.climbN) or down.Normal
			local corr = (down.Position + down.Normal * H - P):Dot(down.Normal)
			if math.abs(corr) > 1e-3 * S then
				P += down.Normal * (corr * (1 - math.exp(-14 * dt)))
			end
		else
			-- walked past an edge: wrap around it (top of a wall, edge of a roof...)
			local back = moveDir or F
			local wrap = sphere(P - U * (H + probeR * 1.2), probeR, -back * (H * 2.5 + probeR * 2))
			if wrap then
				upGoal = wrap.Normal
				P = P:Lerp(wrap.Position + wrap.Normal * H, 1 - math.exp(-18 * dt))
			else
				sp.airborne = true
				sp.fall = vel
			end
		end
	end

	if sp.airborne then
		sp.fall += Vector3.new(0, -workspace.Gravity * 0.6 * dt, 0)
		local step = sp.fall * dt
		local land = sphere(P, probeR, step + step.Unit * H)
		if land then
			sp.airborne = false
			sp.fall, vel = Vector3.zero, Vector3.zero
			P = land.Position + land.Normal * H
			upGoal = land.Normal
		else
			P += step
			upGoal = Vector3.yAxis
		end
		if P.Y < workspace.FallenPartsDestroyHeight + 50 then
			local root = getRoot()
			P = (root and root.Position or Vector3.zero) + Vector3.new(0, 6, 0)
			sp.fall = Vector3.zero
		end
	end

	if upGoal and upGoal:Dot(U) < 0.99999 then
		if upGoal:Dot(U) < -0.95 then
			upGoal = (upGoal + F * 0.5).Unit
		end
		-- small, fast spiders must turn onto a new surface quickly or they run into it
		local upRate = 8 + 2.5 * speed / S
		U = U:Lerp(upGoal, 1 - math.exp(-upRate * dt)).Unit
	end

	-- face the way we walk (or toward the target when standing)
	local faceGoal = moveDir or (dist > 0.1 and planar / dist) or F
	faceGoal -= U * faceGoal:Dot(U)
	if faceGoal.Magnitude > 1e-3 and faceGoal.Unit:Dot(F) < 0.99999 then
		F = F:Lerp(faceGoal.Unit, 1 - math.exp(-SPIDER_TURN * dt))
	end
	F -= U * F:Dot(U)
	if F.Magnitude < 1e-3 then
		F = U:Cross(Vector3.xAxis)
	end
	sp.P, sp.U, sp.F, sp.vel = P, U, F.Unit, vel
	buildSpiderCF(sp)
	local cf = sp.cf
	U, F = sp.U, sp.F

	-- legs: each one steps on its own when its foot lags too far behind
	local legs = sp.legs
	local moving = spd > 0.2 * S
	local stepTime = 0.06 + 0.04 * S
	-- only re-aim the feet when the body moved or turned; in a big army, half the spiders
	-- re-aim on even frames and half on odd frames
	local stagger = #spiders < 6 or (spiderFrame + idx) % 2 == 0
	local rescan = sp.airborne or (stagger and ((P - sp.scanP).Magnitude > 0.03 * S or F:Dot(sp.scanF) < 0.9995 or now - sp.scanT > 0.5))
	if rescan then
		sp.scanP, sp.scanF, sp.scanT = P, F, now
	end
	local inAir = 0
	for _, leg in legs do
		leg.hipW = cf * leg.hipLocal
		if sp.airborne then
			local restW = cf * leg.restLocal
			leg.target = restW
			leg.planted = leg.planted:Lerp(restW, 1 - math.exp(-10 * dt))
			leg.stepping = false
		elseif rescan then
			leg.target = findFoot(sp, leg.hipW, cf * leg.restLocal)
		end
		if leg.stepping then
			inAir += 1
		end
	end
	if not sp.airborne then
		local maxLen = (FEMUR + TIBIA) * S
		local thresh = (moving and STEP_DIST or IDLE_STEP_DIST) * S
		local startIdx = math.floor(now * 7) % 8
		for n = 0, 7 do
			local i = (startIdx + n) % 8 + 1
			local leg = legs[i]
			if not leg.stepping then
				local err = (leg.planted - leg.target).Magnitude
				local over = (leg.planted - leg.hipW).Magnitude > maxLen * 0.97
				if over or (err > thresh and inAir < 4) then
					local blocked = false
					if not over then
						for _, nb in LEG_NEIGHBORS[i] do
							if legs[nb].stepping then
								blocked = true
								break
							end
						end
					end
					if not blocked then
						leg.stepping = true
						leg.t = 0
						leg.from = leg.foot
						inAir += 1
					end
				end
			end
		end
	end

	-- is anything on this spider moving this frame? If not, its bots can rest.
	local active = sp.airborne or inAir > 0
		or (P - sp.prevP).Magnitude > 1e-4 * S or U:Dot(sp.prevU) < 0.999999 or F:Dot(sp.prevF) < 0.999999
	sp.prevP, sp.prevU, sp.prevF = P, U, F
	sp.active = active
	if not active then
		return
	end

	for _, leg in legs do
		if leg.stepping then
			leg.t += dt / stepTime
			local to = leg.target + vel * (stepTime * 0.8)
			if leg.t >= 1 then
				leg.stepping = false
				leg.planted = to
				leg.foot = to
			else
				local s = leg.t
				leg.foot = leg.from:Lerp(to, s * s * (3 - 2 * s)) + U * (math.sin(math.pi * s) * 0.7 * S)
			end
		else
			leg.foot = leg.planted
		end
		local outward = leg.hipW - P
		outward -= U * outward:Dot(U)
		local pole = U + (outward.Magnitude > 1e-3 and outward.Unit * 0.5 or Vector3.zero)
		leg.knee, leg.footVis = solveKnee(sp, leg.hipW, leg.foot, FEMUR * S, TIBIA * S, pole)
	end
	spiderFrames(sp)
end

local function spiderUpdate(dt)
	spiderFrame += 1
	local tgt = getMouseHit()
	local n = lastMouseNormal
	-- spread the army out over the surface under the cursor (floor, wall or ceiling)
	local t1 = n:Cross(math.abs(n.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis).Unit
	local t2 = n:Cross(t1).Unit
	for _, sp in spiders do
		if sp.fresh then
			spiderPlace(sp)
		end
	end
	for i, sp in spiders do
		local ringR = (4.2 * sp.S + 1) * math.sqrt(i - 1)
		local ang = (i - 1) * GOLDEN
		local slot = tgt + (t1 * math.cos(ang) + t2 * math.sin(ang)) * ringR
		-- keep some room between spiders
		local push = Vector3.zero
		local P = sp.P
		for q, o in spiders do
			if q ~= i then
				local off = P - o.P
				local minD = 1.7 * (sp.S + o.S)
				if math.abs(off.X) < minD and math.abs(off.Z) < minD and math.abs(off.Y) < minD then
					local dd = off.Magnitude
					if dd < minD then
						local dir = dd > 1e-3 and off / dd or Vector3.new(math.cos(i), 0, math.sin(i))
						push += dir * ((minD - dd) * 4)
					end
				end
			end
		end
		spiderStep(sp, dt, slot, n, push, i)
	end
end

local function spiderTarget(j)
	return spiders[botSpider[j]].parts[botPart[j]].frame * botLCF[j]
end

local function spiderClear()
	detachAll()
	for i = #spiders, 1, -1 do
		for _, r in spiders[i].roots do
			r:Destroy()
		end
		spiders[i] = nil
	end
end

-- move the joints of every spider that moved this frame (their welded bots come along)
local jointParts, jointCFs = {}, {}
local function spiderMoveJoints()
	table.clear(jointParts)
	table.clear(jointCFs)
	local n = 0
	for _, sp in spiders do
		if sp.active then
			local roots = sp.roots
			for i, p in sp.parts do
				n += 1
				jointParts[n] = roots[i]
				jointCFs[n] = p.frame
			end
		end
	end
	if n > 0 then
		workspace:BulkMoveTo(jointParts, jointCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------- MEGABOT
-- A big microbot made of microbots: head / chest / pelvis spheres and six hexagonal spike
-- limbs on shoulder balls, with a red face. Body space: X = right, Y = up, -Z = forward,
-- origin on the ground between the feet. Sizes are x megabot size.
local MB_HEAD_C, MB_CHEST_C, MB_PELVIS_C = Vector3.new(0, 3.6, 0), Vector3.new(0, 2.75, 0), Vector3.new(0, 1.92, 0)
local MB_HEAD_R, MB_CHEST_R, MB_PELVIS_R = 0.5, 0.55, 0.48
local MB_BALL_R, MB_SPIKE_LEN, MB_SPIKE_R0, MB_SPIKE_R1 = 0.3, 1.75, 0.32, 0.09
local MB_FACE_Z = 0.62 -- front of the head left open for the face
local MB_LIMBS = {
	{ ball = Vector3.new(-0.5, 3.45, 0), dir = Vector3.new(-0.6, 0.8, 0), kind = "top" },
	{ ball = Vector3.new(0.5, 3.45, 0), dir = Vector3.new(0.6, 0.8, 0), kind = "top" },
	{ ball = Vector3.new(-0.64, 2.78, 0), dir = Vector3.new(-1, 0.12, 0), kind = "arm" },
	{ ball = Vector3.new(0.64, 2.78, 0), dir = Vector3.new(1, 0.12, 0), kind = "arm" },
	{ ball = Vector3.new(-0.42, 1.75, 0), dir = Vector3.new(-0.38, -0.925, 0), kind = "leg" },
	{ ball = Vector3.new(0.42, 1.75, 0), dir = Vector3.new(0.38, -0.925, 0), kind = "leg" },
}
for _, limb in MB_LIMBS do
	limb.dir = limb.dir.Unit
end

-- parts: 1 head, 2 chest, 3 pelvis, 4-9 shoulder balls, 10-15 spikes
local MB_PARTS = {
	{ kind = "sph", r = MB_HEAD_R, cap = true },
	{ kind = "sph", r = MB_CHEST_R },
	{ kind = "sph", r = MB_PELVIS_R },
}
for i = 1, 6 do
	table.insert(MB_PARTS, { kind = "ball", r = MB_BALL_R, limb = i })
end
for i = 1, 6 do
	table.insert(MB_PARTS, { kind = "spike", limb = i })
end
local MB_WEIGHTS, MB_UNIT_AREA = {}, 0
for i, p in MB_PARTS do
	local a
	if p.kind == "spike" then
		a = 6.93 * (MB_SPIKE_R0 + MB_SPIKE_R1) * 0.5 * MB_SPIKE_LEN
	elseif p.kind == "ball" then
		a = 4 * math.pi * p.r * p.r * 0.5 -- half of it is buried in the body
	else
		a = 4 * math.pi * p.r * p.r * (p.cap and 0.81 or 1)
	end
	MB_WEIGHTS[i] = a
	MB_UNIT_AREA += a
end

local megas = {}
local botMega, botMPart, botMV, botMT, botMTh, botMFrac = {}, {}, {}, {}, {}, {}
local mbAllocCache, mbAllocCount = {}, 0
local SEC = math.pi / 3

local function megaAlloc(count)
	local cached = mbAllocCache[count]
	if cached then
		return cached
	end
	if mbAllocCount > 64 then
		table.clear(mbAllocCache)
		mbAllocCount = 0
	end
	local counts = allocate(MB_WEIGHTS, count)
	local list = { part = {}, a = {}, t = {}, th = {} }
	local k = 0
	for i, p in MB_PARTS do
		local c = counts[i]
		for q = 1, c do
			k += 1
			list.part[k] = i
			local th = q * GOLDEN
			if p.kind == "spike" then
				list.t[k] = (q - 0.5) / c
				list.th[k] = th % (2 * math.pi)
			elseif p.cap then
				local z = -MB_FACE_Z + (1 + MB_FACE_Z) * (q - 0.5) / c
				local r = math.sqrt(math.max(0, 1 - z * z))
				list.a[k] = Vector3.new(math.cos(th) * r, math.sin(th) * r, z)
			else
				local y = 1 - 2 * (q - 0.5) / c
				local r = math.sqrt(math.max(0, 1 - y * y))
				list.a[k] = Vector3.new(math.cos(th) * r, y, math.sin(th) * r)
			end
		end
	end
	mbAllocCache[count] = list
	mbAllocCount += 1
	return list
end

-- red face plate with an angry face drawn on it
local function buildFacePlate()
	local p = Instance.new("Part")
	p.Name = "MegabotFace"
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(200, 28, 32)
	p.Transparency = 1
	p.Size = Vector3.new(0.05, 0.84, 0.84)

	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Right
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = Vector2.new(200, 200)
	sg.LightInfluence = 0.4
	sg.Enabled = false
	sg.Parent = p

	local function fr(size, pos, color, rot, z, corner)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(size.X, size.Y)
		f.Position = UDim2.fromOffset(pos.X, pos.Y)
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Rotation = rot or 0
		f.ZIndex = z or 1
		if corner then
			local c = Instance.new("UICorner")
			c.CornerRadius = corner
			c.Parent = f
		end
		f.Parent = sg
		return f
	end
	local WHITE, BLACK = Color3.new(1, 1, 1), Color3.fromRGB(10, 10, 12)
	for _, sx in { -1, 1 } do
		local ex = 100 + sx * 42
		fr(Vector2.new(50, 42), Vector2.new(ex, 80), WHITE, 0, 1, UDim.new(1, 0)) -- eye
		fr(Vector2.new(18, 18), Vector2.new(ex - sx * 7, 86), BLACK, 0, 2, UDim.new(1, 0)) -- pupil
		fr(Vector2.new(66, 14), Vector2.new(ex + sx * 2, 58), BLACK, sx == -1 and 22 or -22, 3) -- angry brow
	end
	-- jagged grin: white mouth split by a black zig-zag
	local mouth = fr(Vector2.new(118, 44), Vector2.new(100, 140), WHITE, 0, 1, UDim.new(0, 14))
	local st = Instance.new("UIStroke")
	st.Color = BLACK
	st.Thickness = 4
	st.Parent = mouth
	local pts = {}
	for i = 0, 7 do
		pts[i + 1] = Vector2.new(46 + i * 108 / 7, (i % 2 == 0) and 123 or 157)
	end
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local d = b - a
		fr(Vector2.new(d.Magnitude + 3, 4), (a + b) / 2, BLACK, math.deg(math.atan2(d.Y, d.X)), 2)
	end
	return p, sg
end

local function megaClear()
	for i = #megas, 1, -1 do
		megas[i].plate:Destroy()
		megas[i] = nil
	end
end

local function megaLayout()
	local n = math.max(#bots, 1)
	local k = math.clamp(math.floor(n / MEGA_BOTS_EACH), 1, MAX_MEGABOTS)
	for i = #megas + 1, k do
		local plate, sg = buildFacePlate()
		plate.Parent = folder
		megas[i] = {
			pos = Vector3.zero, vel = Vector3.zero, yaw = 0, phase = math.random() * 6.28, moveF = 0,
			s = 1, count = 0, first = 1, plate = plate, gui = sg, born = now, fresh = true,
			rot = CFrame.identity, cen = {}, rad = {}, spA = {}, spAx = {}, spU = {}, spV = {}, spLen = {},
		}
	end
	for i = #megas, k + 1, -1 do
		megas[i].plate:Destroy()
		megas[i] = nil
	end

	local base, extra = math.floor(n / k), n % k
	local botArea = BOT_LEN * BOT_THICK * 1.15
	local j = 0
	for i, m in megas do
		local c = base + (i <= extra and 1 or 0)
		m.count = c
		m.first = j + 1
		m.s = math.max(MEGA_MIN_SIZE * BOT_SCALE, math.sqrt(c * botArea / (MB_UNIT_AREA * MEGA_COVERAGE)))
		m.plate.Size = Vector3.new(0.05, 0.84, 0.84) * m.s
		local list = megaAlloc(c)
		for q = 1, c do
			j += 1
			botMega[j] = i
			botMPart[j] = list.part[q]
			botMV[j] = list.a[q]
			botMT[j] = list.t[q]
			botMTh[j] = list.th[q]
			botMFrac[j] = c > 1 and (q - 1) / (c - 1) or 0
		end
	end
end

-- put a megabot where its own bots currently are, facing the cursor
local function megaPlace(m)
	local c, cnt = Vector3.zero, 0
	for j = m.first, m.first + m.count - 1 do
		local b = bots[j]
		if b then
			c += b.cf.Position
			cnt += 1
		end
	end
	c /= math.max(cnt, 1)
	m.pos = groundBelow(c + Vector3.new(0, 2, 0))
	m.vel = Vector3.zero
	local d = getMouseHit() - m.pos
	m.yaw = (math.abs(d.X) + math.abs(d.Z) > 1e-3) and math.atan2(-d.X, -d.Z) or 0
	m.born = now
	m.fresh = false
end

local function megaInit()
	for _, m in megas do
		megaPlace(m)
	end
end

local function megaUpdate(dt)
	local tgt = getMouseHit()
	for _, m in megas do
		if m.fresh then
			megaPlace(m)
		end
	end
	for i, m in megas do
		local s = m.s
		-- each megabot has its own spot in a sunflower-shaped crowd around the cursor
		local ringR = (3.6 * s + 1) * math.sqrt(i - 1)
		local ang = (i - 1) * GOLDEN
		local to = Vector3.new(tgt.X + math.cos(ang) * ringR - m.pos.X, 0, tgt.Z + math.sin(ang) * ringR - m.pos.Z)
		local d = to.Magnitude
		local speed = MEGA_SPEED + 3 * s
		local desired = d > 0.25 * s and to * (math.min(speed, d * 2.5) / d) or Vector3.zero
		-- don't walk through each other
		for q, o in megas do
			if q ~= i then
				local off = Vector3.new(m.pos.X - o.pos.X, 0, m.pos.Z - o.pos.Z)
				local dd = off.Magnitude
				local minD = 1.6 * (s + o.s)
				if dd < minD then
					local push = dd > 1e-3 and off / dd or Vector3.new(math.cos(i), 0, math.sin(i))
					desired += push * ((minD - dd) * 5)
				end
			end
		end
		m.vel = m.vel:Lerp(desired, 1 - math.exp(-5 * dt))
		local p = m.pos + m.vel * dt
		local hit = workspace:Raycast(p + Vector3.new(0, 2.5 * s + 1, 0), Vector3.new(0, -80, 0), rayParams)
		local gy = hit and hit.Position.Y or p.Y
		m.pos = Vector3.new(p.X, p.Y + (gy - p.Y) * (1 - math.exp(-14 * dt)), p.Z)

		-- face where we walk, or the cursor when standing
		local spd = m.vel.Magnitude
		local look = spd > 0.6 and m.vel or (tgt - m.pos)
		if look.X * look.X + look.Z * look.Z > 1e-4 then
			local goal = math.atan2(-look.X, -look.Z)
			local diff = (goal - m.yaw + math.pi) % (2 * math.pi) - math.pi
			m.yaw += diff * (1 - math.exp(-8 * dt))
		end
		local moveGoal = math.clamp(spd / (speed * 0.5), 0, 1)
		m.moveF += (moveGoal - m.moveF) * (1 - math.exp(-6 * dt))
		m.phase += dt * (1.5 + 7 * m.moveF)

		-- body pose: bob + lean while walking
		local mf = m.moveF
		local bob = s * (0.1 * math.abs(math.sin(m.phase)) * mf + 0.04 * math.sin(now * 2 + i))
		local body = CFrame.new(m.pos) * CFrame.Angles(0, m.yaw, 0) * CFrame.new(0, bob, 0) * CFrame.Angles(-0.12 * mf, 0, 0)
		m.rot = body.Rotation
		m.cen[1] = body * (MB_HEAD_C * s)
		m.cen[2] = body * (MB_CHEST_C * s)
		m.cen[3] = body * (MB_PELVIS_C * s)
		m.rad[1], m.rad[2], m.rad[3] = MB_HEAD_R * s, MB_CHEST_R * s, MB_PELVIS_R * s

		-- limbs: bottom spikes step like legs, middle ones swing like arms, top ones sway
		local sw = math.sin(m.phase)
		for L, limb in MB_LIMBS do
			local side = limb.ball.X < 0 and -1 or 1
			local rot
			if limb.kind == "leg" then
				rot = CFrame.Angles(0.5 * sw * mf * side + 0.05 * math.sin(now * 2 + L), 0, 0)
			elseif limb.kind == "arm" then
				rot = CFrame.Angles(0, -0.45 * sw * mf * side + 0.08 * math.sin(now * 1.7 + L), 0)
			else
				rot = CFrame.Angles(0.15 * math.sin(now * 2.3 + L) + 0.2 * sw * mf * side, 0, 0)
			end
			local shoulder = body * (limb.ball * s)
			m.cen[3 + L] = shoulder
			m.rad[3 + L] = MB_BALL_R * s
			local dirW = body:VectorToWorldSpace(rot:VectorToWorldSpace(limb.dir))
			local u = dirW:Cross(body.LookVector)
			if u.Magnitude < 0.1 then
				u = dirW:Cross(body.RightVector)
			end
			u = u.Unit
			m.spA[L] = shoulder + dirW * (0.12 * s)
			m.spAx[L] = dirW
			m.spU[L] = u
			m.spV[L] = u:Cross(dirW)
			m.spLen[L] = MB_SPIKE_LEN * s
		end

		-- face plate fades in once the head has formed
		local fwd, up = m.rot.LookVector, m.rot.UpVector
		m.plate.CFrame = CFrame.fromMatrix(m.cen[1] + fwd * (MB_HEAD_R * 0.9 * s), fwd, up)
		local vis = math.clamp((now - m.born - 0.7) / 0.35, 0, 1)
		m.plate.Transparency = 1 - vis
		m.gui.Enabled = vis > 0.6
	end
end

local function spikeProfile(t)
	if t < 0.14 then
		return MB_SPIKE_R0
	end
	return MB_SPIKE_R0 * 0.92 + (MB_SPIKE_R1 - MB_SPIKE_R0 * 0.92) * ((t - 0.14) / 0.86)
end

local function megaTarget(j, b)
	local m = megas[botMega[j]]
	local pi = botMPart[j]
	if pi <= 9 then
		-- sphere / shoulder ball
		local n = m.rot:VectorToWorldSpace(botMV[j])
		local pos = m.cen[pi] + n * (m.rad[pi] * (1 + 0.03 * math.sin(now * 5 + b.phase)))
		local ref = m.rot.LookVector
		local x = ref - n * n:Dot(ref)
		if x.Magnitude < 0.15 then
			ref = m.rot.RightVector
			x = ref - n * n:Dot(ref)
		end
		b.radial = n
		return CFrame.fromMatrix(pos, x.Unit, n)
	end
	-- hexagonal spike: bots lie flat on the six facets
	local L = pi - 9
	local t, th = botMT[j], botMTh[j]
	local sector = math.floor(th / SEC)
	local within = th - sector * SEC - SEC * 0.5
	local facet = sector * SEC + SEC * 0.5
	local u, v, axis = m.spU[L], m.spV[L], m.spAx[L]
	local radial = u * math.cos(th) + v * math.sin(th)
	local fn = u * math.cos(facet) + v * math.sin(facet)
	b.radial = fn
	return CFrame.fromMatrix(m.spA[L] + axis * (m.spLen[L] * t) + radial * (spikeProfile(t) * m.s / math.cos(within)), axis, fn)
end

---------------------------------------------------------------- FORM DISPATCH
local function formLayout()
	if form == "snake" then
		snakeLayout()
	elseif form == "spider" then
		spiderLayout()
	else
		megaLayout()
	end
end

local function formInit()
	if form == "snake" then
		snakeInit()
	elseif form == "spider" then
		spiderInit()
	else
		megaInit()
	end
end

---------------------------------------------------------------- BOTS
local function newBot(cf)
	local parts = table.create(nParts)
	for k, tp in templateParts do
		local p = tp.part:Clone()
		p.CFrame = cf * tp.offset
		p.Parent = folder
		parts[k] = p
	end
	return {
		cf = cf,
		parts = parts,
		state = "ground", -- "ground" | "air" | "linked"
		resting = true,
		groundCF = cf,
		nextWander = now + 2 + math.random() * 5,
		delay = 0,
		locked = false,
		speedMul = 0.75 + math.random() * 0.6,
		maxSpeed = 45 + math.random() * 45,
		phase = math.random() * math.pi * 2,
		radial = Vector3.zero,
	}
end

-- throw a bot in an arc to a landing spot
local function launch(b, toCF, height, dur)
	b.state = "air"
	b.fromPos = b.cf.Position
	b.fromRot = b.cf.Rotation
	b.toCF = toCF
	b.groundCF = toCF
	b.t0 = now
	b.dur = dur
	b.height = height
	b.spinX = (math.random() - 0.5) * 24
	b.spinY = (math.random() - 0.5) * 24
	b.locked = false
	b.resting = false
end

---------------------------------------------------------------- COUNT
local function syncCount()
	local n = #bots
	if n == targetCount then
		return
	end
	if n < targetCount then
		local root = getRoot()
		local origin = root and root.Position or (lastMouseHit + Vector3.new(0, 3, 0))
		local rad = scatterRadius(targetCount)
		for i = n + 1, math.min(targetCount, n + SPAWN_PER_FRAME) do
			local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			local b = newBot(CFrame.new(origin + jitter) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, 0))
			bots[i] = b
			if mode == "linked" then
				b.state = "linked"
				b.resting = false
			else
				launch(b, groundSpot(origin, 1.5, rad), 2 + math.random() * 4, 0.5 + math.random() * 0.6)
			end
		end
	else
		for i = n, targetCount + 1, -1 do
			for _, p in bots[i].parts do
				p:Destroy()
			end
			bots[i] = nil
		end
	end
	if mode == "linked" then
		detachAll() -- bots may move to a different spider / spot
		formLayout()
		if form == "snake" then
			snakeResize()
		end
	end
end

---------------------------------------------------------------- MODES
local function assemble()
	if #bots == 0 then
		return
	end
	mode = "linked"
	formLayout()
	formInit()
	local n = #bots
	for j, b in bots do
		local frac = if form == "megabot" then botMFrac[j] elseif form == "spider" then botSFrac[j] else (j - 1) / math.max(n - 1, 1)
		b.delay = now + frac * 0.8 + math.random() * 0.15
		b.locked = false
	end
	updateModeUI()
end

local function scatter()
	mode = "scatter"
	spiderClear()
	megaClear()
	local extra = 3 + math.sqrt(#bots) * 0.25
	for _, b in bots do
		if b.state == "linked" then
			local pos = b.cf.Position
			local r = b.cf.UpVector -- bots always face outward from the body they were part of
			local out = Vector3.new(r.X, 0, r.Z)
			if out.Magnitude < 0.25 then
				local a = math.random() * math.pi * 2
				out = Vector3.new(math.cos(a), 0, math.sin(a))
			else
				out = out.Unit
			end
			local land = pos + out * (1.5 + math.random() * extra) + Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
			launch(b, lyingCF(groundBelow(Vector3.new(land.X, pos.Y + 0.5, land.Z))), 1 + math.random() * 3.5, 0.4 + math.random() * 0.5)
		end
	end
	updateModeUI()
end

local function toggle()
	if mode == "linked" then
		scatter()
	else
		assemble()
	end
end

local function setForm(f)
	if f == form then
		return
	end
	if form == "megabot" then
		megaClear()
	elseif form == "spider" then
		spiderClear()
	end
	form = f
	updateFormUI()
	if mode == "linked" and #bots > 0 then
		-- reshape: every linked bot flows to its new spot
		detachAll()
		formLayout()
		formInit()
	end
end

---------------------------------------------------------------- INPUT
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == TOGGLE_KEY then
		toggle()
	elseif input.KeyCode == FORM_KEY then
		setForm(if form == "snake" then "spider" elseif form == "spider" then "megabot" else "snake")
	end
end)

modeBtn.Activated:Connect(toggle)
snakeBtn.Activated:Connect(function()
	setForm("snake")
end)
spiderBtn.Activated:Connect(function()
	setForm("spider")
end)
megaBtn.Activated:Connect(function()
	setForm("megabot")
end)

local dragging = false
local function sliderFromX(x)
	local ax, aw = track.AbsolutePosition.X, track.AbsoluteSize.X
	if aw <= 0 then
		return
	end
	local p = math.clamp((x - ax) / aw, 0, 1)
	setTarget(MIN_BOTS + (MAX_BOTS - MIN_BOTS) * p * p)
end

sliderHit.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		sliderFromX(input.Position.X)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		sliderFromX(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

countBox.FocusLost:Connect(function()
	local n = tonumber((countBox.Text:gsub("%D", "")))
	if n then
		setTarget(n)
	end
	countBox.Text = tostring(targetCount)
end)

player.CharacterAdded:Connect(function()
	task.wait()
	refreshFilter()
end)

---------------------------------------------------------------- MAIN LOOP
do
	local char = player.Character or player.CharacterAdded:Wait()
	char:WaitForChild("HumanoidRootPart", 10)
	refreshFilter()
end

local movedParts, movedCFs = {}, {}
local moveCount = 0

local function push(b, cf)
	b.cf = cf
	local parts = b.parts
	if singlePart then
		moveCount += 1
		movedParts[moveCount] = parts[1]
		movedCFs[moveCount] = cf
	else
		for k = 1, nParts do
			moveCount += 1
			movedParts[moveCount] = parts[k]
			movedCFs[moveCount] = cf * offsets[k]
		end
	end
end

local filterTimer = 0

RunService.RenderStepped:Connect(function(dt)
	dt = math.min(dt, 0.05)
	now = os.clock()

	local root = getRoot()
	if root then
		lastGroundY = root.Position.Y - 3
	end
	filterTimer -= dt
	if filterTimer <= 0 then
		filterTimer = 2
		refreshFilter()
	end

	syncCount()

	local linked = mode == "linked" and #bots > 0
	if linked then
		if form == "snake" then
			if #nodes == 0 then
				snakeLayout()
				snakeInit()
			end
			snakeUpdate(dt)
		elseif form == "spider" then
			if #spiders == 0 then
				spiderLayout()
				spiderInit()
			end
			spiderUpdate(dt)
			spiderMoveJoints()
		else
			if #megas == 0 then
				megaLayout()
				megaInit()
			end
			megaUpdate(dt)
		end
	end

	table.clear(movedParts)
	table.clear(movedCFs)
	moveCount = 0

	local lockAlpha = 1 - math.exp(-35 * dt)
	local crawlAlpha = 1 - math.exp(-2.5 * dt)
	local shimmerT = now * 9
	local isSnake = form == "snake"
	local isSpider = form == "spider"

	for j = 1, #bots do
		local b = bots[j]
		if linked and b.state ~= "linked" and now >= b.delay then
			b.state = "linked"
			b.locked = false
			b.resting = false
		end

		local st = b.state
		if st == "linked" and isSpider then
			-- spider bots: fly to the spider, settle into place riding along with it, then weld on
			if b.welds then
				continue
			end
			local sp = spiders[botSpider[j]]
			local pi = botPart[j]
			local frame = sp.parts[pi].frame
			local goal = botLCF[j]
			local lcf = b.lcf
			if lcf then
				lcf = lcf:Lerp(goal, lockAlpha)
				if (lcf.Position - goal.Position).Magnitude < 0.01 * BOT_SCALE then
					attachBot(b, sp.roots[pi], frame * goal)
				else
					b.lcf = lcf
					push(b, frame * lcf)
				end
				continue
			end
			local target = frame * goal
			local cp = b.cf.Position
			local d = target.Position - cp
			if d.Magnitude < 1.5 then
				b.lcf = frame:ToObjectSpace(b.cf)
				continue
			end
			local alpha = 1 - math.exp(-9 * b.speedMul * dt)
			local step = d * alpha
			local maxStep = b.maxSpeed * dt
			local sm = step.Magnitude
			if sm > maxStep then
				step = step * (maxStep / sm)
			end
			push(b, CFrame.new(cp + step) * b.cf.Rotation:Lerp(target.Rotation, alpha))

		elseif st == "linked" then
			local target = if isSnake then snakeTarget(j, b, shimmerT) else megaTarget(j, b)
			if b.locked then
				push(b, b.cf:Lerp(target, lockAlpha))
			else
				local cp = b.cf.Position
				local d = target.Position - cp
				local alpha = 1 - math.exp(-9 * b.speedMul * dt)
				local step = d * alpha
				local maxStep = b.maxSpeed * dt
				local sm = step.Magnitude
				if sm > maxStep then
					step = step * (maxStep / sm)
				end
				if d.Magnitude < 0.5 * BOT_SCALE then
					b.locked = true
				end
				push(b, CFrame.new(cp + step) * b.cf.Rotation:Lerp(target.Rotation, alpha))
			end

		elseif st == "air" then
			local s = (now - b.t0) / b.dur
			if s >= 1 then
				b.state = "ground"
				b.resting = true
				b.nextWander = now + 1 + math.random() * 5
				push(b, b.toCF)
			else
				local pos = b.fromPos:Lerp(b.toCF.Position, s) + Vector3.new(0, b.height * 4 * s * (1 - s), 0)
				local tt = now - b.t0
				local spin = b.fromRot * CFrame.Angles(b.spinX * tt, b.spinY * tt, 0)
				push(b, CFrame.new(pos) * spin:Lerp(b.toCF.Rotation, s * s))
			end

		else -- ground: sit still, occasionally crawl to a nearby spot
			if now >= b.nextWander then
				b.nextWander = now + 2 + math.random() * 6
				b.groundCF = groundSpot(b.groundCF.Position, 0.3, 1.4)
				b.resting = false
			end
			if not b.resting then
				local g = b.groundCF
				local cf = b.cf:Lerp(g, crawlAlpha)
				if (cf.Position - g.Position).Magnitude < 0.005 then
					cf = g
					b.resting = true
				end
				push(b, cf)
			end
		end
	end

	if moveCount > 0 then
		workspace:BulkMoveTo(movedParts, movedCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
