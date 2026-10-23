extends Node

## Nastavení grafiky: rozlišení vykreslování, třpyt kamenů a stíny. Ukládá se do stejného
## souboru jako zvuk, do vlastní sekce.
##
## Úsporné rozlišení kreslí hru v základní velikosti okna z projektu (1280 × 720, širší
## obrazovka přidá do strany) a obrazovka ji jen roztáhne. Na velkém displeji je to několikrát
## méně pixelů, hra a HUD jsou stejně velké, jen méně ostré. Plné kreslí v rozlišení obrazovky.
## Na ARM (Raspberry Pi) je úsporné výchozí.
##
## Třpyt vypne odlesky kamenů, příšer a dolů přes globální uniformu sparkle_on.
## Stíny vypnou stíny od slunce, měsíce i čelovek (Shadows). Den, noc a světlo čelovek zůstanou.
## Bez persist se změna neuloží (benchmark přepíná jen na dobu měření).

signal changed

const SETTINGS := "user://settings.cfg"
const SECTION := "graphics"

var _reduced := false
var _sparkle := true
var _shadows := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reduced = Engine.get_architecture_name().begins_with("arm")
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		_reduced = bool(config.get_value(SECTION, "reduced", _reduced))
		_sparkle = bool(config.get_value(SECTION, "sparkle", _sparkle))
		_shadows = bool(config.get_value(SECTION, "shadows", _shadows))
	_apply()


func reduced() -> bool:
	return _reduced


func sparkle_on() -> bool:
	return _sparkle


func shadows_on() -> bool:
	return _shadows


func set_shadows(on: bool, persist := true) -> void:
	_shadows = on
	_apply()
	if persist:
		_save()


func set_reduced(on: bool, persist := true) -> void:
	_reduced = on
	_apply()
	if persist:
		_save()


func set_sparkle(on: bool, persist := true) -> void:
	_sparkle = on
	_apply()
	if persist:
		_save()


func _apply() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if _reduced else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	RenderingServer.global_shader_parameter_set(&"sparkle_on", 1.0 if _sparkle else 0.0)
	changed.emit()


## Soubor sdílí se zvukem. Načte se celý, ať se jeho sekce nepřepíše.
func _save() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value(SECTION, "reduced", _reduced)
	config.set_value(SECTION, "sparkle", _sparkle)
	config.set_value(SECTION, "shadows", _shadows)
	config.save(SETTINGS)
