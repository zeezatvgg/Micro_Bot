--[[
	Builds the microbot model used by MicrobotController and saves it as ReplicatedStorage.Microbot.

	How to use: open your place in Roblox Studio, paste this whole file into the Command Bar
	(View -> Command Bar) and press Enter. Run it again any time to rebuild the model.

	The bot is a tiny glossy black core sphere with two hexagonal arms. It is built at 10x size
	so the solid-modeling union comes out clean, then scaled down (~0.52 studs long).
	The controller script scales it again with BOT_SCALE.
]]

local GeometryService = game:GetService("GeometryService")
local RS = game:GetService("ReplicatedStorage")

local old = RS:FindFirstChild("Microbot")
if old then
	old:Destroy()
end

local S = 10
local tmp = Instance.new("Folder")
tmp.Name = "_MicrobotBuild"
tmp.Parent = workspace

local function mk(shape, size, cf, color)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.Parent = tmp
	return p
end

local base = CFrame.new(0, 200, 0)
local core = mk(Enum.PartType.Ball, Vector3.new(1.8, 1.8, 1.8), base, Color3.fromRGB(8, 8, 10))

local others = {}
local function hexPrism(flat, x0, x1, color)
	-- regular hexagon (flat-to-flat = flat) as a union of 3 rotated rectangles, on both sides
	local side = flat / math.sqrt(3)
	local len = x1 - x0
	local cx = (x0 + x1) / 2
	for sign = -1, 1, 2 do
		for k = 0, 2 do
			local cf = base * CFrame.new(sign * cx, 0, 0) * CFrame.Angles(math.rad(60 * k), 0, 0)
			table.insert(others, mk(Enum.PartType.Block, Vector3.new(len, side, flat), cf, color))
		end
	end
end
hexPrism(1.0, 0.55, 2.2, Color3.fromRGB(26, 26, 30)) -- main arm
hexPrism(0.62, 2.2, 2.6, Color3.fromRGB(16, 16, 18)) -- narrower tip

local ok, res = pcall(function()
	return GeometryService:UnionAsync(core, others, {
		CollisionFidelity = Enum.CollisionFidelity.Box,
		RenderFidelity = Enum.RenderFidelity.Automatic,
		SplitApart = false,
	})
end)

local result
if ok and res and res[1] then
	local u = res[1]
	u.UsePartColor = false
	u.Size = u.Size / S
	u.CFrame = CFrame.new()
	result = u
	tmp:Destroy()
else
	warn("Union failed, using a multi-part model instead: " .. tostring(res))
end

if not result then
	-- fallback: a model of plain parts at final size
	for _, c in tmp:GetChildren() do
		c:Destroy()
	end
	local m = Instance.new("Model")
	local c = mk(Enum.PartType.Ball, Vector3.new(0.18, 0.18, 0.18), CFrame.new(), Color3.fromRGB(8, 8, 10))
	c.Name = "Core"
	c.Parent = m
	for sign = -1, 1, 2 do
		local a = mk(Enum.PartType.Cylinder, Vector3.new(0.2, 0.1, 0.1), CFrame.new(sign * 0.155, 0, 0), Color3.fromRGB(26, 26, 30))
		a.Name = "Arm"
		a.Parent = m
	end
	m.PrimaryPart = c
	tmp:Destroy()
	result = m
end

local function setup(p)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0
end
if result:IsA("BasePart") then
	setup(result)
else
	for _, d in result:GetDescendants() do
		if d:IsA("BasePart") then
			setup(d)
		end
	end
end

result.Name = "Microbot"
result.Parent = RS
print("Microbot model saved to ReplicatedStorage.Microbot")
