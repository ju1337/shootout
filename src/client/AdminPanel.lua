-- AdminPanel (ModuleScript, nur Client)
-- Für Admins (Attribut "IsAdmin" vom Server) mit allen Kategorien; Moderatoren (Attribut "IsMod", Team-Rang aus
-- StaffConfig) sehen nur SPIELER und SUCHE mit Kick und den Sperren, die ihr Rang erlaubt. Öffnen/Schließen mit P oder
-- dem ADMIN-Knopf.
-- Aussehen wie das Menü der offenen Welt (TAB/M, ExtinctionClient), aber deckend fast schwarz (nichts scheint durch),
-- Rot als einziger Akzent, flache Knöpfe, Schrift Builder Sans (UITheme), keine Symbole/Emojis.
-- Aufbau (wie die Vorlage, im Stil des Spiels):
--   * links die Seitenleiste: ADMIN mit Rang, darunter die Kategorien SPIELER, EFFEKTE, EVENTS, NACHRICHTEN, WELT,
--     LOGS, ÖKONOMIE, SUCHE (aktive mit rotem Streifen links)
--   * rechts die Fläche mit Kopfzeile (Titel der Kategorie, Umschalter DIESER SERVER / ALLE SERVER, Schließen)
--   * SPIELER / EFFEKTE / NACHRICHTEN: in der Fläche links die Spielerliste (Avatar, Name, AKTUALISIEREN, Sperre per
--     UserId), rechts die Detailansicht des gewählten Spielers (Werte-Kacheln oben, Aktionsknöpfe darunter)
--   * die anderen Kategorien nutzen die ganze Fläche
--   * unten eine Zeile mit der Rückmeldung des Servers
-- Mit ALLE SERVER laufen Server-Aktionen (Events, Ankündigung, Uhrzeit, Nebel, Münzen an alle) über Remote "AllServers"
-- auf jedem Server. Alle Befehle prüft der Server noch einmal (AdminService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Modes = require(Shared.Modes)
local GameSettings = require(Shared.GameSettings)
local DayCycle = require(Shared.DayCycle)
local StaffConfig = require(Shared.StaffConfig)
local LevelConfig = require(Shared.LevelConfig)
local ExtinctionConfig = require(Shared.ExtinctionConfig)
local Cosmetics = require(Shared.Cosmetics)
local UITheme = require(Shared.UITheme)

local player = Players.LocalPlayer

local AdminPanel = {}

-- ---------- Aussehen (wie das Menü der offenen Welt) ----------
local F = UITheme.Fonts
local FONT = F.Bold
local BODY_FONT = F.Medium
local PANEL_W, PANEL_H = 1200, 680
local SIDEBAR_W = 210
local HEADER_Y, HEADER_H = 18, 50
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(214, 58, 58) -- Akzent wie im Menü der offenen Welt (aktiver Reiter, Hauptknöpfe)
local GLASS = Color3.fromRGB(8, 9, 11)  -- Knopf ADMIN (P) über der Welt
-- Flächen des Panels deckend (die Welt soll nicht durchscheinen): Seitenleiste fast schwarz, Fläche, Kopfzeile und
-- Spalten in leicht helleren Stufen, Kästen (Karten, Kacheln, Felder) eine Stufe heller
local BLACK = Color3.fromRGB(5, 5, 6)
local SURFACE = Color3.fromRGB(11, 12, 14)
local RAISED = Color3.fromRGB(17, 18, 21)
local BOX = Color3.fromRGB(22, 24, 28)
-- Knopf-Arten (Wert bei button()/buttonRow): C.Green = Hauptaktion (rot gefüllt), C.Red = gefährlich (dunkel mit roter
-- Schrift), alles andere flach und halbtransparent. Als Textfarbe stehen C.Green/C.Red für Gut/Schlecht.
local C = {
	Text = UITheme.Colors.Text,
	Muted = UITheme.Colors.Muted,
	Gold = UITheme.Colors.Gold,
	Green = UITheme.Colors.Good,
	Red = UITheme.Colors.Bad,
	Dark = UITheme.Colors.Card,
	Blue = UITheme.Colors.Card,
	Orange = UITheme.Colors.Card,
	Purple = UITheme.Colors.Card,
	Yellow = UITheme.Colors.Card,
	Teal = UITheme.Colors.Card,
	Pink = UITheme.Colors.Card,
}

-- Kategorien: { Id, Text, mit Spielerliste?, nur volle Admins? }
local CATEGORIES = {
	{ Id = "Players", Text = "SPIELER", List = true },
	{ Id = "Effects", Text = "EFFEKTE", List = true, Admin = true },
	{ Id = "Events", Text = "EVENTS", Admin = true },
	{ Id = "Messages", Text = "NACHRICHTEN", List = true, Admin = true },
	{ Id = "World", Text = "WELT", Admin = true },
	{ Id = "Logs", Text = "LOGS", Admin = true },
	{ Id = "Economy", Text = "ÖKONOMIE", Admin = true },
	{ Id = "Lookup", Text = "SUCHE" },
}

-- Aktionen, die mit ALLE SERVER auf jedem Server laufen (wie AdminService GLOBAL)
local GLOBAL = { Announce = true, ExtAirdrop = true, ExtConvoy = true, ExtHeliCrash = true, ExtHordeCrate = true,
	ExtBosses = true, ExtRedzone = true, ExtStop = true, BloodMoon = true, Storm = true, SetClock = true, SetFog = true,
	GiveAllCoins = true, DungeonStopAll = true }

-- ---------- Zustand ----------
local gui, panel, statusLabel, toggleButton, scopeButton
local pages, categoryButtons = {}, {}
local listColumn, listHolder, listTitle, contentArea, headerTitle
local currentCategory = "Players"
local selectedId = nil -- UserId des gewählten Spielers
local allServers = false
local isOpen = false
local listSignature = ""
local detailBuilders = {} -- [Kategorie] = function(frame, target)
local detailFrames = {} -- [Kategorie] = ScrollingFrame rechts
local tiles = {} -- [Key] = TextLabel (Werte des gewählten Spielers)
local watchConnection = nil -- AttributeChanged des gewählten Spielers (Einfrieren, Gottmodus, Rang)
local hideButton
local eventStatus = {} -- [Event] = TextLabel
local valueLabels = {} -- [Einstellung] = TextLabel
local botCountLabel
local bans = {}
local banSection
local logSection
local lookupSection
local logs = {}
local lookup = nil

-- Item- und Skin-Auswahl (Pfeile < >)
local itemIds = {}
for id in ExtinctionConfig.Items do
	table.insert(itemIds, id)
end
table.sort(itemIds, function(a, b)
	local ia, ib = ExtinctionConfig.Get(a), ExtinctionConfig.Get(b)
	if ia.Kind ~= ib.Kind then
		return tostring(ia.Kind) < tostring(ib.Kind)
	end
	return tostring(ia.Name) < tostring(ib.Name)
end)
local skinIds = {}
for _, item in Cosmetics.Items do
	table.insert(skinIds, item.Id)
end
table.sort(skinIds, function(a, b)
	return tostring(Cosmetics.Get(a).Name) < tostring(Cosmetics.Get(b).Name)
end)
local itemIndex, skinIndex = 1, 1

-- ---------- Bausteine ----------

local function make(className, props, parent)
	local obj = Instance.new(className)
	for key, value in props do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function corner(obj, radius)
	UITheme.Corner(obj, radius or 3)
end

-- Haarfeiner heller Rand (UITheme)
local function stroke(obj, color, thickness, transparency)
	return UITheme.Stroke(obj, color, thickness or 1, transparency)
end

local function padding(obj, all)
	make("UIPadding", { PaddingLeft = UDim.new(0, all), PaddingRight = UDim.new(0, all), PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all) }, obj)
end

local function list(obj, gap, horizontal)
	return make("UIListLayout", { Padding = UDim.new(0, gap or 6), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		VerticalAlignment = horizontal and Enum.VerticalAlignment.Center or Enum.VerticalAlignment.Top }, obj)
end

local function label(text, size, parent, props)
	props = props or {}
	props.Text = text
	props.Size = props.Size or UDim2.new(1, 0, 0, size + 6)
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT
	props.TextSize = size
	props.TextColor3 = props.TextColor3 or C.Text
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd
	return make("TextLabel", props, parent)
end

-- Flacher Knopf wie im Menü der offenen Welt: Hauptaktion rot gefüllt, gefährlich dunkel mit roter Schrift, sonst
-- helle Schicht über dem Glas. Beim Darüberfahren etwas heller.
local function style(b, color)
	local kind = color == C.Green and "Primary" or color == C.Red and "Danger" or "Flat"
	local rest = kind == "Primary" and 0 or kind == "Danger" and 0 or 0.92
	b.BackgroundColor3 = kind == "Primary" and RED or kind == "Danger" and BLACK or WHITE
	b.BackgroundTransparency = rest
	b.TextColor3 = kind == "Danger" and C.Red or C.Text
	b:SetAttribute("Rest", rest)
	local edge = b:FindFirstChild("Edge")
	if kind == "Danger" and not edge then
		edge = make("UIStroke", { Name = "Edge", Color = C.Red, Thickness = 1, Transparency = 0.55,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	end
	if edge then
		edge.Enabled = kind == "Danger"
	end
end

local function button(text, width, parent, color, onClick, height)
	local b = make("TextButton", { Size = UDim2.new(width <= 1 and width or 0, width > 1 and width or 0, 0, height or 34),
		BorderSizePixel = 0, Font = FONT, TextSize = 14, Text = text, AutoButtonColor = false, TextWrapped = true }, parent)
	corner(b, 3)
	style(b, color)
	b.MouseEnter:Connect(function()
		local rest = b:GetAttribute("Rest") or 0.92
		b.BackgroundTransparency = rest == 0 and 0.12 or rest - 0.06
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundTransparency = b:GetAttribute("Rest") or 0.92
	end)
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

-- Art eines Knopfs später ändern (Umschalter)
local function recolor(b, color)
	style(b, color)
end

-- Zeile, deren Knöpfe sich die Breite teilen (Breiten < 1 = Anteil, sonst Pixel)
local function row(parent, height)
	local frame = make("Frame", { Size = UDim2.new(1, 0, 0, height or 34), BackgroundTransparency = 1 }, parent)
	list(frame, 6, true)
	return frame
end

-- n Knöpfe gleichmäßig in einer Zeile: defs = { { Text, Farbe, onClick }, ... }
local function buttonRow(parent, defs, height)
	local r = row(parent, height)
	local count = #defs
	local result = {}
	for i, def in defs do
		local b = button(def[1], 1, r, def[2], def[3], height)
		b.Size = UDim2.new(1 / count, -6 * (count - 1) / count, 1, 0)
		b.LayoutOrder = i
		result[i] = b
	end
	return r, result
end

local function textBox(placeholder, parent, props)
	local box = make("TextBox", { Size = UDim2.new(0, 120, 0, 34), BackgroundColor3 = BOX, BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Font = BODY_FONT, TextSize = 13, TextColor3 = C.Text, Text = "", PlaceholderText = placeholder,
		PlaceholderColor3 = C.Muted, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd }, parent)
	corner(box, 3)
	stroke(box)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8) }, box)
	for key, value in props or {} do
		box[key] = value
	end
	return box
end

-- Nur Ziffern (optional mit Minus) im Feld zulassen
local function numeric(box, allowMinus)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local clean = string.gsub(box.Text, allowMinus and "[^%d%-]" or "%D", "")
		if clean ~= box.Text then
			box.Text = clean
		end
	end)
end

-- Abschnitts-Überschrift (klein, gedämpft, wie im Menü der offenen Welt)
local function section(title, parent)
	return label(title, 12, parent, { Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.Muted, Font = F.Bold })
end

-- Karte (dunkler Kasten, wächst mit dem Inhalt)
local function card(parent)
	local frame = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = BOX,
		BackgroundTransparency = 0, BorderSizePixel = 0 }, parent)
	corner(frame, 4)
	stroke(frame)
	padding(frame, 10)
	list(frame, 6)
	return frame
end

-- Reihenfolge = Erstellungsreihenfolge
local function order(frame)
	for i, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child.LayoutOrder = i
		end
	end
end

local function clear(frame)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function scroller(parent, props)
	local frame = make("ScrollingFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = RED, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y }, parent)
	for key, value in props or {} do
		frame[key] = value
	end
	list(frame, 8)
	make("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, frame)
	return frame
end

local function avatar(userId, size, parent)
	local image = make("ImageLabel", { Size = UDim2.new(0, size, 0, size), BackgroundColor3 = WHITE, BackgroundTransparency = 0.92,
		BorderSizePixel = 0, Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150" }, parent)
	corner(image, 4)
	stroke(image)
	return image
end

-- Zahl kurz: 1234 -> 1.2K, 2500000 -> 2.5M
local function short(n)
	n = tonumber(n) or 0
	local abs = math.abs(n)
	if abs >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif abs >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif abs >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

-- ---------- Rechte ----------

-- Rechte des eigenen Rangs; volle Admins ohne Rang (StaffService.AdminIds) dürfen alles außer Ränge vergeben
local function rights()
	return StaffConfig.Of(player) or (player:GetAttribute("IsAdmin") and { Kick = true, BanDays = 0, Unban = true, Power = 0 })
		or {}
end

local function full()
	return player:GetAttribute("IsAdmin") == true
end

-- Sperre über days Tage (0 = dauerhaft) erlaubt?
local function banAllowed(days)
	local limit = rights().BanDays
	return limit ~= nil and (limit == 0 or (days > 0 and days <= limit))
end

-- Darf ich gegen diesen Spieler vorgehen? (schwächerer Rang oder ich selbst; der Server prüft es noch einmal)
local function outranks(target)
	if target == player then
		return true
	end
	local mine = StaffConfig.Of(player)
	if not mine then
		return full()
	end
	return StaffConfig.Power(target) < mine.Power
end

-- ---------- Senden ----------

local function setStatus(text, color)
	if statusLabel then
		statusLabel.Text = text
		statusLabel.TextColor3 = color or C.Muted
	end
end

local function send(action, a, b)
	setStatus("…")
	Remotes.AdminAction:FireServer(action, a, b)
end

-- Server-Aktion: mit ALLE SERVER auf jedem Server, sonst nur hier
local function sendScoped(action, a, b)
	if allServers and GLOBAL[action] and a ~= "Here" then
		setStatus("… (alle Server)")
		Remotes.AdminAction:FireServer("AllServers", action, { A = a, B = b })
	else
		send(action, a, b)
	end
end

local function selected()
	return selectedId and Players:GetPlayerByUserId(selectedId) or nil
end

-- Knopf mit Sicherheitsabfrage: erster Klick "SICHER?", zweiter innerhalb von 3 s führt aus
local function confirmButton(text, width, parent, color, onConfirm)
	local armed = false
	local b
	b = button(text, width, parent, color, function()
		if armed then
			armed = false
			b.Text = text
			onConfirm()
			return
		end
		armed = true
		b.Text = "SICHER?"
		task.delay(3, function()
			if armed then
				armed = false
				b.Text = text
			end
		end)
	end)
	return b
end

-- Knöpfe zum Rang-Vergeben (nur Ränge bis StaffConfig Assign des eigenen Rangs) für eine UserId
local function rankButtons(parent, getUserId)
	local assign = rights().Assign
	if not assign then
		return
	end
	local defs = {}
	for _, rank in StaffConfig.Ranks do
		if rank.Power <= assign then
			table.insert(defs, { rank.Name, nil, function()
				local id = getUserId()
				if id then
					send("SetRank", id, rank.Id)
				else
					setStatus("UserId eingeben", C.Red)
				end
			end })
		end
	end
	table.insert(defs, { "KEIN RANG", C.Dark, function()
		local id = getUserId()
		if id then
			send("SetRank", id, nil)
		else
			setStatus("UserId eingeben", C.Red)
		end
	end })
	-- höchstens 5 pro Zeile
	for i = 1, #defs, 5 do
		buttonRow(parent, { defs[i], defs[i + 1], defs[i + 2], defs[i + 3], defs[i + 4] }, 30)
	end
end

-- ---------- Spielerliste (Mitte) ----------

local function refreshTiles()
	local target = selected()
	if not target then
		return
	end
	local stats: { [string]: any } = {}
	pcall(function()
		stats = game:GetService("HttpService"):JSONDecode(target:GetAttribute("Stats") or "{}")
	end)
	local level = LevelConfig.Get(target)
	local values = {
		Coins = short(target:GetAttribute("Coins")),
		RedPoints = short(target:GetAttribute("RedPoints")),
		Level = tostring(level.Level) .. (level.Prestige > 0 and (" P" .. level.Prestige) or ""),
		Rap = short(target:GetAttribute("Rap")),
		Zombies = short(stats.Zombies),
		Kills = short(stats.Kills),
	}
	for key, tile in tiles do
		if tile.Parent then
			tile.Text = values[key] or "0"
		end
	end
	if hideButton and hideButton.Parent then
		local hidden = target:GetAttribute("HideBoards") == true
		hideButton.Text = hidden and "IN BESTENLISTE ZEIGEN" or "VOR BESTENLISTE VERSTECKEN"
		recolor(hideButton, hidden and C.Green or C.Red)
	end
end

local refreshDetail, refreshList

local function selectPlayer(userId)
	selectedId = userId
	refreshList(true) -- Markierung neu zeichnen
	refreshDetail()
end

refreshList = function(force)
	if not listHolder then
		return
	end
	local parts = {}
	for _, p in Players:GetPlayers() do
		table.insert(parts, p.UserId .. ":" .. tostring(p:GetAttribute("StaffRank")))
	end
	local signature = table.concat(parts, "|") .. "#" .. tostring(selectedId)
	if signature == listSignature and not force then
		return
	end
	listSignature = signature
	clear(listHolder)
	local all = Players:GetPlayers()
	listTitle.Text = "SPIELER (" .. #all .. ")"
	-- gewählter Spieler weg: niemanden mehr anzeigen
	if selectedId and not Players:GetPlayerByUserId(selectedId) then
		selectedId = nil
		refreshDetail()
	end
	for i, p in all do
		local on = p.UserId == selectedId
		-- wie die Reiter im Menü: gewählt heller mit rotem Streifen links
		local entry = make("TextButton", { Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = WHITE,
			BackgroundTransparency = on and 0.9 or 0.96, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = i },
			listHolder)
		corner(entry, 3)
		make("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = RED, BorderSizePixel = 0, Visible = on }, entry)
		if not on then
			entry.MouseEnter:Connect(function()
				entry.BackgroundTransparency = 0.93
			end)
			entry.MouseLeave:Connect(function()
				entry.BackgroundTransparency = 0.96
			end)
		end
		local face = avatar(p.UserId, 40, entry)
		face.Position = UDim2.new(0, 9, 0.5, -20)
		local staff = StaffConfig.Of(p)
		label((staff and (StaffConfig.Prefix(staff, 11) .. " ") or "") .. p.DisplayName, 15, entry,
			{ Position = UDim2.new(0, 54, 0, 7), Size = UDim2.new(1, -60, 0, 20), RichText = true })
		label("@" .. p.Name, 12, entry, { Position = UDim2.new(0, 54, 0, 28), Size = UDim2.new(1, -60, 0, 16),
			TextColor3 = C.Muted, Font = BODY_FONT })
		entry.Activated:Connect(function()
			selectPlayer(p.UserId)
		end)
	end
end

local function buildListColumn(parent)
	listColumn = make("Frame", { Size = UDim2.new(0, 260, 1, 0), BackgroundColor3 = RAISED, BackgroundTransparency = 0,
		BorderSizePixel = 0 }, parent)
	corner(listColumn, 4)
	padding(listColumn, 10)
	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, listColumn)
	listTitle = label("SPIELER (0)", 16, head, { Size = UDim2.new(0.55, 0, 1, 0), Font = F.Display })
	local refresh = button("AKTUALISIEREN", 1, head, nil, function()
		refreshList(true)
		refreshDetail()
	end, 28)
	refresh.AnchorPoint = Vector2.new(1, 0)
	refresh.Position = UDim2.new(1, 0, 0, 1)
	refresh.Size = UDim2.new(0.45, 0, 0, 28)
	refresh.TextSize = 12
	listHolder = scroller(listColumn, { Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 8, 1, -124) })
	-- unten: Sperre per UserId (auch offline), Grund und Dauer aus der Detailansicht bzw. Standard
	local foot = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 78),
		BackgroundTransparency = 1 }, listColumn)
	list(foot, 6)
	local idBox = textBox("UserId (offline)", foot, { Size = UDim2.new(1, 0, 0, 34) })
	numeric(idBox)
	local defs = {}
	if banAllowed(0) or banAllowed(7) then
		table.insert(defs, { "BAN ID", C.Red, function()
			local id = tonumber(idBox.Text)
			if not id then
				setStatus("UserId eingeben", C.Red)
				return
			end
			send("Ban", id, { Days = banAllowed(0) and 0 or 7, Reason = "Regelverstoß" })
		end })
	end
	if rights().Unban then
		table.insert(defs, { "UNBAN", C.Green, function()
			local id = tonumber(idBox.Text)
			if id then
				send("Unban", id)
			else
				setStatus("UserId eingeben", C.Red)
			end
		end })
	end
	if #defs > 0 then
		buttonRow(foot, defs, 34)
	end
	order(foot)
end

-- ---------- Detailansicht (rechts) ----------

-- Kopf: Avatar, Name, @Name · UserId, Rang, VERSTECKEN; darunter die Werte-Kacheln
local function detailHead(frame, target)
	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1 }, frame)
	avatar(target.UserId, 60, head).Position = UDim2.new(0, 0, 0, 2)
	local staff = StaffConfig.Of(target)
	label(UITheme.Upper(target.DisplayName) .. (staff and ("  " .. StaffConfig.Prefix(staff, 13)) or ""), 22, head,
		{ Position = UDim2.new(0, 72, 0, 6), Size = UDim2.new(1, -270, 0, 28), RichText = true, Font = F.Display })
	label("@" .. target.Name .. " · " .. target.UserId .. " · " .. tostring(target:GetAttribute("Mode") or "?"), 13, head,
		{ Position = UDim2.new(0, 72, 0, 36), Size = UDim2.new(1, -270, 0, 18), TextColor3 = C.Muted, Font = BODY_FONT })
	if full() and outranks(target) then
		hideButton = button("VOR BESTENLISTE VERSTECKEN", 1, head, C.Red, function()
			send("HideLeaderboard", target.UserId)
		end, 32)
		hideButton.AnchorPoint = Vector2.new(1, 0)
		hideButton.Position = UDim2.new(1, 0, 0, 4)
		hideButton.Size = UDim2.new(0, 190, 0, 32)
		hideButton.TextSize = 12
	end
	-- Werte-Kacheln
	local tileRow = make("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1 }, frame)
	list(tileRow, 6, true)
	local defs = { { "Coins", "MÜNZEN" }, { "RedPoints", "RZ" }, { "Level", "LEVEL" }, { "Rap", "RAP" },
		{ "Zombies", "ZOMBIES" }, { "Kills", "KILLS" } }
	tiles = {}
	for i, def in defs do
		local tile = make("Frame", { Size = UDim2.new(1 / #defs, -5, 1, 0), BackgroundColor3 = BOX, BackgroundTransparency = 0,
			BorderSizePixel = 0, LayoutOrder = i }, tileRow)
		corner(tile, 4)
		stroke(tile)
		tiles[def[1]] = label("0", 20, tile, { Position = UDim2.new(0, 10, 0, 5), Size = UDim2.new(1, -16, 0, 24),
			Font = F.Display, TextColor3 = def[1] == "Coins" and C.Gold or C.Text })
		label(def[2], 11, tile, { Position = UDim2.new(0, 10, 0, 30), Size = UDim2.new(1, -16, 0, 14), TextColor3 = C.Muted })
	end
		refreshTiles()
end

-- Kick, Ban mit Grund und Dauer, Daten zurücksetzen, Rang
local function moderationRows(frame, target)
	local mine = rights()
	if target == player or not outranks(target) then
		return
	end
	local r = row(frame)
	local reasonBox = textBox("Grund", r, { Size = UDim2.new(0.3, -6, 1, 0), Text = "Regelverstoß" })
	local daysBox = textBox("Tage (0 = für immer)", r, { Size = UDim2.new(0.22, -6, 1, 0) })
	numeric(daysBox)
	local rest = make("Frame", { Size = UDim2.new(0.48, 0, 1, 0), BackgroundTransparency = 1 }, r)
	list(rest, 6, true)
	local defs = {}
	if mine.Kick then
		table.insert(defs, { "KICK", C.Orange, function()
			send("Kick", target.UserId, reasonBox.Text)
		end })
	end
	if mine.BanDays ~= nil then
		table.insert(defs, { "BAN", C.Red, function()
			local days = tonumber(daysBox.Text) or (banAllowed(0) and 0 or 1)
			if not banAllowed(days) then
				setStatus("So lange darfst du nicht sperren (höchstens " .. tostring(mine.BanDays) .. " Tage).", C.Red)
				return
			end
			send("Ban", target.UserId, { Days = days, Reason = reasonBox.Text })
		end })
	end
	for i, def in defs do
		local b = button(def[1], 1, rest, def[2], def[3])
		b.Size = UDim2.new(full() and 0.3 or 0.5, -6, 1, 0)
		b.LayoutOrder = i
	end
	if full() then
		local reset = confirmButton("RESET DATA", 1, rest, C.Red, function()
			send("ResetData", target.UserId, "CONFIRM")
		end)
		reset.Size = UDim2.new(0.4, -6, 1, 0)
		reset.LayoutOrder = 9
	end
	if mine.Assign then
		label("TEAM-RANG", 13, frame, { TextColor3 = C.Muted })
		rankButtons(frame, function()
			return target.UserId
		end)
	end
end

-- Pfeil-Auswahl: < Name > und ein Knopf daneben
local function picker(frame, getText, step, actionText, actionColor, onAction, extra)
	local r = row(frame)
	local left = button("<", 1, r, C.Dark, nil)
	left.Size = UDim2.new(0, 40, 1, 0)
	local name = label("", 15, r, { Size = UDim2.new(0.42, -46, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
	name.BackgroundColor3 = BOX
	name.BackgroundTransparency = 0
	corner(name, 3)
	local right = button(">", 1, r, C.Dark, nil)
	right.Size = UDim2.new(0, 40, 1, 0)
	if extra then
		extra(r)
	end
	local go = button(actionText, 1, r, actionColor, onAction)
	go.Size = UDim2.new(0.3, 0, 1, 0)
	local function update()
		name.Text = getText()
	end
	left.Activated:Connect(function()
		step(-1)
		update()
	end)
	right.Activated:Connect(function()
		step(1)
		update()
	end)
	update()
	order(r)
	return r
end

detailBuilders.Players = function(frame, target)
	detailHead(frame, target)
	if full() then
		-- Werte: Menge eintippen, dann +/SET
		local r1 = row(frame)
		local amountBox = textBox("Menge (z.B. 1000)", r1, { Size = UDim2.new(0.28, -6, 1, 0) })
		numeric(amountBox, true)
		local function value(key, op)
			return function()
				local amount = tonumber(amountBox.Text)
				if not amount then
					setStatus("Menge eingeben", C.Red)
					return
				end
				send("PlayerValue", target.UserId, { Key = key, Op = op, Amount = amount })
			end
		end
		for i, def in { { "+MÜNZEN", C.Green, value("Coins", "Add") }, { "SET MÜNZEN", C.Dark, value("Coins", "Set") },
			{ "+RZ", C.Red, value("RedPoints", "Add") }, { "SET RZ", C.Dark, value("RedPoints", "Set") } } do
			local b = button(def[1], 1, r1, def[2], def[3])
			b.Size = UDim2.new(0.18, -6, 1, 0)
			b.LayoutOrder = i + 1
			b.TextSize = 13
		end
		buttonRow(frame, { { "+XP", C.Purple, value("XP", "Add") }, { "SET LEVEL", C.Dark, value("Level", "Set") },
			{ "SET PRESTIGE", C.Dark, value("Prestige", "Set") }, { "+RAP", C.Orange, value("Rap", "Add") },
			{ "SET RAP", C.Yellow, value("Rap", "Set") } })
		-- Item der offenen Welt
		local countBox
		picker(frame, function()
			local item = ExtinctionConfig.Get(itemIds[itemIndex])
			return item and item.Name or "?"
		end, function(delta)
			itemIndex = (itemIndex - 1 + delta) % #itemIds + 1
		end, "ITEM GEBEN", C.Green, function()
			send("GiveItem", target.UserId, { Id = itemIds[itemIndex], Count = tonumber(countBox.Text) or 1 })
		end, function(r)
			countBox = textBox("Anzahl", r, { Size = UDim2.new(0.12, -6, 1, 0), Text = "1" })
			numeric(countBox)
		end)
		-- Skin
		picker(frame, function()
			local item = Cosmetics.Get(skinIds[skinIndex])
			return item and item.Name or "?"
		end, function(delta)
			skinIndex = (skinIndex - 1 + delta) % #skinIds + 1
		end, "SKIN GEBEN", C.Purple, function()
			send("GiveSkin", target.UserId, skinIds[skinIndex])
		end, function(r)
			button("SCHLÜSSEL", 1, r, C.Teal, function()
				send("GiveItem", target.UserId, { Id = ExtinctionConfig.Dungeon.KeyItem, Count = 1 })
			end).Size = UDim2.new(0.12, -6, 1, 0)
		end)
		-- Bewegen
		local frozen = target:GetAttribute("AdminFrozen") == true
		local defs = { { "HINGEHEN", C.Blue, function()
			send("GoTo", target.UserId)
		end } }
		if outranks(target) then
			table.insert(defs, { "HERHOLEN", C.Blue, function()
				send("Bring", target.UserId)
			end })
			table.insert(defs, { "INS CAMP", C.Blue, function()
				send("SendCamp", target.UserId)
			end })
			table.insert(defs, { frozen and "AUFTAUEN" or "EINFRIEREN", C.Dark, function()
				send("Freeze", target.UserId)
			end })
			table.insert(defs, { "RESPAWN", C.Dark, function()
				send("Respawn", target.UserId)
			end })
		end
		buttonRow(frame, defs)
		local life = { { "HEILEN", C.Green, function()
			send("Heal", target.UserId)
		end } }
		if outranks(target) then
			table.insert(life, { "TÖTEN", C.Red, function()
				send("Kill", target.UserId)
			end })
		end
		-- Arcade-Modi: verschieben und Team wechseln nur, solange Arcade an ist
		if Modes.ArcadeEnabled and outranks(target) then
			table.insert(life, { "TEAM", C.Dark, function()
				send("SwitchTeam", target.UserId)
			end })
			table.insert(life, { "FFA", C.Dark, function()
				send("MovePlayer", target.UserId, "FreeForAll")
			end })
		end
		buttonRow(frame, life)
	end
	moderationRows(frame, target)
end

detailBuilders.Effects = function(frame, target)
	detailHead(frame, target)
	section("EFFEKTE", frame)
	local god = target:GetAttribute("AdminGod") == true
	buttonRow(frame, {
		{ god and "GOTTMODUS AUS" or "GOTTMODUS AN", C.Yellow, function()
			send("God", target.UserId)
		end },
		{ "HEILEN", C.Green, function()
			send("Heal", target.UserId)
		end },
	}, 40)
	buttonRow(frame, {
		{ "DOPPEL-XP 30 MIN", C.Purple, function()
			send("XPBoost", target.UserId, 30)
		end },
		{ "DOPPEL-XP 2 STD", C.Purple, function()
			send("XPBoost", target.UserId, 120)
		end },
		{ "DOPPEL-XP 24 STD", C.Purple, function()
			send("XPBoost", target.UserId, 1440)
		end },
	}, 40)
	if outranks(target) then
		local frozen = target:GetAttribute("AdminFrozen") == true
		buttonRow(frame, {
			{ frozen and "AUFTAUEN" or "EINFRIEREN", C.Blue, function()
				send("Freeze", target.UserId)
			end },
			{ "RESPAWN", C.Dark, function()
				send("Respawn", target.UserId)
			end },
			{ "TÖTEN", C.Red, function()
				send("Kill", target.UserId)
			end },
		}, 40)
	end
	section("ICH", frame)
	buttonRow(frame, {
		{ "NOCLIP (B)", C.Teal, function()
			send("Noclip")
		end },
		{ "MEIN GOTTMODUS", C.Yellow, function()
			send("God", player.UserId)
		end },
	}, 40)
end

detailBuilders.Messages = function(frame, target)
	detailHead(frame, target)
	section("NACHRICHT AN " .. string.upper(target.DisplayName), frame)
	local r = row(frame, 40)
	local box = textBox("Nachricht (sieht nur dieser Spieler)", r, { Size = UDim2.new(0.72, -6, 1, 0) })
	button("SENDEN", 1, r, C.Green, function()
		if box.Text ~= "" then
			send("Message", target.UserId, box.Text)
			box.Text = ""
		end
	end).Size = UDim2.new(0.28, 0, 1, 0)
end

-- Rechte Seite neu bauen (gewählter Spieler, aktuelle Kategorie)
refreshDetail = function()
	local frame = detailFrames[currentCategory]
	if not frame then
		return
	end
	clear(frame)
	hideButton = nil
	tiles = {}
	if watchConnection then
		watchConnection:Disconnect()
		watchConnection = nil
	end
	local target = selected()
	if target then
		-- Knopftexte (EINFRIEREN/AUFTAUEN, Gottmodus, Rang) folgen den Attributen des Spielers
		watchConnection = target.AttributeChanged:Connect(function(name)
			if name == "AdminFrozen" or name == "AdminGod" or name == "StaffRank" then
				task.defer(refreshDetail)
			end
		end)
	end
	if not target then
		local hint = card(frame)
		label("Wähle links einen Spieler aus.", 16, hint, { TextColor3 = C.Muted })
		if currentCategory == "Messages" then
			-- Ankündigung geht auch ohne Spieler
			section("ANKÜNDIGUNG AN ALLE", frame)
			local r = row(frame, 40)
			local box = textBox("Text der Ankündigung", r, { Size = UDim2.new(0.72, -6, 1, 0) })
			button("ANKÜNDIGEN", 1, r, C.Green, function()
				if box.Text ~= "" then
					sendScoped("Announce", box.Text)
					box.Text = ""
				end
			end).Size = UDim2.new(0.28, 0, 1, 0)
		end
		order(frame)
		return
	end
	detailBuilders[currentCategory](frame, target)
	if currentCategory == "Messages" then
		section("ANKÜNDIGUNG AN ALLE", frame)
		local r = row(frame, 40)
		local box = textBox("Text der Ankündigung", r, { Size = UDim2.new(0.72, -6, 1, 0) })
		button("ANKÜNDIGEN", 1, r, C.Green, function()
			if box.Text ~= "" then
				sendScoped("Announce", box.Text)
				box.Text = ""
			end
		end).Size = UDim2.new(0.28, 0, 1, 0)
	end
	order(frame)
end

-- ---------- Seiten ohne Spielerliste ----------

-- Event-Karte: Name, Live-Status rechts, Knöpfe darunter. buttons = { { Text, Aktion, Wert, Farbe } }
local function eventCard(page, key, title, buttons)
	local c = card(page)
	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, c)
	label(title, 17, head, { Size = UDim2.new(0.6, 0, 1, 0) })
	eventStatus[key] = label("", 13, head, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.4, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Muted })
	local defs = {}
	for _, def in buttons do
		table.insert(defs, { def[1], def[4], function()
			sendScoped(def[2], def[3])
		end })
	end
	buttonRow(c, defs)
	order(c)
end

local function buildEvents(page)
	section("ALLES", page)
	local all = card(page)
	buttonRow(all, {
		{ "ALLE EVENTS BEENDEN", C.Red, function()
			sendScoped("ExtStop", "All")
		end },
		{ "ZOMBIES ENTFERNEN", C.Dark, function()
			sendScoped("ExtStop", "Zombies")
		end },
		{ "DUNGEONS BEENDEN", C.Dark, function()
			sendScoped("DungeonStopAll")
		end },
	}, 38)
	order(all)
	section("EVENTS DER OFFENEN WELT", page)
	eventCard(page, "Airdrop", "Lootdrop", {
		{ "START", "ExtAirdrop", nil, C.Orange }, { "BEI MIR", "ExtAirdrop", "Here", C.Orange }, { "STOP", "ExtStop", "Airdrop", C.Red } })
	eventCard(page, "Convoy", "Konvoi", { { "START", "ExtConvoy", nil, C.Orange }, { "STOP", "ExtStop", "Convoy", C.Red } })
	eventCard(page, "HeliCrash", "Heli-Absturz", { { "START", "ExtHeliCrash", nil, C.Orange },
		{ "VOR MIR", "ExtHeliCrash", "Here", C.Orange }, { "STOP", "ExtStop", "HeliCrash", C.Red } })
	eventCard(page, "Horde", "Horden-Kiste", { { "START", "ExtHordeCrate", nil, C.Orange },
		{ "VOR MIR", "ExtHordeCrate", "Here", C.Orange }, { "STOP", "ExtStop", "HordeCrate", C.Red } })
	eventCard(page, "BloodMoon", "Blutmond", { { "START", "BloodMoon", "Start", nil },
		{ "STOP", "ExtStop", "BloodMoon", C.Red } })
	eventCard(page, "Storm", "Sturmnacht", { { "START", "Storm", "Start", nil },
		{ "STOP", "ExtStop", "Storm", C.Red } })
	eventCard(page, "Bounty", "Kopfgeld", { { "AUF MICH", "ExtBountyMe", nil, nil },
		{ "STOP", "ExtStop", "Bounty", C.Red } })
	eventCard(page, "Redzone", "Rote Zone", { { "WEITERZIEHEN", "ExtRedzone", nil, C.Orange } })
	section("SPAWNEN", page)
	local spawn = card(page)
	buttonRow(spawn, {
		{ "12 ZOMBIES UM MICH", C.Orange, function()
			send("ExtHorde", 12)
		end },
		{ "30 ZOMBIES UM MICH", C.Orange, function()
			send("ExtHorde", 30)
		end },
		{ "BOSSE SPAWNEN", C.Red, function()
			sendScoped("ExtBosses")
		end },
	})
	order(spawn)
end

-- Live-Status der Events (Karten-Attribute der offenen Welt, Blutmond/Sturm aus DayCycle)
local function refreshEvents()
	local maps = workspace:FindFirstChild("Maps")
	local map = maps and maps:FindFirstChild("Extinction")
	local function listActive(attribute)
		local raw = map and map:GetAttribute(attribute)
		return type(raw) == "string" and raw ~= "" and raw ~= "[]"
	end
	local now = workspace:GetServerTimeNow()
	local bounty = map and map:GetAttribute("Bounty")
	local states = {
		Airdrop = listActive("Airdrops"),
		Convoy = listActive("Convoys"),
		HeliCrash = listActive("HeliCrashes"),
		Horde = listActive("Hordes"),
		BloodMoon = DayCycle.IsBloodMoon(now),
		Storm = DayCycle.IsStorm(now),
		Bounty = type(bounty) == "string" and bounty ~= "",
	}
	for key, statusText in eventStatus do
		if key ~= "Redzone" then
			local on = states[key]
			statusText.Text = on and "● LÄUFT" or "○ aus"
			statusText.TextColor3 = on and C.Green or C.Muted
		end
	end
end

local clockLabel
local function buildWorld(page)
	section("UHRZEIT", page)
	local time = card(page)
	clockLabel = label("", 15, time, { TextColor3 = C.Muted, Font = BODY_FONT })
	local defs = {}
	for _, hour in { 6, 12, 18, 22, 0 } do
		table.insert(defs, { string.format("%02d:00", hour), hour >= 6 and hour < 20 and C.Orange or nil,
			function()
				sendScoped("SetClock", hour)
			end })
	end
	buttonRow(time, defs, 38)
	order(time)
	section("WETTER", page)
	local weather = card(page)
	buttonRow(weather, {
		{ "KEIN NEBEL", C.Blue, function()
			sendScoped("SetFog", 0)
		end },
		{ "LEICHTER NEBEL", C.Dark, function()
			sendScoped("SetFog", 0.5)
		end },
		{ "DICHTER NEBEL", C.Dark, function()
			sendScoped("SetFog", 1)
		end },
		{ "AUTOMATISCH", C.Green, function()
			sendScoped("SetFog", "auto")
		end },
	}, 38)
	buttonRow(weather, {
		{ "STURMNACHT AN/AUS", nil, function()
			sendScoped("Storm")
		end },
		{ "BLUTMOND AN/AUS", nil, function()
			sendScoped("BloodMoon")
		end },
	}, 38)
	order(weather)
	section("ICH", page)
	local me = card(page)
	buttonRow(me, {
		{ "NOCLIP (B)", C.Teal, function()
			send("Noclip")
		end },
		{ "TAG / NACHT", C.Orange, function()
			send("DayNight")
		end },
	})
	order(me)
	-- Bots der offenen Welt (spawnen beim Admin draußen, sonst in der roten Zone)
	section("BOTS", page)
	local bots = card(page)
	buttonRow(bots, {
		{ "+1 BOT", C.Orange, function()
			send("SpawnBot", "Extinction")
		end },
		{ "+5 BOTS", C.Orange, function()
			for _ = 1, 5 do
				send("SpawnBot", "Extinction")
			end
		end },
		{ "ALLE BOTS ENTFERNEN", C.Red, function()
			send("RemoveBots")
		end },
	})
	botCountLabel = label("", 13, bots, { TextColor3 = C.Muted, Font = BODY_FONT })
	order(bots)
	-- Arcade-Modi steuern und ihre Einstellungen: nur solange Arcade an ist (Modes.ArcadeEnabled)
	if Modes.ArcadeEnabled then
		section("MODI", page)
		for _, modeId in { "Domination", "Wingman", "Arena" } do
			local c = card(page)
			label(modeId, 15, c)
			buttonRow(c, {
				{ "JETZT STARTEN", C.Green, function()
					send("ModeStart", modeId)
				end },
				{ "RUNDE BEENDEN", C.Dark, function()
					send("ModeEndRound", modeId)
				end },
				{ "RESET", C.Red, function()
					send("ModeResetMatch", modeId)
				end },
			})
			order(c)
		end
	end
end

local function refreshWorld()
	if clockLabel then
		local now = workspace:GetServerTimeNow()
		clockLabel.Text = "Jetzt " .. DayCycle.Label(DayCycle.Clock(now)) .. (DayCycle.Fog(now) > 0.05 and "  ·  Nebel" or "")
	end
	if botCountLabel then
		local count = 0
		local folder = ReplicatedStorage:FindFirstChild("BotInfo")
		for _, info in folder and folder:GetChildren() or {} do
			if info:GetAttribute("Mode") == "Extinction" then
				count += 1
			end
		end
		botCountLabel.Text = "Bots in der offenen Welt: " .. count
	end
end

-- Logs: Admin-Log (neueste zuerst)
local function refreshLogs()
	if not logSection then
		return
	end
	clear(logSection)
	if #logs == 0 then
		label("Noch keine Einträge", 14, card(logSection), { TextColor3 = C.Muted })
		return
	end
	for i, entry in logs do
		local box = make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = WHITE,
			BackgroundTransparency = i % 2 == 0 and 0.96 or 0.93, BorderSizePixel = 0, LayoutOrder = i }, logSection)
		corner(box, 4)
		label(os.date("%H:%M", tonumber(entry.At) or 0) .. "  " .. tostring(entry.Admin) .. "  ·  " .. tostring(entry.Action)
			.. (entry.Target ~= "" and ("  →  " .. tostring(entry.Target)) or ""), 14, box,
			{ Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -20, 0, 18) })
		label(tostring(entry.Text), 12, box, { Position = UDim2.new(0, 10, 0, 23), Size = UDim2.new(1, -20, 0, 16),
			TextColor3 = C.Muted, Font = BODY_FONT })
	end
end

local function buildLogs(page)
	local head = row(page, 36)
	label("ADMIN-LOG (DIESER SERVER)", 16, head, { Size = UDim2.new(0.7, 0, 1, 0), Font = F.Display })
	button("AKTUALISIEREN", 1, head, C.Blue, function()
		send("Logs")
	end).Size = UDim2.new(0.3, 0, 1, 0)
	logSection = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 },
		page)
	list(logSection, 4)
	refreshLogs()
end

local function buildSettings(page)
	local lastGroup, c = nil, nil
	for _, def in GameSettings.List do
		-- ohne Arcade nur die allgemeinen Einstellungen (Arcade-Modi laufen nicht)
		if not Modes.ArcadeEnabled and def.Group ~= "Allgemein" then
			continue
		end
		if def.Group ~= lastGroup then
			if c then
				order(c)
			end
			lastGroup = def.Group
			section(string.upper(def.Group), page)
			c = card(page)
		end
		local r = row(c)
		label(def.Label, 15, r, { Size = UDim2.new(0.55, 0, 1, 0), Font = BODY_FONT })
		local minus = button("−", 1, r, C.Dark, function()
			send("SetSetting", def.Key, GameSettings.Get(def.Key) - def.Step)
		end)
		minus.Size = UDim2.new(0, 40, 1, 0)
		valueLabels[def.Key] = label("", 16, r, { Size = UDim2.new(0, 70, 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.Text })
		local plus = button("+", 1, r, C.Dark, function()
			send("SetSetting", def.Key, GameSettings.Get(def.Key) + def.Step)
		end)
		plus.Size = UDim2.new(0, 40, 1, 0)
		order(r)
	end
	if c then
		order(c)
	end
end

local function refreshSettings()
	for key, valueLabel in valueLabels do
		valueLabel.Text = tostring(GameSettings.Get(key))
	end
end

local function buildEconomy(page)
	section("ALLE SPIELER", page)
	local all = card(page)
	local defs = {}
	for _, amount in { 1000, 10000, 100000 } do
		table.insert(defs, { "+" .. short(amount) .. " MÜNZEN AN ALLE", C.Gold, function()
			sendScoped("GiveAllCoins", amount)
		end })
	end
	buttonRow(all, defs, 38)
	order(all)
	section("MIR GEBEN", page)
	local give = card(page)
	buttonRow(give, {
		{ "AUFSÄTZE", C.Teal, function()
			send("ExtGive", "Attachments")
		end },
		{ "GRANATEN", C.Teal, function()
			send("ExtGive", "Throwables")
		end },
		{ "AUSRÜSTUNG", C.Teal, function()
			send("ExtGive", "Kit")
		end },
		{ "DUNGEON-SCHLÜSSEL", C.Teal, function()
			send("ExtGive", "DungeonKey")
		end },
	})
	local r = row(give)
	local rzBox = textBox("Menge RZ", r, { Size = UDim2.new(0.3, -6, 1, 0), Text = "100" })
	numeric(rzBox)
	button("RZ GEBEN", 1, r, C.Red, function()
		send("GiveRedPoints", tonumber(rzBox.Text) or 0)
	end).Size = UDim2.new(0.3, 0, 1, 0)
	order(r)
	order(give)
	buildSettings(page)
end

-- Sperrliste (Suche)
local function refreshBans()
	if not banSection then
		return
	end
	clear(banSection)
	if #bans == 0 then
		label("Keine Sperren", 14, card(banSection), { TextColor3 = C.Muted })
		return
	end
	for i, entry in bans do
		local box = card(banSection)
		box.LayoutOrder = i
		label(tostring(entry.Name) .. "  ·  " .. tostring(entry.UserId), 16, box)
		label(tostring(entry.Reason) .. "  ·  " .. tostring(entry.Left) .. "  ·  von " .. tostring(entry.By), 12, box,
			{ TextColor3 = C.Muted, Font = BODY_FONT })
		if rights().Unban then
			local r = row(box, 30)
			button("ENTSPERREN", 1, r, C.Green, function()
				send("Unban", entry.UserId)
			end, 30).Size = UDim2.new(0, 130, 1, 0)
		end
		order(box)
	end
end

-- Ergebnis der Suche (AdminData "Lookup")
local function refreshLookup()
	if not lookupSection then
		return
	end
	clear(lookupSection)
	if not lookup then
		return
	end
	local data = lookup
	local box = card(lookupSection)
	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1 }, box)
	avatar(data.UserId, 56, head)
	local rank = StaffConfig.Get(data.Rank)
	label(string.upper(tostring(data.Name)) .. (rank and ("  " .. StaffConfig.Prefix(rank, 13)) or ""), 20, head,
		{ Position = UDim2.new(0, 68, 0, 4), Size = UDim2.new(1, -70, 0, 26), RichText = true })
	label(tostring(data.UserId) .. "  ·  " .. (data.Online and "auf diesem Server" or "nicht auf diesem Server")
		.. (data.Hidden and "  ·  vor Bestenliste versteckt" or ""), 13, head,
		{ Position = UDim2.new(0, 68, 0, 32), Size = UDim2.new(1, -70, 0, 18), TextColor3 = C.Muted, Font = BODY_FONT })
	if data.Found then
		local tileRow = make("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1 }, box)
		list(tileRow, 6, true)
		local defs = { { short(data.Coins), "MÜNZEN" }, { short(data.RedPoints), "RZ" },
			{ tostring(data.Level) .. (data.Prestige > 0 and (" P" .. data.Prestige) or ""), "LEVEL" },
			{ short(data.Rap), "RAP" }, { short(data.Zombies), "ZOMBIES" }, { short(data.Kills), "KILLS" } }
		for i, def in defs do
			local tile = make("Frame", { Size = UDim2.new(1 / #defs, -5, 1, 0), BackgroundColor3 = BOX, BackgroundTransparency = 0,
				BorderSizePixel = 0, LayoutOrder = i }, tileRow)
			corner(tile, 4)
			stroke(tile)
			label(def[1], 18, tile, { Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(1, -12, 0, 22), Font = F.Display })
			label(def[2], 11, tile, { Position = UDim2.new(0, 8, 0, 26), Size = UDim2.new(1, -12, 0, 14), TextColor3 = C.Muted })
		end
	else
		label("Kein Spielstand gefunden" .. (data.Error and (" (" .. tostring(data.Error) .. ")") or ""), 13, box,
			{ TextColor3 = C.Muted, Font = BODY_FONT })
	end
	if data.Ban then
		local untilTime = tonumber(data.Ban.Until) or 0
		label("GESPERRT " .. (untilTime == 0 and "dauerhaft" or ("bis " .. os.date("%d.%m.%Y %H:%M", untilTime))) .. "  ·  "
			.. tostring(data.Ban.Reason) .. "  ·  von " .. tostring(data.Ban.By), 14, box, { TextColor3 = C.Red })
	end
	-- Moderation per UserId (der Server prüft den Rang, auch offline)
	local r = row(box)
	local reasonBox = textBox("Grund", r, { Size = UDim2.new(0.3, -6, 1, 0), Text = "Regelverstoß" })
	local daysBox = textBox("Tage (0 = für immer)", r, { Size = UDim2.new(0.22, -6, 1, 0) })
	numeric(daysBox)
	if rights().BanDays ~= nil then
		button("BAN", 1, r, C.Red, function()
			local days = tonumber(daysBox.Text) or (banAllowed(0) and 0 or 1)
			if not banAllowed(days) then
				setStatus("So lange darfst du nicht sperren.", C.Red)
				return
			end
			send("Ban", data.UserId, { Days = days, Reason = reasonBox.Text })
			task.delay(1, function()
				send("Lookup", data.UserId)
			end)
		end).Size = UDim2.new(0.22, -6, 1, 0)
	end
	if rights().Unban and data.Ban then
		button("UNBAN", 1, r, C.Green, function()
			send("Unban", data.UserId)
			task.delay(1, function()
				send("Lookup", data.UserId)
			end)
		end).Size = UDim2.new(0.22, -6, 1, 0)
	end
	order(r)
	if rights().Assign then
		label("TEAM-RANG", 13, box, { TextColor3 = C.Muted })
		rankButtons(box, function()
			return data.UserId
		end)
	end
	order(box)
end

local function buildLookup(page)
	section("SPIELER SUCHEN (AUCH OFFLINE)", page)
	local r = row(page, 40)
	local box = textBox("Name oder UserId", r, { Size = UDim2.new(0.7, -6, 1, 0) })
	local function search()
		if box.Text ~= "" then
			send("Lookup", box.Text)
		end
	end
	box.FocusLost:Connect(function(enter)
		if enter then
			search()
		end
	end)
	button("SUCHEN", 1, r, C.Red, search).Size = UDim2.new(0.3, 0, 1, 0)
	lookupSection = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 },
		page)
	list(lookupSection, 8)
	local head = row(page, 36)
	label("SPERRLISTE", 16, head, { Size = UDim2.new(0.7, 0, 1, 0), Font = F.Display })
	button("AKTUALISIEREN", 1, head, C.Blue, function()
		send("BanList")
	end).Size = UDim2.new(0.3, 0, 1, 0)
	banSection = make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 },
		page)
	list(banSection, 8)
	refreshBans()
end

-- ---------- Rahmen ----------

local function showCategory(id)
	currentCategory = id
	local def
	for _, entry in CATEGORIES do
		if entry.Id == id then
			def = entry
		end
	end
	local withList = def and def.List
	listColumn.Visible = withList == true
	contentArea.Position = withList and UDim2.new(0, 276, 0, 0) or UDim2.new(0, 0, 0, 0)
	contentArea.Size = withList and UDim2.new(1, -276, 1, 0) or UDim2.new(1, 0, 1, 0)
	for pageId, page in pages do
		page.Visible = pageId == id
	end
	-- aktiver Reiter: weiße Schrift, helle Schicht, roter Streifen links (wie im Menü der offenen Welt)
	for catId, b in categoryButtons do
		local on = catId == id
		b.TextColor3 = on and C.Text or C.Muted
		b.BackgroundTransparency = on and 0.92 or 1
		b.Underline.Visible = on
	end
	if headerTitle and def then
		headerTitle.Text = def.Text
	end
	if withList then
		refreshList(true)
		refreshDetail()
	elseif id == "Logs" then
		send("Logs")
	end
end

local function setOpen(open)
	isOpen = open
	panel.Visible = open
	if open then
		refreshSettings()
		refreshEvents()
		refreshWorld()
		showCategory(currentCategory)
		RunService:BindToRenderStep("AdminMouse", Enum.RenderPriority.Camera.Value + 2, function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
	else
		RunService:UnbindFromRenderStep("AdminMouse")
	end
	UITheme.HoldCamera("Admin", open) -- Blickrichtung nach dem Schließen wie vorher
	UITheme.SetBlur("Admin", open) -- Welt dahinter unscharf wie beim Menü der offenen Welt
end

local function newPage(id, withList)
	if withList then
		local frame = scroller(contentArea, { Name = "Detail_" .. id, Visible = false })
		detailFrames[id] = frame
		pages[id] = frame
		return frame
	end
	local page = scroller(contentArea, { Name = "Page_" .. id, Visible = false })
	pages[id] = page
	return page
end

-- Panel an den Bildschirm anpassen (kleine Bildschirme, Handy)
local function fitScale(scale)
	local camera = workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.min(1.1, size.X * 0.96 / PANEL_W, size.Y * 0.9 / PANEL_H)
end

local function build()
	gui = make("ScreenGui", { Name = "AdminPanel", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

	-- Knopf oben links: dunkles Glas mit rotem Streifen
	toggleButton = button(full() and "ADMIN (P)" or "MOD (P)", 110, gui, nil, function()
		setOpen(not isOpen)
	end, 30)
	toggleButton.Position = UDim2.new(0, 150, 0, 6)
	toggleButton.TextSize = 13
	toggleButton.BackgroundColor3 = GLASS
	toggleButton.BackgroundTransparency = 0.1
	toggleButton:SetAttribute("Rest", 0.1)
	make("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = RED, BorderSizePixel = 0 }, toggleButton)

	panel = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, PANEL_W, 0, PANEL_H), BackgroundTransparency = 1, Visible = false, Active = true }, gui)
	local scale = make("UIScale", {}, panel)
	fitScale(scale)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			fitScale(scale)
		end)
	end

	-- Seitenleiste: ADMIN, Rang, Kategorien untereinander, unten der Hinweis zum Schließen
	local sidebar = make("Frame", { Size = UDim2.new(0, SIDEBAR_W, 1, 0), BackgroundColor3 = BLACK, BackgroundTransparency = 0,
		BorderSizePixel = 0 }, panel)
	label("ADMIN", 24, sidebar, { Position = UDim2.new(0, 24, 0, 40), Size = UDim2.new(1, -48, 0, 28), Font = F.Display,
		TextColor3 = RED })
	local staff = StaffConfig.Of(player)
	label(UITheme.Upper((staff and staff.Name or (full() and "ADMIN" or "MOD")) .. " · PANEL"), 11, sidebar,
		{ Position = UDim2.new(0, 25, 0, 68), Size = UDim2.new(1, -48, 0, 14), TextColor3 = C.Muted })
	local categories = make("Frame", { Position = UDim2.new(0, 0, 0, 110), Size = UDim2.new(1, 0, 1, -160),
		BackgroundTransparency = 1 }, sidebar)
	list(categories, 2)
	label("P  SCHLIESSEN", 11, sidebar, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -20),
		Size = UDim2.new(1, -48, 0, 14), TextColor3 = C.Muted })
	for index, def in CATEGORIES do
		if def.Admin and not full() then
			continue -- Moderatoren: nur SPIELER und SUCHE
		end
		local b = make("TextButton", { Name = "Tab_" .. def.Id, Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = WHITE,
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = def.Text, Font = FONT, TextSize = 15, TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false, LayoutOrder = index }, categories)
		make("UIPadding", { PaddingLeft = UDim.new(0, 24) }, b)
		make("Frame", { Name = "Underline", Position = UDim2.new(0, -24, 0, 0), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = RED,
			BorderSizePixel = 0, Visible = false }, b)
		b.MouseEnter:Connect(function()
			if currentCategory ~= def.Id then
				b.TextColor3 = C.Text
				b.BackgroundTransparency = 0.96
			end
		end)
		b.MouseLeave:Connect(function()
			if currentCategory ~= def.Id then
				b.TextColor3 = C.Muted
				b.BackgroundTransparency = 1
			end
		end)
		b.Activated:Connect(function()
			showCategory(def.Id)
		end)
		categoryButtons[def.Id] = b
	end

	-- Fläche rechts: Kopfzeile (roter Strich, Titel, Server-Umschalter, Schließen), Inhalt, Rückmeldung
	local right = make("Frame", { Position = UDim2.new(0, SIDEBAR_W, 0, 0), Size = UDim2.new(1, -SIDEBAR_W, 1, 0),
		BackgroundColor3 = SURFACE, BackgroundTransparency = 0, BorderSizePixel = 0 }, panel)
	local header = make("Frame", { Position = UDim2.new(0, 22, 0, HEADER_Y), Size = UDim2.new(1, -44, 0, HEADER_H),
		BackgroundColor3 = RAISED, BackgroundTransparency = 0, BorderSizePixel = 0 }, right)
	make("Frame", { Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = RED, BorderSizePixel = 0 }, header)
	headerTitle = label("SPIELER", 20, header, { Position = UDim2.new(0, 20, 0, 0), Size = UDim2.new(0.5, 0, 1, 0),
		Font = F.Display })
	if full() then
		scopeButton = button("DIESER SERVER", 1, header, nil, function()
			allServers = not allServers
			scopeButton.Text = allServers and "ALLE SERVER" or "DIESER SERVER"
			recolor(scopeButton, allServers and C.Green or nil)
			setStatus(allServers and "Server-Aktionen (Events, Ankündigung, Welt, Münzen an alle) laufen jetzt auf ALLEN Servern."
				or "Aktionen nur auf diesem Server.", allServers and C.Text or C.Muted)
		end, 34)
		scopeButton.AnchorPoint = Vector2.new(1, 0.5)
		scopeButton.Position = UDim2.new(1, -56, 0.5, 0)
		scopeButton.Size = UDim2.new(0, 170, 0, 34)
	end
	local close = make("TextButton", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.new(0, 42, 0, 42), BackgroundColor3 = WHITE, BackgroundTransparency = 1, Text = "", AutoButtonColor = false },
		header)
	UITheme.Cross(close, 14, C.Text, 2)
	close.MouseEnter:Connect(function()
		close.BackgroundTransparency = 0.9
	end)
	close.MouseLeave:Connect(function()
		close.BackgroundTransparency = 1
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local main = make("Frame", { Position = UDim2.new(0, 22, 0, HEADER_Y + HEADER_H + 16),
		Size = UDim2.new(1, -44, 1, -(HEADER_Y + HEADER_H + 16) - 40), BackgroundTransparency = 1 }, right)
	buildListColumn(main)
	contentArea = make("Frame", { BackgroundTransparency = 1 }, main)

	statusLabel = label("Bereit", 13, right, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -12),
		Size = UDim2.new(1, -48, 0, 18), TextColor3 = C.Muted })
	UITheme.Outline(statusLabel)

	newPage("Players", true)
	if full() then
		newPage("Effects", true)
		buildEvents(newPage("Events"))
		newPage("Messages", true)
		buildWorld(newPage("World"))
		buildLogs(newPage("Logs"))
		buildEconomy(newPage("Economy"))
	end
	buildLookup(newPage("Lookup"))
	for _, page in pages do
		order(page)
	end
	showCategory(currentCategory)
end

function AdminPanel.Init()
	-- warten, bis der Server Admin oder Moderator setzt (StaffService)
	while not (player:GetAttribute("IsAdmin") or player:GetAttribute("IsMod")) do
		player.AttributeChanged:Wait()
	end
	build()

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.P then
			setOpen(not isOpen)
		end
	end)
	Remotes.AdminStatus.OnClientEvent:Connect(function(message)
		setStatus(tostring(message), C.Text)
	end)
	Remotes.AdminData.OnClientEvent:Connect(function(kind, data)
		if type(data) ~= "table" then
			return
		end
		if kind == "Bans" then
			bans = data
			refreshBans()
		elseif kind == "Logs" then
			logs = data
			refreshLogs()
		elseif kind == "Lookup" then
			lookup = data
			refreshLookup()
		end
	end)
	send("BanList")
	ReplicatedStorage.AttributeChanged:Connect(function()
		if isOpen then
			refreshSettings()
		end
	end)
	task.spawn(function()
		while true do
			if isOpen then
				refreshEvents()
				refreshWorld()
				if detailFrames[currentCategory] then
					refreshList(false)
					refreshTiles()
				end
			end
			task.wait(1)
		end
	end)
end

return AdminPanel
