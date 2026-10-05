-- Damage (ModuleScript, nur Server)
-- Zentrale Stelle für Schaden an Spielern und Bots (Waffen der Spieler und der Bots).
-- Achtet auf Schutzschilde, die Safe Zone (Attribut "SafeZone") und Rüstung (Attribut "Armor") und schlägt im Drop-Modus
-- nieder statt zu töten. Lädt die Ultimate des angreifenden Spielers (Attribut "UltCharge").

local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local AgentConfig = require(ReplicatedStorage:WaitForChild("Shared").AgentConfig)

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

-- Schaden pro Spieler am Charakter (für Assists): [model] = { [Player] = Schaden }
local contributors = setmetatable({}, { __mode = "k" })

function Damage.Contributors(model)
	return contributors[model] or {}
end

-- Ultimate des angreifenden Spielers aufladen (Schaden, Kill/Niederschlag)
local function chargeUltimate(attacker, model, dealt, finished)
	local player = attacker and attacker.Player
	if not player or dealt <= 0 or player.Character == model then
		return -- kein Aufladen an sich selbst (z.B. eigene Granate)
	end
	local ult = AgentConfig.Ultimate
	local gain = dealt * ult.ChargePerDamage + (finished and ult.ChargePerKill or 0)
	player:SetAttribute("UltCharge", math.min(100, (player:GetAttribute("UltCharge") or 0) + gain))
end

-- Schaden anwenden. attacker = { Player = ..., BotName = ..., Weapon = ..., Headshot = ... }
-- Gibt zurück: tatsächlicher Schaden, getötet?, niedergeschlagen?, davon von der Rüstung geschluckt
function Damage.Apply(model, humanoid, amount, attacker)
	-- Schutzschild oder Safe Zone der offenen Welt (Attribut "SafeZone" am Charakter): kein Schaden
	if humanoid.Health <= 0 or model:FindFirstChildOfClass("ForceField") or model:GetAttribute("SafeZone") then
		return 0, false, false, 0
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
	-- Getroffener Spieler sieht, aus welcher Richtung (Treffer-Anzeige im HUD)
	local victim = Players:GetPlayerFromCharacter(model)
	local attackerRoot = attackerModel and attackerModel:FindFirstChild("HumanoidRootPart")
	if victim and attackerRoot and attackerModel ~= model then
		Remotes.DamageFrom:FireClient(victim, attackerRoot.Position, amount)
	end

	-- Rüstung schluckt zuerst
	local absorbed = 0
	local armor = model:GetAttribute("Armor") or 0
	if armor > 0 then
		absorbed = math.min(armor, amount)
		model:SetAttribute("Armor", armor - absorbed)
		amount -= absorbed
		if amount <= 0 then
			chargeUltimate(attacker, model, absorbed, false)
			return absorbed, false, false, absorbed
		end
	end

	local before = humanoid.Health
	if before - amount <= 0 and DownedService.CanBeDowned(model) then
		DownedService.Down(model, humanoid, attacker)
		chargeUltimate(attacker, model, absorbed + before, true)
		return absorbed + before, false, true, absorbed
	end
	humanoid.Health = math.max(0, before - amount)
	local dealt = absorbed + before - humanoid.Health
	if attacker and attacker.Player then
		contributors[model] = contributors[model] or {}
		contributors[model][attacker.Player] = (contributors[model][attacker.Player] or 0) + dealt
	end
	chargeUltimate(attacker, model, dealt, humanoid.Health <= 0)
	return dealt, humanoid.Health <= 0, false, absorbed
end

return Damage
