class_name CameraController
extends Camera2D
## Smooth pan (WASD / arrows / middle- or right-drag / screen edge) and smooth zoom toward the cursor.

const PAN_SPEED := 900.0
const MIN_ZOOM := 0.35
const MAX_ZOOM := 5.0

var target_zoom := 2.2
var bounds := Rect2(0, 0, 4096, 4096)
var edge_scroll := false
var _dragging := false


func _ready() -> void:
	zoom = Vector2(target_zoom, target_zoom)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if edge_scroll:
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		if mp.x < 6:
			dir.x -= 1.0
		elif mp.x > vs.x - 6:
			dir.x += 1.0
		if mp.y < 6:
			dir.y -= 1.0
		elif mp.y > vs.y - 6:
			dir.y += 1.0
	if typing:
		dir = Vector2.ZERO
	if dir != Vector2.ZERO:
		var fast := 2.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		position += dir.normalized() * PAN_SPEED * fast * delta / zoom.x
	# smooth zoom that keeps the point under the cursor fixed
	if absf(zoom.x - target_zoom) > 0.0005:
		var before := get_global_mouse_position()
		var z := lerpf(zoom.x, target_zoom, 1.0 - exp(-delta * 12.0))
		zoom = Vector2(z, z)
		force_update_scroll()
		var after := get_global_mouse_position()
		position += before - after
	position = position.clamp(bounds.position, bounds.end)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clampf(target_zoom * 1.15, MIN_ZOOM, MAX_ZOOM)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clampf(target_zoom / 1.15, MIN_ZOOM, MAX_ZOOM)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		position -= mm.relative / zoom.x


func jump_to(p: Vector2) -> void:
	position = p
