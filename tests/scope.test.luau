-- Zielfernrohr (DMR mit 3D-Modell): Ohne Modell hat der DMR Kimme und Korn (kein Fernrohr), das Fernrohr vergrößert
-- stärker als normales Zielen, und die Fernrohr-Ansicht (ScopeOverlay) entsteht erst beim ersten Zeigen, liegt unter
-- dem HUD und lässt sich wieder ausblenden
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local GunModels = require("GunModels")
local WeaponConfig = require("WeaponConfig")
local ScopeOverlay = require("ScopeOverlay")

check(GunModels.Info.DMR.Scope == true, "DMR ist als Waffe mit Zielfernrohr markiert")
check(not GunModels.HasScope("DMR"), "ohne 3D-Modell kein Zielfernrohr (Quader-DMR zielt über Kimme und Korn)")
check(not GunModels.HasScope("Rifle") and not GunModels.HasScope("Nichts"), "andere Waffen ohne Zielfernrohr")
local dmr = WeaponConfig.Get("DMR")
check(type(dmr.ScopeFov) == "number" and dmr.ScopeFov < dmr.AimFov, "Fernrohr vergrößert stärker als Zielen")

local bob = SIM.Join("Bob")
rawget(SIM.Players, "__props").LocalPlayer = bob
local playerGui = bob:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", bob)
SIM.Advance(1, 20)

ScopeOverlay.Update(false)
check(playerGui:FindFirstChild("ScopeOverlay") == nil, "ohne Zielen wird nichts gebaut")
ScopeOverlay.Update(true)
local gui = playerGui:FindFirstChild("ScopeOverlay")
check(gui ~= nil and gui.Enabled and ScopeOverlay.IsShown(), "Fernrohr-Ansicht wird gezeigt")
check(gui ~= nil and gui.DisplayOrder < 0, "liegt unter dem HUD")
check(gui ~= nil and gui:FindFirstChild("View") ~= nil and gui.View:FindFirstChild("Dot") ~= nil, "Durchblick mit Mittelpunkt")
ScopeOverlay.Update(false)
check(gui ~= nil and not gui.Enabled and not ScopeOverlay.IsShown(), "ausgeblendet nach dem Zielen")
ScopeOverlay.Update(true)
check(#playerGui:GetChildren() == 1, "wird nur einmal gebaut")

if failures > 0 then
	error(failures .. " Fehler")
end
print("scope ok")
