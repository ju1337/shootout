-- Zentrale (ModuleScript)
-- Einsatzzentrale in Camp Phoenix (Safe Zone der offenen Welt, früher der Hub): Halle mit Shop-Vitrine, Bestenlisten,
-- Top-3-Podest, Agent der Woche, Glücksrad, Einsatz-Tafel und dem Tor zum Markt. Die Teile liegen in der Gruppe
-- "Zentrale" der Map Extinction (immer geladen, siehe tools/streaming.py); gebaut von build_zentrale() in
-- tools/build_maps.py, aufgestellt von zentrale() in tools/extinction_world.py.

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
