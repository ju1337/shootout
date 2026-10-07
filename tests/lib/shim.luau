-- Nachbildung der Roblox-Datentypen für Tests außerhalb von Roblox (Vector3, CFrame, Color3, Enum, UDim2, ...)
-- Semantik wie in Roblox: CFrame.Angles = Rx * Ry * Rz, fromMatrix = Spalten, LookVector = -Z-Spalte.

local Vector3 = {}
local V3mt = {}

local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __isV3 = true }, V3mt)
end

V3mt.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3mt.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3mt.__div = function(a, b)
	if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3mt.__tostring = function(a) return string.format("(%.4f, %.4f, %.4f)", a.X, a.Y, a.Z) end
V3mt.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then return v3(0 / 0, 0 / 0, 0 / 0) end
		return v3(self.X / m, self.Y / m, self.Z / m)
	end
	return Vector3[key]
end
function Vector3.new(x, y, z) return v3(x, y, z) end
function Vector3.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function Vector3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vector3.Lerp(a, b, t) return a + (b - a) * t end
function Vector3.FuzzyEq(a, b, eps) return (a - b).Magnitude <= (eps or 1e-5) end
function Vector3.Abs(a) return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z)) end
function Vector3.Min(a, b) return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)) end
function Vector3.Max(a, b) return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)) end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

-- CFrame: Position p + Rotationsmatrix r (Zeilen r[1..9]: r00 r01 r02 r10 ...)
local CFrame = {}
local CFmt = {}

local function cf(px, py, pz, m)
	return setmetatable({ px = px, py = py, pz = pz, m = m, __isCF = true }, CFmt)
end
local IDENT = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function mulMat(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function mulVec(m, x, y, z)
	return m[1] * x + m[2] * y + m[3] * z, m[4] * x + m[5] * y + m[6] * z, m[7] * x + m[8] * y + m[9] * z
end
local function transpose(m)
	return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
end

function CFrame.new(a, b, c, ...)
	if a == nil then
		return cf(0, 0, 0, IDENT)
	end
	if type(a) == "table" and a.__isV3 then
		if b ~= nil and type(b) == "table" and b.__isV3 then
			return CFrame.lookAt(a, b)
		end
		return cf(a.X, a.Y, a.Z, IDENT)
	end
	local rest = { ... }
	if #rest == 9 then
		return cf(a, b, c, rest)
	end
	return cf(a, b or 0, c or 0, IDENT)
end

local function rx(t) local c, s = math.cos(t), math.sin(t) return { 1, 0, 0, 0, c, -s, 0, s, c } end
local function ry(t) local c, s = math.cos(t), math.sin(t) return { c, 0, s, 0, 1, 0, -s, 0, c } end
local function rz(t) local c, s = math.cos(t), math.sin(t) return { c, -s, 0, s, c, 0, 0, 0, 1 } end

function CFrame.Angles(x, y, z)
	return cf(0, 0, 0, mulMat(mulMat(rx(x or 0), ry(y or 0)), rz(z or 0)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles

function CFrame.fromMatrix(pos, vX, vY, vZ)
	vZ = vZ or vX:Cross(vY).Unit
	return cf(pos.X, pos.Y, pos.Z, { vX.X, vY.X, vZ.X, vX.Y, vY.Y, vZ.Y, vX.Z, vY.Z, vZ.Z })
end

function CFrame.lookAt(at, target, up)
	up = up or Vector3.yAxis
	local zAxis = (at - target).Unit
	local xAxis = up:Cross(zAxis)
	if xAxis.Magnitude < 1e-6 then
		-- Roblox wählt hier eine andere Hilfsachse
		xAxis = Vector3.zAxis:Cross(zAxis)
		if xAxis.Magnitude < 1e-6 then xAxis = Vector3.xAxis:Cross(zAxis) end
	end
	xAxis = xAxis.Unit
	local yAxis = zAxis:Cross(xAxis).Unit
	return CFrame.fromMatrix(at, xAxis, yAxis, zAxis)
end

CFmt.__mul = function(a, b)
	if type(b) == "table" and b.__isCF then
		local x, y, z = mulVec(a.m, b.px, b.py, b.pz)
		return cf(a.px + x, a.py + y, a.pz + z, mulMat(a.m, b.m))
	end
	local x, y, z = mulVec(a.m, b.X, b.Y, b.Z)
	return v3(a.px + x, a.py + y, a.pz + z)
end
CFmt.__add = function(a, v) return cf(a.px + v.X, a.py + v.Y, a.pz + v.Z, a.m) end
CFmt.__sub = function(a, v) return cf(a.px - v.X, a.py - v.Y, a.pz - v.Z, a.m) end
CFmt.__tostring = function(a)
	return string.format("CF(%.3f, %.3f, %.3f | %.3f %.3f %.3f / %.3f %.3f %.3f / %.3f %.3f %.3f)", a.px, a.py, a.pz,
		a.m[1], a.m[2], a.m[3], a.m[4], a.m[5], a.m[6], a.m[7], a.m[8], a.m[9])
end
CFmt.__index = function(self, key)
	local m = self.m
	if key == "Position" or key == "p" then return v3(self.px, self.py, self.pz)
	elseif key == "Rotation" then return cf(0, 0, 0, m)
	elseif key == "X" then return self.px
	elseif key == "Y" then return self.py
	elseif key == "Z" then return self.pz
	elseif key == "LookVector" then return v3(-m[3], -m[6], -m[9])
	elseif key == "RightVector" or key == "XVector" then return v3(m[1], m[4], m[7])
	elseif key == "UpVector" or key == "YVector" then return v3(m[2], m[5], m[8])
	elseif key == "ZVector" then return v3(m[3], m[6], m[9])
	end
	return CFrame[key]
end

function CFrame.Inverse(a)
	local t = transpose(a.m)
	local x, y, z = mulVec(t, a.px, a.py, a.pz)
	return cf(-x, -y, -z, t)
end
function CFrame.ToObjectSpace(a, b) return a:Inverse() * b end
function CFrame.ToWorldSpace(a, b) return a * b end
function CFrame.PointToWorldSpace(a, v) return a * v end
function CFrame.PointToObjectSpace(a, v) return a:Inverse() * v end
function CFrame.VectorToWorldSpace(a, v) local x, y, z = mulVec(a.m, v.X, v.Y, v.Z) return v3(x, y, z) end
function CFrame.VectorToObjectSpace(a, v) local x, y, z = mulVec(transpose(a.m), v.X, v.Y, v.Z) return v3(x, y, z) end
function CFrame.GetComponents(a)
	local m = a.m
	return a.px, a.py, a.pz, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9]
end
CFrame.components = CFrame.GetComponents

-- Rotation <-> Quaternion für Lerp (Slerp wie Roblox)
local function toQuat(m)
	local tr = m[1] + m[5] + m[9]
	local w, x, y, z
	if tr > 0 then
		local s = math.sqrt(tr + 1) * 2
		w = 0.25 * s; x = (m[8] - m[6]) / s; y = (m[3] - m[7]) / s; z = (m[4] - m[2]) / s
	elseif m[1] > m[5] and m[1] > m[9] then
		local s = math.sqrt(1 + m[1] - m[5] - m[9]) * 2
		w = (m[8] - m[6]) / s; x = 0.25 * s; y = (m[2] + m[4]) / s; z = (m[3] + m[7]) / s
	elseif m[5] > m[9] then
		local s = math.sqrt(1 + m[5] - m[1] - m[9]) * 2
		w = (m[3] - m[7]) / s; x = (m[2] + m[4]) / s; y = 0.25 * s; z = (m[6] + m[8]) / s
	else
		local s = math.sqrt(1 + m[9] - m[1] - m[5]) * 2
		w = (m[4] - m[2]) / s; x = (m[3] + m[7]) / s; y = (m[6] + m[8]) / s; z = 0.25 * s
	end
	return w, x, y, z
end
local function fromQuat(w, x, y, z)
	local n = math.sqrt(w * w + x * x + y * y + z * z)
	w, x, y, z = w / n, x / n, y / n, z / n
	return {
		1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
		2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
		2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
	}
end
function CFrame.Lerp(a, b, t)
	local aw, ax, ay, az = toQuat(a.m)
	local bw, bx, by, bz = toQuat(b.m)
	local dot = aw * bw + ax * bx + ay * by + az * bz
	if dot < 0 then bw, bx, by, bz = -bw, -bx, -by, -bz; dot = -dot end
	local w, x, y, z
	if dot > 0.9995 then
		w, x, y, z = aw + (bw - aw) * t, ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t
	else
		local theta = math.acos(dot)
		local s = math.sin(theta)
		local fa, fb = math.sin((1 - t) * theta) / s, math.sin(t * theta) / s
		w, x, y, z = aw * fa + bw * fb, ax * fa + bx * fb, ay * fa + by * fb, az * fa + bz * fb
	end
	return cf(a.px + (b.px - a.px) * t, a.py + (b.py - a.py) * t, a.pz + (b.pz - a.pz) * t, fromQuat(w, x, y, z))
end
-- Wie Roblox: Winkel (x, y, z) mit CFrame.fromOrientation(x, y, z) = Ry(y) * Rx(x) * Rz(z)
function CFrame.ToOrientation(a)
	local m = a.m
	local x = math.asin(math.clamp(-m[6], -1, 1))
	local y, z
	if math.abs(m[6]) < 0.9999 then
		y = math.atan2(m[3], m[9]); z = math.atan2(m[4], m[5])
	else
		y = math.atan2(-m[7], m[1]); z = 0
	end
	return x, y, z
end
CFrame.ToEulerAnglesYXZ = CFrame.ToOrientation
function CFrame.fromOrientation(x, y, z)
	return CFrame.Angles(0, y, 0) * CFrame.Angles(x, 0, 0) * CFrame.Angles(0, 0, z)
end
CFrame.fromEulerAnglesYXZ = CFrame.fromOrientation
function CFrame.ToEulerAnglesXYZ(a)
	local m = a.m
	local y = math.asin(math.clamp(m[3], -1, 1))
	local x, z
	if math.abs(m[3]) < 0.9999 then
		x = math.atan2(-m[6], m[9]); z = math.atan2(-m[2], m[1])
	else
		x = math.atan2(m[8], m[5]); z = 0
	end
	return x, y, z
end

-- Winkel (Grad) zwischen zwei Rotationen
local function angleBetween(a, b)
	local r = a.Rotation:Inverse() * b.Rotation
	local tr = r.m[1] + r.m[5] + r.m[9]
	return math.deg(math.acos(math.clamp((tr - 1) / 2, -1, 1)))
end

local Color3 = {}
local Color3Meta = { __index = {} }
function Color3Meta.__index.ToHex(c)
	local function byte(v)
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return string.format("%02X%02X%02X", byte(c.R), byte(c.G), byte(c.B))
end
function Color3Meta.__index.Lerp(a, b, t)
	return setmetatable({ R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t }, Color3Meta)
end
function Color3.fromRGB(r, g, b) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, Color3Meta) end
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3Meta) end

-- Enum-Werte wie in Roblox: Enum.Gruppe.Name ist immer dasselbe Objekt mit Name, Value und EnumType (hier der Name der
-- Gruppe); tostring ergibt "Enum.Gruppe.Name". Value: bekannte Zahlen aus ENUM_VALUES, sonst fortlaufend je Gruppe.
local ENUM_VALUES = {
	RenderPriority = { First = 0, Input = 100, Camera = 200, Character = 300, Last = 2000 },
	ContextActionPriority = { Low = 1000, Medium = 2000, Default = 2000, High = 3000 },
}
local EnumItemMeta = {
	__tostring = function(item)
		return "Enum." .. item.EnumType .. "." .. item.Name
	end,
	__concat = function(a, b)
		return tostring(a) .. tostring(b)
	end,
}
local enumGroups = {}
local Enum = setmetatable({}, { __index = function(_, group)
	local items = enumGroups[group]
	if not items then
		local count = 0
		items = setmetatable({}, { __index = function(list, name)
			local known = ENUM_VALUES[group]
			count += 1
			local item = setmetatable({ Name = name, Value = known and known[name] or count - 1, EnumType = group,
				__type = "EnumItem" }, EnumItemMeta)
			rawset(list, name, item)
			return item
		end })
		enumGroups[group] = items
	end
	return items
end })


function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local row = ({ { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } })[i % 6 + 1]
	return Color3.new(row[1], row[2], row[3])
end
function Color3Meta.__index.ToHSV(c)
	local maxc, minc = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
	local d = maxc - minc
	local h = 0
	if d > 0 then
		if maxc == c.R then
			h = ((c.G - c.B) / d) % 6
		elseif maxc == c.G then
			h = (c.B - c.R) / d + 2
		else
			h = (c.R - c.G) / d + 4
		end
		h /= 6
	end
	return h, maxc > 0 and d / maxc or 0, maxc
end
Color3Meta.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
Color3Meta.__tostring = function(c) return string.format("%g, %g, %g", c.R, c.G, c.B) end

-- Vector2
local Vector2 = {}
local V2mt = {}
local function v2(x, y) return setmetatable({ X = x or 0, Y = y or 0, __isV2 = true }, V2mt) end
V2mt.__add = function(a, b) return v2(a.X + b.X, a.Y + b.Y) end
V2mt.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
V2mt.__unm = function(a) return v2(-a.X, -a.Y) end
V2mt.__mul = function(a, b)
	if type(a) == "number" then return v2(a * b.X, a * b.Y) end
	if type(b) == "number" then return v2(a.X * b, a.Y * b) end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2mt.__div = function(a, b)
	if type(b) == "number" then return v2(a.X / b, a.Y / b) end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
V2mt.__tostring = function(a) return string.format("%g, %g", a.X, a.Y) end
V2mt.__index = function(self, key)
	if key == "Magnitude" then return math.sqrt(self.X * self.X + self.Y * self.Y) end
	if key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y)
		return v2(self.X / m, self.Y / m)
	end
	return Vector2[key]
end
function Vector2.new(x, y) return v2(x, y) end
function Vector2.Dot(a, b) return a.X * b.X + a.Y * b.Y end
function Vector2.Lerp(a, b, t) return a + (b - a) * t end
Vector2.zero = v2(0, 0)
Vector2.one = v2(1, 1)
Vector2.xAxis = v2(1, 0)
Vector2.yAxis = v2(0, 1)

-- UDim / UDim2
local UDim, UDim2 = {}, {}
local UDimMT, UDim2MT = {}, {}
function UDim.new(scale, offset) return setmetatable({ Scale = scale or 0, Offset = offset or 0, __type = "UDim" }, UDimMT) end
UDimMT.__add = function(a, b) return UDim.new(a.Scale + b.Scale, a.Offset + b.Offset) end
UDimMT.__sub = function(a, b) return UDim.new(a.Scale - b.Scale, a.Offset - b.Offset) end
UDimMT.__eq = function(a, b) return a.Scale == b.Scale and a.Offset == b.Offset end
local function udim2(x, y)
	return setmetatable({ X = x, Y = y, Width = x, Height = y, __type = "UDim2" }, UDim2MT)
end
function UDim2.new(xs, xo, ys, yo)
	if type(xs) == "table" then return udim2(xs, xo) end
	return udim2(UDim.new(xs, xo), UDim.new(ys, yo))
end
function UDim2.fromScale(x, y) return UDim2.new(x, 0, y, 0) end
function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end
UDim2MT.__add = function(a, b) return udim2(a.X + b.X, a.Y + b.Y) end
UDim2MT.__sub = function(a, b) return udim2(a.X - b.X, a.Y - b.Y) end
UDim2MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
UDim2MT.__index = { Lerp = function(a, b, t)
	return UDim2.new(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t,
		a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t)
end }

-- Datentypen, die Module nur als Werte weiterreichen (Felder wie in Roblox)
local function record(typeName, fields)
	fields.__type = typeName
	return fields
end
local NumberRange = { new = function(min, max) return record("NumberRange", { Min = min, Max = max or min }) end }
local NumberSequenceKeypoint = { new = function(time, value, envelope)
	return record("NumberSequenceKeypoint", { Time = time, Value = value, Envelope = envelope or 0 })
end }
local NumberSequence = { new = function(a, b)
	local points = type(a) == "table" and a or { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
	return record("NumberSequence", { Keypoints = points })
end }
local ColorSequenceKeypoint = { new = function(time, value)
	return record("ColorSequenceKeypoint", { Time = time, Value = value })
end }
local ColorSequence = { new = function(a, b)
	local points = (type(a) == "table" and a.R == nil) and a or { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
	return record("ColorSequence", { Keypoints = points })
end }
local TweenInfo = { new = function(time, style, direction, repeatCount, reverses, delayTime)
	return record("TweenInfo", { Time = time or 1, EasingStyle = style, EasingDirection = direction,
		RepeatCount = repeatCount or 0, Reverses = reverses or false, DelayTime = delayTime or 0 })
end }
local Font = { new = function(family, weight, style)
	return record("Font", { Family = family, Weight = weight, Style = style })
end, fromEnum = function(value)
	return record("Font", { Family = tostring(value) })
end, fromName = function(name, weight, style)
	return record("Font", { Family = name, Weight = weight, Style = style })
end }
local Rect = { new = function(a, b, c, d)
	if type(a) == "table" then return record("Rect", { Min = a, Max = b }) end
	return record("Rect", { Min = v2(a, b), Max = v2(c, d) })
end }
local PhysicalProperties = { new = function(density, friction, elasticity, frictionWeight, elasticityWeight)
	return record("PhysicalProperties", { Density = density, Friction = friction, Elasticity = elasticity,
		FrictionWeight = frictionWeight, ElasticityWeight = elasticityWeight })
end }
local Ray = { new = function(origin, direction) return record("Ray", { Origin = origin, Direction = direction }) end }
local BrickColor = { new = function(name)
	return record("BrickColor", { Name = tostring(name), Color = Color3.new(0.6, 0.6, 0.6) })
end }
BrickColor.random = function() return BrickColor.new("Random") end
BrickColor.Red = function() return BrickColor.new("Bright red") end
BrickColor.Blue = function() return BrickColor.new("Bright blue") end
BrickColor.White = function() return BrickColor.new("White") end
local RaycastParams = { new = function()
	return record("RaycastParams", { FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {},
		IgnoreWater = false, CollisionGroup = "Default", RespectCanCollide = false })
end }
local OverlapParams = { new = function()
	return record("OverlapParams", { FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {},
		MaxParts = 0, CollisionGroup = "Default", RespectCanCollide = false })
end }

-- Zufall wie in Roblox (eigener Zustand pro Objekt, mit Startwert reproduzierbar)
local RandomMT = {}
RandomMT.__index = RandomMT
local function nextRaw(self)
	self.State = (self.State * 1103515245 + 12345) % 2147483648
	return self.State / 2147483648
end
function RandomMT:NextNumber(a, b)
	a, b = a or 0, b or 1
	return a + nextRaw(self) * (b - a)
end
function RandomMT:NextInteger(a, b)
	return math.min(b, a + math.floor(nextRaw(self) * (b - a + 1)))
end
function RandomMT:NextUnitVector()
	local z = self:NextNumber(-1, 1)
	local angle = self:NextNumber(0, 2 * math.pi)
	local r = math.sqrt(1 - z * z)
	return v3(r * math.cos(angle), r * math.sin(angle), z)
end
function RandomMT:Shuffle(list)
	for i = #list, 2, -1 do
		local j = self:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end
function RandomMT:Clone()
	return setmetatable({ State = self.State }, RandomMT)
end
local randomSeeds = 0
local Random = { new = function(seed)
	randomSeeds += 1
	return setmetatable({ State = math.floor(seed or (randomSeeds * 7919)) % 2147483648 }, RandomMT)
end }

local typeofOriginal = typeof
local function typeof(value)
	if type(value) == "table" then
		if rawget(value, "__isInstance") then return "Instance" end
		if value.__isCF then return "CFrame" end
		if value.__isV3 then return "Vector3" end
		if value.__isV2 then return "Vector2" end
		if getmetatable(value) == Color3Meta then return "Color3" end
		if rawget(value, "__type") then return value.__type end
	end
	return typeofOriginal(value)
end

return {
	Vector3 = Vector3,
	Vector2 = Vector2,
	CFrame = CFrame,
	Color3 = Color3,
	Enum = Enum,
	UDim = UDim,
	UDim2 = UDim2,
	NumberRange = NumberRange,
	NumberSequence = NumberSequence,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequence = ColorSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	TweenInfo = TweenInfo,
	Font = Font,
	Rect = Rect,
	PhysicalProperties = PhysicalProperties,
	Ray = Ray,
	BrickColor = BrickColor,
	RaycastParams = RaycastParams,
	OverlapParams = OverlapParams,
	Random = Random,
	typeof = typeof,
	angleBetween = angleBetween,
}
