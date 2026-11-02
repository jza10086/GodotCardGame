extends RefCounted
static func theme() -> Theme:
	var value := Theme.new(); value.default_font = preload("res://assets/ui_font.ttf"); value.default_font_size = 18
	return value
static func style(color: Color, radius := 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = 22; box.content_margin_right = 22; box.content_margin_top = 15; box.content_margin_bottom = 15
	return box
static func label(value: String, size := 18, color := Color("d6e4df")) -> Label:
	var node := Label.new(); node.text = value; node.add_theme_font_size_override("font_size",size); node.add_theme_color_override("font_color",color)
	return node
static func button(value: String, callback: Callable, primary := false) -> Button:
	var node := Button.new(); node.text = value; node.custom_minimum_size.y = 52
	node.add_theme_stylebox_override("normal",style(Color("c9a65c") if primary else Color("24464f")))
	node.add_theme_stylebox_override("hover",style(Color("e9c678") if primary else Color("365e65")))
	node.add_theme_stylebox_override("pressed",style(Color("b59250") if primary else Color("183c43")))
	node.add_theme_stylebox_override("disabled",style(Color("203336")))
	node.add_theme_color_override("font_color",Color("162b30") if primary else Color("e1e9e2"))
	node.add_theme_color_override("font_hover_color",Color("162b30") if primary else Color.WHITE)
	node.add_theme_color_override("font_disabled_color",Color("688183"))
	node.pressed.connect(callback); return node
