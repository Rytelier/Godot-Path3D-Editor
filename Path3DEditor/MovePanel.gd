@tool
extends Button

var panel
var parent

var move

func _ready():
	panel = get_node("../..")
	parent = panel.get_parent()
	visibility_changed.connect(ClampPos.bind())

func _pressed():
	move = true

func _gui_input(event):
	if event is InputEventMouseButton:
		if !event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			move = false
	
	if event is InputEventMouseMotion:
		if move:
			panel.position += event.relative
			ClampPos()

func ClampPos():
	panel.position = panel.position.clamp(Vector2.ZERO, parent.size-panel.size)
