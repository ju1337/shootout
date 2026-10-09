-- DayCycle (ModuleScript, Server und Client)
-- Tag und Nacht der offenen Welt (EXTINCTION). Die Uhrzeit hängt nur an der Serverzeit (workspace:GetServerTimeNow()),
-- darum sehen alle Spieler dieselbe Tageszeit, ohne dass etwas übertragen wird. Werte in ExtinctionConfig.Day.
--   Clock(serverTime)   Uhrzeit 0..24 (wie Lighting.ClockTime)
--   Darkness(clock)     0 = heller Tag, 1 = tiefe Nacht, dazwischen Dämmerung
--   IsNight(clock)      Darkness >= 0,5 (nachts mehr Zombies, siehe ZombieService)
--   IsBloodMoon(t)      läuft gerade das Blutmond-Ereignis? (BloodMoonService, Attribute an ReplicatedStorage)
--   IsStorm(t)          läuft gerade die Sturmnacht? (StormService); StormFactor, StormLeft, StormPvPPaused
--   Label(clock)        "14:20"
--   Fog(t)              Nebel 0..1 (Admin: Attribut "FogOverride" legt ihn fest)
--   SetClock(hour)      (nur Server, Admin) springt zur Uhrzeit: Attribut "DayOffset" (Sekunden) an ReplicatedStorage,
--                       das alle Berechnungen zur Serverzeit addieren

local ExtinctionConfig = require(script.Parent.ExtinctionConfig)

local DayCycle = {}

local D = ExtinctionConfig.Day
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Serverzeit plus Verschiebung durch den Admin-Knopf (Tag/Nacht)
local function shifted(serverTime)
	return (serverTime or 0) + (tonumber(ReplicatedStorage:GetAttribute("DayOffset")) or 0)
end

function DayCycle.Clock(serverTime)
	if D.Fixed then
		return D.Fixed -- feste Uhrzeit (Tests)
	end
	return (D.StartHour + shifted(serverTime) / D.Length * 24) % 24
end

-- Uhrzeit (0..24) ab jetzt erzwingen; der Tag läuft danach normal weiter
function DayCycle.SetClock(hour, serverTime)
	serverTime = serverTime or workspace:GetServerTimeNow()
	local offset = ((hour - D.StartHour) / 24 * D.Length - serverTime) % D.Length
	ReplicatedStorage:SetAttribute("DayOffset", offset)
	return offset
end

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

function DayCycle.Darkness(clock)
	local dusk = D.Dusk -- Dauer der Dämmerung in Stunden
	if clock >= D.NightFrom or clock < D.NightTo then
		-- Nacht; am Anfang (Abenddämmerung) und Ende (Morgengrauen) weich
		local sinceDusk = (clock - D.NightFrom) % 24
		local untilDawn = (D.NightTo - clock) % 24
		return smooth(math.min(sinceDusk, untilDawn) / dusk * 0.5 + 0.5)
	end
	local afterDawn = clock - D.NightTo
	local beforeDusk = D.NightFrom - clock
	return smooth(0.5 - math.min(afterDawn, beforeDusk) / dusk * 0.5)
end

function DayCycle.IsNight(clock)
	return DayCycle.Darkness(clock) >= 0.5
end

-- Nummer des Tages (der Abend und die folgende Nacht gehören zum selben Tag)
function DayCycle.DayIndex(serverTime)
	local hours = D.StartHour + shifted(serverTime) / D.Length * 24 - D.NightTo
	return math.floor(hours / 24)
end

-- Blutmond: ein Ereignis (BloodMoonService), das der Server mit den Attributen BloodMoonStart / BloodMoonEnd (Serverzeit)
-- an ReplicatedStorage ankündigt – alle sehen dieselbe Zeit
function DayCycle.IsBloodMoon(serverTime)
	if D.FixedBloodMoon ~= nil then
		return D.FixedBloodMoon -- Tests
	end
	local start = tonumber(ReplicatedStorage:GetAttribute("BloodMoonStart"))
	local finish = tonumber(ReplicatedStorage:GetAttribute("BloodMoonEnd"))
	local t = serverTime or 0
	return start ~= nil and finish ~= nil and t >= start and t < finish
end

-- Sekunden bis zum Ende des Blutmonds (0, wenn keiner ist)
function DayCycle.BloodMoonLeft(serverTime)
	local finish = tonumber(ReplicatedStorage:GetAttribute("BloodMoonEnd"))
	if not finish or not DayCycle.IsBloodMoon(serverTime) then
		return 0
	end
	return math.max(0, finish - (serverTime or 0))
end

-- Sturmnacht: Ereignis (StormService) mit den Attributen StormStart / StormEnd (Serverzeit) an ReplicatedStorage
function DayCycle.IsStorm(serverTime)
	local start = tonumber(ReplicatedStorage:GetAttribute("StormStart"))
	local finish = tonumber(ReplicatedStorage:GetAttribute("StormEnd"))
	local t = serverTime or 0
	return start ~= nil and finish ~= nil and t >= start and t < finish
end

-- Sekunden bis zum Ende des Sturms (0, wenn keiner ist)
function DayCycle.StormLeft(serverTime)
	local finish = tonumber(ReplicatedStorage:GetAttribute("StormEnd"))
	if not finish or not DayCycle.IsStorm(serverTime) then
		return 0
	end
	return math.max(0, finish - (serverTime or 0))
end

-- Stärke des Sturms 0..1: zieht in FADE Sekunden auf und genauso wieder ab (Licht, Regen, Wind)
local STORM_FADE = 25
function DayCycle.StormFactor(serverTime)
	local start = tonumber(ReplicatedStorage:GetAttribute("StormStart"))
	local finish = tonumber(ReplicatedStorage:GetAttribute("StormEnd"))
	local t = serverTime or 0
	if not start or not finish or t < start or t >= finish + STORM_FADE then
		return 0
	end
	return math.clamp(math.min((t - start) / STORM_FADE, (finish + STORM_FADE - t) / STORM_FADE), 0, 1)
end

-- PvP ausgesetzt? Während des Sturms und Storm.Grace Sekunden danach. Gibt außerdem die Serverzeit zurück, ab der es
-- wieder gilt.
function DayCycle.StormPvPPaused(serverTime)
	local start = tonumber(ReplicatedStorage:GetAttribute("StormStart"))
	local finish = tonumber(ReplicatedStorage:GetAttribute("StormEnd"))
	local t = serverTime or 0
	if not start or not finish or t < start then
		return false, nil
	end
	local resume = finish + ExtinctionConfig.Storm.Grace
	return t < resume, resume
end

-- Nebel 0..1 (an manchen Tagen morgens). Der Admin kann ihn festlegen: Attribut "FogOverride" (0..1) an
-- ReplicatedStorage, ohne Attribut wieder automatisch.
function DayCycle.Fog(serverTime)
	local override = tonumber(ReplicatedStorage:GetAttribute("FogOverride"))
	if override then
		return math.clamp(override, 0, 1)
	end
	local clock = DayCycle.Clock(serverTime)
	if clock < D.FogFrom or clock > D.FogTo then
		return 0
	end
	local day = math.floor((D.StartHour + shifted(serverTime) / D.Length * 24) / 24)
	if ((day * 7919 + 13) % 100) / 100 >= D.FogChance then
		return 0
	end
	local t = (clock - D.FogFrom) / (D.FogTo - D.FogFrom)
	return math.sin(t * math.pi) ^ 0.6
end

function DayCycle.Label(clock)
	local hours = math.floor(clock)
	local minutes = math.floor((clock - hours) * 60 + 1e-6)
	return string.format("%02d:%02d", hours, minutes)
end

return DayCycle
