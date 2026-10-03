@tool
extends RefCounted

const PAPER = Color("ffffff")
const DESK = Color("c6c6c6")
const INK = Color("111111")
const EDGE = Color("686868")

static func box(fill: Color, border: Color = EDGE, inset: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = inset
	style.content_margin_right = inset
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

static func create_theme() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Helvetica", "Arial", "Liberation Sans"])
	theme.default_font = font
	theme.default_font_size = 14
	for kind in ["Label", "Button", "OptionButton", "LineEdit", "TextEdit", "ItemList", "PopupMenu", "CheckButton"]:
		theme.set_color("font_color", kind, INK)
		theme.set_color("font_hover_color", kind, INK)
		theme.set_color("font_focus_color", kind, INK)
		theme.set_color("font_pressed_color", kind, PAPER)
		theme.set_color("font_disabled_color", kind, Color("777777"))
		theme.set_color("font_selected_color", kind, PAPER)
		theme.set_color("font_uneditable_color", kind, INK)
		theme.set_color("font_readonly_color", kind, INK)
		theme.set_color("selection_color", kind, INK)
		theme.set_color("caret_color", kind, INK)
	for kind in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", kind, box(Color("e7e7e7")))
		theme.set_stylebox("hover", kind, box(PAPER, INK))
		theme.set_stylebox("pressed", kind, box(INK, INK))
		theme.set_stylebox("disabled", kind, box(DESK))
		theme.set_stylebox("focus", kind, box(Color.TRANSPARENT, INK))
	for kind in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", kind, box(PAPER))
		theme.set_stylebox("read_only", kind, box(Color("e0e0e0")))
		theme.set_stylebox("focus", kind, box(Color.TRANSPARENT, INK))
		theme.set_color("font_placeholder_color", kind, Color("666666"))
	theme.set_stylebox("panel", "ItemList", box(PAPER, EDGE, 4))
	theme.set_stylebox("selected", "ItemList", box(INK, INK, 3))
	theme.set_stylebox("selected_focus", "ItemList", box(INK, INK, 3))
	theme.set_stylebox("cursor", "ItemList", box(Color.TRANSPARENT, INK, 3))
	theme.set_stylebox("cursor_unfocused", "ItemList", box(Color.TRANSPARENT, EDGE, 3))
	theme.set_constant("v_separation", "ItemList", 5)
	theme.set_stylebox("panel", "PopupMenu", box(DESK, INK))
	theme.set_stylebox("hover", "PopupMenu", box(INK, INK))
	theme.set_color("font_hover_color", "PopupMenu", PAPER)
	theme.set_stylebox("panel", "PanelContainer", box(DESK, INK, 0))
	theme.set_stylebox("panel", "TooltipPanel", box(PAPER, INK))
	theme.set_color("font_color", "TooltipLabel", INK)
	theme.set_color("arrow_color", "OptionButton", INK)
	theme.set_constant("modulate_arrow", "OptionButton", 1)
	theme.set_color("arrow_color", "SpinBox", INK)
	return theme
