extends CSGMesh3D
@export var clouds_to_spawn : int = 10
@export var _cloud: PackedScene

func _ready():
	spawn_clouds()

var rng = RandomNumberGenerator.new()

	
func spawn_clouds():
	var cloud_count : int = clouds_to_spawn
	while cloud_count >= 0:
		cloud_count -= 1
		
		var x : float = rng.randf_range(size.x / 2, -size.x /2)
		var y : float = rng.randf_range(size.y / 2, -size.y /2)
		var z : float = rng.randf_range(size.z / 2, -size.z /2)
		var spawn_pos : Vector3 = Vector3(x, y, z)
		
		var cloud := _cloud.instantiate()
		add_child(cloud)
		cloud.global_position = self.global_position + spawn_pos
