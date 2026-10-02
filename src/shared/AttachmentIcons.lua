-- AttachmentIcons (ModuleScript, nur Client)
-- Flache Symbole für die Waffen-Aufsätze (Lobby: LOADOUT · AUFSÄTZE), aus Formen gebaut (keine Bilder nötig).
-- Jedes Symbol ist eine Liste von Teilen im 100x100-Raster: { Mitte X, Mitte Y, Breite, Höhe, Drehung,
-- Rundung 0..1, Ton } mit Ton "main" (Symbolfarbe), "dark" (abgedunkelt) oder "accent" (Laser rot).
-- Benutzung: AttachmentIcons.Build(parent, id, size, color) -> Frame

local AttachmentIcons = {}

local SHAPES = {
	Compensator = {
		{ 50, 50, 58, 24, 0, 0.3, "main" },
		{ 36, 42, 5, 9, 0, 0, "dark" }, { 48, 42, 5, 9, 0, 0, "dark" }, { 60, 42, 5, 9, 0, 0, "dark" },
		{ 81, 50, 6, 12, 0, 0.5, "dark" },
	},
	MuzzleBrake = {
		{ 50, 50, 52, 18, 0, 0.3, "main" },
		{ 38, 50, 7, 38, 0, 0.3, "main" }, { 56, 50, 7, 38, 0, 0.3, "main" },
		{ 77, 50, 5, 10, 0, 0.5, "dark" },
	},
	Suppressor = {
		{ 54, 50, 72, 26, 0, 1, "main" },
		{ 20, 50, 7, 30, 0, 0.3, "dark" },
		{ 56, 50, 56, 2, 0, 0, "dark" },
	},
	LongBarrel = {
		{ 52, 50, 84, 8, 0, 1, "main" },
		{ 86, 43, 6, 7, 0, 0.3, "main" },
		{ 16, 50, 14, 16, 0, 0.3, "dark" },
	},
	ShortBarrel = {
		{ 42, 50, 44, 9, 0, 1, "main" },
		{ 52, 50, 30, 22, 0, 0.3, "dark" },
		{ 52, 50, 30, 3, 0, 0, "main" },
	},
	HeavyBarrel = {
		{ 50, 50, 80, 18, 0, 0.5, "main" },
		{ 32, 50, 4, 30, 0, 0, "dark" }, { 46, 50, 4, 30, 0, 0, "dark" }, { 60, 50, 4, 30, 0, 0, "dark" },
	},
	VerticalGrip = {
		{ 50, 24, 72, 9, 0, 0.2, "dark" },
		{ 50, 56, 20, 54, 0, 0.45, "main" },
		{ 50, 52, 22, 3, 0, 0, "dark" }, { 50, 62, 22, 3, 0, 0, "dark" }, { 50, 72, 22, 3, 0, 0, "dark" },
	},
	Laser = {
		{ 44, 32, 60, 9, 0, 0.2, "dark" },
		{ 42, 50, 36, 22, 0, 0.3, "main" },
		{ 62, 50, 5, 12, 0, 0.5, "accent" },
		{ 82, 50, 32, 3, 0, 0, "accent" },
	},
	AngledGrip = {
		{ 50, 26, 72, 9, 0, 0.2, "dark" },
		{ 50, 52, 24, 48, 35, 0.3, "main" },
		{ 50, 52, 26, 3, 35, 0, "dark" },
	},
	ExtendedMag = {
		{ 50, 52, 28, 80, 10, 0.25, "main" },
		{ 50, 40, 28, 3, 10, 0, "dark" }, { 50, 54, 28, 3, 10, 0, "dark" }, { 50, 68, 28, 3, 10, 0, "dark" },
	},
	FastMag = {
		{ 38, 52, 22, 62, 6, 0.25, "main" },
		{ 62, 52, 22, 62, 6, 0.25, "main" },
		{ 50, 52, 54, 11, 6, 0, "dark" },
	},
	DrumMag = {
		{ 50, 22, 18, 26, 0, 0.2, "main" },
		{ 50, 60, 58, 58, 0, 1, "main" },
		{ 50, 60, 30, 30, 0, 1, "dark" },
		{ 50, 60, 9, 9, 0, 1, "main" },
	},
}

function AttachmentIcons.Has(id)
	return SHAPES[id] ~= nil
end

-- Symbol als quadratischer Frame (size x size), color = Symbolfarbe
function AttachmentIcons.Build(parent, id, size, color)
	local holder = Instance.new("Frame")
	holder.Name = "AttachmentIcon"
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local tones = {
		main = color,
		dark = color:Lerp(Color3.new(0, 0, 0), 0.55),
		accent = Color3.fromRGB(255, 70, 60),
	}
	for i, shape in SHAPES[id] or {} do
		local part = Instance.new("Frame")
		part.AnchorPoint = Vector2.new(0.5, 0.5)
		part.Position = UDim2.fromScale(shape[1] / 100, shape[2] / 100)
		part.Size = UDim2.fromScale(shape[3] / 100, shape[4] / 100)
		part.Rotation = shape[5]
		part.BackgroundColor3 = tones[shape[7]] or color
		part.BorderSizePixel = 0
		part.ZIndex = (holder.ZIndex or 1) + i
		part.Parent = holder
		if shape[6] > 0 then
			local corner = Instance.new("UICorner")
			-- Rundung relativ zur kürzeren Seite
			corner.CornerRadius = UDim.new(0, math.floor(math.min(shape[3], shape[4]) / 100 * size * shape[6] / 2 + 0.5))
			corner.Parent = part
		end
	end
	return holder
end

return AttachmentIcons
