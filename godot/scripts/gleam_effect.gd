extends RichTextEffect

## Odlesk, který občas přeběhne nadpisem zleva doprava, jako bliknutí kamenů ve hře.
## Použití: [gleam]text[/gleam].

var bbcode := "gleam"

## Jak často odlesk přeběhne, v sekundách, a o kolik se zpozdí každé další písmeno.
const PERIOD := 3.6
const STEP := 0.055
## Šířka odlesku v sekundách a jak moc písmeno zesvětlí.
const WIDTH := 0.12
const STRENGTH := 0.6


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var at := fposmod(char_fx.elapsed_time, PERIOD) - 0.4 - float(char_fx.relative_index) * STEP
	var flash := exp(-at * at / (WIDTH * WIDTH))
	char_fx.color = char_fx.color.lerp(Color(1.0, 0.98, 0.94, char_fx.color.a), flash * STRENGTH)
	return true
