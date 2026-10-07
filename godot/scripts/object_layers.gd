extends RefCounted

## Společný posun vrstev všech objektů nad zemí. Výška vrstvy zůstává v katalogu objektu.
## Číslo platí při zoomu 1. Oddálení ho zmenší: čím je kamera výš, tím míň se vrstvy hnou.
## Strom 8 m vysoký u kraje okna (asi 640 px) odsune špičku zhruba o 82 px.
const PARALLAX := 0.016
## Menší posun na kraji obrazovky už není vidět, shader vrstvy se vypne.
const MIN_SCREEN_SHIFT := 1.0


## Posun v pixelech obrazovky pro objekt v rohu záběru.
static func edge_shift(viewport: Vector2, zoom: float, height: float) -> float:
	return viewport.length() * 0.5 * height * PARALLAX * zoom


static func shader_needed(viewport: Vector2, zoom: float, height: float) -> bool:
	return edge_shift(viewport, zoom, height) >= MIN_SCREEN_SHIFT


## O kolik pixelů vrchol uteče z obrázku. Zoom se vykrátí: kraj okna je dál,
## ale shader ten posun zase násobí zoomem.
static func vertex_pad(viewport: Vector2, height: float) -> float:
	return viewport.length() * 0.5 * height * PARALLAX + 8.0


## Lineární filtr potřebuje mipmapy. Průhledné okraje jinak zčernají.
static func with_mipmaps(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty() or image.has_mipmaps():
		return texture
	image = image.duplicate()
	if image.detect_alpha() != Image.ALPHA_NONE:
		image.fix_alpha_edges()
	if image.generate_mipmaps() != OK:
		return texture
	return ImageTexture.create_from_image(image)


static func fit_sprite(sprite: Sprite2D, material: ShaderMaterial, viewport: Vector2, enabled: bool) -> void:
	var height := float(sprite.get_meta("layer_height", 0.0))
	if not enabled or height <= 0.0:
		sprite.material = null
		RenderingServer.canvas_item_set_custom_rect(sprite.get_canvas_item(), false, Rect2())
		return
	sprite.material = material
	var rect := sprite.get_rect()
	RenderingServer.canvas_item_set_custom_rect(sprite.get_canvas_item(), true, rect.grow(vertex_pad(viewport, height)))
