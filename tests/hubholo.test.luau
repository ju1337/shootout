--!expose HubLineup buildAgentOfWeek buildShopVitrine dailyOffers
-- Camp: Statue „Agent der Woche“ mit Holo-Schrift darüber (11 Studs breit). In Kameranähe blendet die Schrift aus –
-- rausgezoomt neben der Statue oder steil von oben hing sie sonst riesig vor dem Bild. Weiter weg ist sie voll da.
-- Shop-Vitrine: drei verschiedene Waffen-Skins des Tages (Agenten-Skins gibt es nicht mehr), je mit Schild.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

-- Lokaler Spieler (HubLineup ist ein Client-Modul, RenderStepped läuft nur auf dem Client); die Remotes legt
-- vorher wie im Spiel der Server an
require("Remotes")
SIM.IsServer = false
local player = SIM.AddPlayer("Spieler")
Instance.new("Folder", player).Name = "PlayerGui"
rawget(SIM.Players, "__props").LocalPlayer = player

-- Camp wie in der Map: Statue auf dem Sockel, Holo-Punkt 17 Studs hoch
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local world = Instance.new("Model", maps)
world.Name = "Extinction"
local decor = Instance.new("Model", world)
decor.Name = "Zentrale"
local spot = Instance.new("Part", decor)
spot.Name = "AgentOfWeekSpot"
spot.CFrame = CFrame.new(0, 3.6, 0) * CFrame.Angles(0, math.pi, 0)
local holoPoint = Instance.new("Part", decor)
holoPoint.Name = "AgentOfWeekHolo"
holoPoint.CFrame = CFrame.new(0, 17, 0)

-- Sichtbarkeit nach Kameraabstand
local HubLineup = require("HubLineup")
check(HubLineup.HoloVisibility(0) == 0 and HubLineup.HoloVisibility(9) == 0, "ganz nah: weg")
check(HubLineup.HoloVisibility(16) == 1 and HubLineup.HoloVisibility(120) == 1, "weiter weg: voll da")
check(math.abs(HubLineup.HoloVisibility(12.5) - 0.5) < 1e-9, "dazwischen: halb")

task.spawn(HubLineup.__buildAgentOfWeek)
SIM.Advance(0.2)
local billboard = player.PlayerGui:FindFirstChild("AgentOfWeekHolo")
check(billboard ~= nil and billboard.Adornee == holoPoint, "Holo-Schrift hängt am Punkt über der Statue")
check(billboard ~= nil and billboard.ResetOnSpawn == false, "Holo-Schrift bleibt nach dem Respawn")
check(workspace:FindFirstChild("AgentOfWeek") ~= nil, "Statue steht")

local camera = workspace.CurrentCamera
local function view(position)
	camera.CFrame = CFrame.lookAt(position, Vector3.new(0, 6, 0))
	SIM.Advance(0.2)
end
local function textTransparency()
	local lowest, highest = 1, 0
	for _, child in billboard:GetChildren() do
		if child:IsA("TextLabel") then
			lowest = math.min(lowest, child.TextTransparency)
			highest = math.max(highest, child.TextTransparency)
		end
	end
	return lowest, highest
end

if billboard then
	-- Vom Spawn aus: voll sichtbar (höchstens das leichte Flackern)
	view(Vector3.new(0, 9, -40))
	local _, highest = textTransparency()
	check(billboard.Enabled and highest <= 0.45 + 1e-6, "vom Spawn aus voll sichtbar: " .. highest)
	-- Rausgezoomt direkt neben der Schrift (wie auf dem Screenshot): ausgeblendet
	view(Vector3.new(3, 18, -3))
	check(not billboard.Enabled, "Kamera direkt daneben: ausgeblendet")
	-- Steil von oben neben der Statue: auch weg
	view(Vector3.new(4, 16.5, -6))
	check(not billboard.Enabled, "steil von oben neben der Statue: ausgeblendet")
	-- Auf halbem Weg: halb durchsichtig
	view(Vector3.new(0, 17, -12.5))
	local lowest
	lowest, highest = textTransparency()
	check(billboard.Enabled and lowest >= 0.5 and highest <= 0.75, ("halb ausgeblendet: %.2f bis %.2f"):format(lowest, highest))
	-- Wieder weg von der Statue: wieder voll da
	view(Vector3.new(30, 8, -20))
	_, highest = textTransparency()
	check(billboard.Enabled and highest <= 0.45 + 1e-6, "wieder weiter weg: voll sichtbar")
end

-- Shop-Vitrine: drei Angebote des Tages, alles kaufbare Waffen-Skins, jedes nur einmal
local Cosmetics = require("Cosmetics")
local offers = HubLineup.__dailyOffers()
local seen = {}
check(#offers == 3, "drei Angebote des Tages")
for _, item in offers do
	check(item.Type == "Weapon" and Cosmetics.ForSale(item) and not seen[item.Id], "Angebot: kaufbarer Waffen-Skin " .. item.Id)
	seen[item.Id] = true
end
Instance.new("Part", decor).Name = "ShopCounter"
for index = 1, 3 do
	local display = Instance.new("Part", decor)
	display.Name = "ShopDisplay" .. index
	display.CFrame = CFrame.new(-30, 4.6, index * 8)
	Instance.new("Part", decor).Name = "ShopPlaque" .. index
end
task.spawn(HubLineup.__buildShopVitrine)
SIM.Advance(0.2)
local shown = {}
for _, gui in player.PlayerGui:GetChildren() do
	if gui.Name == "PlaqueGui" then
		shown[gui.ItemName.Text] = true
	end
end
for _, item in offers do
	check(shown[string.upper(item.Name)], "Schild in der Vitrine: " .. item.Name)
end
local rifles = 0
for _, child in workspace:GetChildren() do
	if child:IsA("Model") and child.Name == "Rifle" then
		rifles += 1
	end
end
check(rifles == 3, "drei Waffen drehen sich in den Vitrinen (" .. rifles .. ")")

if failures == 0 then
	print("Holo-Schrift Agent der Woche und Shop-Vitrine: alles in Ordnung")
end
