extends Node

## Zvuky a hudba. Soubory jsou v res://audio (vyrábí je tools/gen_sounds.py), hudba a voda
## v OGG, krátké zvuky ve WAV. Sběrnice Music,
## Sfx, Ambient a Ui jdou ztlumit zvlášť. Zvuky ve světě hrají z místa (AudioStreamPlayer2D,
## slábnou se vzdáleností od kamery), zvuky menu bez místa.
## Hudba: v menu hraje menu. Level hraje dvojici hudba do hry a hudba při honičce naráz,
## honička se jen plynule zesílí a zeslabí, takže obě běží dál od místa, kde byly.
## Tlačítka v menu zvučí sama: posun fokusu a stisk tlačítka se hlídají tady.

const ROOT := "res://audio"
const BUSES := {"Music": -6.0, "Sfx": 0.0, "Ambient": -4.0, "Ui": -9.0}
## Herních hudeb a hudeb při honičce je tolik, level si vybere náhodnou dvojici.
const GAME_TRACKS := 4
const CHASE_TRACKS := 4
## Prolínání hudeb v sekundách. Do honičky rychle, z honičky zpátky pomaleji.
const FADE := 1.2
const FADE_BACK := 3.0
const SILENT := -60.0
## Kolik zvuků ve světě hraje naráz. Další vezme nejstarší přehrávač.
const VOICES := 24
## Do kolika pixelů od kamery je zvuk ve světě slyšet.
const HEARING := 1400.0

var _cache := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _ui_player: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer2D] = []
var _next_voice := 0
## Cílová hlasitost hudeb: _music_a je hudba menu nebo hry, _music_b honička.
var _a_target := SILENT
var _b_target := SILENT
var _ambient_target := SILENT
## Hudba při honičce hraje celý level potichu, honička ji jen zesílí. Vypne se až s hudbou levelu.
var _chase_armed := false
## Posun fokusu zvučí jen do tohoto času (ms) po navigační klávese. Fokus, který si obrazovka
## nastaví sama (po startu hry, po otevření menu), je tichý.
var _nav_until := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus: String in BUSES:
		_bus(bus, BUSES[bus])
	_music_a = _player("Music")
	_music_b = _player("Music")
	_ui_player = _player("Ui")
	_ambient = _player("Ambient")
	for i in VOICES:
		var voice := AudioStreamPlayer2D.new()
		voice.bus = "Sfx"
		voice.max_distance = HEARING
		voice.attenuation = 1.6
		add_child(voice)
		_voices.append(voice)
	get_viewport().gui_focus_changed.connect(_on_focus)
	get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	var step := 60.0 / FADE * delta
	var back := 60.0 / FADE_BACK * delta
	# Z honičky zpátky: honička slábne a hra sílí pomaleji než naopak.
	var calming := _chase_armed and _b_target < _music_b.volume_db
	_music_a.volume_db = move_toward(_music_a.volume_db, _a_target, back if calming else step)
	_music_b.volume_db = move_toward(_music_b.volume_db, _b_target, back if calming else step)
	_ambient.volume_db = move_toward(_ambient.volume_db, _ambient_target, step * 0.5)
	if _music_a.playing and _a_target <= SILENT and _music_a.volume_db <= SILENT:
		_music_a.stop()
	if _music_b.playing and not _chase_armed and _b_target <= SILENT and _music_b.volume_db <= SILENT:
		_music_b.stop()


# --- Hudba ---

## Hudba menu. Když už hraje, pokračuje, mezi obrazovkami menu se nepřerušuje.
func play_menu_music() -> void:
	var stream := _stream("music/menu", true)
	_chase_armed = false
	if _music_a.stream == stream and _music_a.playing:
		_a_target = 0.0
		_b_target = SILENT
		return
	_start(_music_a, stream)
	_a_target = 0.0
	_b_target = SILENT
	_chase_armed = false


## Hudba levelu: náhodná dvojice hudby do hry a hudby při honičce. Honička zatím mlčí.
func play_level_music(rng: RandomNumberGenerator) -> void:
	_start(_music_a, _stream("music/game_%d" % rng.randi_range(1, GAME_TRACKS), true))
	_start(_music_b, _stream("music/chase_%d" % rng.randi_range(1, CHASE_TRACKS), true))
	_a_target = 0.0
	_b_target = SILENT
	_chase_armed = true


## Honička: hudba při honičce se zesílí, herní hudba se zeslabí. Bez honičky naopak.
func set_chase(on: bool) -> void:
	if not _music_b.playing:
		return
	_a_target = -18.0 if on else 0.0
	_b_target = 0.0 if on else SILENT


## Konec levelu: hudba se ztiší, ať je slyšet znělka výsledku.
func duck_music() -> void:
	_a_target = -20.0
	_b_target = SILENT
	_chase_armed = false


func stop_music() -> void:
	_a_target = SILENT
	_b_target = SILENT
	_chase_armed = false


func _start(player: AudioStreamPlayer, stream: AudioStream) -> void:
	if stream == null:
		return
	player.stream = stream
	player.volume_db = SILENT
	player.play()


# --- Prostředí ---

## Šumění vody. near je 0 až 1, jak blízko je voda.
func set_water(near: float) -> void:
	if near <= 0.0:
		_ambient_target = SILENT
		return
	if not _ambient.playing:
		_ambient.stream = _stream("ambient/water", true)
		_ambient.volume_db = SILENT
		_ambient.play()
	_ambient_target = lerpf(-30.0, 0.0, clampf(near, 0.0, 1.0))


func stop_ambient() -> void:
	_ambient_target = SILENT


# --- Zvuky ---

## Zvuk menu, bez místa.
func ui(name: String) -> void:
	var stream := _stream("ui/" + name)
	if stream == null:
		return
	_ui_player.stream = stream
	_ui_player.play()


## Zvuk ve světě na místě pos. name je cesta pod res://audio bez přípony, třeba steps/grass_2.
## pitch mírně mění výšku, ať se stejné zvuky neopakují do písmene.
func at(name: String, pos: Vector2, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream := _stream(name)
	if stream == null:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.global_position = pos
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()


## Náhodná varianta: name_1 až name_count.
func at_variant(name: String, count: int, pos: Vector2, volume_db: float = 0.0) -> void:
	at("%s_%d" % [name, randi_range(1, count)], pos, volume_db, randf_range(0.94, 1.06))


# --- Menu ---

func _input(event: InputEvent) -> void:
	for action: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev"]:
		if event.is_action_pressed(action):
			_nav_until = Time.get_ticks_msec() + 200
			return


func _on_focus(_control: Control) -> void:
	if Time.get_ticks_msec() < _nav_until:
		ui("move")


func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button != null and not button.pressed.is_connected(_on_button):
		button.pressed.connect(_on_button)


func _on_button() -> void:
	ui("select")


# --- Načítání ---

## Zvuk z res://audio, OGG (hudba, voda) nebo WAV (krátké zvuky). Importovaný soubor se načte
## jako zdroj, nenaimportovaný přímo ze souboru. loop nastaví smyčku přes celý soubor.
func _stream(name: String, loop: bool = false) -> AudioStream:
	var key := name + ("#loop" if loop else "")
	if _cache.has(key):
		return _cache[key]
	var stream: AudioStream
	for ext: String in ["ogg", "wav"]:
		var path := "%s/%s.%s" % [ROOT, name, ext]
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
		elif FileAccess.file_exists(path):
			var file := ProjectSettings.globalize_path(path)
			stream = AudioStreamOggVorbis.load_from_file(file) if ext == "ogg" else AudioStreamWAV.load_from_file(file)
		if stream != null:
			break
	if stream != null and loop:
		stream = stream.duplicate()
		var wav := stream as AudioStreamWAV
		var ogg := stream as AudioStreamOggVorbis
		if wav != null:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
		elif ogg != null:
			ogg.loop = true
	_cache[key] = stream
	return stream


func _player(bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


func _bus(name: String, volume_db: float) -> void:
	if AudioServer.get_bus_index(name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, name)
	AudioServer.set_bus_send(index, "Master")
	AudioServer.set_bus_volume_db(index, volume_db)
