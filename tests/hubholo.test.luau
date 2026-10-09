--!expose HubLineup buildShopVitrine dailyOffers
-- Camp, Shop-Vitrine beim Ausrüster: drei verschiedene Waffen-Skins des Tages (Agenten-Skins gibt es nicht mehr), je mit Schild.
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

-- Camp wie in der Map: Gruppe Zentrale in Maps.Extinction
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local world = Instance.new("Model", maps)
world.Name = "Extinction"
local decor = Instance.new("Model", world)
decor.Name = "Zentrale"

local HubLineup = require("HubLineup")

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
	print("Shop-Vitrine: alles in Ordnung")
end
