extends TextureRect

const PATH := "res://graphics/menu/background.png"


func _ready() -> void:
	if texture != null:
		return
	if not FileAccess.file_exists(PATH):
		push_error("Chybí pozadí menu.")
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path(PATH))
	if image == null or image.is_empty():
		push_error("Pozadí menu nejde načíst.")
		return
	texture = ImageTexture.create_from_image(image)
