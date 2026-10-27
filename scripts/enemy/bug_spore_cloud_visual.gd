extends EnemyAttackField
class_name BugSporeCloudVisual

## Static, camera-facing sprites: no custom shader, emitter or simulation.
## Geometry, sprite texture and native materials are shared by every cloud.
const SPORE_COUNT: int = 96
const SPORE_DIAMETER: float = 0.075
const SPORE_COLOR: Color = Color(0.75, 0.95, 0.20, 0.5)

static var _boundary_mesh: ArrayMesh = null
static var _boundary_material: StandardMaterial3D = null
static var _sprite_cloud: MultiMesh = null

var _spores: MultiMeshInstance3D = null

func configure_sphere(radius: float) -> void:
	if _boundary_mesh == null:
		_boundary_mesh = EnemyAttackField._build_sphere(false)
		_boundary_material = _make_native_material()
	mesh = _boundary_mesh
	material_override = _boundary_material
	basis = Basis.IDENTITY.scaled(Vector3.ONE * maxf(radius, 1.0))
	if _sprite_cloud == null:
		_sprite_cloud = _build_sprite_cloud()
	if _spores == null:
		_spores = MultiMeshInstance3D.new()
		_spores.name = "StaticSpores"
		_spores.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spores.multimesh = _sprite_cloud
		add_child(_spores)

func set_charge(_progress: float, _elapsed: float) -> void:
	visible = true
	transparency = 0.0
	if _spores != null:
		_spores.transparency = 0.0

func set_release(fraction: float) -> void:
	var fade: float = clampf(fraction, 0.0, 1.0)
	transparency = 1.0 - fade
	if _spores != null:
		_spores.transparency = 1.0 - fade
	visible = fade > 0.0

static func _make_native_material() -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.disable_receive_shadows = true
	result.albedo_color = SPORE_COLOR
	return result

static func _build_sprite_cloud() -> MultiMesh:
	var sprite_material: StandardMaterial3D = _make_native_material()
	sprite_material.albedo_color.a = 0.25
	sprite_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sprite_material.billboard_keep_scale = true
	sprite_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# One tiny disc texture, generated once; no animated noise or effect shader.
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for row: int in range(8):
		for column: int in range(8):
			if Vector2(float(column) - 3.5, float(row) - 3.5).length_squared() <= 14.0:
				image.set_pixel(column, row, Color.WHITE)
	sprite_material.albedo_texture = ImageTexture.create_from_image(image)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * SPORE_DIAMETER
	quad.material = sprite_material
	var result: MultiMesh = MultiMesh.new()
	result.transform_format = MultiMesh.TRANSFORM_3D
	result.mesh = quad
	result.instance_count = SPORE_COUNT
	# Local RNG never consumes the combat, wave or drop random sequence.
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 7193
	for index: int in range(SPORE_COUNT):
		var point: Vector3 = Vector3.ONE
		while point.length_squared() > 0.9 * 0.9:
			point = Vector3(random.randf_range(-0.9, 0.9), random.randf_range(-0.9, 0.9), random.randf_range(-0.9, 0.9))
		result.set_instance_transform(index, Transform3D(Basis.IDENTITY, point))
	result.custom_aabb = AABB(Vector3.ONE * -1.0, Vector3.ONE * 2.0)
	return result
