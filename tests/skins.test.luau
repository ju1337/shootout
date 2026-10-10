-- Skins: Waffen-Skins und die neuen Agenten-Skins (Type = "Agent", Ids "AS_…", ein Platz "Agent" für den einen Agenten).
-- Die alten Agenten-Skins je Agent ("A_…", Plätze "A:<Agent>") bleiben entfernt: keine RAP-Werte, keine Kisten.
-- Agenten-Skins sind gebunden (nicht handelbar, nicht in Kisten); ohne Skin zeigt der Agent seinen Standard-Look
-- (AgentColors = Agentenfarbe), mit Skin dessen Farbe und Material. Battle-Pass-Stufe 20 gibt den Waffen-Skin Saison-Elite;
-- alte Spielstände verlieren beim Laden entfernte Skins (Besitz, Ausrüstung "A:<Agent>", Merkliste).
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Run(SIM.Now + (seconds or 1))
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v1")
local HttpService = game:GetService("HttpService")
local Cosmetics = require("Cosmetics")
local RapConfig = require("RapConfig")
local PassConfig = require("PassConfig")
local CrateConfig = require("CrateConfig")
local AgentConfig = require("AgentConfig")
local Remotes = require("Remotes")
local ProgressService = require("ProgressService")
local ShopService = require("ShopService")
ProgressService.Init()
ShopService.Init()

-- Waffen-Skins und neue Agenten-Skins; die alten Agenten-Skins bleiben weg (Cosmetics, RAP-Werte, Kisten)
local REMOVED = { "A_Viper_Nacht", "A_Viper_Gift", "A_Bastion_Stahl", "A_Bastion_Royal", "A_Mender_Feld", "A_Mender_Neon",
	"A_Hawk_Wueste", "A_Hawk_Phantom", "A_Viper_Saison", "A_Ghost_Schatten", "A_Ghost_Nebel", "A_Blaze_Inferno",
	"A_Blaze_Asche", "A_Aegis_Bollwerk", "A_Aegis_Sanitaet", "A_Trapper_Wildnis", "A_Trapper_Jaeger",
	"A_Volt_Hochspannung", "A_Volt_Kupfer" }
for _, item in Cosmetics.Items do
	check(item.Type == "Weapon" or item.Type == "Agent", "Waffen- oder Agenten-Skin: " .. item.Id .. " ist " .. tostring(item.Type))
	check(item.Agent == nil and item.Primary == nil and item.Accent == nil, "keine Farben je Agent an " .. item.Id)
	check(string.sub(item.Id, 1, 2) ~= "A_", "keine alte Agenten-Skin-Id: " .. item.Id)
	if item.Type == "Agent" then
		check(string.sub(item.Id, 1, 3) == "AS_" and typeof(item.Color) == "Color3" and typeof(item.Material) == "EnumItem",
			item.Id .. ": Agenten-Skin mit Farbe und Material")
		check(not RapConfig.Tradeable(item.Id), item.Id .. ": gebunden, nicht handelbar")
		check(Cosmetics.ForSale(item) or item.Creator or item.Reward, item.Id .. ": im Shop oder als Belohnung zu bekommen")
	end
end
local agentSkins = Cosmetics.List("Agent")
check(#agentSkins >= 6, "Agenten-Skins vorhanden (" .. #agentSkins .. ")")
for _, id in REMOVED do
	check(Cosmetics.Get(id) == nil and RapConfig.Values[id] == nil, id .. " ist entfernt (Skin und RAP-Wert)")
end
for id in RapConfig.Values do
	check(Cosmetics.Get(id) ~= nil and Cosmetics.Get(id).Type == "Weapon", "RAP-Wert nur für Waffen-Skins: " .. id)
end
for _, crate in CrateConfig.Crates do
	for _, item in CrateConfig.Pool(crate) do
		check(item.Type == "Weapon", "keine Agenten-Skins in Kisten: " .. item.Id)
	end
end
check(#CrateConfig.Crates == 1 and CrateConfig.Crates[1].Type == "Weapon" and CrateConfig.Get("Agent") == nil,
	"nur die Waffen-Kiste, keine Agenten-Kiste")

-- Agenten: immer der Standard-Look aus der Agentenfarbe, auch wenn der Client noch alte Attribute hat
local oldClient = Instance.new("Folder")
oldClient:SetAttribute("Owned", HttpService:JSONEncode({ A_Viper_Nacht = 1 }))
oldClient:SetAttribute("Equipped", HttpService:JSONEncode({ ["A:Viper"] = "A_Viper_Nacht" }))
for _, agent in AgentConfig.Agents do
	local primary, accent = Cosmetics.AgentColors(oldClient, agent.Id)
	check(accent == agent.Color and primary == agent.Color:Lerp(Color3.new(0, 0, 0), 0.6),
		agent.Id .. ": Standardfarben (Uniform dunkel, Akzent in Agentenfarbe)")
	local botPrimary, botAccent = Cosmetics.AgentColors(nil, agent.Id)
	check(botPrimary == primary and botAccent == accent, agent.Id .. ": ohne Spieler (Bots) dieselben Farben")
end
local first = AgentConfig.Agents[1]
local _, unknownAccent = Cosmetics.AgentColors(nil, "GibtEsNicht")
check(unknownAccent == first.Color, "unbekannter Agent: Farben des ersten Agenten")

-- Battle Pass: jede Stufe gibt Münzen oder einen exklusiven Waffen-Skin, Stufe 20 den neuen Saison-Elite
for tier, reward in PassConfig.Tiers do
	if reward.Item then
		local item = Cosmetics.Get(reward.Item)
		check(item ~= nil and item.Type == "Weapon" and item.Pass == true and not Cosmetics.ForSale(item),
			"Stufe " .. tier .. ": exklusiver Waffen-Skin (" .. tostring(reward.Item) .. ")")
	else
		check(type(reward.Coins) == "number" and reward.Coins > 0, "Stufe " .. tier .. ": Münzen")
	end
end
check(PassConfig.Tiers[20].Item == "W_Saison_Elite", "Stufe 20: Saison-Elite statt Agenten-Skin")
local elite = Cosmetics.Get("W_Saison_Elite")
check(elite ~= nil and elite.Name == "Saison-Elite" and elite.Rarity == "Legendary" and elite.Pass == true,
	"Saison-Elite: legendärer Pass-Skin")
check(RapConfig.Tradeable("W_Saison_Elite") and RapConfig.Values.W_Saison_Elite >= RapConfig.Values.W_Goldrausch,
	"Saison-Elite: handelbar, RAP wie die legendären Pass-Skins")
for _, item in Cosmetics.Items do
	if elite and item ~= elite then
		check(not (item.Color == elite.Color and item.Material == elite.Material), "Saison-Elite sieht anders aus als " .. item.Id)
	end
end

-- Alter Spielstand mit Agenten-Skins: beim Laden weg, Waffen-Skins (mit Stückzahl) bleiben
store.Data.u1 = { XP = {}, Coins = 5000, Rap = 0, PassXP = 0,
	Owned = { A_Viper_Nacht = 1, A_Ghost_Nebel = 2, A_Viper_Saison = true, W_Lava = 2, W_Rekrut = true, GibtEsNicht = 1 },
	Equipped = { ["A:Viper"] = "A_Viper_Nacht", ["A:Ghost"] = "A_Ghost_Nebel", ["W:Rifle"] = "W_Lava", ["W:SMG"] = "A_Ghost_Nebel" },
	MarketWatch = { A_Ghost_Nebel = true, W_Chrom = true } }
local alice = SIM.Join("Alice")
step(2)
check(ProgressService.IsLoaded(alice), "Profil geladen")
local profile = ProgressService.Get(alice)
check(profile.Owned.W_Lava == 2 and profile.Owned.W_Rekrut == true, "Waffen-Skins bleiben (mit Stückzahl)")
for id in profile.Owned do
	check(Cosmetics.Get(id) ~= nil, "nur bekannte Skins im Besitz: " .. tostring(id))
end
local slots = {}
for slot in profile.Equipped do
	table.insert(slots, slot)
end
check(#slots == 1 and profile.Equipped["W:Rifle"] == "W_Lava", "ausgerüstet bleibt nur der Waffen-Skin: " .. table.concat(slots, ", "))
check(profile.MarketWatch.W_Chrom == true and profile.MarketWatch.A_Ghost_Nebel == nil, "Merkliste ohne entfernte Skins")
local ownedAttr = HttpService:JSONDecode(alice:GetAttribute("Owned"))
check(ownedAttr.A_Ghost_Nebel == nil and ownedAttr.A_Viper_Saison == nil and ownedAttr.W_Lava == 2,
	"Owned-Attribut für den Client ohne Agenten-Skins")
check(not string.find(alice:GetAttribute("Equipped"), "A:", 1, true), "Equipped-Attribut ohne Agenten-Plätze")
check(alice:GetAttribute("RapValue") == 2 * RapConfig.Value("W_Lava"), "RAP-Wert zählt nur Waffen-Skins: "
	.. tostring(alice:GetAttribute("RapValue")))

-- Shop: Agenten-Skins weder kaufen noch ausrüsten oder ablegen, Waffen-Skins wie bisher
local function lastStatus(player)
	for i = #SIM.RemoteLog, 1, -1 do
		local entry = SIM.RemoteLog[i]
		if entry.Remote == "ShopStatus" and entry.Player == player then
			return entry.Args[1], entry.Args[2]
		end
	end
	return nil
end
local function action(player, ...)
	Remotes.ShopAction.OnServerEvent:Fire(player, ...)
	step(0.2)
	return lastStatus(player)
end
local message, ok = action(alice, "Buy", "A_Viper_Nacht")
check(ok == false and alice:GetAttribute("Coins") == 5000, "Agenten-Skin kaufen geht nicht: " .. tostring(message))
message, ok = action(alice, "Equip", "A_Ghost_Nebel", "Rifle")
check(ok == false and profile.Equipped["W:Rifle"] == "W_Lava", "Agenten-Skin ausrüsten geht nicht: " .. tostring(message))
message, ok = action(alice, "Unequip", "A:Viper")
check(ok == false, "Agenten-Platz gibt es nicht mehr: " .. tostring(message))
message, ok = action(alice, "Unequip", "W:Rifle")
check(ok == true and ProgressService.Get(alice).Equipped["W:Rifle"] == nil, "Waffen-Skin ablegen: " .. tostring(message))
message, ok = action(alice, "Equip", "W_Lava", "SMG")
check(ok == true and ProgressService.Get(alice).Equipped["W:SMG"] == "W_Lava", "Waffen-Skin ausrüsten: " .. tostring(message))
message, ok = action(alice, "Buy", "W_Chrom")
check(ok == true and ProgressService.Owns(alice, "W_Chrom") and alice:GetAttribute("Coins") == 5000
	- require("ShopOffers").PriceFor(Cosmetics.Get("W_Chrom"), workspace:GetServerTimeNow()),
	"Waffen-Skin kaufen: " .. tostring(message))

-- Agenten-Skins: kaufen, ausrüsten (Platz "Agent"), Farben und Material am Agenten, ablegen
local feldgrau = Cosmetics.Get("AS_Feldgrau")
message, ok = action(alice, "Equip", "AS_Feldgrau")
check(ok == false and ProgressService.Get(alice).Equipped.Agent == nil, "Agenten-Skin ohne Besitz ausrüsten geht nicht: "
	.. tostring(message))
message, ok = action(alice, "Equip", "AS_Creator")
check(ok == false and ProgressService.Get(alice).Equipped.Agent == nil, "Creator-Agenten-Skin ohne Rang geht nicht: "
	.. tostring(message))
local coinsBefore = alice:GetAttribute("Coins")
message, ok = action(alice, "Buy", "AS_Feldgrau")
check(ok == true and ProgressService.Owns(alice, "AS_Feldgrau") and alice:GetAttribute("Coins") == coinsBefore
	- require("ShopOffers").PriceFor(feldgrau, workspace:GetServerTimeNow()),
	"Agenten-Skin kaufen: " .. tostring(message))
message, ok = action(alice, "Equip", "AS_Feldgrau")
check(ok == true and ProgressService.Get(alice).Equipped.Agent == "AS_Feldgrau", "Agenten-Skin ausrüsten: " .. tostring(message))
check(ProgressService.Get(alice).Equipped["W:SMG"] == "W_Lava", "Waffen-Skins bleiben ausgerüstet")
check(Cosmetics.AgentSkin(alice) == feldgrau, "AgentSkin: ausgerüsteter Skin")
local skinPrimary, skinAccent, skinMaterial = Cosmetics.AgentColors(alice, AgentConfig.MainId)
check(skinPrimary == feldgrau.Color and skinMaterial == feldgrau.Material and skinAccent == AgentConfig.Get(AgentConfig.MainId).Color,
	"AgentColors: Farbe und Material des Skins")
message, ok = action(alice, "Unequip", "Agent")
check(ok == true and ProgressService.Get(alice).Equipped.Agent == nil and Cosmetics.AgentSkin(alice) == nil,
	"Agenten-Skin ablegen: " .. tostring(message))
local _, _, noMaterial = Cosmetics.AgentColors(alice, AgentConfig.MainId)
check(noMaterial == nil, "ohne Skin: Standard-Material")
message, ok = action(alice, "Equip", "AS_Feldgrau")
check(ok == true, "wieder ausrüsten (wird gespeichert)")
message, ok = action(alice, "Equip", "W_Chrom")
check(ok == false and ProgressService.Get(alice).Equipped.Agent == "AS_Feldgrau", "Waffen-Skin ohne Waffe kommt nicht auf den Agenten")
message, ok = action(alice, "SellSkin", "AS_Feldgrau", 1)
check(ok == false and ProgressService.Owns(alice, "AS_Feldgrau"), "Agenten-Skin nicht verkaufbar: " .. tostring(message))

-- Battle Pass bis Stufe 20: Saison-Neon (Stufe 10) und Saison-Elite (Stufe 20) im Inventar
ProgressService.AddPassXP(alice, 20 * PassConfig.XPPerTier)
check(ProgressService.Owns(alice, "W_Saison") and ProgressService.Owns(alice, "W_Saison_Elite"), "Stufe 20 schaltet Saison-Elite frei")
check(not ProgressService.Owns(alice, "W_Goldrausch"), "Stufe 30 noch nicht")

-- Gespeichert ohne die entfernten Skins
SIM.Leave(alice)
step(3)
local saved = store.Data.u1
check(saved.Owned.A_Ghost_Nebel == nil and saved.Owned.A_Viper_Saison == nil and saved.Owned.GibtEsNicht == nil
	and saved.Owned.W_Lava == 2 and saved.Owned.W_Saison_Elite == 1, "gespeicherter Besitz ohne entfernte Skins")
check(saved.Equipped["A:Viper"] == nil and saved.Equipped["A:Ghost"] == nil and saved.MarketWatch.A_Ghost_Nebel == nil,
	"gespeichert ohne alte Agenten-Plätze und ohne entfernte Skins auf der Merkliste")
check(saved.Owned.AS_Feldgrau == 1 and saved.Equipped.Agent == "AS_Feldgrau", "Agenten-Skin gespeichert (Besitz und Platz)")

-- Neu laden: Agenten-Skin bleibt; ein Waffen-Skin auf dem Agenten-Platz fällt weg
store.Data.u1.Equipped.Agent = "AS_Feldgrau"
local alice2 = SIM.Join("Alice", 1)
step(2)
check(alice2 and ProgressService.Get(alice2).Equipped.Agent == "AS_Feldgrau", "Agenten-Skin nach dem Laden ausgerüstet")
SIM.Leave(alice2)
step(3)
store.Data.u1.Equipped.Agent = "W_Lava"
store.Data.u1.Equipped["W:Rifle"] = "AS_Feldgrau"
alice2 = SIM.Join("Alice", 1)
step(2)
check(ProgressService.Get(alice2).Equipped.Agent == nil and ProgressService.Get(alice2).Equipped["W:Rifle"] == nil,
	"falsche Art auf einem Platz fällt beim Laden weg")
SIM.Leave(alice2)
step(3)

-- Lobby (Client): SHOP mit Reiter AGENTEN-SKINS; LOADOUT nur mit Waffen;
-- BATTLE PASS zeigt auf Stufe 20 Saison-Elite
store.Data.u2 = { XP = {}, Coins = 1000, Rap = 0, Owned = { W_Lava = 1 }, Equipped = {} }
local bob = SIM.Join("Bob", 2)
step(2)
rawget(SIM.Players, "__props").LocalPlayer = bob
local LobbyPages = require("LobbyPages")
local function texts(root)
	local found, buy = {}, 0
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			found[d.Text] = true
		end
		-- Kaufen-Knöpfe der Karten im Raster (nicht der auf dem Angebot der Startseite)
		if d.Name == "BuyButton" and d:IsA("TextButton") and d.Parent and d.Parent.Parent and d.Parent.Parent.Name ~= "Home" then
			buy += 1
		end
	end
	return found, buy
end
local forSale = 0
local agentForSale = 0
for _, item in Cosmetics.Items do
	if Cosmetics.ForSale(item) then
		if item.Type == "Agent" then
			agentForSale += 1
		else
			forSale += 1
		end
	end
end
local shopPage = Instance.new("Frame")
LobbyPages.Shop(shopPage)
step(0.2)
-- Startseite: Angebot des Tages und Kacheln
local homeTexts = texts(shopPage)
local homeFrame = shopPage:FindFirstChild("Home")
check(homeFrame and homeFrame.Visible and homeTexts["ANGEBOT DES TAGES"] and homeTexts["ENDET IN"],
	"SHOP: Start mit Angebot des Tages")
for _, tab in { "Tile_WAFFEN-SKINS", "Tile_AGENTEN-SKINS", "Tile_ROBUX", "Tile_VERKAUFEN" } do
	check(homeFrame and homeFrame:FindFirstChild(tab), "SHOP: Kachel " .. tab)
end
local offerNow = require("ShopOffers").Daily(workspace:GetServerTimeNow())
check(offerNow and homeTexts[string.upper(offerNow.Item.Name)] and homeTexts["-" .. offerNow.Discount .. " %"],
	"SHOP: Startseite zeigt den Angebots-Skin mit Rabatt")
homeFrame:FindFirstChild("Tile_WAFFEN-SKINS").Activated:Fire()
step(0.2)
check(not homeFrame.Visible, "SHOP: Kachel öffnet den Reiter")
local shopTexts, buttons = texts(shopPage)
check(shopTexts["WAFFEN-SKINS"] and shopTexts.ROBUX and shopTexts.VERKAUFEN and shopTexts["AGENTEN-SKINS"] and shopTexts.START,
	"SHOP: Reiter mit START und AGENTEN-SKINS")
check(forSale >= 8 and buttons == forSale, "SHOP: eine Karte je kaufbarem Waffen-Skin (" .. buttons .. " von " .. forSale .. ")")
for _, d in shopPage:GetDescendants() do
	if d:IsA("TextButton") and d.Text == "AGENTEN-SKINS" then
		d.Activated:Fire()
	end
end
step(0.2)
local agentTexts, agentButtons = texts(shopPage)
check(agentButtons == agentForSale and agentTexts.FELDGRAU, "SHOP AGENTEN-SKINS: eine Karte je kaufbarem Agenten-Skin ("
	.. agentButtons .. " von " .. agentForSale .. ")")
local loadoutPage = Instance.new("Frame")
LobbyPages.Loadout(loadoutPage, function() end)
step(0.2)
local loadoutTexts = texts(loadoutPage)
check(loadoutTexts.WAFFEN and loadoutTexts.SKINS and not loadoutTexts.AGENTEN, "LOADOUT: nur Waffen, kein Reiter AGENTEN")
for _, agent in AgentConfig.Agents do
	check(not loadoutTexts[string.upper(agent.Name)], "LOADOUT: kein Agent in der Liste (" .. agent.Name .. ")")
end
local passPage = Instance.new("Frame")
LobbyPages.Pass(passPage)
step(0.2)
local passTexts = texts(passPage)
check(passTexts["SAISON-ELITE"] and not passTexts["SAISON-AGENTIN"], "BATTLE PASS: Stufe 20 zeigt Saison-Elite")

if failures == 0 then
	print("Skins: nur noch Waffen-Skins, alles in Ordnung")
end
