class_name Vfx

const DEATH_BURST_SCENE: PackedScene = preload("res://scenes/effects/death_burst.tscn")

const COLOR_ALBEDO: Dictionary = {
	"red": Color(0.5, 0.1, 0.1, 1),
	"blue": Color(0.2, 0.4, 0.85, 1),
	"green": Color(0.2, 0.6, 0.2, 1),
	"purple": Color(0.4, 0.2, 0.6, 1),
	"gold": Color(0.8, 0.7, 0.2, 1),
	"white": Color(0.8, 0.8, 0.78, 1),
}

static func spawn_death_burst(pos: Vector3, color: Color, parent: Node) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var burst: GPUParticles3D = DEATH_BURST_SCENE.instantiate() as GPUParticles3D
	if burst == null:
		return
	parent.add_child(burst)
	burst.global_position = pos
	var mat: ParticleProcessMaterial = burst.process_material as ParticleProcessMaterial
	if mat != null:
		var local_mat: ParticleProcessMaterial = mat.duplicate() as ParticleProcessMaterial
		burst.process_material = local_mat
		local_mat.color = color
	burst.emitting = true
	burst.finished.connect(burst.queue_free)
