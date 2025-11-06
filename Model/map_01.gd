extends Node3D

func _process(delta: float) -> void:
	$Windbase/WindNearFan_001.rotate_z(delta)
