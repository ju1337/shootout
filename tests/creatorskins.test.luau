-- Creator-Skins: frei für Team-Rang CREATOR und höher (nicht für VIP/Booster), nicht im Shop, nicht in Kisten, nicht
-- handelbar; stehen nicht im Spielstand, nur im Attribut Owned; Rang weg = gesperrt (ausgerüstet bleibt gespeichert,
-- die Waffe zeigt den Standard), Rang zurück = wieder da
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
local Cosmetics = require("Cosmetics")
local RapConfig = require("RapConfig")
local CrateConfig = require("CrateConfig")
local Remotes = require("Remotes")
local ProgressService = require("ProgressService")
local ShopService = require("ShopService")
ProgressService.Init()
ShopService.Init()

local ids = Cosmetics.CreatorItems()
check(#ids >= 1, "es gibt Creator-Skins")
local inPool = {}
for _, item in CrateConfig.Pool(CrateConfig.Get("Weapon")) do
	inPool[item.Id] = true
end
for _, id in ids do
	local item = Cosmetics.Get(id)
	check(not Cosmetics.ForSale(item), id .. ": nicht im Shop")
	check(not RapConfig.Tradeable(id), id .. ": nicht handelbar")
	check(not inPool[id], id .. ": nicht in der Kiste")
	if item.Type == "Agent" then
		check(not Cosmetics.FitsWeapon(item, "Pistol"), id .. ": Agenten-Skin, auf keine Waffe")
	else
		check(item.Weapon == nil and Cosmetics.FitsWeapon(item, "Pistol") and Cosmetics.FitsWeapon(item, "LMG"), id .. ": alle Waffen")
	end
end

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
store.Data.u2 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local creator, vip = SIM.Join("Streamerin"), SIM.Join("Fan")
step(2)
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

check(Cosmetics.GetOwned(creator).W_Creator == nil, "ohne Rang nichts")
creator:SetAttribute("StaffRank", "Creator")
vip:SetAttribute("StaffRank", "Booster")
step(0.2)
check(Cosmetics.GetOwned(creator).W_Creator ~= nil and Cosmetics.GetOwned(creator).W_CreatorLive ~= nil, "Rang CREATOR: Skins da")
check(Cosmetics.GetOwned(vip).W_Creator == nil, "BOOSTER bekommt sie nicht")
check(ProgressService.Get(creator).Owned.W_Creator == nil, "nicht im Spielstand")
check(creator:GetAttribute("RapValue") == 0, "zählen nicht zum RAP-Wert")
local message, ok = action(creator, "Equip", "W_Creator", "Pistol")
check(ok == true, "ausrüsten: " .. tostring(message))
check(Cosmetics.WeaponSkin(creator, nil, "Pistol").Id == "W_Creator", "Pistole zeigt den Creator-Skin")
message, ok = action(vip, "Equip", "W_Creator", "Pistol")
check(ok == false, "ohne Rang nicht ausrüstbar")

-- Rang weg: gesperrt, aber gespeichert
creator:SetAttribute("StaffRank", nil)
step(0.2)
check(Cosmetics.GetOwned(creator).W_Creator == nil, "Rang weg: nicht mehr im Besitz")
check(Cosmetics.WeaponSkin(creator, nil, "Pistol") == nil, "Waffe zeigt den Standard")
check(ProgressService.Get(creator).Equipped["W:Pistol"] == "W_Creator", "ausgerüstet bleibt gespeichert")
-- höherer Rang zählt auch
creator:SetAttribute("StaffRank", "Mod")
step(0.2)
check(Cosmetics.WeaponSkin(creator, nil, "Pistol").Id == "W_Creator", "Rang zurück (MOD): Skin wieder da")

if failures > 0 then
	error(failures .. " Fehler")
end
print("creatorskins: alles ok")
