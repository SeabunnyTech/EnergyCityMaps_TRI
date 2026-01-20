extends Node3D

@onready var camera = $Camera3D
@onready var positions = $CameraPositions

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		# 按 1-9 對應索引 0-8，按 0 對應索引 9
		var index = -1
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			index = event.keycode - KEY_1
		elif event.keycode == KEY_0:
			index = 9
		
		if index >= 0 and index < positions.get_child_count():
			var target = positions.get_child(index)
			var pos_id = target.get_meta("position_id", "")
			#camera.zoom_to(pos_id)
			zoom_to_topic(pos_id)
			print("運鏡到: ", pos_id)


func boost_facility(topic: String):
	if topic == 'wind' and has_node("WindTurbines"):
		for turbine in $WindTurbines.get_children():
			turbine.boost_level += 1


func reset():
	if has_node("WindTurbines"):
		for turbine in $WindTurbines.get_children():
			turbine.boost_level = 0

func zoom_to_topic(topic: String, duration: float=1.5):
	camera.zoom_to(topic, duration)
