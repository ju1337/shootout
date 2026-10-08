-- KitConfig (ModuleScript, Server und Client)
-- Kits beim Kit-Händler am Spawn im Camp (Punkt KitConfig.Point in Stands, KitService). Jedes Kit hat eine Wartezeit
-- (Cooldown, Sekunden) und optional einen Gamepass aus RobuxConfig (Pass). Items = { { Item-Id, Anzahl } }; ein Kit
-- ohne Items wird als COMING SOON angezeigt und kann nicht abgeholt werden. Abgeholt: Profil Kits[Id] = os.time().

local KitConfig = {}

KitConfig.Point = "Kits"

KitConfig.List = {
	{ Id = "Starter", Name = "STARTER KIT", Description = "Pistol, SMG, ammo, bandages, a vest and a bike",
		Cooldown = 30 * 60, Color = Color3.fromRGB(96, 200, 120),
		Items = { { "Pistol", 1 }, { "SMG", 1 }, { "Ammo_9mm", 150 }, { "Bandage", 5 }, { "Vest", 1 }, { "V_Bicycle", 1 } } },
	{ Id = "Daily", Name = "DAILY KIT", Description = "Coming soon", Cooldown = 24 * 3600,
		Color = Color3.fromRGB(110, 176, 230), Items = {} },
	{ Id = "Weekly", Name = "WEEKLY KIT", Description = "Coming soon", Cooldown = 7 * 24 * 3600,
		Color = Color3.fromRGB(200, 150, 230), Items = {} },
	{ Id = "VIP", Name = "VIP KIT", Description = "Coming soon", Pass = "VIP", Cooldown = 24 * 3600,
		Color = Color3.fromRGB(230, 186, 70), Items = {} },
}

function KitConfig.Get(id)
	for _, kit in KitConfig.List do
		if kit.Id == id then
			return kit
		end
	end
	return nil
end

-- Sekunden bis zum nächsten Abholen (0 = bereit); claimed = Profil-/Attribut-Tabelle Kits
function KitConfig.Remaining(kit, claimed, now)
	local last = type(claimed) == "table" and tonumber(claimed[kit.Id]) or 0
	return math.max(0, last + kit.Cooldown - now)
end

-- Wartezeit als Text: "2D 4H", "3H 12M", "12:05"
function KitConfig.FormatTime(seconds)
	seconds = math.ceil(seconds)
	if seconds >= 86400 then
		return string.format("%dD %dH", seconds // 86400, seconds % 86400 // 3600)
	elseif seconds >= 3600 then
		return string.format("%dH %dM", seconds // 3600, seconds % 3600 // 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return KitConfig
