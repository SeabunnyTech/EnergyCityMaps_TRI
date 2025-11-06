extends Node3D

func _process(delta: float) -> void:
	$WindNearFan.rotate_x(delta)
