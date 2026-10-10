-- Tempo-Effekte mit eigener Laufzeit je Quelle (Adrenalin, Spritze des Chirurgen, BLAZE nach einem Kill).
-- Alle wirken zusammen: SpeedMultiplier am Charakter ist das Produkt der laufenden Effekte. Vorher schrieben alle direkt
-- auf SpeedMultiplier, und wer zuletzt ablief, setzte auf 1 zurück (z. B. beendete die Spritze das Adrenalin).

local SpeedEffects = {}

local tokens = setmetatable({}, { __mode = "k" }) -- [Charakter] = { [Quelle] = Marke des laufenden Effekts }

local function recompute(character)
	local product = 1
	for name, value in character:GetAttributes() do
		if string.sub(name, 1, 6) == "Speed_" and type(value) == "number" then
			product *= value
		end
	end
	character:SetAttribute("SpeedMultiplier", product)
end

-- Effekt source mit Faktor factor für duration Sekunden (gleiche Quelle erneut: ersetzt und verlängert)
function SpeedEffects.Apply(character, source, factor, duration)
	local token = {}
	tokens[character] = tokens[character] or {}
	tokens[character][source] = token
	character:SetAttribute("Speed_" .. source, factor)
	recompute(character)
	task.delay(duration, function()
		local list = tokens[character]
		if list and list[source] == token and character.Parent then
			list[source] = nil
			character:SetAttribute("Speed_" .. source, nil)
			recompute(character)
		end
	end)
end

return SpeedEffects
