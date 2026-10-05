-- DayCycle (ModuleScript, Server und Client)
-- Tag und Nacht der offenen Welt (EXTINCTION). Die Uhrzeit hängt nur an der Serverzeit (workspace:GetServerTimeNow()),
-- darum sehen alle Spieler dieselbe Tageszeit, ohne dass etwas übertragen wird. Werte in ExtinctionConfig.Day.
--   Clock(serverTime)   Uhrzeit 0..24 (wie Lighting.ClockTime)
--   Darkness(clock)     0 = heller Tag, 1 = tiefe Nacht, dazwischen Dämmerung
--   IsNight(clock)      Darkness >= 0,5 (nachts mehr Zombies, siehe ZombieService)
--   Label(clock)        "14:20"

local ExtinctionConfig = require(script.Parent.ExtinctionConfig)

local DayCycle = {}

local D = ExtinctionConfig.Day

function DayCycle.Clock(serverTime)
	if D.Fixed then
		return D.Fixed -- feste Uhrzeit (Tests)
	end
	return (D.StartHour + (serverTime or 0) / D.Length * 24) % 24
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

function DayCycle.Label(clock)
	local hours = math.floor(clock)
	local minutes = math.floor((clock - hours) * 60 + 1e-6)
	return string.format("%02d:%02d", hours, minutes)
end

return DayCycle
