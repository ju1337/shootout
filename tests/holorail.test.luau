-- Holo-Visier auf den echten 3D-Modellen (assets/Weapons): sitzt auf der Schiene statt darüber zu schweben,
-- Absehen liegt beim Zielen in der Bildmitte, am M60 wandert es mit dem Zuführdeckel (Gruppe Cover).
local failures = 0
local function check(c, m) if not c then failures += 1 print("FEHLER: " .. m) end end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local att = ReplicatedStorage.Assets:FindFirstChild("Attachments") or Instance.new("Folder", ReplicatedStorage.Assets)
att.Name = "Attachments"
-- Holo wie in tests/attachmentmodels.test.luau (Maße aus art/sources/Attachments)
local m = Instance.new("Model") m.Name = "HoloSight"
for _, d in {{"HoloSight", -0.0001,0.1582,-0.0000, 0.2616,0.3164,0.4558},{"Glass_Window", -0.0000,0.2236,-0.1022, 0.1344,0.1008,0.0010},{"Neon_Reticle", -0.0000,0.2236,-0.0998, 0.0581,0.0581,0.0012},{"Point_Mount", -0.0000,0.0000,-0.0000, 0.0200,0.0200,0.0200},{"Point_SightRear", -0.0000,0.2236,-0.1094, 0.0200,0.0200,0.0200},{"Point_SightFront", -0.0000,0.2236,0.1342, 0.0200,0.0200,0.0200}} do
	local p = Instance.new("MeshPart") p.Name = d[1] p.Size = Vector3.new(d[5], d[6], d[7])
	p.CFrame = CFrame.new(-20, 1, 9) * CFrame.Angles(0, math.rad(180), 0) * CFrame.new(d[2], d[3], d[4]) p.Parent = m
end
m.Parent = att
local GunModels = require("GunModels")
for _, weapon in { "SMG", "Shotgun", "LMG" } do
	local built = GunModels.Build(weapon, nil, { "HoloSight" })
	local handle = built.PrimaryPart
	local holo = built:FindFirstChild("AttHoloSight_HoloSight")
	local ret = built:FindFirstChild("AttHoloSight_Neon_Reticle")
	check(holo and ret, weapon .. ": Holo angebaut")
	if holo and ret then
		local h = handle.CFrame:ToObjectSpace(holo.CFrame).Position
		local bottom, front, back = h.Y - holo.Size.Y / 2, h.Z - holo.Size.Z / 2, h.Z + holo.Size.Z / 2
		-- höchste Oberkante der Waffe unter dem Holo (Umrisse der Teile)
		local top = -math.huge
		for _, p in built:GetChildren() do
			if p:IsA("BasePart") and not string.match(p.Name, "^Att") and p ~= handle and p.Transparency < 1 then
				local r = handle.CFrame:ToObjectSpace(p.CFrame)
				local size = r:VectorToWorldSpace(p.Size)
				local sz = math.abs(size.Z) / 2
				if r.Position.Z + sz > front and r.Position.Z - sz < back and r.Position.Y + math.abs(size.Y) / 2 < bottom + 0.3 then
					top = math.max(top, r.Position.Y + math.abs(size.Y) / 2)
				end
			end
		end
		print(string.format("HINWEIS %s: Holo unten %.3f, Waffe darunter bis %.3f, Kimme %.3f", weapon, bottom, top,
			GunModels.Info[weapon].SightHeight))
		check(bottom <= top + 0.005, weapon .. ": Holo schwebt über der Waffe")
		check(bottom < GunModels.Info[weapon].SightHeight - 0.05, weapon .. ": Holo sitzt auf Kimmenhöhe statt auf der Schiene")
		local aim = GunModels.AimOffset(weapon, { "HoloSight" })
		local r = handle.CFrame:ToObjectSpace(ret.CFrame).Position
		check(math.abs(r.X) < 0.01 and math.abs(r.Y + aim.Position.Y) < 0.01, weapon .. ": Absehen auf der Ziellinie")
		check(holo:GetAttribute("Group") == (weapon == "LMG" and "Cover" or nil), weapon .. ": Animationsgruppe des Holos")
	end
end
if failures > 0 then error(failures .. " Fehler") end
print("OK")
