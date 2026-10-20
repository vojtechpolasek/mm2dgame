extends RichTextLabel

## Nadpis v barvách materiálů jako logo. Každé písmeno má barvu jiného materiálu, tlumenou
## k šedi stejně jako v logu (tools/gen_logo.py), shader ho nasvítí jako broušený kámen
## a občas jím přeběhne odlesk (gleam_effect.gd). Tmavý obrys a stín drží čitelnost.
## Barvy se vybírají podle textu, stejný nadpis má vždy stejné barvy.

const GleamEffect := preload("res://scripts/gleam_effect.gd")
const SHADER := preload("res://shaders/material_title.gdshader")

## Materiály ze hry: pískovec, křemen, lávový kámen, zlato, magnetit, stříbro, jantar, rubín,
## smaragd, safír. Barvy jsou z katalogu krystalů.
const MATERIALS: PackedColorArray = [
	Color8(196, 165, 106), Color8(230, 214, 184), Color8(106, 51, 44), Color8(236, 196, 32), Color8(74, 81, 88),
	Color8(168, 180, 198), Color8(180, 98, 28), Color8(196, 32, 48), Color8(30, 138, 69), Color8(42, 91, 215),
]
## Stejné jako SATURATION a MIN_LUMA v gen_logo.py, tady s větším jasem kvůli čitelnosti.
const SATURATION := 0.62
const MIN_LUMA := 0.42
const OUTLINE := Color(0.045, 0.04, 0.032)
## Kde leží písmena v řádku, jako díl výšky řádku. Pro nasvícení v shaderu.
const LETTER_TOP := 0.24
const LETTER_HEIGHT := 0.56

@export var title := "":
	set(value):
		title = value
		_rebuild()

@export var font_size := 36:
	set(value):
		font_size = value
		add_theme_font_size_override("normal_font_size", value)
		add_theme_constant_override("outline_size", maxi(int(value * 0.16), 3))
		add_theme_constant_override("shadow_offset_y", maxi(int(value * 0.07), 2))


func _init() -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_OFF
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	install_effect(GleamEffect.new())
	var shading := ShaderMaterial.new()
	shading.shader = SHADER
	material = shading
	add_theme_color_override("font_outline_color", OUTLINE)
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	add_theme_constant_override("shadow_offset_x", 0)
	font_size = font_size
	resized.connect(_light)


func _light() -> void:
	var shading := material as ShaderMaterial
	shading.set_shader_parameter("letter_top", size.y * LETTER_TOP)
	shading.set_shader_parameter("letter_height", size.y * LETTER_HEIGHT)


func _rebuild() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(title)
	var last := -1
	var out := "[center][gleam]"
	for i in title.length():
		var letter := title[i]
		if letter == "[":
			letter = "[lb]"
		if title[i].strip_edges().is_empty() or not _is_letter(title[i]):
			out += "[color=#%s]%s[/color]" % [Color(0.95, 0.93, 0.88).to_html(false), letter]
			continue
		# Sousední písmena nemají stejný materiál.
		var pick := rng.randi_range(0, MATERIALS.size() - 2)
		if pick >= last and last >= 0:
			pick += 1
		last = pick
		out += "[color=#%s]%s[/color]" % [_muted(MATERIALS[pick], rng).to_html(false), letter]
	text = out + "[/gleam][/center]"


static func _is_letter(c: String) -> bool:
	return c.to_upper() != c.to_lower() or c.is_valid_int()


## Barva stažená k šedi jako v logu, tmavé materiály zesvětlené, každé písmeno trochu jiné.
static func _muted(color: Color, rng: RandomNumberGenerator) -> Color:
	var gray := color.get_luminance()
	var out := Color(gray, gray, gray).lerp(color, SATURATION)
	var luma := out.get_luminance()
	if luma < MIN_LUMA:
		var lift := MIN_LUMA - luma
		out = Color(out.r + lift, out.g + lift, out.b + lift)
	var tone := rng.randf_range(0.9, 1.08)
	return Color(out.r * tone, out.g * tone, out.b * tone)
