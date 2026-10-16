-- Leben über Markt-Portal und Neubeitritt (Extinction, Profil ExtLife): Wer verletzt die offene Welt verlässt, kommt
-- innerhalb von ExtinctionConfig.KeepHealthTime (30 Min) mit demselben Leben zurück, auch nach Spiel verlassen und
-- neu beitreten (Spielstand); volles Leben merkt sich nichts; nach Ablauf der Zeit wieder volles Leben; kaputte oder
-- alte Werte im Spielstand heilen voll statt Fehler; ein gemerkter Wert gilt nur einmal.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FEHLER: " .. msg)
	end
end
local function step(seconds)
	SIM.Advance(seconds or 1, 20)
end

game.JobId = "server-1"
local store = SIM.DataStore("PlayerData_v2")
local ExtinctionConfig = require("ExtinctionConfig")
local ProgressService = require("ProgressService")
local WeaponService = require("WeaponService")
ProgressService.Init()
WeaponService.Init()

local CENTER = Vector3.new(0, 0, -6000)
local maps = Instance.new("Folder", workspace)
maps.Name = "Maps"
local map = Instance.new("Model", maps)
map.Name = "Extinction"
map:SetAttribute("Center", CENTER)
for _, name in { "Zone", "Spawns", "Portals", "Stands" } do
	Instance.new("Folder", map).Name = name
end
local zone = Instance.new("Part", map.Zone)
zone.Name = "SafeZone"
zone.Size = Vector3.new(200, 80, 200)
zone.CFrame = CFrame.new(CENTER + Vector3.new(0, 40, 0))
Instance.new("Part", map.Spawns).CFrame = CFrame.new(CENTER + Vector3.new(0, 0.5, 13))

local InventoryService = require("InventoryService")
local LootService = require("LootService")
local Extinction = require("Extinction")
InventoryService.Init()
LootService.Init()
ExtinctionConfig.Airdrop.FirstDelay = math.huge
ExtinctionConfig.Horde.Enabled = false
ExtinctionConfig.HeliCrash.Enabled = false
ExtinctionConfig.Day.Fixed = 12
ExtinctionConfig.Zombies.PerPlayer = 0
ExtinctionConfig.Redzone.Enabled = false

-- Modus-Verwaltung (vereinfacht): Hub (= Markt-Portal) und offene Welt
local joinedEvent = Instance.new("BindableEvent")
local manager
manager = {
	Joined = joinedEvent.Event,
	Status = function() end,
	Join = function(player, modeId)
		local current = player:GetAttribute("Mode")
		if current == modeId then
			return
		end
		if current == "Extinction" then
			Extinction.RemovePlayer(player)
		end
		player:SetAttribute("Mode", modeId)
		if modeId == "Extinction" then
			Extinction.AddPlayer(player)
		end
		joinedEvent:Fire(player, modeId)
	end,
}
Extinction.Init(manager)

store.Data.u1 = { XP = {}, Coins = 0, Rap = 0, Owned = {}, Equipped = {} }
local function join()
	local player = SIM.Join("Alice", 1)
	Instance.new("Backpack", player).Name = "Backpack"
	step(2)
	manager.Join(player, "Extinction")
	step(1)
	return player
end
local function health(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.Health or -1, humanoid and humanoid.MaxHealth or -1
end
local function hurt(player, fraction)
	local humanoid = player.Character.Humanoid
	humanoid.Health = humanoid.MaxHealth * fraction
	step(0.5)
end
-- durchs Markt-Portal und zurück (Spiel bleibt offen)
local function portal(player)
	manager.Join(player, "Hub")
	step(0.5)
	manager.Join(player, "Extinction")
	step(1)
end

local alice = join()
local hp, max = health(alice)
check(hp == max and max > 0, "erster Beitritt: volles Leben (" .. hp .. " / " .. max .. ")")

-- ---------- Markt-Portal: Leben bleibt ----------
hurt(alice, 0.4)
portal(alice)
hp, max = health(alice)
check(math.abs(hp - max * 0.4) < 1, "nach dem Markt-Portal: 40 % Leben (" .. hp .. " / " .. max .. ")")
check(ProgressService.Get(alice).ExtLife == nil, "gemerkter Wert ist verbraucht")

-- ---------- volles Leben merkt sich nichts ----------
alice.Character.Humanoid.Health = max
step(0.5)
manager.Join(alice, "Hub")
step(0.5)
check(ProgressService.Get(alice).ExtLife == nil, "volles Leben: nichts gemerkt")
manager.Join(alice, "Extinction")
step(1)
hp, max = health(alice)
check(hp == max, "mit vollem Leben zurück (" .. hp .. ")")

-- ---------- Spiel verlassen und neu beitreten: Leben steht im Spielstand ----------
hurt(alice, 0.25)
SIM.Leave(alice)
step(3)
local saved = store.Data.u1 and store.Data.u1.ExtLife
check(type(saved) == "table" and math.abs((saved.H or 0) - 0.25) < 0.01 and type(saved.T) == "number",
	"Leben im Spielstand gespeichert (" .. tostring(saved and saved.H) .. ")")
alice = join()
hp, max = health(alice)
check(math.abs(hp - max * 0.25) < 1, "nach Neubeitritt: 25 % Leben (" .. hp .. " / " .. max .. ")")

-- ---------- abgelaufen: nach mehr als KeepHealthTime volles Leben ----------
hurt(alice, 0.5)
manager.Join(alice, "Hub")
step(0.5)
local life = ProgressService.Get(alice).ExtLife
check(type(life) == "table" and math.abs(life.H - 0.5) < 0.01, "50 % gemerkt")
life.T -= ExtinctionConfig.KeepHealthTime + 1 -- so, als wäre die Zeit schon um
manager.Join(alice, "Extinction")
step(1)
hp, max = health(alice)
check(hp == max, "nach Ablauf der Zeit: volles Leben (" .. hp .. ")")
check(ProgressService.Get(alice).ExtLife == nil, "abgelaufener Wert ist gelöscht")

-- ---------- kaputte Werte im Spielstand: volles Leben, kein Fehler ----------
for i, bad in {
	{ H = 0 / 0, T = os.time() },        -- NaN
	{ H = "0.3", T = os.time() },        -- Text
	{ H = 0.3 },                         -- ohne Zeit
	"0.3",                               -- gar keine Tabelle
} do
	manager.Join(alice, "Hub")
	step(0.5)
	ProgressService.Get(alice).ExtLife = bad
	manager.Join(alice, "Extinction")
	step(1)
	hp, max = health(alice)
	check(hp == max, "kaputter Wert " .. i .. ": volles Leben (" .. hp .. ")")
	check(ProgressService.Get(alice).ExtLife == nil, "kaputter Wert " .. i .. ": gelöscht")
end

-- ---------- Werte außerhalb 0..1: begrenzt, niemand kommt tot oder überheilt zurück ----------
manager.Join(alice, "Hub")
step(0.5)
ProgressService.Get(alice).ExtLife = { H = 0, T = os.time() }
manager.Join(alice, "Extinction")
step(1)
hp, max = health(alice)
check(hp >= 1 and hp < max * 0.05, "Leben 0 im Spielstand: lebt mit wenig Leben (" .. hp .. ")")
manager.Join(alice, "Hub")
step(0.5)
ProgressService.Get(alice).ExtLife = { H = 5, T = os.time() }
manager.Join(alice, "Extinction")
step(1)
hp, max = health(alice)
check(hp == max, "Leben über 100 % im Spielstand: nicht mehr als voll (" .. hp .. " / " .. max .. ")")

if failures > 0 then
	error(failures .. " Prüfungen fehlgeschlagen")
end
print("extlife: alles ok")
