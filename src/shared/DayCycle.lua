-- DayCycle (ModuleScript, Server und Client)
-- Tag und Nacht der offenen Welt (EXTINCTION). Die Uhrzeit hängt nur an der Serverzeit (workspace:GetServerTimeNow()),
-- darum sehen alle Spieler dieselbe Tageszeit, ohne dass etwas übertragen wird. Werte in ExtinctionConfig.Day.
--   Clock(serverTime)   Uhrzeit 0..24 (wie Lighting.ClockTime)
--   Darkness(clock)     0 = heller Tag, 1 = tiefe Nacht, dazwischen Dämmerung
--   IsNight(clock)      Darkness >= 0,5 (nachts mehr Zombies, siehe ZombieService)
--   Label(clock)        "14:20"
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

-- Blutmond: jede BloodMoonEvery-te Nacht
function DayCycle.IsBloodMoon(serverTime)
	if D.FixedBloodMoon ~= nil then
		return D.FixedBloodMoon -- Tests
	end
	local clock = DayCycle.Clock(serverTime)
	return DayCycle.IsNight(clock) and DayCycle.DayIndex(serverTime) % D.BloodMoonEvery == D.BloodMoonEvery - 1
end

-- Nebel 0..1 (an manchen Tagen morgens)
function DayCycle.Fog(serverTime)
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
