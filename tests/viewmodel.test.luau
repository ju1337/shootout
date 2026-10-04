-- ViewModel: Beim Zielen müssen Kimmen-Mitte und Kornspitze genau in der Bildmitte liegen
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local ViewModel = require("ViewModel")
local GunModels = require("GunModels")
local WeaponAnimations = require("WeaponAnimations")
local WeaponConfig = require("WeaponConfig")

local camera = CFrame.new(12, 7, -30) * CFrame.Angles(0.2, 1.1, 0)
for weaponName, info in GunModels.Info do
	local vm = ViewModel.new(weaponName, nil, Color3.fromRGB(80, 80, 80))
	vm.DrawStart = os.clock() - 5 -- Ziehen vorbei
	for _ = 1, 3 do
		vm:Update(1 / 60, { Camera = camera, Aim = 1, Sprinting = false, Speed = 0 })
	end
	local function camPoint(partName, offset)
		local part = vm.Model:FindFirstChild(partName)
		local world = part.CFrame * offset
		return camera:PointToObjectSpace(world), part
	end
	-- Kornspitze (Oberkante des Leuchtpunkts; Schrotflinte: Mitte der Perle; Rotpunkt: Mitte des Punkts)
	local tip, rearL, rearR
	if GunModels.HasAsset(weaponName) then
		-- 3D-Modell: Kimme und Korn liegen dort, wo die Marker Point_SightRear/Point_SightFront saßen
		local s = ViewModel.Scale()
		tip = camera:PointToObjectSpace(vm.GunWorld * (Vector3.new(0, info.SightHeight, info.SightFrontZ) * s))
		rearL = camera:PointToObjectSpace(vm.GunWorld * (Vector3.new(0, info.SightHeight, info.SightZ) * s))
		rearR = rearL
	elseif info.Reflex then
		tip = camPoint("DotReticle", Vector3.zero)
		rearL = camPoint("DotHoodL", Vector3.zero)
		rearR = camPoint("DotHoodR", Vector3.zero)
	else
		local dot = vm.Model:FindFirstChild("FrontDot")
		local tipOffset = weaponName == "Shotgun" and Vector3.zero or Vector3.new(0, dot.Size.Y / 2, 0)
		tip = camPoint("FrontDot", tipOffset)
		-- Kimme: Mitte zwischen linkem und rechtem Teil, Höhe = Visierlinie
		rearL = camPoint("RearL", Vector3.zero)
		rearR = camPoint("RearR", Vector3.zero)
	end
	local rearMid = (rearL + rearR) / 2
	local sightLine = info.SightHeight * ViewModel.Scale()
	local rearHeightCam = camera:PointToObjectSpace(vm.GunWorld * Vector3.new(0, sightLine, info.SightZ * ViewModel.Scale())).Y
	local tipAngle = math.deg(math.atan2(math.sqrt(tip.X ^ 2 + tip.Y ^ 2), -tip.Z))
	print(string.format("%-9s Zielen: Korn (%.4f, %.4f, %.3f) %.3f°, Kimme x %.4f, Visierlinie hinten y %.4f",
		weaponName, tip.X, tip.Y, tip.Z, tipAngle, rearMid.X, rearHeightCam))
	check(tipAngle < 0.05, weaponName .. ": Korn nicht in der Bildmitte")
	check(math.abs(rearMid.X) < 1e-3, weaponName .. ": Kimme nicht mittig")
	check(math.abs(rearHeightCam) < 1e-3, weaponName .. ": Visierlinie hinten nicht auf Augenhöhe")
	check(tip.Z < -0.3, weaponName .. ": Korn zu nah an der Kamera")
	-- Nichts darf vor der Kamera näher als die Near-Plane (0.1) mitten im Bild liegen
	for _, part in vm.Model:GetChildren() do
		if (part.Transparency or 0) < 1 then
			local p = camera:PointToObjectSpace(part.CFrame.Position)
			if p.Z > -0.12 and p.Z < 0 and math.abs(p.X) < 0.05 and math.abs(p.Y) < 0.05 then
				check(false, weaponName .. ": " .. part.Name .. " klebt an der Kamera")
			end
		end
	end

	-- Hüfte: Waffe rechts unten
	local vm2 = ViewModel.new(weaponName, nil, Color3.fromRGB(80, 80, 80))
	vm2.DrawStart = os.clock() - 5
	vm2:Update(1 / 60, { Camera = camera, Aim = 0, Sprinting = false, Speed = 0 })
	local muzzle = camera:PointToObjectSpace(vm2:MuzzleCFrame().Position)
	check(muzzle.X > 0 and muzzle.Y < 0 and muzzle.Z < 0, weaponName .. ": Hüfte nicht rechts unten")
	-- Hüfte: Mündung im Bild (Sichtfeld 70°, 16:9)
	local vertical = math.deg(math.atan2(math.abs(muzzle.Y), -muzzle.Z))
	local horizontal = math.deg(math.atan2(math.abs(muzzle.X), -muzzle.Z))
	check(vertical < 35 and horizontal < 55, weaponName .. ": Mündung aus der Hüfte nicht im Bild")
	-- Linke Hand (Handschuh) nahe an der Waffe
	local glove = vm2.Model:FindFirstChild("LeftGlove")
	local handTarget = vm2.GunWorld * (info.LeftHand * ViewModel.Scale())
	check((glove.CFrame.Position - handTarget).Magnitude < 1e-3, weaponName .. ": linke Hand nicht an der Waffe")

	-- Nachladen durchspielen: keine Fehler, linke Hand bleibt im Bereich unter/vor der Kamera
	local anim, duration = WeaponAnimations.Reload(weaponName, WeaponConfig.Get(weaponName).ReloadTime, 3)
	for i = 0, 50 do
		vm2:Update(1 / 60, { Camera = camera, Aim = 0, Sprinting = false, Speed = 0, Reload = { Anim = anim, T = i / 50 } })
		local g = camera:PointToObjectSpace(vm2.Model:FindFirstChild("LeftGlove").CFrame.Position)
		check(g.Z < 0.5, weaponName .. ": Hand hinter der Kamera beim Nachladen (t=" .. i / 50 .. ")")
	end
	print(string.format("%-9s Hüfte: Mündung %.1f° unten, %.1f° rechts; Nachladen %.2fs ok", weaponName, vertical, horizontal, duration))
end

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))
