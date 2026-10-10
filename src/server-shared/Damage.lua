-- Damage (ModuleScript, nur Server)
-- Zentrale Stelle für Schaden an Spielern und Bots (Waffen der Spieler und der Bots).
-- Achtet auf Schutzschilde, die Safe Zone (Attribut "SafeZone"), Rüstung (Attribut "Armor"), Helm/Weste gepanzerter Zombies
-- (ZHelmet / ZVest) und schlägt im Drop-Modus
-- nieder statt zu töten. Lädt die Ultimate des angreifenden Spielers (Attribut "UltCharge", nicht in der offenen Welt).

local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared").Remotes)
local AgentConfig = require(ReplicatedStorage:WaitForChild("Shared").AgentConfig)
local Modes = require(ReplicatedStorage:WaitForChild("Shared").Modes)
local ExtinctionConfig = require(ReplicatedStorage:WaitForChild("Shared").ExtinctionConfig)

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

-- Letzten Angreifer vergessen (Schaden ohne Verursacher, z.B. Blitz: sonst nennt die Todesanzeige einen alten Treffer)
function Damage.Forget(model)
	lastHit[model] = nil
end

-- Schaden pro Spieler am Charakter (für Assists): [model] = { [Player] = Schaden }
local contributors = setmetatable({}, { __mode = "k" })

function Damage.Contributors(model)
	return contributors[model] or {}
end

-- Ultimate des angreifenden Spielers aufladen (Schaden, Kill/Niederschlag). Nicht in der offenen Welt (keine Ultimate).
local function chargeUltimate(attacker, model, dealt, finished)
	local player = attacker and attacker.Player
	if not player or dealt <= 0 or player.Character == model then
		return -- kein Aufladen an sich selbst (z.B. eigene Granate)
	end
	if Modes.IsSurvival(player:GetAttribute("Mode")) then
		return
	end
	local ult = AgentConfig.Ultimate
	local gain = dealt * ult.ChargePerDamage + (finished and ult.ChargePerKill or 0)
	player:SetAttribute("UltCharge", math.min(100, (player:GetAttribute("UltCharge") or 0) + gain))
end

-- Schaden anwenden. attacker = { Player = ..., BotName = ..., Weapon = ..., Headshot = ... }
-- Gibt zurück: tatsächlicher Schaden, getötet?, niedergeschlagen?, davon von der Rüstung geschluckt
function Damage.Apply(model, humanoid, amount, attacker)
	-- Schutzschild oder Safe Zone der offenen Welt (Attribut "SafeZone" am Charakter): kein Schaden
	local noclip = Players:GetPlayerFromCharacter(model)
	if humanoid.Health <= 0 or model:FindFirstChildOfClass("ForceField") or model:GetAttribute("SafeZone")
		or (noclip and (noclip:GetAttribute("Noclip") or noclip:GetAttribute("AdminGod"))) then -- Admin: Noclip oder Gottmodus
		return 0, false, false, 0
	end
	-- Spawnschutz der offenen Welt (ProtectedUntil): Geschützte nehmen keinen Schaden und teilen keinen aus
	local now = workspace:GetServerTimeNow()
	if (noclip and (noclip:GetAttribute("ProtectedUntil") or 0) > now)
		or (attacker and attacker.Player and (attacker.Player:GetAttribute("ProtectedUntil") or 0) > now) then
		return 0, false, false, 0
	end
	-- Angreifer inzwischen in der Safe Zone (Granate/Molotow draußen geworfen, dann hineingegangen): kein Schaden
	if attacker and attacker.Player and attacker.Player ~= Players:GetPlayerFromCharacter(model)
		and attacker.Player:GetAttribute("InSafeZone") == true then
		return 0, false, false, 0
	end
	-- Angreifer merken (Spieler-Charakter oder Bot-Modell)
	local attackerModel = attacker and (attacker.Model or (attacker.Player and attacker.Player.Character))
	if attackerModel then
		lastHit[model] = {
			Model = attackerModel,
			Name = attacker.Player and attacker.Player.Name or attacker.BotName or attackerModel.Name,
			Weapon = attacker.Weapon,
			Player = attacker.Player, -- auch nach dem Respawn des Schützen (Molotow brennt nach, Zombie stirbt später)
		}
	end
	model:SetAttribute("LastDamaged", os.clock())
	-- Kampf in der offenen Welt (Spieler gegen Spieler): beide kommen eine Weile nicht in die Safe Zone
	local hitPlayer = Players:GetPlayerFromCharacter(model)
	local shooter = attacker and attacker.Player
	if hitPlayer and shooter and shooter ~= hitPlayer and hitPlayer:GetAttribute("Mode") == "Extinction" then
		local untilTime = workspace:GetServerTimeNow() + ExtinctionConfig.CombatTime
		hitPlayer:SetAttribute("CombatUntil", untilTime)
		shooter:SetAttribute("CombatUntil", untilTime)
	end
	-- Getroffener Spieler sieht, aus welcher Richtung (Treffer-Anzeige im HUD)
	local victim = Players:GetPlayerFromCharacter(model)
	local attackerRoot = attackerModel and attackerModel:FindFirstChild("HumanoidRootPart")
	if victim and attackerRoot and attackerModel ~= model then
		Remotes.DamageFrom:FireClient(victim, attackerRoot.Position, amount)
	end

	-- Gepanzerte Zombies (Attribute ZHelmet / ZVest): Helm schluckt einen Teil der Kopftreffer, Weste den der übrigen
	local absorbed = 0
	local plating = attacker and attacker.Headshot and "ZHelmet" or "ZVest"
	local plate = model:GetAttribute(plating)
	if plate and plate > 0 then
		local A = ExtinctionConfig.ArmoredZombies
		local share = plating == "ZHelmet" and A.HelmetFactor or A.VestFactor
		absorbed = math.min(plate, amount * share)
		model:SetAttribute(plating, plate - absorbed)
		amount -= absorbed
	end

	-- Rüstung schluckt zuerst
	local armor = model:GetAttribute("Armor") or 0
	if armor > 0 then
		local taken = math.min(armor, amount)
		model:SetAttribute("Armor", armor - taken)
		absorbed += taken
		amount -= taken
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
