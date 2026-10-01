-- Damage (ModuleScript, nur Server)
-- Zentrale Stelle für Schaden an Spielern und Bots (Waffen der Spieler und der Bots).
-- Achtet auf Schutzschilde und Rüstung (Attribut "Armor") und schlägt im Drop-Modus
-- nieder statt zu töten.

local ServerStorage = game:GetService("ServerStorage")

local DownedService = require(ServerStorage:WaitForChild("ServerShared").DownedService)

local Damage = {}

-- Letzter Treffer pro Charakter: { Model, Name, Weapon } – für "Racheblick" und die Todesanzeige
local lastHit = setmetatable({}, { __mode = "k" })

function Damage.LastAttacker(model)
	return lastHit[model] and lastHit[model].Model
end

function Damage.LastHit(model)
	return lastHit[model]
end

-- Schaden anwenden. attacker = { Player = ..., BotName = ..., Weapon = ..., Headshot = ... }
-- Gibt zurück: tatsächlicher Schaden, getötet?, niedergeschlagen?
function Damage.Apply(model, humanoid, amount, attacker)
	if humanoid.Health <= 0 or model:FindFirstChildOfClass("ForceField") then
		return 0, false, false
	end
	-- Angreifer merken (Spieler-Charakter oder Bot-Modell)
	local attackerModel = attacker and (attacker.Model or (attacker.Player and attacker.Player.Character))
	if attackerModel then
		lastHit[model] = {
			Model = attackerModel,
			Name = attacker.Player and attacker.Player.Name or attacker.BotName or attackerModel.Name,
			Weapon = attacker.Weapon,
		}
	end
	model:SetAttribute("LastDamaged", os.clock())

	-- Rüstung schluckt zuerst
	local absorbed = 0
	local armor = model:GetAttribute("Armor") or 0
	if armor > 0 then
		absorbed = math.min(armor, amount)
		model:SetAttribute("Armor", armor - absorbed)
		amount -= absorbed
		if amount <= 0 then
			return absorbed, false, false
		end
	end

	local before = humanoid.Health
	if before - amount <= 0 and DownedService.CanBeDowned(model) then
		DownedService.Down(model, humanoid, attacker)
		return absorbed + before, false, true
	end
	humanoid.Health = math.max(0, before - amount)
	return absorbed + before - humanoid.Health, humanoid.Health <= 0, false
end

return Damage
