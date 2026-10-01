-- Damage (ModuleScript, nur Server)
-- Zentrale Stelle für Schaden an Spielern und Bots (Waffen der Spieler und der Bots).
-- Achtet auf Schutzschilde und schlägt im Drop-Modus nieder statt zu töten.

local ServerStorage = game:GetService("ServerStorage")

local DownedService = require(ServerStorage:WaitForChild("ServerShared").DownedService)

local Damage = {}

-- Schaden anwenden. attacker = { Player = ..., BotName = ..., Weapon = ..., Headshot = ... }
-- Gibt zurück: tatsächlicher Schaden, getötet?, niedergeschlagen?
function Damage.Apply(model, humanoid, amount, attacker)
	if humanoid.Health <= 0 or model:FindFirstChildOfClass("ForceField") then
		return 0, false, false
	end
	local before = humanoid.Health
	if before - amount <= 0 and DownedService.CanBeDowned(model) then
		DownedService.Down(model, humanoid, attacker)
		return before, false, true
	end
	humanoid.Health = math.max(0, before - amount)
	return before - humanoid.Health, humanoid.Health <= 0, false
end

return Damage
