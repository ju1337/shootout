-- Waffe inspizieren (Taste X): jede Waffe hat ihre eigene Animation, die in Ruhe anfängt und endet; das HUD
-- verschwindet währenddessen (InspectView) und kommt unverändert zurück; WeaponClient startet mit X, beendet von
-- selbst, bei Schuss, Zielen oder nochmal X und meldet es dem Server; der Server setzt die Attribute für die anderen
-- und räumt sie bei Wechsel und Nachladen weg.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function near(a, b, eps)
	local ca, cb = { a:GetComponents() }, { b:GetComponents() }
	for i = 1, 12 do
		if math.abs(ca[i] - cb[i]) > (eps or 1e-4) then
			return false
		end
	end
	return true
end

game.JobId = "server-1"
SIM.DataStore("PlayerData_v1")
local GunModels = require("GunModels")
local WeaponConfig = require("WeaponConfig")
local WeaponAnimations = require("WeaponAnimations")
local Remotes = require("Remotes")

-- ---------- Animationen ----------
local signatures = {}
for weaponName in GunModels.Info do
	local anim, duration = WeaponAnimations.Inspect(weaponName)
	check(anim ~= nil and duration >= 3 and duration <= 5.5, weaponName .. ": Inspizieren fehlt oder falsche Dauer")
	if anim then
		local first = WeaponAnimations.Sample(anim, weaponName, 0)
		local last = WeaponAnimations.Sample(anim, weaponName, 1)
		check(near(first.Gun, CFrame.new()) and near(last.Gun, CFrame.new()), weaponName .. ": Waffe beginnt/endet nicht in Ruhe")
		local rest = CFrame.new(GunModels.Info[weaponName].LeftHand)
		check(first.Hand and near(first.Hand, rest) and near(last.Hand, rest), weaponName .. ": linke Hand nicht in Ruhe")
		for group, offset in last.Groups do
			check(near(offset, CFrame.new()), weaponName .. ": Gruppe " .. group .. " nicht in Ruhe")
		end
		-- unterwegs: wirklich bewegt, Werte endlich, Gruppen gibt es an der Waffe
		local moved = 0
		for i = 1, 99 do
			local pose = WeaponAnimations.Sample(anim, weaponName, i / 100)
			local p = pose.Gun.Position
			check(p.X == p.X and p.Magnitude < 2, weaponName .. ": Waffe springt weg (t=" .. i / 100 .. ")")
			moved = math.max(moved, p.Magnitude)
			for group in pose.Groups do
				check(GunModels.GroupPivot(weaponName, group) ~= nil, weaponName .. ": unbekannte Gruppe " .. group)
			end
		end
		check(moved > 0.3, weaponName .. ": Waffe wird kaum bewegt")
		for _, event in anim.Events do
			check(event[2] ~= "Sound" or WeaponConfig.ActionSounds[event[3]] ~= nil, weaponName .. ": unbekannter Sound")
		end
		local mid = WeaponAnimations.Sample(anim, weaponName, 0.5).Gun
		signatures[weaponName] = string.format("%.2f %.2f %.2f", mid.LookVector.X, mid.LookVector.Y, mid.UpVector.X)
	end
end
local seen = {}
for weaponName, signature in signatures do
	check(seen[signature] == nil, weaponName .. ": gleiche Animation wie " .. tostring(seen[signature]))
	seen[signature] = weaponName
end
-- Hand "Hold": bleibt beim Wirbeln ruhig (Waffe * Hand = Haltung * Versatz)
local pistol = WeaponAnimations.Inspect("Pistol")
local spinA = WeaponAnimations.Sample(pistol, "Pistol", 0.83)
local spinB = WeaponAnimations.Sample(pistol, "Pistol", 0.87)
check(not near(spinA.Gun, spinB.Gun, 1e-2), "Pistole wirbelt")
check(((spinA.Gun * spinA.Hand).Position - (spinB.Gun * spinB.Hand).Position).Magnitude < 1e-3, "linke Hand bleibt beim Wirbeln ruhig")

-- ---------- Server: Attribute für die anderen ----------
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
ProgressService.Init()
WeaponService.Init()
local alice = SIM.Join("Alice")
Instance.new("Backpack", alice).Name = "Backpack"
SIM.Advance(1, 20)
if not alice.Character then
	alice:LoadCharacter()
	SIM.Advance(0.5, 20)
end
local character = alice.Character
WeaponService.SetCarried(alice, "Rifle", 30)
Remotes.Inspect.OnServerEvent:Fire(alice, true)
check(typeof(character:GetAttribute("InspectStart")) == "number" and character:GetAttribute("InspectWeapon") == "Rifle",
	"Server: Inspizieren gemeldet")
SIM.Advance(0.3, 20)
Remotes.Inspect.OnServerEvent:Fire(alice, false)
check(character:GetAttribute("InspectStart") == nil and character:GetAttribute("InspectWeapon") == nil, "Server: Ende gemeldet")
SIM.Advance(0.3, 20)
Remotes.Inspect.OnServerEvent:Fire(alice, true)
Remotes.Inspect.OnServerEvent:Fire(alice, false)
check(character:GetAttribute("InspectStart") ~= nil, "Server: zu schnelle Meldungen werden verworfen")
WeaponService.SetCarried(alice, "SMG", 30)
check(character:GetAttribute("InspectStart") == nil, "Server: Waffenwechsel beendet das Inspizieren")
SIM.Advance(0.3, 20)
WeaponService.SetCarried(alice, nil)
Remotes.Inspect.OnServerEvent:Fire(alice, true)
check(character:GetAttribute("InspectStart") == nil, "Server: ohne Waffe kein Inspizieren")

-- ---------- Client: InspectView und WeaponClient ----------
rawget(SIM.Players, "__props").LocalPlayer = alice
local playerGui = alice:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", alice)
local hud = Instance.new("ScreenGui", playerGui)
hud.Name = "HUD"
local extHud = Instance.new("ScreenGui", playerGui)
extHud.Name = "ExtinctionHUD"
extHud.Enabled = false
local touch = Instance.new("ScreenGui", playerGui)
touch.Name = "TouchControls"

local InspectView = require("InspectView")
InspectView.Start("Rifle", false)
check(InspectView.IsActive(), "Präsentation läuft")
check(hud.Parent == nil and extHud.Parent == nil, "HUD-Oberflächen verschwinden")
check(touch.Parent == playerGui, "Touch-Knöpfe bleiben")
check(playerGui:FindFirstChild("Inspect") and playerGui.Inspect.Enabled, "Kino-Ebene sichtbar")
local focus = game:GetService("Lighting"):FindFirstChild("InspectFocus")
check(focus and focus.Enabled, "Tiefenschärfe an")
local card = playerGui.Inspect:FindFirstChild("Card", true)
local texts = {}
for _, obj in card:GetDescendants() do
	if obj:IsA("TextLabel") then
		texts[obj.Text] = true
	end
end
check(texts["STURMGEWEHR"] and texts["SCHADEN"] and texts["FEUERRATE"] and texts["MAGAZIN"] and texts["REICHWEITE"],
	"Karte zeigt Name und Werte")
check(texts["STANDARD"] and texts["KEINE"], "Karte zeigt Skin und Aufsätze")
InspectView.Stop()
check(hud.Parent == playerGui and extHud.Parent == playerGui and extHud.Enabled == false, "HUD kommt unverändert zurück")
SIM.Advance(0.5, 20)
check(not playerGui.Inspect.Enabled and not focus.Enabled, "Kino-Ebene und Tiefenschärfe wieder aus")

-- WeaponClient: X startet, läuft von selbst aus; Schuss und nochmal X beenden
SIM.IsServer = false -- Client-Takt (RenderStepped)
alice:SetAttribute("Mode", "FFA")
local WeaponClient = require("WeaponClient")
local InputActions = require("InputActions")
-- Taste X, keine andere Aktion auf X (Messer bleibt V)
check(InputActions.Bindings.Inspect.Keys[1] == Enum.KeyCode.X and InputActions.Hint("Inspect") == "X", "Inspizieren liegt auf X")
for action, binding in InputActions.Bindings do
	check(action == "Inspect" or table.find(binding.Keys, Enum.KeyCode.X) == nil, action .. " liegt auch auf X")
end
check(InputActions.Bindings.Melee.Keys[1] == Enum.KeyCode.V, "Messer bleibt auf V")
WeaponClient.Init()
Remotes.AmmoUpdate.OnClientEvent:Fire("Rifle", 30, 90, false, 30, 0, true)
SIM.Advance(0.5, 20)
local function inspectMessages()
	local list = {}
	for _, entry in SIM.RemoteLog do
		if entry.Remote == "Inspect" and entry.Player == "server" then
			table.insert(list, entry.Args[1])
		end
	end
	return list
end
InputActions.Trigger("Inspect", true)
InputActions.Trigger("Inspect", false)
SIM.Advance(0.1, 20)
check(WeaponClient.Inspecting() ~= nil and WeaponClient.Inspecting().Weapon == "Rifle", "X startet das Inspizieren")
check(InspectView.IsActive() and hud.Parent == nil, "HUD weg beim Inspizieren")
check(inspectMessages()[1] == true, "Start an den Server gemeldet")
local _, duration = WeaponAnimations.Inspect("Rifle")
SIM.Advance(duration + 0.1, 20)
check(WeaponClient.Inspecting() == nil and not InspectView.IsActive() and hud.Parent == playerGui, "läuft von selbst aus, HUD zurück")
check(inspectMessages()[2] == false, "Ende an den Server gemeldet")
InputActions.Trigger("Inspect", true)
SIM.Advance(0.5, 20)
InputActions.Trigger("Inspect", true)
SIM.Advance(0.05, 20)
check(WeaponClient.Inspecting() == nil and hud.Parent == playerGui, "nochmal X beendet")
InputActions.Trigger("Inspect", true)
SIM.Advance(0.5, 20)
InputActions.Trigger("Fire", true)
InputActions.Trigger("Fire", false)
SIM.Advance(0.05, 20)
check(WeaponClient.Inspecting() == nil and hud.Parent == playerGui, "Schuss beendet das Inspizieren")
SIM.Advance(1, 20)
InputActions.Trigger("Inspect", true)
SIM.Advance(0.3, 20)
InputActions.Trigger("Aim", true)
SIM.Advance(0.1, 20)
InputActions.Trigger("Aim", false)
check(WeaponClient.Inspecting() == nil, "Zielen beendet das Inspizieren")

print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))
