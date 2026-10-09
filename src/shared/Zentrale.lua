-- Zentrale (ModuleScript)
-- Phönixplatz in Camp Phoenix (Safe Zone der offenen Welt, früher der Hub): Agent der Woche, Glücksrad, Ausrüster mit
-- Shop-Vitrine, Ruhmeswand mit Bestenlisten, Siegerpodest mit Lagebericht und das Tor zum Markt im Depot. Die Teile
-- liegen in der Gruppe "Zentrale" der Map Extinction (immer geladen, siehe tools/streaming.py); gebaut in
-- tools/camp_phoenix.py.

local Zentrale = {}

Zentrale.Map = "Extinction"
Zentrale.Group = "Zentrale"

-- Ordner mit den Teilen der Zentrale. timeout: so lange warten (Client: Streaming), nil = nicht warten
function Zentrale.Folder(timeout: number?): Instance?
	local maps = if timeout then workspace:WaitForChild("Maps", timeout) else workspace:FindFirstChild("Maps")
	local map = maps and (if timeout then maps:WaitForChild(Zentrale.Map, timeout) else maps:FindFirstChild(Zentrale.Map))
	if not map then
		return nil
	end
	if timeout then
		return map:WaitForChild(Zentrale.Group, timeout)
	end
	return map:FindFirstChild(Zentrale.Group)
end

-- Ein Teil der Zentrale (z. B. "WheelSpot"); wartet höchstens timeout Sekunden
function Zentrale.Part(name: string, timeout: number?): Instance?
	local folder = Zentrale.Folder(timeout)
	if not folder then
		return nil
	end
	if timeout then
		return folder:WaitForChild(name, timeout)
	end
	return folder:FindFirstChild(name)
end

return Zentrale
