-- StaffConfig (ModuleScript, Server und Client)
-- Team-Ränge mit Präfix im Chat und auf dem Namensschild. Spieler-Attribut "StaffRank" = Id (vom StaffService).
-- Vergabe (höchster gewinnt):
--   * Besitzer des Spiels (bzw. Gruppenrang 255) -> Owner, Gruppenrang 254 -> Developer
--   * fest im Code: StaffConfig.Members unten
--   * im Spiel: Admin-Panel → SPIELER → Rang (gespeichert im DataStore, gilt auf allen Servern)
--   * VIP automatisch mit dem Gamepass VIP
-- Rechte: Admin = ganzes Admin-Panel; Kick / BanDays (längste Sperre in Tagen, 0 = auch dauerhaft) / Unban = Moderation
-- im Reiter SPIELER; Assign = bis zu welcher Stärke man Ränge vergeben darf. Niemand darf Spieler mit gleich hohem oder
-- höherem Rang kicken, sperren oder umstufen.

local StaffConfig = {}

-- Reihenfolge = Stärke (oben am stärksten)
StaffConfig.Ranks = {
	{ Id = "Owner", Name = "OWNER", Icon = "👑", Color = Color3.fromRGB(255, 59, 92), Power = 100,
		Admin = true, Kick = true, BanDays = 0, Unban = true, Assign = 90 },
	{ Id = "Developer", Name = "DEV", Icon = "⚙", Color = Color3.fromRGB(0, 210, 255), Power = 90,
		Admin = true, Kick = true, BanDays = 0, Unban = true, Assign = 70 },
	{ Id = "LeadMod", Name = "LEAD MOD", Icon = "⚔", Color = Color3.fromRGB(255, 138, 31), Power = 70,
		Kick = true, BanDays = 0, Unban = true },
	{ Id = "Mod", Name = "MOD", Icon = "🛡", Color = Color3.fromRGB(61, 220, 132), Power = 60,
		Kick = true, BanDays = 7 },
	{ Id = "Helper", Name = "HELPER", Icon = "✚", Color = Color3.fromRGB(127, 178, 255), Power = 40,
		Kick = true },
	{ Id = "Creator", Name = "CREATOR", Icon = "🎬", Color = Color3.fromRGB(190, 100, 255), Power = 20 },
	{ Id = "VIP", Name = "VIP", Icon = "⭐", Color = Color3.fromRGB(255, 210, 74), Power = 10 },
}

-- Feste Ränge: [Roblox-UserId] = Rang-Id, z.B. [12345678] = "Mod"
StaffConfig.Members = {
}

local byId = {}
for _, rank in StaffConfig.Ranks do
	byId[rank.Id] = rank
end

function StaffConfig.Get(id)
	return id and byId[id] or nil
end

-- Rang eines Spielers (über das Attribut) oder nil
function StaffConfig.Of(player)
	return player and StaffConfig.Get(player:GetAttribute("StaffRank")) or nil
end

function StaffConfig.Power(player)
	local rank = StaffConfig.Of(player)
	return rank and rank.Power or 0
end

-- Darf actor gegen target vorgehen (Kick, Sperre, Rang ändern)? Nur gegen schwächere Ränge.
function StaffConfig.Outranks(actor, targetPower)
	return StaffConfig.Power(actor) > (targetPower or 0)
end

-- Präfix als RichText, z.B. <font color="#FF3B5C"><b>👑 OWNER</b></font>
function StaffConfig.Prefix(rank, size)
	if not rank then
		return ""
	end
	local text = "<b>" .. rank.Icon .. " " .. rank.Name .. "</b>"
	if size then
		text = '<font size="' .. size .. '">' .. text .. "</font>"
	end
	return '<font color="#' .. rank.Color:ToHex() .. '">' .. text .. "</font>"
end

return StaffConfig
