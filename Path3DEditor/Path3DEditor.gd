@tool
extends EditorPlugin

var panelScene = preload("res://addons/Path3DEditor/Resources/Path3DEdit.tscn")
var editModeButtonScene = preload("res://addons/Path3DEditor/Resources/EditModeButton.tscn")
var heightPreviewScene = preload("res://addons/Path3DEditor/Resources/HeightPreview.tscn")
var editModeButton
var panel
var panelContainer
var selection
var buttonOn = false

var inEditMode = false
var brushSelected = 0

#Edit panel
var buttonAdd
var buttonDelete
var buttonMove
var buttonSubdivide
var above
var buttonMask

var brushScene = preload("res://addons/Path3DEditor/Resources/Brush.tscn")
var brush : Node3D
var heightPreview : Node3D
var heightPreviewNumber : Label3D
var brushPointer : Node3D
var path : Path3D
var pointSelected = 0
var brushHold
var undo
var maskSelect : Popup
var maskButtons : Array[Node]

var viewport3DContainer
var panelAdded = false

#Brush types
var ADD = 0
var DELETE = 1
var SUBDIVIDE = 2
var MOVE = 3
var HEIGHTSET = 4

var brushColors = [Color.GREEN, Color.RED, Color.DARK_GOLDENROD, Color.ORANGE, Color.TRANSPARENT]
var brushShowPointer = [true, false, true, true, false]
var brushKeys = [KEY_ALT, KEY_SHIFT, KEY_SPACE, KEY_B] #Starting from 1

func _enter_tree():
	editModeButton = editModeButtonScene.instantiate()
	editModeButton.pressed.connect(SwitchPanel.bind())
	panel = panelScene.instantiate()
	panelContainer = panel.get_child(0)
	selection = get_editor_interface().get_selection()
	selection.selection_changed.connect(AddEditModeButton.bind())
	selection.selection_changed.connect(RemoveEditModeButton.bind())
	
	buttonAdd = panelContainer.get_node("Buttons/Add")
	buttonAdd.pressed.connect(SetBrush.bind(ADD))
	buttonDelete = panelContainer.get_node("Buttons/Delete")
	buttonDelete.pressed.connect(SetBrush.bind(DELETE))
	buttonSubdivide = panelContainer.get_node("Buttons/Subdivide")
	buttonSubdivide.pressed.connect(SetBrush.bind(SUBDIVIDE))
	buttonMove = panelContainer.get_node("Buttons/Move")
	buttonMove.pressed.connect(SetBrush.bind(MOVE))
	above = panelContainer.get_node("Above")
	buttonMask = panelContainer.get_node("Mask select")
	
	maskSelect = panel.get_node("Mask selection")
	maskButtons = maskSelect.get_node("Panel/1").get_children()
	maskButtons.append_array(maskSelect.get_node("Panel/2").get_children())
	for button in maskButtons:
		button.button_pressed = true
	
	buttonMask.pressed.connect(PopupMaskSelector.bind())
	
	undo = get_undo_redo()

func _exit_tree():
	RemoveEditModeButton()
	SwitchPanel(true)
	editModeButton.queue_free()
	panel.queue_free()

func _handles(object):
	if object.get_class() == "Path3D":
		return true

func _forward_3d_gui_input(viewport_camera, event):
	if viewport3DContainer == null:
		viewport3DContainer = viewport_camera.get_viewport().get_node("../..").get_child(1)
		if !panelAdded:
			viewport3DContainer.add_child(panel)

	if inEditMode:
		#Set brush
		if event is InputEventKey:
			for key in range(brushKeys.size()):
				if event.keycode == brushKeys[key]:
					if event.pressed:
						SetBrush(key+1)
					elif !event.pressed:
						SetBrush(ADD)
		
		#Brush action
		if event is InputEventMouseButton:
			if !event.is_echo() and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				if brushSelected == ADD:
					undo.create_action("Path3D: add point")
					undo.add_undo_property(path, 'curve', path.curve.duplicate())
					
					path.curve.add_point(brush.position)
					
					undo.add_do_property(path, 'curve', path.curve.duplicate())
					undo.commit_action()
				elif brushSelected == DELETE and path.curve.point_count != 0:
					undo.create_action("Path3D: delete point")
					undo.add_undo_property(path, 'curve', path.curve.duplicate())
					
					path.curve.remove_point(pointSelected)
					
					undo.add_do_property(path, 'curve', path.curve.duplicate())
					undo.commit_action()
				elif brushSelected == SUBDIVIDE and path.curve.point_count != 0:
					undo.create_action("Path3D: subdivide segment")
					undo.add_undo_property(path, 'curve', path.curve.duplicate())
					
					path.curve.add_point(brush.position, Vector3.ZERO, Vector3.ZERO, pointSelected)
					
					undo.add_do_property(path, 'curve', path.curve.duplicate())
					undo.commit_action()
			if event.button_index == MOUSE_BUTTON_LEFT and path.curve.point_count != 0:
				if event.is_pressed(): 
					brushHold = true
					if brushSelected == MOVE:
						undo.create_action("Path3D: move point")
						undo.add_undo_property(path, 'curve', path.curve.duplicate())
				else: 
					brushHold = false
					if brushSelected == MOVE:
						undo.add_do_property(path, 'curve', path.curve.duplicate())
						undo.commit_action()
		
		#Mouse hold down brush
		if brushHold:
			if brushSelected == MOVE:
				path.curve.set_point_position(pointSelected, brush.position)
		
		#Collision mask
		var mask : int = 0
		for b in range(32):
			if maskButtons[b].button_pressed:
				mask = mask | 1 << (b)
		
		#Brush position
		var mouse = viewport_camera.get_viewport().get_mouse_position()
		
		var from = viewport_camera.project_ray_origin(mouse)
		var to = from + viewport_camera.project_ray_normal(mouse) * 100
		var space_state = brush.get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(from, to, mask)
		var ray = space_state.intersect_ray(query)
		
		brushPointer.visible = brushShowPointer[brushSelected] and !brushHold and path.curve.point_count != 0
		if ray.has("position"):
			var pos = ray.position + ray.normal * above.value
			
			if event is InputEventMouseMotion:
				if brushSelected == HEIGHTSET:
					above.value += event.relative.y*0.01
			
			if brushSelected == HEIGHTSET:
				heightPreview.visible = true
				heightPreview.position = pos
				heightPreviewNumber.text = above.value
			else:
				heightPreview.visible = false
			
			if (brushSelected == DELETE or brushSelected == SUBDIVIDE or brushSelected == MOVE or brushSelected == HEIGHTSET) and !brushHold:
				var maxdist = 9999
				for p in path.curve.point_count:
					if (path.curve.get_point_position(p) + path.position).distance_to(pos) < maxdist:
						maxdist = (path.curve.get_point_position(p) + path.position).distance_to(pos)
						
						if brushSelected == DELETE:
							brush.position = path.curve.get_point_position(p) + path.position
							pointSelected = p
						elif brushSelected == SUBDIVIDE or brushSelected == MOVE:
							brush.position = pos
							DrawLine(brushPointer.mesh, pos, path.curve.get_point_position(p) + path.position)
							pointSelected = p
			else:
				if(path.curve.point_count != 0):
					DrawLine(brushPointer.mesh, pos, path.curve.get_point_position(path.curve.point_count-1) + path.position)
				brush.position = pos
		return EditorPlugin.AFTER_GUI_INPUT_CUSTOM

func DrawLine(mesh : ImmediateMesh, start, end):
	mesh.clear_surfaces()
	mesh.surface_begin(ImmediateMesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(end)
	mesh.surface_end()

#
#
# PANEL
#
#

func AddEditModeButton():
	var nodes = selection.get_selected_nodes()
	
	if nodes.size() > 0 and nodes[0].get_class() == "Path3D":
		if !buttonOn:
			path = nodes[0]
			add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, editModeButton)
			buttonOn = true
			SwitchPanel()

func RemoveEditModeButton(close = false):
	if(close):
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, editModeButton)
		SwitchPanel(true)
		buttonOn = false
		return
	
	var nodes = selection.get_selected_nodes()
	
	if nodes.size() == 0 or nodes[0].get_class() != "Path3D":
		if buttonOn:
			remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, editModeButton)
			SwitchPanel(true)
			buttonOn = false

func SwitchPanel(close = false):
	if close:
		if inEditMode:
			panel.visible = false
			
			brush.queue_free()
			brushPointer.queue_free()
			inEditMode = false
			return
		return
	
	if !inEditMode:
		panel.visible = true
		
		brush = brushScene.instantiate()
		get_editor_interface().get_edited_scene_root().add_child(brush)
		brushPointer = brush.get_node("Pointer")
		brushPointer.reparent(brush.get_parent())
		SetBrush(ADD)
		
		heightPreview = heightPreviewScene.instantiate()
		get_editor_interface().get_edited_scene_root().add_child(heightPreview)
		heightPreviewNumber = heightPreview.get_child(0)
		heightPreview.visible = false
		
		inEditMode = true
	else:
		panel.visible = false
		
		brush.queue_free()
		brushPointer.queue_free()
		heightPreview.queue_free()
		
		inEditMode = false

#
#
# EDIT
#
#

func FindByClass(node: Node, className : String, result : Array) -> void:
	if node.is_class(className) :
		result.push_back(node)
	for child in node.get_children():
		FindByClass(child, className, result)

func SetBrush(b):
	brushSelected = b
	
	brush.get_surface_override_material(0).set("shader_parameter/color", brushColors[brushSelected])

func PopupMaskSelector():
	maskSelect.position = Vector2i(0,0)
	maskSelect.popup()
	maskSelect.position += Vector2i(get_window().get_mouse_position())
