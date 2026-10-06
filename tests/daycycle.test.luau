-- Tag und Nacht (DayCycle): Uhrzeit läuft mit der Serverzeit (ein Tag = Day.Length Sekunden), Nacht von NightFrom bis
-- NightTo mit weicher Dämmerung, Anzeige HH:MM, feste Uhrzeit für Tests; nachts mehr Zombies (ZombieService)
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end

local ExtinctionConfig = require("ExtinctionConfig")
local DayCycle = require("DayCycle")
local D = ExtinctionConfig.Day

check(math.abs(DayCycle.Clock(0) - D.StartHour) < 1e-6, "Serverzeit 0 = Starthour")
check(math.abs(DayCycle.Clock(D.Length / 4) - (D.StartHour + 6) % 24) < 1e-6, "ein Viertel Tag = 6 Stunden")
check(math.abs(DayCycle.Clock(D.Length * 3 + 10) - DayCycle.Clock(10)) < 1e-6, "Tage wiederholen sich")
check(DayCycle.Darkness(12) == 0 and not DayCycle.IsNight(12), "Mittag ist hell")
check(DayCycle.Darkness(0) == 1 and DayCycle.IsNight(0), "Mitternacht ist dunkel")
check(math.abs(DayCycle.Darkness(D.NightFrom) - 0.5) < 0.01, "Abenddämmerung halb dunkel")
check(math.abs(DayCycle.Darkness(D.NightTo) - 0.5) < 0.01, "Morgengrauen halb dunkel")
local last = -1
local monotone = true
for k = 0, 20 do
	local value = DayCycle.Darkness(D.NightFrom - D.Dusk + k * D.Dusk / 10)
	monotone = monotone and value >= last - 1e-9
	last = value
end
check(monotone, "es wird abends gleichmäßig dunkler")
check(DayCycle.Label(14.5) == "14:30" and DayCycle.Label(3.05) == "03:03", "Uhrzeit als HH:MM")
-- Anteil der Nacht am Tag: etwa ein Drittel
local nights = 0
for k = 0, 239 do
	if DayCycle.IsNight(k / 10) then
		nights += 1
	end
end
check(nights > 60 and nights < 110, "Nacht dauert etwa ein Drittel (" .. nights .. "/240)")
D.Fixed = 23
check(DayCycle.Clock(12345) == 23 and DayCycle.IsNight(DayCycle.Clock(0)), "feste Uhrzeit (Tests)")
D.Fixed = nil
check(D.NightZombies > 1 and D.NightSight > 1, "nachts mehr Zombies, die weiter sehen")

-- Blutmond: jede BloodMoonEvery-te Nacht, nie am Tag
local bloodNights, nightsSeen, dayBlood = 0, 0, false
local lastDay = nil
for k = 0, D.Length * D.BloodMoonEvery * 3, 30 do
	local clock = DayCycle.Clock(k)
	if DayCycle.IsBloodMoon(k) and not DayCycle.IsNight(clock) then
		dayBlood = true
	end
	if DayCycle.IsNight(clock) and math.abs(clock - 0) < 0.4 then -- um Mitternacht zählen
		local day = DayCycle.DayIndex(k)
		if day ~= lastDay then
			lastDay = day
			nightsSeen += 1
			if DayCycle.IsBloodMoon(k) then
				bloodNights += 1
			end
		end
	end
end
check(not dayBlood, "kein Blutmond am Tag")
check(nightsSeen >= D.BloodMoonEvery * 3 - 1 and bloodNights >= 2 and bloodNights <= 4, "jede " .. D.BloodMoonEvery .. ". Nacht Blutmond ("
	.. bloodNights .. " von " .. nightsSeen .. ")")
-- Nebel nur morgens, an manchen Tagen
local foggyDays, fogOutside = 0, false
for day = 0, 49 do
	local morning = (day * 24 + 7 - D.StartHour) / 24 * D.Length
	local evening = (day * 24 + 15 - D.StartHour) / 24 * D.Length
	if DayCycle.Fog(morning) > 0.5 then
		foggyDays += 1
	end
	if DayCycle.Fog(evening) > 0 then
		fogOutside = true
	end
end
check(foggyDays >= 5 and foggyDays <= 30, "Nebel an manchen Morgen (" .. foggyDays .. "/50)")
check(not fogOutside, "nachmittags kein Nebel")
-- Admin-Knopf: Uhrzeit setzen (Verschiebung an ReplicatedStorage), danach läuft der Tag weiter
do
	local t0 = 12345.6
	DayCycle.SetClock(22, t0)
	check(math.abs(DayCycle.Clock(t0) - 22) < 0.01, "SetClock 22 -> Nacht (" .. DayCycle.Clock(t0) .. ")")
	check(DayCycle.IsNight(DayCycle.Clock(t0)), "jetzt Nacht")
	DayCycle.SetClock(10, t0)
	check(math.abs(DayCycle.Clock(t0) - 10) < 0.01 and not DayCycle.IsNight(DayCycle.Clock(t0)), "SetClock 10 -> Tag")
	local later = DayCycle.Clock(t0 + D.Length / 24)
	check(math.abs(later - 11) < 0.01, "läuft danach normal weiter (" .. later .. ")")
	game:GetService("ReplicatedStorage"):SetAttribute("DayOffset", nil)
end
print(failures == 0 and "ALLE TESTS OK" or ("FEHLER: " .. failures))
