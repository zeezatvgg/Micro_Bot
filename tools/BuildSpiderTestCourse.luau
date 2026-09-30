--[[
	Builds a small obstacle course (Workspace.SpiderTestCourse) for trying out the spider form:
	a climbing wall, an overhang whose underside is a ceiling, a ladder and a staircase.

	How to use: paste this whole file into Roblox Studio's Command Bar and press Enter.
	Run it again to rebuild it; delete Workspace.SpiderTestCourse to remove it.
]]

local old = workspace:FindFirstChild("SpiderTestCourse")
if old then
	old:Destroy()
end

local course = Instance.new("Model")
course.Name = "SpiderTestCourse"

local function block(name, size, cf, color, mat)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.Concrete
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = course
	return p
end

local WALL = Color3.fromRGB(125, 125, 130)
local DARK = Color3.fromRGB(95, 95, 100)
local METAL = Color3.fromRGB(70, 72, 78)
local STEP = Color3.fromRGB(150, 150, 155)

-- Wall: x -14..14, 18 tall, front face at z = -58
block("ClimbWall", Vector3.new(28, 18, 4), CFrame.new(0, 9, -60), WALL)

-- Overhang roof over the left half: its underside is a ceiling at y = 18
block("Overhang", Vector3.new(14, 1.5, 18), CFrame.new(-7, 18.75, -53), DARK)

-- Ladder leaning on the right half of the wall
local ladder = Instance.new("Model")
ladder.Name = "Ladder"
ladder.Parent = course
local bottom = Vector3.new(6, 0, -51)
local top = Vector3.new(6, 18, -58)
local dir = top - bottom
local len = dir.Magnitude
local unit = dir.Unit
local mid = (top + bottom) / 2
local frame = CFrame.lookAt(mid, top)
for _, x in { -2.8, 2.8 } do
	local r = block("Rail", Vector3.new(0.4, 0.4, len + 0.6), frame * CFrame.new(x, 0, 0), METAL, Enum.Material.Metal)
	r.Parent = ladder
end
local s = 0.6
while s < len - 0.2 do
	local c = CFrame.lookAt(bottom + unit * s, bottom + unit * s + unit)
	local rung = block("Rung", Vector3.new(5.6, 0.3, 0.3), c, METAL, Enum.Material.Metal)
	rung.Parent = ladder
	s += 1.0
end

-- Stairs up to a landing next to the right end of the wall
local stairs = Instance.new("Model")
stairs.Name = "Stairs"
stairs.Parent = course
local stepH, stepD, steps = 1.2, 1.6, 15
for i = 1, steps do
	local h = stepH * i
	local z = -34 - stepD * (i - 0.5)
	local st = block("Step", Vector3.new(8, h, stepD), CFrame.new(19, h / 2, z), STEP)
	st.Parent = stairs
end
local landing = block("Landing", Vector3.new(8, 18, 4), CFrame.new(19, 9, -60), STEP)
landing.Parent = stairs

course.Parent = workspace
print("SpiderTestCourse built")
