-- Skins: nur noch Waffen-Skins. Keine Agenten-Skins in Cosmetics, RAP-Werten und Kisten; Agenten zeigen immer ihren
-- Standard-Look (AgentColors = Agentenfarbe); Battle-Pass-Stufe 20 gibt den Waffen-Skin Saison-Elite;
-- alte Spielstände verlieren beim Laden entfernte Skins (Besitz, Ausrüstung "A:<Agent>", Merkliste); Agenten-Skins
-- kaufen, ausrüsten oder ablegen geht nicht mehr, Waffen-Skins wie bisher
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

-- Nur Waffen-Skins: keine Agenten-Skins mehr in Cosmetics, RAP-Werten und Kisten
local REMOVED = { "A_Viper_Nacht", "A_Viper_Gift", "A_Bastion_Stahl", "A_Bastion_Royal", "A_Mender_Feld", "A_Mender_Neon",
	"A_Hawk_Wueste", "A_Hawk_Phantom", "A_Viper_Saison", "A_Ghost_Schatten", "A_Ghost_Nebel", "A_Blaze_Inferno",
	"A_Blaze_Asche", "A_Aegis_Bollwerk", "A_Aegis_Sanitaet", "A_Trapper_Wildnis", "A_Trapper_Jaeger",
	"A_Volt_Hochspannung", "A_Volt_Kupfer" }
for _, item in Cosmetics.Items do
	check(item.Type == "Weapon", "nur Waffen-Skins: " .. item.Id .. " ist " .. tostring(item.Type))
	check(item.Agent == nil and item.Primary == nil and item.Accent == nil, "keine Agenten-Farben an " .. item.Id)
	check(string.sub(item.Id, 1, 2) ~= "A_", "keine Agenten-Skin-Id: " .. item.Id)
end
check(#Cosmetics.List("Agent") == 0, "Cosmetics.List: keine Agenten-Skins")
for _, id in REMOVED do
	check(Cosmetics.Get(id) == nil and RapConfig.Values[id] == nil, id .. " ist entfernt (Skin und RAP-Wert)")
end
for id in RapConfig.Values do
	check(Cosmetics.Get(id) ~= nil and Cosmetics.Get(id).Type == "Weapon", "RAP-Wert nur für Waffen-Skins: " .. id)
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
check(ok == true and ProgressService.Owns(alice, "W_Chrom") and alice:GetAttribute("Coins") == 5000 - Cosmetics.Get("W_Chrom").Price,
	"Waffen-Skin kaufen: " .. tostring(message))

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
	"gespeichert ohne Agenten-Plätze und ohne entfernte Skins auf der Merkliste")

-- Lobby (Client): SHOP ohne Reiter AGENTEN-SKINS, nur Waffen-Skins zu kaufen; LOADOUT nur mit Waffen;
-- BATTLE PASS zeigt auf Stufe 20 Saison-Elite
store.Data.u2 = { XP = {}, Coins = 1000, Rap = 0, Owned = { W_Lava = 1 }, Equipped = {} }
local bob = SIM.Join("Bob")
step(2)
rawget(SIM.Players, "__props").LocalPlayer = bob
local LobbyPages = require("LobbyPages")
local function texts(root)
	local found, buy = {}, 0
	for _, d in root:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			found[d.Text] = true
			if string.sub(d.Text, 1, 8) == "KAUFEN  " or d.Text == "IM BESITZ" then
				buy += 1
			end
		end
	end
	return found, buy
end
local forSale = 0
for _, item in Cosmetics.Items do
	if Cosmetics.ForSale(item) then
		forSale += 1
	end
end
local shopPage = Instance.new("Frame")
LobbyPages.Shop(shopPage)
step(0.2)
local shopTexts, buttons = texts(shopPage)
check(shopTexts["WAFFEN-SKINS"] and shopTexts.ROBUX and shopTexts.VERKAUFEN and not shopTexts["AGENTEN-SKINS"],
	"SHOP: Reiter ohne AGENTEN-SKINS")
check(forSale >= 8 and buttons == forSale, "SHOP: eine Karte je kaufbarem Waffen-Skin (" .. buttons .. " von " .. forSale .. ")")
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
