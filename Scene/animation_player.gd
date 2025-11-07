extends AnimationPlayer

func _ready() -> void:
	print("ready, playing Cloud_move...")
	play("Cloud_move")

	animation_finished.connect(_on_animation_finished)

func _on_animation_finished(anim_name: String) -> void:
	print("animation_finished signal:", anim_name)
	if anim_name == "Cloud_move":
		print("Finished! replaying...")
		play("Cloud_move")
