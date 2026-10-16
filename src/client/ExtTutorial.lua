-- ExtTutorial (ModuleScript, nur Client)
-- Pflicht-Tutorial der offenen Welt für neue Spieler (Schritte und Phasen: TutorialConfig). Der Server setzt beim
-- Betreten die Attribute ExtTutorial, TutorialForced und TutorialStep (Profil ohne TutorialDone und ohne GuideHinted,
-- siehe Extinction.AddPlayer). Beim ersten Mal erscheint die Karte WILLKOMMEN mit nur einem Knopf (LOS GEHT'S), danach
-- führt das Tutorial Schritt für Schritt; nach einem erneuten Beitritt geht es beim zuletzt erreichten Schritt weiter.
-- Überspringen geht nicht; bis zum Schritt "Leave" lässt der Server den Spieler nicht aus dem Camp (TutorialLock).
--
-- Anzeigen:
--   * Tafel oben in der Mitte: Schritt n/15, Phase (IM CAMP / DRAUSSEN), Ziel, Text, Fortschritt, Ziel-Entfernung
--   * Wegpunkt in der Welt (rote Raute mit Name und Entfernung über dem Ziel), Pfeil am Bildschirmrand, wenn das Ziel
--     außer Sicht ist, und eine Raute auf der Minimap (Minimap.SetGuide)
--   * Hervorhebung im Menü: pulsierender roter Rahmen um den Knopf/Bereich, daneben eine Erklär-Karte (Coach). Karten
--     mit WEITER erklären, Karten ohne warten, bis der Spieler die Aktion wirklich gemacht hat (Flags vom Server).
-- Jeder Schritt zählt erst, wenn der Spieler es getan hat: Attribute vom Server (ExtBag, ExtEquipped, InSafeZone,
-- ZombieKills, TutorialFlags = Kit geholt, gekauft, verkauft, Container, Markt) oder das offene Fenster.
-- Fertig meldet ExtAction "Tutorial" "Done" (Profil TutorialDone, Badge). Im GUIDE-Reiter startet ein Knopf das
-- Tutorial jederzeit noch einmal (freiwillig, dann mit BEENDEN).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local UITheme = require(Shared.UITheme)
local TopStack = require(Shared.TopStack)
local InputActions = require(Shared.InputActions)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local KitConfig = require(Shared.KitConfig)
local TutorialConfig = require(Shared.TutorialConfig)
local Minimap = require(Shared.Minimap)
local Sfx = require(Shared.Sfx)

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts
local make, label = UITheme.Make, UITheme.Label

local ExtTutorial = {}

local RED = Color3.fromRGB(214, 58, 58) -- Akzent wie im Menü der offenen Welt
local INFO_TIME = 14 -- Sekunden je Erklär-Schritt (rote Zone, Schluss)
local LOOT_WAIT = 60 -- so lange wartet der Beute-Schritt höchstens
local FALLBACK = 45 -- Coach-Karten, die auf eine Aktion warten: danach erscheint trotzdem WEITER (nie festhängen)
local CHECK_EVERY = 0.2

local hooks: { WindowKind: (() -> (string?, string?))? } = {}
local gui, canvas, panel, stepText, phaseText, titleText, bodyText, targetText, bar, timerBar, footText, intro
local focusGui, highlight, highlightStroke, callout, calloutCaption, calloutText, calloutButton, calloutWait, edgeArrow,
	edgeText
local waypoint, waypointText, waypointDistance, anchor, edgeDistance
local state = {
	Active = false, -- Tutorial läuft
	Step = 0,
	StepStart = 0,
	Coach = 1, -- aktuelle Coach-Karte des Schritts
	CoachStart = 0,
	CoachMissing = nil, -- seit wann das Element der Coach-Karte im richtigen Fenster fehlt
	ResumedAt = 0,
	Kills = 0, -- ZombieKills beim Start des Zombie-Schritts
	PickedAt = 0, -- os.clock() des letzten Aufhebens (ExtUpdate "Picked")
	NoCorpseSince = nil, -- Beute-Schritt: seit wann keine Leiche mit Beute in der Nähe
	Target = nil, -- Vector3 des aktuellen Ziels (Wegpunkt, Pfeil, Minimap)
	TargetName = "",
	HighlightObject = nil, -- GuiObject mit rotem Rahmen
	Started = false, -- schon begonnen (nach Verlassen und Wiederkommen weiter, ohne neue Karte)
	Finished = false, -- fertig (in dieser Sitzung nicht mehr von selbst)
}

-- ---------- Hilfen ----------

-- Text mit Platzhaltern {1}, {2} … (die Vorlage steht so in LocaleStrings, das Ergebnis passt auf das Muster)
local function fmt(template, ...)
	local args = { ... }
	return (string.gsub(template, "{(%d+)}", function(n)
		return tostring(args[tonumber(n) or 0] or "")
	end))
end

local function windowKind(): (string?, string?)
	local get = hooks.WindowKind
	if not get then
		return nil, nil
	end
	return get()
end

local function inExtinction()
	return Modes.IsSurvival(player:GetAttribute("Mode"))
end

-- Ladebildschirm (ReplicatedFirst) noch zu sehen: Tafel und Markierungen erst danach
local function loading()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	return playerGui ~= nil and playerGui:FindFirstChild("LoadingScreen") ~= nil
end

local function forced()
	return player:GetAttribute("TutorialForced") == true
end

local function key(action, fallback)
	local hint = InputActions.Hint(action)
	return hint ~= "" and ("[" .. hint .. "]") or fallback
end

-- Coach-Text je nach Gerät: mit Maus/Touch "anklicken", mit dem Controller die Taste ✕ (bzw. A)
-- pad(taste) baut den Controller-Text (Muster mit [{1}] in LocaleStrings)
local function padText(mouse, pad)
	return function()
		if InputActions.Device() == "Gamepad" then
			return pad(InputActions.PadName(Enum.KeyCode.ButtonA))
		end
		return mouse
	end
end

local function coachText(entry)
	return type(entry.Text) == "function" and entry.Text() or entry.Text
end

local function interactKey()
	return key("Interact", "den Knopf auf dem Bildschirm")
end

local function flag(name)
	local ok, flags = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("TutorialFlags") or "{}")
	return ok and type(flags) == "table" and flags[name] == true
end

local function bagEntries()
	local ok, list = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("ExtBag") or "[]")
	return ok and type(list) == "table" and list or {}
end

-- Erster Hotbar-Platz mit einer Waffe (nil = keine Waffe in der Hotbar)
local function weaponSlot()
	local best = nil
	for _, entry in bagEntries() do
		local config = type(entry) == "table" and ExtinctionConfig.Get(entry.Id)
		if config and config.Kind == "Weapon" and type(entry.S) == "number" and entry.S <= ExtinctionConfig.HotbarSlots
			and (not best or entry.S < best) then
			best = entry.S
		end
	end
	return best
end

-- Startpaket gerade nicht abholbar (schon geholt, Wartezeit läuft): Schritt nicht daran hängen lassen
local function starterWaiting()
	local kit = KitConfig.Get("Starter")
	local ok, claimed = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Kits") or "{}")
	return kit ~= nil and KitConfig.Remaining(kit, ok and claimed or {}, workspace:GetServerTimeNow()) > 0
end

local function hasWeapon()
	for _, entry in bagEntries() do
		local config = type(entry) == "table" and ExtinctionConfig.Get(entry.Id)
		if config and config.Kind == "Weapon" then
			return true
		end
	end
	return false
end

-- Liegt in der Tasche etwas, das beim Verkaufen Münzen bringt (keine Kit-Items, nicht nur Kit-Guthaben)?
local function hasSellable()
	local ok, credit = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("KitCredit") or "{}")
	credit = ok and type(credit) == "table" and credit or {}
	for _, entry in bagEntries() do
		local config = type(entry) == "table" and ExtinctionConfig.Get(entry.Id)
		if config and not config.Kit and (tonumber(entry.N) or 1) > (tonumber(credit[entry.Id]) or 0) then
			return true
		end
	end
	return false
end

local function rootPart()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function map()
	local maps = workspace:FindFirstChild("Maps")
	return maps and maps:FindFirstChild("Extinction")
end

-- Nächstes Teil aus einer Liste (nach Entfernung zum Spieler)
local function nearest(parts)
	local root = rootPart()
	local best, bestDistance = nil, math.huge
	for _, part in parts do
		local distance = root and (part.Position - root.Position).Magnitude or 0
		if distance < bestDistance then
			best, bestDistance = part, distance
		end
	end
	return best, bestDistance
end

-- Nächster Stand mit einem dieser Namen (Camp oder Safehouse)
local function nearestStand(...)
	local names = { ... }
	local stands = map() and map():FindFirstChild("Stands")
	local list = {}
	for _, part in stands and stands:GetChildren() or {} do
		if part:IsA("BasePart") and table.find(names, part.Name) then
			table.insert(list, part)
		end
	end
	local part = nearest(list)
	return part and part.Position or nil
end

local function safeZones()
	local zone = map() and map():FindFirstChild("Zone")
	local list = {}
	for _, part in zone and zone:GetChildren() or {} do
		if part:IsA("BasePart") and (part.Name == "SafeZone" or string.sub(part.Name, 1, 9) == "SafeZone_") then
			table.insert(list, part)
		end
	end
	return list
end

-- Nächstes Tor der Safe Zone, in der der Spieler steht: die vier Tore liegen auf den Achsen, das Ziel knapp draußen
local function nearestGate()
	local root = rootPart()
	local zone = nearest(safeZones())
	if not zone or not root then
		return nil
	end
	local radius = zone.Size.X / 2 + 8
	local best, bestDistance = nil, math.huge
	for _, direction in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local point = Vector3.new(zone.Position.X, root.Position.Y, zone.Position.Z) + direction * radius
		local distance = (point - root.Position).Magnitude
		if distance < bestDistance then
			best, bestDistance = point, distance
		end
	end
	return best
end

local function nearestSafeZone()
	local zone = nearest(safeZones())
	local root = rootPart()
	return zone and Vector3.new(zone.Position.X, root and root.Position.Y or zone.Position.Y, zone.Position.Z) or nil
end

-- Zombies, die dieser Spieler sieht (fremde liegen in HiddenZombies): lebend oder Leiche mit Beute
local function zombieTarget(corpse)
	local folder = workspace:FindFirstChild("Zombies")
	local root = rootPart()
	local best, bestDistance = nil, corpse and 150 or 400
	for _, model in folder and folder:GetChildren() or {} do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local part = model:FindFirstChild("HumanoidRootPart") or (model:IsA("Model") and model.PrimaryPart)
		local owner = model:GetAttribute("ZombieOwnerId")
		if part and part:IsA("BasePart") and (owner == nil or owner == player.UserId) then
			local ok
			if corpse then
				local prompt = model:FindFirstChild("CorpsePrompt", true)
				ok = prompt ~= nil and prompt:IsA("ProximityPrompt") and prompt.Enabled
			else
				ok = humanoid ~= nil and humanoid.Health > 0
			end
			local distance = root and (part.Position - root.Position).Magnitude or 0
			if ok and distance < bestDistance then
				best, bestDistance = part.Position, distance
			end
		end
	end
	return best
end

local function mapOpen()
	local playerGui = player:FindFirstChild("PlayerGui")
	local mapGui = playerGui and playerGui:FindFirstChild("ExtinctionMap")
	return mapGui ~= nil and mapGui:IsA("ScreenGui") and mapGui.Enabled
end

-- Ist ein GuiObject wirklich zu sehen (es und alle Eltern bis zum ScreenGui sichtbar)? anySize: Größe egal
-- (Zwischenstufen der Suche, z.B. Karten in einem Layout)
local function shown(object, anySize)
	local current = object
	while current and not current:IsA("LayerCollector") do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current ~= nil and current.Enabled and (anySize or object.AbsoluteSize.X > 0)
end

-- Element im Menü/HUD suchen: path = { ScreenGui-Name, Name, Name … } (jeder Name irgendwo darunter, erste sichtbare)
local function findGui(path)
	local playerGui = player:FindFirstChild("PlayerGui")
	local scope = playerGui and playerGui:FindFirstChild(path[1])
	if not scope or not scope:IsA("LayerCollector") or not scope.Enabled then
		return nil
	end
	for i = 2, #path do
		local found = nil
		for _, object in scope:GetDescendants() do
			if object.Name == path[i] and object:IsA("GuiObject") and shown(object, i < #path) then
				found = object
				break
			end
		end
		if not found then
			return nil
		end
		scope = found
	end
	return scope
end

-- ---------- Schritte ----------
-- Text() = Anweisung auf der Tafel, Target() = Ziel in der Welt (Vector3), TargetName, Done() = erledigt,
-- Coach = Erklär-Karten im Menü { Find = Pfad, Text, Done = Aktion (ohne: Knopf WEITER) },
-- Highlight() = Pfad eines Elements, das rot umrandet wird, solange die Tafel steht, Duration = reiner Text-Schritt,
-- Window = Art des Fensters der Coach-Karten (ist es offen und fehlt ein Element, z.B. ein anderer Aufbau am Handy,
-- geht es nach kurzer Zeit mit der nächsten Karte weiter).
-- Ein Schritt ist fertig, wenn Done() wahr ist, sonst wenn alle Coach-Karten durch sind.
local STEPS = {}

STEPS.Kit = { Title = "HOL DIR DEIN STARTER KIT", TargetName = "KIT-HÄNDLER", Window = "Kits",
	Text = function()
		return ("Geh zum <b>Kit-Händler</b> (folge der roten Markierung) und drück " .. interactKey()
			.. ". Das <b>STARTER KIT</b> ist kostenlos: Pistole, MP, Munition, Verbände, eine Weste und "
			.. "ein Fahrrad.")
	end,
	Target = function()
		return nearestStand(KitConfig.Point)
	end,
	Coach = {
		{ Find = { "ExtinctionWindow", "Kit_Starter", "Claim" }, Text = padText("Klick auf <b>ABHOLEN</b>. Kits holst du immer wieder "
			.. "kostenlos ab, jedes hat seine eigene Wartezeit.", function(key)
				return "Drück [" .. key .. "] auf <b>ABHOLEN</b>. Kits holst du immer wieder kostenlos ab, jedes hat seine eigene "
					.. "Wartezeit."
			end), Done = function()
			return flag("Kit") or hasWeapon() or starterWaiting()
		end },
	},
	Done = function()
		return flag("Kit") or hasWeapon() or starterWaiting()
	end }

STEPS.Inventory = { Title = "ÖFFNE DEIN INVENTAR",
	Text = function()
		return fmt("Drück {1}, um dein Inventar zu öffnen.", key("Inventory", "den Taschen-Knopf"))
	end,
	Done = function()
		return (windowKind()) == "Inventory"
	end }

STEPS.Safe = { Title = "TASCHE UND CONTAINER", Window = "Inventory",
	Text = function()
		return fmt("Öffne dein Inventar wieder ({1}): dort zeigen wir dir, was beim Tod sicher ist.",
			key("Inventory", "den Taschen-Knopf"))
	end,
	Coach = {
		{ Find = { "ExtinctionWindow", "InventoryGrids", "Grid_Bag" .. (ExtinctionConfig.HotbarSlots + 1) },
			Text = "<b>TASCHE</b>: alles, was du kaufst oder aufhebst, landet hier. Stirbst du draußen, <b>fällt die Tasche zu "
				.. "Boden</b> und jeder kann sie plündern." },
		{ Find = { "ExtinctionWindow", "InventoryGrids", "Grid_Bag1" },
			Text = function()
				if InputActions.Device() == "Gamepad" then
					return "<b>SCHNELLLEISTE</b>: ohne Menü wechselst du hier die Waffe mit [" .. InputActions.Hint("Gadget")
						.. "], heilst mit [" .. InputActions.Hint("QuickHeal") .. "] und wirfst Granaten mit ["
						.. InputActions.Hint("QuickThrow") .. "]. Waffen, Heilung und Granaten gehören hierher."
				end
				return "<b>SCHNELLLEISTE</b>: diese Plätze benutzt du direkt mit den Zahlentasten, ohne Menü. Waffen, Heilung und "
					.. "Granaten gehören hierher."
			end },
		{ Find = { "ExtinctionWindow", "InventoryGrids", "Grid_Safe1" },
			Text = padText("<b>CONTAINER</b>: was hier liegt, <b>behältst du auch beim Tod</b>. Zieh jetzt ein Item aus der Tasche hier "
				.. "hinein (oder anklicken und einen Container-Platz wählen).", function(key)
					return "<b>CONTAINER</b>: was hier liegt, <b>behältst du auch beim Tod</b>. Wähl ein Item in der Tasche mit ["
						.. key .. "] und dann einen Container-Platz."
				end), Done = function()
				return flag("Safe")
			end },
	} }

STEPS.Equip = { Title = "NIMM EINE WAFFE IN DIE HAND",
	Text = function()
		local slot = weaponSlot()
		local hint = slot and InputActions.Hint("Hotbar" .. slot) or ""
		if InputActions.Device() == "Gamepad" then
			hint = InputActions.Hint("Gadget") .. " / " .. InputActions.Hint("Ability") -- Controller: Waffe wechseln mit R1/L1
		end
		return ("Schließ das Menü und drück "
			.. (hint ~= "" and ("[" .. hint .. "]") or "eine Waffe in deiner Schnellleiste")
			.. ", um deine Waffe zu ziehen. Im Camp kannst du sie halten, schießen geht nur draußen.")
	end,
	Highlight = function()
		local slot = weaponSlot()
		return slot and { "ExtinctionHUD", "Hotbar", "Hotbar" .. slot } or nil
	end,
	Done = function()
		-- ohne Waffe (Startpaket schon geholt und weg) gibt es nichts zu ziehen
		return (player:GetAttribute("ExtEquipped") or 0) > 0 or (not hasWeapon() and starterWaiting())
	end }

local AMMO = ExtinctionConfig.AmmoFor("Pistol") or "Ammo_9mm"
STEPS.Trader = { Title = "KAUF MUNITION BEIM HÄNDLER", TargetName = "HÄNDLER", Window = "Stand",
	Text = function()
		return ("Geh zum <b>HÄNDLER</b> und drück " .. interactKey()
			.. ". Dort kaufst du Munition, Heilung und Westen und verkaufst deine Beute.")
	end,
	Target = function()
		return nearestStand("Stand_Weapons")
	end,
	Coach = {
		{ Find = { "ExtinctionWindow", "Offer" }, Text = "<b>KAUFEN</b>: links steht alles, was der Händler verkauft. "
			.. "Bezahlt wird mit <b>Münzen</b> (oben rechts)." },
		{ Find = { "ExtinctionWindow", "Offer_" .. AMMO, "Buy" }, Text = "Kauf jetzt eine Packung <b>Munition</b> für deine "
			.. "Pistole.", Done = function()
				return flag("Buy")
			end },
		{ Find = { "ExtinctionWindow", "SellHint" }, Text = padText("<b>VERKAUFEN</b>: rechts ist dein Inventar. Item anklicken und "
			.. "<b>VERKAUFEN</b> wählen. Items aus Kits bringen keine Münzen, Beute schon.", function(key)
				return "<b>VERKAUFEN</b>: rechts ist dein Inventar. Item mit [" .. key .. "] wählen und <b>VERKAUFEN</b> drücken. "
					.. "Items aus Kits bringen keine Münzen, Beute schon."
			end) },
	} }

STEPS.Stash = { Title = "DEIN LAGER", TargetName = "LAGER", Window = "Stash",
	Text = function()
		return fmt("Geh zum <b>LAGER</b> und drück {1}.", interactKey())
	end,
	Target = function()
		return nearestStand("Stash")
	end,
	Coach = {
		{ Find = { "ExtinctionWindow", "Grid_Stash1" }, Text = "<b>LAGER</b>: hier liegt alles für immer sicher, auch wenn du "
			.. "stirbst. Du erreichst es nur direkt am Lager in einer Safe Zone. Wertvolles nach jeder Runde hier ablegen." },
		{ Find = { "ExtinctionWindow", "Loadout" }, Text = "<b>AUSRÜSTUNGEN</b>: speichere deine Ausrüstung und hol sie dir "
			.. "später mit einem Klick zurück in die Tasche." },
	} }

STEPS.Market = { Title = "DER SPIELERMARKT", TargetName = "TAUSCHMARKT", Window = "Market",
	Text = function()
		return ("Geh zum <b>TAUSCHMARKT</b> am Platz und drück " .. interactKey()
			.. ": im <b>Spielermarkt</b> handelst du mit anderen Spielern.")
	end,
	Target = function()
		return nearestStand("Stand_Market")
	end,
	Coach = {
		{ Find = { "ExtinctionWindow", "MarketPage", "Results" }, Text = "<b>ANGEBOTE</b>: alles, was andere Spieler gerade "
			.. "verkaufen, oft billiger als beim Händler. <b>KAUFEN</b> legt es sofort in deine Tasche." },
		{ Find = { "ExtinctionWindow", "MarketPage", "Filters" }, Text = "<b>SUCHEN UND FILTERN</b>: Namen eintippen oder eine "
			.. "Kategorie wählen. Oben rechts sortierst du nach Preis oder nach neuen Angeboten." },
		{ Find = { "ExtinctionWindow", "MarketPage", "Sell" }, Text = ("<b>VERKAUFEN</b>: Item aus deiner Tasche anklicken, "
			.. "Preis festlegen, <b>ANBIETEN</b>. Kauft es jemand, bekommst du sofort die Münzen (minus "
			.. tostring(math.floor(ExtinctionConfig.Market.FeeRate * 100 + 0.5)) .. " % Gebühr).") },
		{ Find = { "ExtinctionWindow", "MarketPage", "TabMine" }, Text = "<b>MEINE ANGEBOTE</b>: Preis ändern oder "
			.. "zurücknehmen. Deine Angebote bleiben in deinem Spielstand, auch wenn du stirbst." },
		{ Find = { "ExtinctionWindow", "Tab_Market" }, Text = ("Den <b>MARKT</b> erreichst du in jeder Safe Zone auch "
			.. "über das Menü " .. key("Menu", "") .. ". Gute Beute hier anbieten bringt oft mehr als der Händler.") },
	} }

STEPS.Leave = { Title = "VERLASS DAS CAMP", TargetName = "TOR",
	Text = function()
		return ("Jetzt geht es raus. Geh durch eines der <b>Tore</b>. Draußen laufen Zombies, und <b>PvP "
			.. "beginnt " .. tostring(ExtinctionConfig.PvPDelay)
			.. " Sekunden</b> nach dem Verlassen. Die Safe Zone, die du zuletzt betreten hast, ist dein "
			.. "Spawnpunkt.")
	end,
	Target = nearestGate,
	Done = function()
		return player:GetAttribute("InSafeZone") == false
	end }

STEPS.Zombie = { Title = "TÖTE EINEN ZOMBIE", TargetName = "ZOMBIE",
	Text = function()
		return ("Zombies lassen <b>Münzen und Beute</b> fallen. Zielen mit " .. key("Aim", "dem Ziel-Knopf")
			.. ", schießen mit " .. key("Fire", "dem Feuer-Knopf")
			.. ". Verletzt? Nimm einen Verband aus deiner Schnellleiste.")
	end,
	Target = function()
		return zombieTarget(false)
	end,
	Start = function()
		state.Kills = player:GetAttribute("ZombieKills") or 0
	end,
	Done = function()
		return (player:GetAttribute("ZombieKills") or 0) > state.Kills
	end }

STEPS.Loot = { Title = "DURCHSUCH DIE LEICHE", TargetName = "BEUTE",
	Text = function()
		return ("Geh zum toten Zombie und drück " .. interactKey()
			.. ": was er dabei hat, landet <b>in deiner Tasche</b>. Taschen, Kisten und Lootdrops "
			.. "durchsuchst du genauso.")
	end,
	Target = function()
		return zombieTarget(true)
	end,
	Start = function()
		state.PickedAt = 0
		state.NoCorpseSince = nil
	end,
	Done = function()
		if state.PickedAt > state.StepStart or os.clock() - state.StepStart > LOOT_WAIT then
			return true
		end
		-- nichts zum Durchsuchen in der Nähe (der Zombie hatte nichts dabei): nach kurzer Zeit weiter
		if zombieTarget(true) == nil then
			state.NoCorpseSince = state.NoCorpseSince or os.clock()
			return os.clock() - state.NoCorpseSince > 4
		end
		state.NoCorpseSince = nil
		return false
	end }

STEPS.Map = { Title = "ÖFFNE DIE KARTE",
	Text = function()
		return ("Drück " .. key("WorldMap", "[N]")
			.. " für die große Karte. Dort siehst du die <b>Safe Zones</b>, die <b>rote Zone</b>, "
			.. "Lootdrops, Konvois, Bosse und deine verlorene Tasche.")
	end,
	Done = mapOpen }

STEPS.Redzone = { Title = "DIE ROTE ZONE", Duration = INFO_TIME,
	Text = function()
		return "Die <b>rote Zone</b> wandert alle 20 Minuten weiter (rote Linie und Rauchsäule). Drinnen gilt <b>sofort PvP</b>, "
			.. "es gibt mehr und härtere Zombies, aber <b>viel bessere Beute</b>. Kills dort bringen <b>RZ-Punkte</b> für den "
			.. "<b>Schieber</b> im Camp."
	end }

STEPS.Return = { Title = "BRING DEINE BEUTE IN SICHERHEIT", TargetName = "SAFE ZONE",
	Text = function()
		return "Geh zurück in eine <b>Safe Zone</b>. Erst dort ist deine Beute sicher: stirbst du vorher, liegt deine Tasche "
			.. "am Boden, und du musst sie dir zurückholen, bevor es jemand anderes tut."
	end,
	Target = nearestSafeZone,
	Done = function()
		return player:GetAttribute("InSafeZone") == true
	end }

STEPS.Sell = { Title = "MACH DEINE BEUTE ZU MÜNZEN", TargetName = "HÄNDLER",
	Text = function()
		return "Verkauf ein Beute-Item beim <b>HÄNDLER</b> oder biete es im <b>MARKT</b> anderen Spielern an. Mit den Münzen "
			.. "kaufst du bessere Ausrüstung."
	end,
	Target = function()
		return nearestStand("Stand_Weapons", "Stand_Market")
	end,
	Done = function()
		return flag("Sell") or flag("MarketList") or not hasSellable() or os.clock() - state.StepStart > 240
	end }

STEPS.Ready = { Title = "DU BIST BEREIT", Duration = INFO_TIME,
	Text = function()
		return ("Ab Level 4 gehört dir ein <b>Versteck</b> im Camp, mit einem Schlüssel geht es in die "
			.. "<b>Katakomben</b>. Container und Lager sind sicher, die Tasche nicht. Alles Weitere: Menü "
			.. key("Menu", "") .. " → <b>GUIDE</b>. Viel Glück da draußen.")
	end }

ExtTutorial.Steps = {}
for _, info in TutorialConfig.Steps do
	local step = STEPS[info.Id]
	assert(step, "ExtTutorial: Schritt fehlt: " .. info.Id)
	step.Id = info.Id
	step.Phase = info.Phase
	table.insert(ExtTutorial.Steps, step)
end

-- ---------- Anzeige: Wegpunkt, Pfeil, Rahmen, Coach-Karte ----------

local function setTarget(position, name)
	state.Target = position
	state.TargetName = name or ""
	Minimap.SetGuide(position)
	if not position then
		if waypoint then
			waypoint.Enabled = false
		end
		return
	end
	if not anchor or not anchor.Parent then
		anchor = make("Attachment", { Name = "TutorialAnchor" }, workspace.Terrain)
	end
	anchor.WorldPosition = position
	if not waypoint then
		waypoint = make("BillboardGui", { Name = "TutorialWaypoint", AlwaysOnTop = true, ResetOnSpawn = false, LightInfluence = 0,
			Size = UDim2.fromOffset(240, 74), StudsOffset = Vector3.new(0, 7, 0), MaxDistance = 5000 },
			player:FindFirstChild("PlayerGui"))
		local diamond = make("Frame", { Name = "Arrow", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.fromOffset(18, 18), Rotation = 45, BackgroundColor3 = RED, BorderSizePixel = 0 }, waypoint)
		make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, diamond)
		waypointText = label({ Name = "Text", Size = UDim2.new(1, 0, 0, 24), Text = "", TextSize = 18, Font = F.Display,
			TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3 }, waypoint)
		waypointDistance = label({ Name = "Distance", Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 20), Text = "",
			TextSize = 15, Font = F.Bold, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3 },
			waypoint)
	end
	waypoint.Adornee = anchor
	waypoint.Enabled = true
	local root = rootPart()
	local distance = root and math.floor((position - root.Position).Magnitude) or nil
	waypointText.Text = state.TargetName
	waypointDistance.Text = distance and (distance .. " M") or ""
end

local function hideFocus()
	state.HighlightObject = nil
	if highlight then
		highlight.Visible = false
		callout.Visible = false
	end
end

local function hidePanel()
	if panel then
		panel.Visible = false
	end
	setTarget(nil)
	hideFocus()
	if edgeArrow then
		edgeArrow.Visible = false
	end
end

local function coachDone(entry)
	return entry.Done ~= nil and entry.Done()
end

-- Lage eines Elements in der Ebene des Tutorials. AbsolutePosition zählt in Roblox immer ab der Unterkante der oberen
-- Leiste (GuiInset), auch in Oberflächen mit IgnoreGuiInset; die Ebene selbst beginnt aber ganz oben (ihre
-- AbsolutePosition ist dann (0, -Inset)). Ohne diesen Abzug saß der Rahmen um die Höhe der Leiste zu weit oben.
local function onFocus(object)
	return object.AbsolutePosition - focusGui.AbsolutePosition
end

-- Coach-Karte neben das Element legen (unten, sonst oben), innerhalb des Bildschirms
local function placeCallout(object)
	local viewport = focusGui.AbsoluteSize
	local width = math.min(360, viewport.X - 32)
	callout.Size = UDim2.fromOffset(width, 0)
	local pos, size = onFocus(object), object.AbsoluteSize
	local height = callout.AbsoluteSize.Y > 0 and callout.AbsoluteSize.Y or 130
	local x = math.clamp(pos.X + size.X / 2 - width / 2, 16, math.max(16, viewport.X - width - 16))
	local y = pos.Y + size.Y + 14
	if y + height > viewport.Y - 16 then
		y = pos.Y - height - 14
	end
	if y < 16 then -- weder darunter noch darüber Platz (großer Bereich): in den Bereich hinein, unten
		y = math.max(16, math.min(viewport.Y - height - 16, pos.Y + size.Y - height - 12))
	end
	callout.Position = UDim2.fromOffset(x, y)
end

local function showFocus(object, text, caption, needsAck, waiting)
	state.HighlightObject = object
	highlight.Visible = object ~= nil
	if not object and text then
		local viewport = focusGui.AbsoluteSize
		local width = math.min(420, viewport.X - 32)
		callout.Size = UDim2.fromOffset(width, 0)
		callout.Position = UDim2.fromOffset((viewport.X - width) / 2, math.max(16, viewport.Y * 0.08))
	end
	if not text then
		callout.Visible = false
		return
	end
	callout.Visible = true
	calloutCaption.Text = caption
	calloutText.Text = text
	local wasVisible = calloutButton.Visible
	calloutButton.Visible = needsAck
	calloutWait.Visible = not needsAck
	calloutWait.Text = waiting and "MACH ES JETZT" or ""
	if needsAck and not wasVisible and InputActions.Device() == "Gamepad" then
		GuiService.SelectedObject = calloutButton
	end
end

-- Scrollbereich so verschieben, dass das Element zu sehen ist
local function scrollInto(object)
	local scroller = object:FindFirstAncestorOfClass("ScrollingFrame")
	if not scroller then
		return
	end
	local top = object.AbsolutePosition.Y - scroller.AbsolutePosition.Y
	local bottom = top + object.AbsoluteSize.Y
	if top < 0 or bottom > scroller.AbsoluteSize.Y then
		scroller.CanvasPosition = Vector2.new(scroller.CanvasPosition.X, math.max(0, scroller.CanvasPosition.Y + top - 12))
	end
end

-- ---------- Ablauf ----------

local function showStep()
	local step = ExtTutorial.Steps[state.Step]
	if not step or not panel then
		return
	end
	stepText.Text = fmt("TUTORIAL  ·  SCHRITT {1}/{2}", state.Step, #ExtTutorial.Steps)
	phaseText.Text = step.Phase == "Camp" and "IM CAMP" or "DRAUSSEN"
	titleText.Text = step.Title
	bodyText.Text = step.Text()
	bar.Size = UDim2.fromScale((state.Step - 1) / #ExtTutorial.Steps, 1)
	footText.Text = forced() and "PFLICHT-TUTORIAL  ·  DANACH GEHT ES RICHTIG LOS" or "BEENDEN: MENÜ → GUIDE → TUTORIAL BEENDEN"
	panel.Visible = inExtinction()
end

local function finish(result)
	state.Active = false
	state.Finished = true
	state.Step = 0
	hidePanel()
	Remotes.ExtAction:FireServer("Tutorial", result)
end

local function enterStep(index)
	state.Step = index
	state.StepStart = os.clock()
	state.Coach = 1
	state.CoachStart = os.clock()
	local step = ExtTutorial.Steps[index]
	if not step then
		finish("Done")
		Sfx.UI("StingGood")
		return
	end
	Remotes.ExtAction:FireServer("Tutorial", "Step", index, step.Id) -- Server: Fortschritt, Camp-Sperre, Trichter
	if step.Start then
		step.Start()
	end
	showStep()
end

local function closeIntro()
	if intro then
		intro:Destroy()
		intro = nil
	end
	RunService:UnbindFromRenderStep("ExtTutorialMouse")
	UITheme.HoldCamera("ExtTutorial", false)
end

-- Schritt, bei dem es weitergeht (vom Server gemerkt), sonst 1
local function savedStep()
	return TutorialConfig.Index(player:GetAttribute("TutorialStep")) or 1
end

-- Tutorial starten. withIntro = erst die Karte WILLKOMMEN (nur beim allerersten Mal)
function ExtTutorial.Start(withIntro)
	if not gui then
		return
	end
	closeIntro()
	state.Finished = false
	if not withIntro then
		state.Active = true
		state.Started = true
		if player:GetAttribute("ExtTutorial") ~= true then
			Remotes.ExtAction:FireServer("Tutorial", "Start") -- Wiederholung über GUIDE: Server läuft wieder mit
			enterStep(1)
		else
			enterStep(savedStep())
		end
		return
	end
	local C2 = UITheme.MenuColors
	local phone = InputActions.IsTouch()
	intro = make("Frame", { Name = "Intro", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(600, 320), BackgroundColor3 = C2.Card, BackgroundTransparency = 0.06, BorderSizePixel = 0,
		ZIndex = 20 }, canvas)
	if phone then
		make("UIScale", { Scale = 1.2 }, intro)
	end
	UITheme.Corner(intro, UITheme.Radius.Medium)
	make("Frame", { Name = "Accent", Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = RED, BorderSizePixel = 0, ZIndex = 21 }, intro)
	label({ Name = "Caption", Position = UDim2.fromOffset(28, 24), Size = UDim2.new(1, -56, 0, 18), Text = "WILLKOMMEN, ÜBERLEBENDER",
		TextSize = 14, Font = F.Bold, TextColor3 = RED, ZIndex = 21 }, intro)
	label({ Name = "Title", Position = UDim2.fromOffset(28, 44), Size = UDim2.new(1, -56, 0, 40), Text = "DEINE ERSTEN SCHRITTE",
		TextSize = 34, Font = F.Display, TextColor3 = C2.Text, ZIndex = 21 }, intro)
	label({ Name = "Text", Position = UDim2.fromOffset(28, 92), Size = UDim2.new(1, -56, 0, 130), Text = "Bevor es raus geht, "
		.. "zeigen wir dir das Camp: <b>Starter Kit</b>, <b>Inventar und Container</b>, den <b>Händler</b>, dein <b>Lager</b> "
		.. "und den <b>Spielermarkt</b>. Danach dein erster Zombie, seine Beute und wie du sie zu Münzen machst. Folge einfach "
		.. "der <b>roten Markierung</b>.", RichText = true, TextSize = 18, Font = F.Medium, TextColor3 = C2.Text,
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 21 }, intro)
	local buttons = make("Frame", { Name = "Buttons", Position = UDim2.new(0, 28, 1, -76), Size = UDim2.new(1, -56, 0, 52),
		BackgroundTransparency = 1, ZIndex = 21 }, intro)
	UITheme.Chunky({ Name = "Start", Size = UDim2.fromScale(1, 1), Color = RED, StrokeColor = RED, Text = "LOS GEHT'S",
		TextSize = 22, ZIndex = 22 }, buttons, function()
		closeIntro()
		Sfx.UI("StingInfo")
		ExtTutorial.Start(false)
	end)
	state.Started = true
	UITheme.HoldCamera("ExtTutorial", true) -- Blickrichtung nach dem Schließen wie vorher
	RunService:BindToRenderStep("ExtTutorialMouse", Enum.RenderPriority.Camera.Value + 2, function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
	InputActions.Focus(buttons) -- ohne Sound: beim Spawn soll nichts klingen
end

-- Tutorial beenden (Knopf im GUIDE): nur die freiwillige Wiederholung, das Pflicht-Tutorial nicht
function ExtTutorial.Stop()
	if not ExtTutorial.CanStop() then
		return
	end
	if state.Active or intro then
		closeIntro()
		finish("Skip")
	end
end

function ExtTutorial.CanStop()
	return not forced()
end

function ExtTutorial.IsActive()
	return state.Active or intro ~= nil
end

function ExtTutorial.CurrentStep()
	local step = state.Active and ExtTutorial.Steps[state.Step]
	return step and step.Id or nil
end

-- Coach-Karte n des laufenden Schritts (für Tests): Index, Element
function ExtTutorial.CurrentCoach()
	return state.Coach, state.HighlightObject
end

-- WEITER auf der Coach-Karte
local function nextCoach()
	local step = ExtTutorial.Steps[state.Step]
	if not state.Active or not step or not step.Coach then
		return
	end
	state.Coach += 1
	state.CoachStart = os.clock()
	Sfx.UI("Click")
end

-- Schritt prüfen (alle CHECK_EVERY Sekunden): erledigt -> nächster, Ziel und Hervorhebung nachführen
local function tick()
	if intro and not inExtinction() then
		closeIntro() -- beim nächsten Betreten kommt die Karte wieder (Attribut)
		state.Started = false
	end
	-- Controller: Auswahl ging verloren (Menü kurz offen): wieder auf die Karte
	if intro and windowKind() == nil and InputActions.Device() == "Gamepad" then
		local selected = GuiService.SelectedObject
		if not (selected and selected:IsDescendantOf(intro)) then
			InputActions.Focus(intro)
		end
	end
	if not state.Active then
		return
	end
	if not inExtinction() then
		hidePanel()
		return
	end
	local step = ExtTutorial.Steps[state.Step]
	if not step then
		return
	end
	-- Tutorial-Stand fällt beim Moduswechsel (Markthalle) weg: wieder anfragen
	if player:GetAttribute("TutorialStep") ~= step.Id and os.clock() - state.ResumedAt > 2 then
		state.ResumedAt = os.clock()
		if player:GetAttribute("ExtTutorial") ~= true then
			Remotes.ExtAction:FireServer("Tutorial", "Start")
		end
		Remotes.ExtAction:FireServer("Tutorial", "Resume", state.Step, step.Id)
	end
	-- Coach-Karten, deren Aktion schon erledigt ist, überspringen
	local coach = step.Coach
	while coach and coach[state.Coach] and coachDone(coach[state.Coach]) do
		state.Coach += 1
		state.CoachStart = os.clock()
	end
	local done
	if step.Duration then
		done = os.clock() - state.StepStart >= step.Duration
	elseif step.Done and step.Done() then
		done = true
	else
		done = coach ~= nil and state.Coach > #coach
	end
	if done then
		if not step.Duration then
			Sfx.UI("StingInfo")
		end
		hideFocus()
		enterStep(state.Step + 1)
		return
	end
	-- Coach-Karte: Element im Menü gefunden -> Rahmen + Erklärung, Tafel aus (das Menü liegt darüber)
	local entry = coach and coach[state.Coach]
	local object = entry and findGui(entry.Find) or nil
	local windowOpen = windowKind() ~= nil or UITheme.IsMenuOpen()
	if entry and not object and step.Window and windowKind() == step.Window then
		state.CoachMissing = state.CoachMissing or os.clock()
		if os.clock() - state.CoachMissing > 2 and not entry.Done then
			state.CoachMissing = nil
			state.Coach += 1
			state.CoachStart = os.clock()
		end
	else
		state.CoachMissing = nil
	end
	if object then
		if state.HighlightObject ~= object then
			scrollInto(object)
		end
		local waiting = entry.Done ~= nil
		local late = waiting and os.clock() - state.CoachStart > FALLBACK
		showFocus(object, coachText(entry), fmt("SCHRITT {1}  ·  TIPP {2}/{3}", state.Step, state.Coach, #coach),
			not waiting or late, waiting)
	elseif entry and step.Window and windowKind() == step.Window then
		-- richtiges Fenster, Element (noch) nicht zu sehen: die Erklärung trotzdem zeigen
		showFocus(nil, coachText(entry), fmt("SCHRITT {1}  ·  TIPP {2}/{3}", state.Step, state.Coach, #coach), false, entry.Done ~= nil)
	elseif windowOpen and not mapOpen() then
		-- ein anderes Menü ist offen: die Anweisung als Karte oben über dem Menü (die Tafel läge darunter)
		showFocus(nil, step.Text(), step.Title, false, false)
	else
		local path = not windowOpen and step.Highlight and step.Highlight()
		local hud = path and findGui(path)
		if hud then
			showFocus(hud, nil)
		else
			hideFocus()
		end
	end
	panel.Visible = not windowOpen and not mapOpen()
	bodyText.Text = step.Text()
	if step.Duration then
		timerBar.Parent.Visible = true
		timerBar.Size = UDim2.fromScale(math.clamp(1 - (os.clock() - state.StepStart) / step.Duration, 0, 1), 1)
	else
		timerBar.Parent.Visible = false
	end
	local target = step.Target and not windowOpen and step.Target() or nil
	setTarget(target, step.TargetName)
	local root = rootPart()
	targetText.Visible = target ~= nil
	if target then
		targetText.Text = fmt("ZIEL: {1}  ·  {2} M", step.TargetName or "", root and math.floor((target - root.Position).Magnitude) or 0)
	end
end

-- Jeden Frame: Rahmen auf das Element, Pfeil am Rand, wenn das Ziel außer Sicht ist
local function render()
	if not highlight then
		return
	end
	local object = state.HighlightObject
	if object and highlight.Visible then
		if object.Parent and shown(object) then
			local at = onFocus(object)
			highlight.Position = UDim2.fromOffset(at.X - 6, at.Y - 6)
			highlight.Size = UDim2.fromOffset(object.AbsoluteSize.X + 12, object.AbsoluteSize.Y + 12)
			local pulse = (math.sin(os.clock() * 5) + 1) / 2
			highlightStroke.Thickness = 2 + pulse * 2
			highlightStroke.Transparency = pulse * 0.35
			if callout.Visible then
				placeCallout(object)
			end
		else
			hideFocus()
		end
	end
	local camera = workspace.CurrentCamera
	local target = state.Active and state.Target
	if not target or not camera or not panel or (not panel.Visible) then
		edgeArrow.Visible = false
		return
	end
	local viewport = camera.ViewportSize
	local point, onScreen = camera:WorldToViewportPoint(target + Vector3.new(0, 7, 0))
	if onScreen and point.Z > 0 then
		edgeArrow.Visible = false
		return
	end
	local center = viewport / 2
	local direction = Vector2.new(point.X, point.Y) - center
	if point.Z < 0 then
		direction = -direction
	end
	if direction.Magnitude < 1 then
		direction = Vector2.new(0, 1)
	end
	local margin = 70
	local scale = math.min((center.X - margin) / math.max(math.abs(direction.X), 1e-3),
		(center.Y - margin) / math.max(math.abs(direction.Y), 1e-3))
	local at = center + direction * scale
	edgeArrow.Visible = true
	edgeArrow.Position = UDim2.fromOffset(at.X, at.Y)
	edgeArrow.Arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
	local root = rootPart()
	edgeText.Text = state.TargetName
	edgeDistance.Text = root and (math.floor((target - root.Position).Magnitude) .. " M") or ""
end

-- Vom Server: Attribut ExtTutorial = true -> Karte zeigen (oder weitermachen, wenn schon begonnen)
local function onAttribute()
	if player:GetAttribute("ExtTutorial") ~= true then
		-- Server hat beendet (fertig): Anzeige weg
		if state.Active and player:GetAttribute("TutorialForced") == nil and state.Finished then
			hidePanel()
		end
		return
	end
	if state.Finished or state.Active or intro then
		return
	end
	if state.Started then
		state.Active = true
		enterStep(math.max(state.Step, savedStep()))
		return
	end
	-- erst, wenn der Ladebildschirm weg ist, kein Fenster offen ist (die Karte liegt unter den Fenstern) und der Spieler da ist
	task.spawn(function()
		local waited = 0
		while waited < 600 and (not inExtinction() or windowKind() ~= nil or loading()) do
			waited += task.wait(0.5)
		end
		if player:GetAttribute("ExtTutorial") == true and not state.Finished and not state.Active and not intro and inExtinction()
			and windowKind() == nil and not loading() then
			-- Karte WILLKOMMEN nur ganz am Anfang; nach einem erneuten Beitritt geht es gleich weiter
			ExtTutorial.Start(savedStep() <= 1)
		end
	end)
end

function ExtTutorial.Init(options: { WindowKind: (() -> (string?, string?))? }?)
	hooks = options or {}
	-- Beute-Schritt: aufgehoben (Karten rechts im HUD kommen mit ExtUpdate "Picked")
	Remotes.ExtUpdate.OnClientEvent:Connect(function(kind)
		if kind == "Picked" then
			state.PickedAt = os.clock()
		end
	end)
	local playerGui = player:WaitForChild("PlayerGui")
	gui = make("ScreenGui", { Name = "ExtTutorial", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 15,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	canvas = UITheme.ScaledRoot(gui, 1600, 900)
	panel = UITheme.HudPanel({ Name = "Panel", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(540, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.15, Visible = false },
		canvas)
	-- unter Zone und Spawnschutz, über Ortsname und Banner (TopStack: nichts liegt übereinander)
	TopStack.Register(panel, { Order = TopStack.Order.Tutorial })
	if InputActions.IsTouch() then
		make("UIScale", { Scale = 1.25 }, panel) -- Handy: Schritt-Text sonst nur ~7 px hoch
	end
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 16) }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, panel)
	local head = make("Frame", { Name = "Head", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1 }, panel)
	stepText = label({ Name = "Step", Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 12, Font = F.Bold, TextColor3 = RED }, head)
	phaseText = label({ Name = "Phase", Size = UDim2.new(1, 0, 1, 0), Text = "", TextSize = 12, Font = F.Bold, TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right }, head)
	titleText = label({ Name = "Title", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 28), Text = "", TextSize = 24,
		Font = F.Display, TextColor3 = C.Text }, panel)
	bodyText = label({ Name = "Text", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Text = "", RichText = true, TextWrapped = true, TextSize = 16, Font = F.Medium, TextColor3 = C.Text,
		TextYAlignment = Enum.TextYAlignment.Top }, panel)
	targetText = label({ Name = "Target", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 18), Text = "", TextSize = 13, Font = F.Bold,
		TextColor3 = RED, Visible = false }, panel)
	local timerTrack = make("Frame", { Name = "Timer", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.Card,
		BorderSizePixel = 0, Visible = false }, panel)
	timerBar = make("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Text, BackgroundTransparency = 0.4,
		BorderSizePixel = 0 }, timerTrack)
	local track = make("Frame", { Name = "Progress", LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = C.Card,
		BorderSizePixel = 0 }, panel)
	bar = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = RED, BorderSizePixel = 0 }, track)
	footText = label({ Name = "Foot", LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 14), Text = "", TextSize = 11, Font = F.Bold,
		TextColor3 = C.Muted }, panel)

	-- Ebene über den Fenstern (DisplayOrder 20): Rahmen, Coach-Karte, Pfeil am Rand. Bildschirm-Pixel, nichts skaliert.
	focusGui = make("ScreenGui", { Name = "ExtTutorialFocus", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	focusGui:SetAttribute("KeepOverMenu", true) -- das Menü blendet sonst alle anderen Oberflächen aus (Inv.hideHud)
	highlight = make("Frame", { Name = "Highlight", BackgroundTransparency = 1, Visible = false, ZIndex = 1 }, focusGui)
	UITheme.Corner(highlight, 6)
	highlightStroke = make("UIStroke", { Color = RED, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, highlight)
	callout = make("Frame", { Name = "Callout", Size = UDim2.fromOffset(360, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = UITheme.MenuColors.Card, BackgroundTransparency = 0.04, BorderSizePixel = 0, Visible = false,
		ZIndex = 2 }, focusGui)
	UITheme.Corner(callout, UITheme.Radius.Small)
	UITheme.Stroke(callout, RED, 1, 0.3)
	make("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14) }, callout)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, callout)
	calloutCaption = label({ Name = "Caption", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 14), Text = "", TextSize = 12, Font = F.Bold,
		TextColor3 = RED, ZIndex = 3 }, callout)
	calloutText = label({ Name = "Text", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Text = "", RichText = true, TextWrapped = true, TextSize = 16, Font = F.Medium, TextColor3 = C.Text,
		TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3 }, callout)
	calloutWait = label({ Name = "Wait", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 16), Text = "", TextSize = 12, Font = F.Bold,
		TextColor3 = C.Muted, ZIndex = 3 }, callout)
	calloutButton = make("TextButton", { Name = "Next", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = RED,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "WEITER", TextSize = 16, Font = F.Display, TextColor3 = C.Text,
		ZIndex = 3, Visible = false }, callout)
	UITheme.Corner(calloutButton, 3)
	calloutButton.Activated:Connect(nextCoach)
	edgeArrow = make("Frame", { Name = "EdgeArrow", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(160, 70),
		BackgroundTransparency = 1, Visible = false }, focusGui)
	label({ Name = "Arrow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.fromOffset(36, 36),
		Text = "▲", TextSize = 34, TextColor3 = RED, TextStrokeTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Center },
		edgeArrow)
	edgeText = label({ Name = "Text", Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 18), Text = "", TextSize = 15,
		Font = F.Display, TextColor3 = C.Text, TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Center }, edgeArrow)
	edgeDistance = label({ Name = "Distance", Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 16), Text = "",
		TextSize = 13, Font = F.Bold, TextColor3 = RED, TextStrokeTransparency = 0.3, TextXAlignment = Enum.TextXAlignment.Center },
		edgeArrow)

	player:GetAttributeChangedSignal("ExtTutorial"):Connect(onAttribute)
	onAttribute()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= CHECK_EVERY then
			elapsed = 0
			tick()
			render() -- auch ohne Bild (Tests, Hintergrund): Stand der Anzeige aktuell halten
		end
	end)
	RunService.RenderStepped:Connect(render)
end

return ExtTutorial
