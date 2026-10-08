extends Control

## Výběr levelu. Hrát jde jen odemčené levely (GameSession.unlocked), předvybraný je nejvyšší.
## Seznam ukazuje vybraný level uprostřed a kolem něj dva nižší a dva vyšší, čím dál od
## vybraného, tím tmavší. Nahoru a dolů vybírá kterýkoli ovladač z Controls (šipky, WASD,
## páčka i křížový ovladač gamepadu), podržení opakuje. Potvrzení hraje, Esc nebo B vrací
## zpět. Myší jde kliknout na sousední level (vybere ho) nebo na vybraný (hraje).

## Kolik levelů je vidět nad a pod vybraným.
const AROUND := 2
## Průhlednost řádku podle vzdálenosti od vybraného.
const FADE: Array[float] = [1.0, 0.55, 0.25]
const ROW_SIZE := Vector2(360, 52)
## Podržený směr opakuje: první opakování po REPEAT_DELAY, další po REPEAT_EVERY sekundách.
const REPEAT_DELAY := 0.4
const REPEAT_EVERY := 0.11

@onready var _list: VBoxContainer = $Center/Panel/Column/List
@onready var _info: Label = $Center/Panel/Column/Info

var _selected := 1
var _rows: Array[Button] = []
## Jak dlouho je směr podržený a kdy se má zopakovat.
var _held := 0
var _held_time := 0.0
var _next_repeat := 0.0


func _ready() -> void:
	Sound.play_menu_music()
	_selected = GameSession.unlocked
	for offset in range(-AROUND, AROUND + 1):
		var row := Button.new()
		row.custom_minimum_size = ROW_SIZE
		row.focus_mode = Control.FOCUS_NONE
		row.pressed.connect(_on_row.bind(offset))
		_list.add_child(row)
		_rows.append(row)
	$Center/Panel/Column/Buttons/Back.pressed.connect(_back)
	$Center/Panel/Column/Buttons/Start.pressed.connect(_choose)
	_show()


## Nahoru a dolů ze všech ovladačů najednou, s opakováním při podržení.
func _process(delta: float) -> void:
	var step := 0
	for device in Controls.COUNT:
		var dir := Controls.direction(device)
		if dir.y < -0.5:
			step = -1
		elif dir.y > 0.5:
			step = 1
		if step != 0:
			break
	if step == 0:
		_held = 0
		return
	if step != _held:
		_held = step
		_held_time = 0.0
		_next_repeat = REPEAT_DELAY
		_move(step)
		return
	_held_time += delta
	if _held_time >= _next_repeat:
		_next_repeat += REPEAT_EVERY
		_move(step)


## Potvrzení, zpět a kolečko myši. Vstup se označí za zpracovaný dřív, než se změní scéna,
## potom už menu ve stromu není.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		Sound.ui("select")
		_choose()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()
	else:
		var wheel := event as InputEventMouseButton
		if wheel == null or not wheel.pressed:
			return
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			_move(-1)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_move(1)
		else:
			return
		get_viewport().set_input_as_handled()


func _move(step: int) -> void:
	var next := clampi(_selected + step, 1, GameSession.unlocked)
	if next == _selected:
		return
	_selected = next
	Sound.ui("move")
	_show()


func _on_row(offset: int) -> void:
	if offset == 0:
		_choose()
	else:
		_move(offset)


## Řádky kolem vybraného levelu. Levely mimo odemčené jsou prázdné, místo zůstává.
func _show() -> void:
	for i in _rows.size():
		var offset := i - AROUND
		var level := _selected + offset
		var row := _rows[i]
		var shown := level >= 1 and level <= GameSession.unlocked
		row.text = "Level %d" % level if shown else ""
		row.disabled = not shown
		row.modulate.a = FADE[absi(offset)] if shown else 0.0
		row.flat = offset != 0
		row.add_theme_font_size_override("font_size", 28 if offset == 0 else 22)
	var size := GameSession.level_size(_selected)
	var time := GameSession.level_time(_selected)
	_info.text = "Mapa %d × %d m · čas %d:%02d · materiálů %d" % [
		size, size, time / 60, time % 60, mini(GameSession.level_materials(_selected), GameSession.material_points().size()),
	]


func _choose() -> void:
	GameSession.level = _selected
	get_tree().change_scene_to_file("res://scenes/character_menu.tscn")


func _back() -> void:
	Sound.ui("back")
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
