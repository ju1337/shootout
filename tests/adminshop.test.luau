-- Admin-Panel › SHOP: Angebot mit Skin, Rabatt und Dauer setzen, laufende Angebote sehen und beenden,
-- Angebot des Tages aus- und einschalten (AdminService -> ShopOfferService, Client-Seite AdminPanel)
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

local Remotes = require("Remotes")
local ShopOffers = require("ShopOffers")
local ProgressService = require("ProgressService")
local AdminService = require("AdminService")
local ShopOfferService = require("ShopOfferService")
ProgressService.Init()
AdminService.Init({ GetModule = function() return nil end, Join = function() end })
ShopOfferService.Init()

local admin = SIM.AddPlayer("Admin", 1)
local mod = SIM.AddPlayer("Mod", 2)
step(1)
admin:SetAttribute("IsAdmin", true)
admin:SetAttribute("StaffRank", "Developer")
mod:SetAttribute("IsMod", true)

-- Moderatoren dürfen keine Angebote setzen
Remotes.AdminAction.OnServerEvent:Fire(mod, "ShopOfferAdd", "W_Lava", { Discount = 50, Hours = 2 })
step(0.2)
check(#ShopOffers.Config().Offers == 0, "Moderator kann kein Angebot setzen")

-- Panel des Admins bauen
rawget(SIM.Players, "__props").LocalPlayer = admin
local playerGui = admin:FindFirstChild("PlayerGui") or Instance.new("PlayerGui", admin)
local AdminPanel = require("AdminPanel")
task.spawn(AdminPanel.Init)
step(1)
local gui = playerGui:FindFirstChild("AdminPanel")
check(gui ~= nil, "Panel gebaut")
local page = gui and gui:FindFirstChild("Page_Shop", true)
check(page ~= nil, "Seite SHOP vorhanden")
-- Knopf drücken; was das Panel an den Server schickt (AdminAction), kommt dort wie von admin an
local function click(text)
	for _, d in page:GetDescendants() do
		if d:IsA("TextButton") and d.Text == text then
			local before = #SIM.RemoteLog
			d.Activated:Fire()
			for i = before + 1, #SIM.RemoteLog do
				local entry = SIM.RemoteLog[i]
				if entry.Remote == "AdminAction" and entry.Player == "server" then
					Remotes.AdminAction.OnServerEvent:Fire(admin, table.unpack(entry.Args, 1, entry.Args.n))
				end
			end
			return true
		end
	end
	return false
end
local function has(text)
	for _, d in page:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and string.find(d.Text, text, 1, true) then
			return true
		end
	end
	return false
end
-- Panel öffnen (Knopf ADMIN (P)) und Kategorie SHOP wählen
for _, text in { "ADMIN (P)", "SHOP" } do
	for _, d in gui:GetDescendants() do
		if d:IsA("TextButton") and d.Text == text then
			d.Activated:Fire()
			break
		end
	end
end
step(0.5)
check(page.Visible, "Kategorie SHOP offen")
local lava = require("Cosmetics").Get("W_Lava")
check(click("LAVA  " .. lava.Price), "Skin-Knopf LAVA")
check(click("40 %"), "Rabatt-Knopf 40 %")
check(click("3 TAGE"), "Dauer-Knopf 3 TAGE")
check(click("HAUPTANGEBOT: NEIN"), "Hauptangebot umschalten")
check(has("LAVA  ·  " .. lava.Price .. " → " .. ShopOffers.Discounted(lava.Price, 40)), "Vorschau zeigt den neuen Preis")
check(click("ANGEBOT STARTEN"), "Starten-Knopf")
step(1.5)
local featured = ShopOffers.Featured(workspace:GetServerTimeNow())
check(featured and featured.Item == lava and featured.Discount == 40 and featured.Featured
	and math.abs(featured.EndsAt - workspace:GetServerTimeNow() - 72 * 3600) < 5, "Angebot läuft: Lava -40 %, 3 Tage, Hauptangebot")
-- Liste zeigt das Angebot (das Panel aktualisiert sie, solange SHOP offen ist), BEENDEN beendet es
check(has("HAUPTANGEBOT") and has("-40 %"), "laufendes Angebot in der Liste")
check(click("BEENDEN"), "BEENDEN-Knopf")
step(1.5)
check(#ShopOffers.Config().Offers == 0, "Angebot beendet")
check(click("ANGEBOT DES TAGES: AN"), "Umschalter Angebot des Tages")
step(1.5)
check(not ShopOffers.Config().AutoDaily and has("ANGEBOT DES TAGES: AUS"), "Angebot des Tages aus")

if failures > 0 then
	error(failures .. " Fehler")
end
print("adminshop: alles ok")
