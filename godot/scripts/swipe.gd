## Swipes and taps for the runs (the Superhero Run, the Roof Run): a swipe counts the moment the finger has moved
## far enough, not when it lifts, so a dodge happens as the thumb moves; a tap is a touch that lifts without having
## moved. Works from a touch screen (as the mouse it emulates) or a mouse; the arrow keys, WASD and space too.
## feed(event) returns "up", "down", "left", "right", "tap" or "".
class_name Swipe
extends RefCounted

const DIST := 26.0        # px (in the 390-high view): this far and it is a swipe
const TAP := 18.0         # px: lifted within this of where it went down, a tap

var _at := Vector2.INF    # where the finger went down
var _used := false        # this touch has given its swipe already

func feed(e: InputEvent) -> String:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_at = e.position
			_used = false
			return ""
		var was := _at
		_at = Vector2.INF
		if was != Vector2.INF and not _used and (e.position - was).length() < TAP + DIST:
			return "tap" if (e.position - was).length() < TAP else _dir(e.position - was)
		return ""
	if e is InputEventMouseMotion and _at != Vector2.INF and not _used:
		var v: Vector2 = e.position - _at
		if v.length() >= DIST:
			_used = true
			return _dir(v)
		return ""
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_UP, KEY_W:
				return "up"
			KEY_DOWN, KEY_S:
				return "down"
			KEY_LEFT, KEY_A:
				return "left"
			KEY_RIGHT, KEY_D:
				return "right"
			KEY_SPACE, KEY_ENTER:
				return "tap"
	return ""

func _dir(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0.0 else "left"
	return "up" if v.y < 0.0 else "down"
