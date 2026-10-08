-- Sfx (ModuleScript, Server und Client)
-- Spielt Geräusche aus SoundLibrary ab (alles außer Waffen, die macht WeaponEffects).
--   Sfx.At(name, where, opts)      einmal an einer Stelle (Vector3) oder an einem Teil/Attachment (wandert mit). Auf dem
--                                  Server hören es alle in der Nähe (der Sound repliziert), auf dem Client nur man selbst.
--   Sfx.Loop(name, where, opts)    Schleife an einem Teil/Attachment; gibt den Sound zurück (Volume/PlaybackSpeed
--                                  dürfen geändert werden, Destroy beendet). Mit Range 0 im Bibliothekseintrag 2D.
--   Sfx.UI(name, opts)             (Client) ohne Raumklang, nur für einen selbst
--   Sfx.ToPlayers(list, name, position, opts)  (Server) nur für diese Spieler (Remote PlaySfx): Ansagen, Kaufen …
--   Sfx.InitClient()               (Client) Remote PlaySfx annehmen und alle Aufnahmen vorladen
-- opts = { Volume = Faktor, Pitch = Faktor, Range = Hörweite (Studs) }

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local SoundLibrary = require(script.Parent.SoundLibrary)
local Remotes = require(script.Parent.Remotes)

local Sfx = {}

local lastClip = {}

-- Zufällige Aufnahme, nie zweimal hintereinander dieselbe
local function pick(name)
	local def = SoundLibrary.Get(name)
	if not def or #def.Clips == 0 then
		return nil, nil
	end
	local index = math.random(1, #def.Clips)
	if #def.Clips > 1 and index == lastClip[name] then
		index = index % #def.Clips + 1
	end
	lastClip[name] = index
	return def, def.Clips[index]
end

-- Sound bauen; gibt Sound und Lebensdauer (Sekunden) zurück
local function build(name, opts, looped)
	local def, clip = pick(name)
	if not def then
		return nil, 0
	end
	opts = opts or {}
	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = clip.Id
	sound.Volume = math.min(10, (clip.Gain or 1) * (opts.Volume or 1))
	local pitch = (def.Pitch or 1) * (opts.Pitch or 1) * (looped and 1 or (0.95 + math.random() * 0.1))
	sound.PlaybackSpeed = pitch
	sound.Looped = looped == true
	local length = 6
	if clip.Region then
		if looped then
			sound.LoopRegion = NumberRange.new(clip.Region[1], clip.Region[2])
		end
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(clip.Region[1], clip.Region[2])
		length = clip.Region[2] - clip.Region[1]
	end
	-- Stimmfilter: Höhen weg (dumpf, kehlig) und angeraut
	local voice = def.Voice
	if voice then
		if voice.Muffle then
			local eq = Instance.new("EqualizerSoundEffect")
			eq.HighGain = voice.Muffle
			eq.MidGain = voice.Muffle * 0.3
			eq.LowGain = 2
			eq.Parent = sound
		end
		if voice.Grit and voice.Grit > 0 then
			local grit = Instance.new("DistortionSoundEffect")
			grit.Level = voice.Grit
			grit.Parent = sound
		end
	end
	local range = opts.Range or def.Range or 80
	if range > 0 then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = math.max(6, range * 0.12)
		sound.RollOffMaxDistance = range
	end
	return sound, length / pitch + 0.5
end

-- Halter für eine Stelle (Attachment im Terrain) oder das Teil selbst
local function holder(where)
	if typeof(where) == "Vector3" then
		local anchor = Instance.new("Attachment")
		anchor.Name = "SfxAnchor"
		anchor.WorldPosition = where
		anchor.Parent = workspace.Terrain
		return anchor, true
	end
	if typeof(where) == "Instance" and (where:IsA("BasePart") or where:IsA("Attachment")) then
		return where, false
	end
	return nil, false
end

function Sfx.At(name, where, opts)
	local parent, own = holder(where)
	if not parent then
		return nil
	end
	local sound, life = build(name, opts, false)
	if not sound then
		if own then
			parent:Destroy()
		end
		return nil
	end
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(own and parent or sound, life)
	return sound
end

function Sfx.Loop(name, where, opts)
	local parent = holder(where)
	if not parent then
		return nil
	end
	local sound = build(name, opts, true)
	if not sound then
		return nil
	end
	sound.Parent = parent
	sound:Play()
	return sound
end

function Sfx.UI(name, opts)
	if not RunService:IsClient() then
		return nil
	end
	local sound, life = build(name, opts, false)
	if not sound then
		return nil
	end
	sound.RollOffMaxDistance = 10000
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, life)
	return sound
end

-- (Server) nur für diese Spieler: mit position im Raum, sonst 2D
function Sfx.ToPlayers(players, name, position, opts)
	if not RunService:IsServer() then
		return
	end
	for _, player in players do
		Remotes.PlaySfx:FireClient(player, name, position, opts)
	end
end

function Sfx.InitClient()
	Remotes.PlaySfx.OnClientEvent:Connect(function(name, position, opts)
		if type(name) ~= "string" then
			return
		end
		opts = type(opts) == "table" and opts or nil
		if typeof(position) == "Vector3" then
			Sfx.At(name, position, opts)
		else
			Sfx.UI(name, opts)
		end
	end)
	-- alle Aufnahmen vorladen, damit nichts zu spät kommt
	task.defer(function()
		local list = {}
		for _, def in SoundLibrary.Sounds do
			for _, clip in def.Clips do
				local sound = Instance.new("Sound")
				sound.SoundId = clip.Id
				table.insert(list, sound)
			end
		end
		pcall(game:GetService("ContentProvider").PreloadAsync, game:GetService("ContentProvider"), list)
	end)
end

return Sfx
