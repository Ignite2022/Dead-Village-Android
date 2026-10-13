extends Node3D
## DEAD VILLAGE - Stage 1
## Night landscape with real photo-scanned textures, walking, native gyroscope aim,
## flashlight and pistol. Zombies and stealth are added in Stage 2.

const TOWER_Z := -312.0
const FIRE_Z := -290.0
const INK := Color(0.91, 0.86, 0.75)

const TERRAIN_SHADER := """
shader_type spatial;
uniform sampler2D g_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D g_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D g_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D p_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D p_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D p_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D r_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D r_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D r_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 g_tint = vec3(1.0);
uniform vec3 p_tint = vec3(1.0);
uniform vec3 r_tint = vec3(1.0);
uniform float tile = 0.3;
varying vec3 w_pos;
varying float w_up;
void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_up = NORMAL.y;
}
void fragment() {
	vec2 uv = w_pos.xz * tile;
	vec2 uv2 = w_pos.xz * tile * 0.29 + vec2(0.37, 0.71);
	float pm = clamp(COLOR.r, 0.0, 1.0);
	float rm = smoothstep(0.86, 0.68, w_up);
	vec3 ga = mix(texture(g_alb, uv).rgb, texture(g_alb, uv2).rgb, 0.45) * g_tint;
	vec3 pa = mix(texture(p_alb, uv).rgb, texture(p_alb, uv2).rgb, 0.35) * p_tint;
	vec3 ra = texture(r_alb, uv * 0.7).rgb * r_tint;
	ALBEDO = mix(mix(ga, pa, pm), ra, rm) * COLOR.g;
	NORMAL_MAP = mix(mix(texture(g_nor, uv).rgb, texture(p_nor, uv).rgb, pm), texture(r_nor, uv * 0.7).rgb, rm);
	NORMAL_MAP_DEPTH = 1.2;
	float ro = mix(mix(texture(g_rgh, uv).g, texture(p_rgh, uv).g, pm), texture(r_rgh, uv * 0.7).g, rm);
	ROUGHNESS = clamp(ro, 0.35, 1.0);
	SPECULAR = 0.35;
}
"""

const TERRAIN_SIMPLE := """
shader_type spatial;
uniform sampler2D g_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D p_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 g_tint = vec3(1.0);
uniform vec3 p_tint = vec3(1.0);
varying vec3 w_pos;
void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = w_pos.xz * 0.3;
	ALBEDO = mix(texture(g_alb, uv).rgb * g_tint, texture(p_alb, uv).rgb * p_tint, clamp(COLOR.r, 0.0, 1.0)) * COLOR.g;
	ROUGHNESS = 0.95;
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base_col : source_color = vec3(0.03, 0.05, 0.02);
uniform vec3 tip_col : source_color = vec3(0.25, 0.29, 0.12);
varying float hf;
void vertex() {
	hf = UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float s = sin(TIME * 1.6 + wp.x * 0.35 + wp.z * 0.22) * 0.7 + sin(TIME * 3.3 + wp.x * 1.1 + wp.z * 0.7) * 0.3;
	VERTEX.x += s * 0.11 * hf * hf;
	VERTEX.z += cos(TIME * 1.25 + wp.z * 0.3 + wp.x * 0.1) * 0.06 * hf * hf;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	ALBEDO = mix(base_col, tip_col, hf) * COLOR.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
"""

# ---------------- settings ----------------
var cfg := ConfigFile.new()
var sens := 1.0
var inv_x := false
var inv_y := false
var swap_axes := false
var use_gyro := true
var quality := 1
var auto_res := true
var res_scale := 0.8
var fps_acc := 0.0
var fps_frames := 0
var tag_heavy := false
var heavy: Array = []

# ---------------- world ----------------
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var A: Dictionary = {}
var obstacles: Array = []
var tree_col: Array = []
var tall_patches: Array = []
var ranged: Array = []
var flicker: Array = []
var window_lights := 0
var world_env: Environment
var moon: DirectionalLight3D
var tower_pos := Vector3.ZERO
var fire_pos := Vector3.ZERO
var soft_tex: ImageTexture
var m_walls: Array = []
var m_roof: Material
var m_stone: Material
var m_win_lit: StandardMaterial3D
var m_win_dark: StandardMaterial3D
var m_door: Material

# ---------------- player ----------------
var player := Node3D.new()
var cam := Camera3D.new()
var gun := Node3D.new()
var gun_base := Vector3(0.19, -0.19, -0.42)
var torch := SpotLight3D.new()
var laser_origin := Node3D.new()
var muzzle := Node3D.new()
var muzzle_light := OmniLight3D.new()
var muzzle_flash := MeshInstance3D.new()
var laser_mesh := ImmediateMesh.new()
var laser := MeshInstance3D.new()
var laser_mat := StandardMaterial3D.new()
var dot := MeshInstance3D.new()
var impacts: Array = []
var impact_i := 0
var pitch := 0.0
var eye := 1.65
var crouching := false
var torch_on := false
var bob := 0.0
var recoil := 0.0
var step_d := 0.0
var clip := 12
var reserve := 36
var reloading := 0.0
var fire_cd := 0.0
var flash_t := 0.0
var playing := false
var started := false
var finished := false
var gyro_seen := false
var gyro_now := Vector3.ZERO

# ---------------- touch ----------------
var joy_id := -1
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO
var look_id := -1
var buttons: Dictionary = {}

# ---------------- ui ----------------
var font: Font = null
var ui_root := Control.new()
var hud := Control.new()
var menu := Control.new()
var menu_box := HBoxContainer.new()
var menu_bg := ColorRect.new()
var lbl_status: Label
var lbl_obj: Label
var lbl_ammo: Label
var lbl_fps: Label
var lbl_msg: Label
var lbl_gyro: Label
var arrow := Polygon2D.new()
var joy_base: Panel
var joy_knob: Panel
var msg_t := 0.0
var menu_btns: Dictionary = {}
var lbl_sens: Label

# ---------------- audio ----------------
var sounds: Dictionary = {}
var sfx_players: Array = []


# =====================================================================
func _ready() -> void:
	load_settings()
	noise.seed = 1337
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.022
	noise.fractal_octaves = 4
	noise2.seed = 99
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = 0.11
	noise2.fractal_octaves = 2
	load_assets()
	soft_tex = make_soft_tex()
	tower_pos = Vector3(path_x(TOWER_Z), 0.0, TOWER_Z)
	tower_pos.y = height_at(tower_pos.x, tower_pos.z)
	fire_pos = Vector3(path_x(FIRE_Z) + 5.0, 0.0, FIRE_Z)
	fire_pos.y = height_at(fire_pos.x, fire_pos.z)
	build_environment()
	build_village()
	build_terrain()
	build_trees()
	build_rocks()
	build_plants()
	build_grass()
	build_player()
	build_audio()
	build_ui()
	get_viewport().size_changed.connect(layout)
	layout()
	apply_quality()
	reset_player()
	show_menu(true)


# =====================================================================
# terrain shape
func path_x(z: float) -> float:
	return sin(z * 0.018) * 14.0 + sin(z * 0.041 + 1.3) * 5.0


func height_at(x: float, z: float) -> float:
	var dx := absf(x - path_x(z))
	var h := noise.get_noise_2d(x, z) * 3.6 + noise2.get_noise_2d(x, z) * 0.5
	h *= clampf((dx - 3.0) / 14.0, 0.12, 1.0)
	h += pow(maxf(0.0, dx - 36.0), 1.5) * 0.12
	return h


func in_house(x: float, z: float, m: float) -> bool:
	for o in obstacles:
		var mn: Vector2 = o["min"]
		var mx: Vector2 = o["max"]
		if x > mn.x - m and x < mx.x + m and z > mn.y - m and z < mx.y + m:
			return true
	return false


# =====================================================================
# assets downloaded by the build (Poly Haven, CC0)
func load_assets() -> void:
	if ResourceLoader.exists("res://asset_list.gd"):
		var s = load("res://asset_list.gd")
		if s != null:
			var m: Dictionary = s.get_script_constant_map()
			if m.has("DATA"):
				A = m["DATA"]
	var fp: String = A.get("font", "")
	if fp != "" and ResourceLoader.exists(fp):
		font = load(fp)


func tex(slot: String, kind: String) -> Texture2D:
	var t: Dictionary = A.get("tex", {})
	if t.has(slot):
		var d: Dictionary = t[slot]
		var p: String = d.get(kind, "")
		if p != "" and ResourceLoader.exists(p):
			return load(p)
	return null


func model_list(group: String) -> Array:
	var m: Dictionary = A.get("models", {})
	var out: Array = m.get(group, [])
	return out


func noise_tex(c1: Color, c2: Color, freq: float, as_normal: bool) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = freq
	fn.seed = randi()
	nt.noise = fn
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	nt.generate_mipmaps = true
	if as_normal:
		nt.as_normal_map = true
		nt.bump_strength = 6.0
	else:
		var g := Gradient.new()
		g.set_color(0, c1)
		g.set_color(1, c2)
		nt.color_ramp = g
	return nt


func pbr_mat(slot: String, col: Color, uv_scale: float, triplanar: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var a := tex(slot, "alb")
	if a != null:
		m.albedo_texture = a
		m.albedo_color = Color(0.82, 0.82, 0.82)
	else:
		m.albedo_texture = noise_tex(col.darkened(0.45), col, 0.06, false)
	var n := tex(slot, "nor")
	m.normal_enabled = true
	if n != null:
		m.normal_texture = n
	else:
		m.normal_texture = noise_tex(col, col, 0.08, true)
	var r := tex(slot, "rgh")
	if r != null:
		m.roughness_texture = r
	m.roughness = 1.0
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func make_soft_tex() -> ImageTexture:
	var S := 64
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var d := Vector2(x - S * 0.5 + 0.5, y - S * 0.5 + 0.5).length() / (S * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func glow_mat(c: Color, billboard: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = soft_tex
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return m


# =====================================================================
var world_sky: Sky
var sky_photo := true
var sky_photo_mat: Material = null
var sky_simple_mat: Material = null
var slow_time := 0.0


func build_sky_materials() -> void:
	var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.015, 0.02, 0.05)
	ps.sky_horizon_color = Color(0.13, 0.14, 0.19)
	ps.ground_bottom_color = Color(0.02, 0.02, 0.02)
	ps.ground_horizon_color = Color(0.13, 0.14, 0.19)
	ps.sun_angle_max = 3.0
	sky_simple_mat = ps
	# The night photo is converted to a half-float texture with mipmaps.
	# A raw 32-bit float panorama is extremely slow on some phone GPUs.
	var hp: String = A.get("hdri", "")
	if hp == "" or not ResourceLoader.exists(hp):
		return
	var src: Texture2D = load(hp)
	if src == null:
		return
	var img: Image = src.get_image()
	if img == null or img.is_empty():
		return
	if img.is_compressed():
		img.decompress()
	if img.is_compressed():
		return
	img.convert(Image.FORMAT_RGBAH)
	if img.get_width() > 2048:
		img.resize(2048, 1024, Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	var psm := PanoramaSkyMaterial.new()
	psm.panorama = ImageTexture.create_from_image(img)
	psm.energy_multiplier = 0.5
	sky_photo_mat = psm


func apply_sky() -> void:
	if sky_photo and sky_photo_mat != null:
		world_sky.sky_material = sky_photo_mat
	else:
		world_sky.sky_material = sky_simple_mat


func build_environment() -> void:
	var we := WorldEnvironment.new()
	world_env = Environment.new()
	world_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	world_sky = sky
	build_sky_materials()
	apply_sky()
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	world_env.sky = sky
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env.ambient_light_energy = 0.7
	world_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	world_env.tonemap_exposure = 1.15
	world_env.glow_enabled = true
	world_env.glow_intensity = 0.8
	world_env.glow_strength = 1.0
	world_env.glow_bloom = 0.04
	world_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	world_env.fog_enabled = true
	world_env.fog_light_color = Color(0.1, 0.11, 0.14)
	world_env.fog_light_energy = 1.0
	world_env.fog_density = 0.032
	world_env.fog_sky_affect = 0.55
	world_env.fog_height = 1.2
	world_env.fog_height_density = 0.1
	world_env.adjustment_enabled = true
	world_env.adjustment_contrast = 1.08
	world_env.adjustment_saturation = 0.85
	we.environment = world_env
	add_child(we)

	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 0.95)
	moon.light_energy = 0.6
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 28.0
	moon.rotation_degrees = Vector3(-38.0, 150.0, 0.0)
	add_child(moon)


# =====================================================================
func build_terrain() -> void:
	var step := 1.25
	var nx := int(200.0 / step) + 1
	var nz := int(380.0 / step) + 1
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	for iz in nz:
		var z := 40.0 - iz * step
		for ix in nx:
			hs[iz * nx + ix] = height_at(-100.0 + ix * step, z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		var z := 40.0 - iz * step
		var pz := path_x(z)
		for ix in nx:
			var x := -100.0 + ix * step
			var i := iz * nx + ix
			var hl: float = hs[i - 1] if ix > 0 else hs[i]
			var hr: float = hs[i + 1] if ix < nx - 1 else hs[i]
			var hn: float = hs[i - nx] if iz > 0 else hs[i]
			var hso: float = hs[i + nx] if iz < nz - 1 else hs[i]
			var nrm := Vector3((hl - hr) / (2.0 * step), 1.0, (hso - hn) / (2.0 * step)).normalized()
			var dx := absf(x - pz)
			var wob := noise2.get_noise_2d(x * 3.0, z * 3.0) * 1.2
			var pathm := 1.0 - smoothstep(1.6 + wob, 3.2 + wob, dx)
			if z < -178.0:
				pathm = maxf(pathm, clampf(1.0 - dx / 16.0, 0.0, 1.0) * 0.55)
			var vary := 0.82 + noise.get_noise_2d(x * 2.0 + 50.0, z * 2.0) * 0.3
			st.set_color(Color(pathm, vary, 0.0))
			st.set_normal(nrm)
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, hs[i], z))
	for iz in nz - 1:
		for ix in nx - 1:
			var i := iz * nx + ix
			st.add_index(i)
			st.add_index(i + nx)
			st.add_index(i + 1)
			st.add_index(i + 1)
			st.add_index(i + nx)
			st.add_index(i + nx + 1)
	st.generate_tangents()
	var mesh := st.commit()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	sm.shader = sh
	set_ground_tex(sm, "g", "ground", Color(0.16, 0.2, 0.1))
	set_ground_tex(sm, "p", "path", Color(0.3, 0.25, 0.18))
	set_ground_tex(sm, "r", "rock", Color(0.32, 0.31, 0.29))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = sm
	terrain_mi = mi
	terrain_simple = ShaderMaterial.new()
	var sh2 := Shader.new()
	sh2.code = TERRAIN_SIMPLE
	terrain_simple.shader = sh2
	for pname in ["g_alb", "p_alb", "g_tint", "p_tint"]:
		terrain_simple.set_shader_parameter(pname, sm.get_shader_parameter(pname))
	groups["terrain"].append(mi)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func set_ground_tex(sm: ShaderMaterial, pre: String, slot: String, col: Color) -> void:
	var a := tex(slot, "alb")
	if a != null:
		sm.set_shader_parameter(pre + "_alb", a)
		sm.set_shader_parameter(pre + "_tint", Vector3(0.78, 0.78, 0.8))
	else:
		sm.set_shader_parameter(pre + "_alb", noise_tex(col.darkened(0.55), col, 0.05, false))
		sm.set_shader_parameter(pre + "_tint", Vector3(1.0, 1.0, 1.0))
	var n := tex(slot, "nor")
	if n != null:
		sm.set_shader_parameter(pre + "_nor", n)
	else:
		sm.set_shader_parameter(pre + "_nor", noise_tex(col, col, 0.08, true))
	var r := tex(slot, "rgh")
	if r != null:
		sm.set_shader_parameter(pre + "_rgh", r)


# =====================================================================
# multimesh helpers (instancing + distance culling per 40 m chunk)
func add_multimesh(mesh: Mesh, xforms: Array, cols: Array, range_end: float, shadows: bool) -> void:
	if xforms.is_empty():
		return
	var c := Vector3.ZERO
	for t in xforms:
		var tt: Transform3D = t
		c += tt.origin
	c /= float(xforms.size())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		var t: Transform3D = xforms[i]
		t.origin -= c
		mm.set_instance_transform(i, t)
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = c
	mmi.visibility_range_end = range_end
	if shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	ranged.append([mmi, range_end])
	if cur_tag != "":
		groups[cur_tag].append(mmi)
	if tag_heavy:
		heavy.append(mmi)


func add_chunked(mesh: Mesh, xforms: Array, cols: Array, range_end: float, shadows: bool, bucket: float) -> void:
	var buckets := {}
	for i in xforms.size():
		var t: Transform3D = xforms[i]
		var key := int(floor(t.origin.z / bucket))
		if not buckets.has(key):
			buckets[key] = [[], []]
		buckets[key][0].append(t)
		if not cols.is_empty():
			buckets[key][1].append(cols[i])
	for key in buckets:
		add_multimesh(mesh, buckets[key][0], buckets[key][1], range_end, shadows)


const MAX_MODEL_TRIS := 25000
var models_ok := 0
var models_skipped := 0
var model_nodes: Array = []
var show_models := true


func mesh_tris(m: Mesh) -> int:
	var n := 0
	if m is ArrayMesh:
		var am := m as ArrayMesh
		for i in am.get_surface_count():
			var il := am.surface_get_array_index_len(i)
			if il <= 0:
				il = am.surface_get_array_len(i)
			n += il / 3
	return n


func usable(parts: Array, path: String) -> bool:
	if parts.is_empty():
		return false
	var n := 0
	for part in parts:
		n += mesh_tris(part[0])
	if n > MAX_MODEL_TRIS:
		models_skipped += 1
		print("Skipping heavy model ", path, " (", n, " triangles)")
		return false
	models_ok += 1
	return true


func mesh_parts(path: String) -> Array:
	var out: Array = []
	if not ResourceLoader.exists(path):
		return out
	var ps = load(path)
	if not (ps is PackedScene):
		return out
	var root: Node = ps.instantiate()
	_collect(root, Transform3D.IDENTITY, out)
	root.free()
	return out


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			out.append([mi.mesh, t])
	for ch in n.get_children():
		_collect(ch, t, out)


func scatter_models(parts_list: Array, xforms_per_model: Dictionary, range_end: float, shadows: bool) -> void:
	for k in xforms_per_model:
		var parts: Array = parts_list[k]
		for t in xforms_per_model[k]:
			var tt: Transform3D = t
			for part in parts:
				var mi := MeshInstance3D.new()
				mi.mesh = part[0]
				var pt: Transform3D = part[1]
				mi.transform = tt * pt
				mi.visibility_range_end = range_end
				mi.lod_bias = 0.3
				if shadows:
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				else:
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				ranged.append([mi, range_end])
				model_nodes.append(mi)
				if cur_tag != "":
					groups[cur_tag].append(mi)


# =====================================================================
func tri(st: SurfaceTool, a: Vector3, na: Vector3, ua: Vector2, b: Vector3, nb: Vector3, ub: Vector2, c: Vector3, nc: Vector3, uc: Vector2) -> void:
	st.set_normal(na)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(nb)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(nc)
	st.set_uv(uc)
	st.add_vertex(c)


func card(st: SurfaceTool, a: Vector3, b: Vector3, hs: Vector3, nrm: Vector3) -> void:
	var p0 := a - hs * 0.35
	var p1 := a + hs * 0.35
	var p2 := b + hs
	var p3 := b - hs
	tri(st, p0, nrm, Vector2(0.0, 0.325), p1, nrm, Vector2(0.0, 0.675), p2, nrm, Vector2(1.0, 1.0))
	tri(st, p0, nrm, Vector2(0.0, 0.325), p2, nrm, Vector2(1.0, 1.0), p3, nrm, Vector2(1.0, 0.0))


func make_needle_tex() -> ImageTexture:
	var S := 256
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in 1500:
		var bx := r.randf_range(2.0, S - 4.0)
		var u := bx / S
		var maxlen := (0.25 + 0.75 * sin(u * PI * 0.9 + 0.15)) * S * 0.42
		var side := -1.0 if r.randf() < 0.5 else 1.0
		var ang := r.randf_range(0.45, 1.1)
		var dvx := cos(ang)
		var dvy := sin(ang) * side
		var ln := r.randf_range(0.5, 1.0) * maxlen
		var c := Color(r.randf_range(0.06, 0.12), r.randf_range(0.16, 0.27), r.randf_range(0.07, 0.12), 1.0)
		var px := bx
		var py := S * 0.5
		for k in int(ln):
			px += dvx
			py += dvy
			var ix := int(px)
			var iy := int(py)
			if ix < 0 or ix >= S or iy < 0 or iy >= S:
				break
			img.set_pixel(ix, iy, c)
	for x in S:
		for dy in 3:
			img.set_pixel(x, S / 2 - 1 + dy, Color(0.16, 0.11, 0.07, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func make_pine() -> Array:
	var H := 12.0
	var bark := pbr_mat("bark", Color(0.24, 0.18, 0.13), 1.0, false)
	bark.uv1_scale = Vector3(1.0, 1.0, 1.0)
	bark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 8
	for i in seg:
		var a0 := TAU * float(i) / seg
		var a1 := TAU * float(i + 1) / seg
		var b0 := Vector3(cos(a0) * 0.3, -0.4, sin(a0) * 0.3)
		var b1 := Vector3(cos(a1) * 0.3, -0.4, sin(a1) * 0.3)
		var t0 := Vector3(cos(a0) * 0.04, H * 0.93, sin(a0) * 0.04)
		var t1 := Vector3(cos(a1) * 0.04, H * 0.93, sin(a1) * 0.04)
		var n0 := Vector3(cos(a0), 0.08, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), 0.08, sin(a1)).normalized()
		var u0 := float(i) / seg
		var u1 := float(i + 1) / seg
		tri(st, b0, n0, Vector2(u0, 0.0), b1, n1, Vector2(u1, 0.0), t1, n1, Vector2(u1, 6.0))
		tri(st, b0, n0, Vector2(u0, 0.0), t1, n1, Vector2(u1, 6.0), t0, n0, Vector2(u0, 6.0))
	st.generate_tangents()
	var trunk := st.commit()
	trunk.surface_set_material(0, bark)

	var nm := StandardMaterial3D.new()
	nm.albedo_texture = make_needle_tex()
	nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	nm.alpha_scissor_threshold = 0.3
	nm.cull_mode = BaseMaterial3D.CULL_DISABLED
	nm.roughness = 0.9
	nm.vertex_color_use_as_albedo = true
	nm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rr := RandomNumberGenerator.new()
	rr.seed = 11
	var levels := 11
	for k in levels:
		var f := float(k) / float(levels - 1)
		var y := 2.0 + f * (H - 2.4)
		var blen := lerpf(3.6, 0.6, pow(f, 0.85))
		var count := 6 if k < levels - 3 else 4
		for j in count:
			var a := TAU * float(j) / float(count) + k * 0.7 + rr.randf_range(-0.2, 0.2)
			var dir := Vector3(cos(a), 0.0, sin(a))
			var droop := rr.randf_range(0.2, 0.45)
			var start := Vector3(0.0, y, 0.0) + dir * 0.1
			var tip := start + dir * blen + Vector3(0.0, -blen * droop, 0.0)
			var side := Vector3(-dir.z, 0.0, dir.x)
			var w := blen * 0.55
			var nrm := (dir * 0.45 + Vector3.UP).normalized()
			card(st2, start, tip, side * w * 0.5, nrm)
			card(st2, start, tip, (Vector3.UP * 0.8 + side * 0.2).normalized() * w * 0.33, nrm)
	for j in 3:
		var a := TAU * float(j) / 3.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		card(st2, Vector3(0.0, H - 1.8, 0.0), Vector3(0.0, H + 0.3, 0.0) + dir * 0.1, dir * 0.45, Vector3.UP)
	var needles := st2.commit()
	needles.surface_set_material(0, nm)
	return [trunk, needles]


func build_trees() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var pts: Array = []
	var tries := 0
	while pts.size() < 480 and tries < 30000:
		tries += 1
		var z := r.randf_range(-338.0, 35.0)
		var x := r.randf_range(-95.0, 95.0)
		var dx := absf(x - path_x(z))
		if dx < 6.5:
			continue
		if z < -176.0 and z > -328.0 and dx < 22.0:
			continue
		if in_house(x, z, 3.0):
			continue
		var forest := z < -90.0 and z > -172.0
		if not forest and r.randf() < 0.5:
			continue
		if z > -90.0 and z < -25.0 and dx < 26.0 and r.randf() < 0.8:
			continue
		pts.append(Vector4(x, height_at(x, z), z, r.randf_range(8.0, 15.0)))
		tree_col.append(Vector3(x, z, 0.4))
	var parts_list: Array = []
	for mp in model_list("trees"):
		var parts := mesh_parts(mp)
		if usable(parts, mp):
			parts_list.append(parts)
	var pine := make_pine()
	var pine_x: Array = []
	var pine_c: Array = []
	var model_x := {}
	var model_n := 0
	for p in pts:
		var v4: Vector4 = p
		if not parts_list.is_empty() and model_n < 12 and r.randf() < 0.12:
			model_n += 1
			var k := r.randi() % parts_list.size()
			if not model_x.has(k):
				model_x[k] = []
			model_x[k].append(Transform3D(Basis(Vector3.UP, r.randf() * TAU), Vector3(v4.x, v4.y, v4.z)))
		else:
			var sc := v4.w / 12.0
			var bs := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(sc, sc * r.randf_range(0.9, 1.1), sc))
			pine_x.append(Transform3D(bs, Vector3(v4.x, v4.y - 0.1, v4.z)))
			var v := r.randf()
			pine_c.append(Color(0.75 + v * 0.35, 0.8 + v * 0.3, 0.75 + v * 0.25))
	cur_tag = "trees"
	add_chunked(pine[0], pine_x, [], 95.0, true, 40.0)
	tag_heavy = true
	add_chunked(pine[1], pine_x, pine_c, 95.0, true, 40.0)
	tag_heavy = false
	scatter_models(parts_list, model_x, 70.0, false)
	cur_tag = ""


func make_rock() -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radial_segments = 18
	sm.rings = 10
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var fn := FastNoiseLite.new()
	fn.frequency = 1.4
	fn.seed = 4
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + fn.get_noise_3dv(v) * 0.38
		verts[i] = Vector3(v.x * k, v.y * k * 0.7, v.z * k)
	arr[Mesh.ARRAY_VERTEX] = verts
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_normals()
	return st.commit()


func build_rocks() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 21
	var parts_list: Array = []
	for mp in model_list("rocks"):
		var parts := mesh_parts(mp)
		if usable(parts, mp):
			parts_list.append(parts)
	var rock := make_rock()
	rock.surface_set_material(0, pbr_mat("rock", Color(0.34, 0.33, 0.31), 0.6))
	var xs: Array = []
	var model_x := {}
	var model_n := 0
	for i in 190:
		var z := r.randf_range(-330.0, 30.0)
		var x := path_x(z) + r.randf_range(-45.0, 45.0)
		if absf(x - path_x(z)) < 3.5 or in_house(x, z, 1.0):
			continue
		var s := 0.25 + r.randf() * r.randf() * 1.6
		var y := height_at(x, z)
		if not parts_list.is_empty() and model_n < 28 and r.randf() < 0.4:
			model_n += 1
			var k := r.randi() % parts_list.size()
			if not model_x.has(k):
				model_x[k] = []
			var ms := r.randf_range(0.5, 1.3)
			model_x[k].append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(ms, ms, ms)), Vector3(x, y - 0.1, z)))
			s = ms
		else:
			var bs := Basis.from_euler(Vector3(r.randf() * 3.0, r.randf() * 3.0, r.randf() * 3.0)).scaled(Vector3(s, s * 0.7, s * r.randf_range(0.7, 1.2)))
			xs.append(Transform3D(bs, Vector3(x, y - s * 0.25, z)))
		if s > 0.7:
			tree_col.append(Vector3(x, z, s * 0.8))
	cur_tag = "rocks"
	add_chunked(rock, xs, [], 70.0, true, 40.0)
	scatter_models(parts_list, model_x, 45.0, false)
	cur_tag = ""


func build_plants() -> void:
	var parts_list: Array = []
	for mp in model_list("plants"):
		var parts := mesh_parts(mp)
		if usable(parts, mp):
			parts_list.append(parts)
	if parts_list.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.seed = 31
	var model_x := {}
	for i in 50:
		var z := r.randf_range(-175.0, -20.0)
		var x := path_x(z) + r.randf_range(-30.0, 30.0)
		if absf(x - path_x(z)) < 3.0 or in_house(x, z, 1.0):
			continue
		var k := r.randi() % parts_list.size()
		if not model_x.has(k):
			model_x[k] = []
		var ms := r.randf_range(0.7, 1.3)
		model_x[k].append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(ms, ms, ms)), Vector3(x, height_at(x, z), z)))
	cur_tag = "rocks"
	scatter_models(parts_list, model_x, 28.0, false)
	cur_tag = ""


func make_tuft() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for b in 7:
		var a := r.randf() * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var base := Vector3(r.randf_range(-0.12, 0.12), 0.0, r.randf_range(-0.12, 0.12))
		var h := r.randf_range(0.55, 1.0)
		var lean := r.randf_range(0.15, 0.45)
		var w := r.randf_range(0.025, 0.045)
		for s in 4:
			var t0 := float(s) / 4.0
			var t1 := float(s + 1) / 4.0
			var p0 := base + dir * lean * t0 * t0 + Vector3(0.0, h * t0, 0.0)
			var p1 := base + dir * lean * t1 * t1 + Vector3(0.0, h * t1, 0.0)
			var a0 := p0 - side * w * (1.0 - t0)
			var b0 := p0 + side * w * (1.0 - t0)
			var a1 := p1 - side * w * (1.0 - t1)
			var b1 := p1 + side * w * (1.0 - t1)
			var up := Vector3.UP
			tri(st, a0, up, Vector2(0.0, t0), b0, up, Vector2(1.0, t0), b1, up, Vector2(1.0, t1))
			tri(st, a0, up, Vector2(0.0, t0), b1, up, Vector2(1.0, t1), a1, up, Vector2(0.0, t1))
	return st.commit()


func build_grass() -> void:
	for p in [[-22, 7, 6], [-42, -9, 8], [-62, 10, 7], [-84, -8, 8], [-108, 9, 6], [-128, -10, 7], [-152, 8, 7], [-176, -12, 6], [-205, 0, 4], [-232, 14, 5], [-258, -14, 5], [-282, -11, 6]]:
		var pz := float(p[0])
		tall_patches.append(Vector3(path_x(pz) + float(p[1]), pz, float(p[2])))
	var tuft := make_tuft()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	sm.shader = sh
	tuft.surface_set_material(0, sm)
	var r := RandomNumberGenerator.new()
	r.seed = 99
	var xs: Array = []
	var cs: Array = []
	var n := 0
	while n < 11000:
		var z := r.randf_range(-330.0, 32.0)
		var x := path_x(z) + r.randf_range(-32.0, 32.0)
		var dx := absf(x - path_x(z))
		if dx < 2.3 or in_house(x, z, 0.4):
			continue
		if r.randf() < dx / 48.0:
			continue
		n += 1
		var s := r.randf_range(0.7, 1.25)
		var bs := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, r.randf_range(0.3, 0.7), s))
		xs.append(Transform3D(bs, Vector3(x, height_at(x, z), z)))
		var v := r.randf()
		cs.append(Color(0.8 + v * 0.4, 0.85 + v * 0.3, 0.8 + v * 0.3))
	for p in tall_patches:
		var tp: Vector3 = p
		for i in 260:
			var a := r.randf() * TAU
			var rad := sqrt(r.randf()) * tp.z
			var x := tp.x + cos(a) * rad
			var z := tp.y + sin(a) * rad
			var s := r.randf_range(1.2, 1.6)
			var bs := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, r.randf_range(1.0, 1.5), s))
			xs.append(Transform3D(bs, Vector3(x, height_at(x, z), z)))
			var v := r.randf()
			cs.append(Color(1.3 + v * 0.3, 1.15 + v * 0.2, 0.9 + v * 0.2))
	cur_tag = "grass"
	add_chunked(tuft, xs, cs, 42.0, false, 24.0)
	cur_tag = ""


# =====================================================================
func build_village() -> void:
	m_walls = [pbr_mat("wall", Color(0.36, 0.34, 0.31), 0.45), pbr_mat("wood", Color(0.3, 0.23, 0.17), 0.5)]
	m_roof = pbr_mat("roof", Color(0.2, 0.14, 0.1), 0.5) if tex("roof", "alb") != null else pbr_mat("wood", Color(0.2, 0.14, 0.1), 0.5)
	m_stone = pbr_mat("wall", Color(0.4, 0.39, 0.36), 0.4)
	m_win_lit = StandardMaterial3D.new()
	m_win_lit.albedo_color = Color(0.2, 0.12, 0.05)
	m_win_lit.emission_enabled = true
	m_win_lit.emission = Color(1.0, 0.6, 0.27)
	m_win_lit.emission_energy_multiplier = 3.0
	m_win_dark = StandardMaterial3D.new()
	m_win_dark.albedo_color = Color(0.03, 0.03, 0.035)
	m_win_dark.roughness = 0.15
	m_win_dark.metallic = 0.4
	m_door = pbr_mat("wood", Color(0.18, 0.12, 0.08), 0.8)
	var r := RandomNumberGenerator.new()
	r.seed = 42
	add_house(path_x(-58.0) - 13.0, -58.0, 9.0, 6.0, 4.2, r)
	add_house(path_x(-70.0) + 12.0, -70.0, 5.0, 5.0, 3.0, r)
	add_house(path_x(-135.0) + 11.0, -135.0, 5.0, 4.5, 3.0, r)
	var z := -186.0
	while z > -272.0:
		for side in [-1.0, 1.0]:
			if r.randf() < 0.18:
				continue
			var w := r.randf_range(4.5, 7.5)
			var d := r.randf_range(4.5, 7.0)
			add_house(path_x(z) + side * r.randf_range(9.5, 13.5), z + r.randf_range(-2.5, 2.5), w, d, r.randf_range(3.0, 4.6), r)
		z -= 17.0
	add_lamp(path_x(-30.0) + 3.0, -30.0)
	add_lamp(path_x(-180.0) - 3.5, -180.0)
	build_tower()
	build_fire()


func box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func add_face(parent: Node3D, pos: Vector3, side: float, sz: Vector2, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	mi.mesh = q
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = side * PI * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func add_house(x: float, z: float, w: float, d: float, h: float, r: RandomNumberGenerator) -> void:
	var lo := 1e9
	var hi := -1e9
	for ax in [x - w * 0.5, x + w * 0.5]:
		for bz in [z - d * 0.5, z + d * 0.5]:
			var y := height_at(ax, bz)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	var base := lo - 0.4
	var wall_h := h + (hi - lo) + 0.4
	var house := Node3D.new()
	house.position = Vector3(x, base, z)
	add_child(house)
	box(house, Vector3(w, wall_h, d), Vector3(0.0, wall_h * 0.5, 0.0), m_walls[r.randi() % m_walls.size()])
	box(house, Vector3(w + 0.1, 0.25, d + 0.1), Vector3(0.0, wall_h - h + 0.1, 0.0), m_door)
	var rh := r.randf_range(1.6, 2.8)
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(w * 1.15, rh, d * 1.12)
	roof.mesh = pm
	roof.material_override = m_roof
	roof.position = Vector3(0.0, wall_h + rh * 0.5, 0.0)
	house.add_child(roof)
	var side := signf(path_x(z) - x)
	if side == 0.0:
		side = 1.0
	var floor_y := wall_h - h
	add_face(house, Vector3(side * (w * 0.5 + 0.02), floor_y + 1.05, 0.0), side, Vector2(1.1, 2.1), m_door)
	for off in [-d * 0.3, d * 0.3]:
		var lit := r.randf() < 0.45
		add_face(house, Vector3(side * (w * 0.5 + 0.02), floor_y + 1.9, off), side, Vector2(0.9, 0.8), m_win_lit if lit else m_win_dark)
		if lit and window_lights < 5 and r.randf() < 0.6:
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.6, 0.28)
			ol.light_energy = 0.9
			ol.omni_range = 7.0
			ol.position = Vector3(side * (w * 0.5 + 1.0), floor_y + 1.9, off)
			house.add_child(ol)
			window_lights += 1
			flicker.append([ol, 0.9, false])
	obstacles.append({"min": Vector2(x - w * 0.5, z - d * 0.5), "max": Vector2(x + w * 0.5, z + d * 0.5), "base": base, "top": base + wall_h + rh})


func add_lamp(x: float, z: float) -> void:
	var y := height_at(x, z)
	var holder := Node3D.new()
	holder.position = Vector3(x, y, z)
	add_child(holder)
	box(holder, Vector3(0.14, 2.7, 0.14), Vector3(0.0, 1.35, 0.0), m_door)
	box(holder, Vector3(0.24, 0.32, 0.24), Vector3(0.0, 2.75, 0.0), m_win_lit)
	var ol := OmniLight3D.new()
	ol.light_color = Color(1.0, 0.66, 0.32)
	ol.light_energy = 1.4
	ol.omni_range = 14.0
	ol.shadow_enabled = false
	ol.position = Vector3(0.0, 2.6, 0.3)
	holder.add_child(ol)
	flicker.append([ol, 1.4, false])
	obstacles.append({"min": Vector2(x - 0.15, z - 0.15), "max": Vector2(x + 0.15, z + 0.15), "base": y, "top": y + 3.0})


func build_tower() -> void:
	var t := Node3D.new()
	t.position = Vector3(tower_pos.x, tower_pos.y - 0.5, tower_pos.z)
	add_child(t)
	box(t, Vector3(5.0, 13.0, 5.0), Vector3(0.0, 6.5, 0.0), m_stone)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var cv: Vector2 = c
		box(t, Vector3(0.7, 3.0, 0.7), Vector3(cv.x * 2.15, 14.5, cv.y * 2.15), m_stone)
	box(t, Vector3(5.2, 0.4, 5.2), Vector3(0.0, 16.1, 0.0), m_stone)
	var roof := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 4.0
	cm.height = 4.5
	cm.radial_segments = 4
	roof.mesh = cm
	roof.material_override = m_roof
	roof.rotation.y = PI * 0.25
	roof.position = Vector3(0.0, 18.5, 0.0)
	t.add_child(roof)
	var bell := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.5
	bm.bottom_radius = 0.95
	bm.height = 1.2
	bell.mesh = bm
	var bron := StandardMaterial3D.new()
	bron.albedo_color = Color(0.45, 0.32, 0.16)
	bron.metallic = 0.9
	bron.roughness = 0.4
	bell.material_override = bron
	bell.position = Vector3(0.0, 14.6, 0.0)
	t.add_child(bell)
	add_face(t, Vector3(0.0, 1.8, 2.52), 0.0, Vector2(1.6, 2.6), m_door)
	obstacles.append({"min": Vector2(tower_pos.x - 2.5, tower_pos.z - 2.5), "max": Vector2(tower_pos.x + 2.5, tower_pos.z + 2.5), "base": tower_pos.y - 0.5, "top": tower_pos.y + 20.0})


func build_fire() -> void:
	var f := Node3D.new()
	f.position = fire_pos
	add_child(f)
	var logm := pbr_mat("bark", Color(0.12, 0.08, 0.05), 1.0)
	for i in 6:
		var lg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 0.12
		cm.height = 1.5
		lg.mesh = cm
		lg.material_override = logm
		lg.position = Vector3(0.0, 0.35, 0.0)
		lg.rotation = Vector3(1.0, i * 1.05, 0.0)
		f.add_child(lg)
	var flame := CPUParticles3D.new()
	flame.amount = 46
	flame.lifetime = 0.9
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = 0.35
	flame.direction = Vector3.UP
	flame.spread = 14.0
	flame.initial_velocity_min = 0.8
	flame.initial_velocity_max = 1.8
	flame.gravity = Vector3(0.0, 0.6, 0.0)
	flame.scale_amount_min = 0.6
	flame.scale_amount_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.75, 0.35, 1.0))
	g.set_color(1, Color(0.7, 0.12, 0.02, 0.0))
	flame.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.9)
	q.material = glow_mat(Color(3.0, 2.0, 1.2), true)
	flame.mesh = q
	flame.position = Vector3(0.0, 0.5, 0.0)
	f.add_child(flame)
	groups["particles"].append(flame)
	var smoke := CPUParticles3D.new()
	smoke.amount = 24
	smoke.lifetime = 4.0
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.4
	smoke.direction = Vector3.UP
	smoke.spread = 10.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.0
	smoke.gravity = Vector3(0.3, 0.2, 0.0)
	smoke.scale_amount_min = 1.5
	smoke.scale_amount_max = 3.0
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.25, 0.24, 0.24, 0.35))
	g2.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	smoke.color_ramp = g2
	var q2 := QuadMesh.new()
	q2.size = Vector2(1.0, 1.0)
	var smat := glow_mat(Color(1, 1, 1), true)
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	q2.material = smat
	smoke.mesh = q2
	smoke.position = Vector3(0.0, 1.5, 0.0)
	f.add_child(smoke)
	groups["particles"].append(smoke)
	var ol := OmniLight3D.new()
	ol.light_color = Color(1.0, 0.5, 0.2)
	ol.light_energy = 2.4
	ol.omni_range = 24.0
	ol.position = Vector3(0.0, 1.3, 0.0)
	f.add_child(ol)
	flicker.append([ol, 2.4, true])
	obstacles.append({"min": Vector2(fire_pos.x - 0.8, fire_pos.z - 0.8), "max": Vector2(fire_pos.x + 0.8, fire_pos.z + 0.8), "base": fire_pos.y, "top": fire_pos.y + 1.0})


# =====================================================================
func build_player() -> void:
	add_child(player)
	player.add_child(cam)
	cam.fov = 72.0
	cam.near = 0.03
	cam.far = 400.0
	cam.make_current()
	cam.add_child(torch)
	torch.position = Vector3(0.25, -0.15, 0.0)
	torch.spot_range = 40.0
	torch.spot_angle = 24.0
	torch.spot_angle_attenuation = 0.8
	torch.light_energy = 0.0
	torch.light_color = Color(1.0, 0.92, 0.8)
	torch.shadow_enabled = true
	build_gun()
	laser.mesh = laser_mesh
	add_child(laser)
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_mat.albedo_color = Color(2.5, 0.15, 0.08, 0.55)
	var sp := SphereMesh.new()
	sp.radius = 0.02
	sp.height = 0.04
	sp.radial_segments = 8
	sp.rings = 4
	dot.mesh = sp
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(4.0, 0.3, 0.15)
	dm.no_depth_test = true
	dot.material_override = dm
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dot)
	for i in 6:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = 14
		p.lifetime = 0.7
		p.explosiveness = 1.0
		p.direction = Vector3.UP
		p.spread = 60.0
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 2.5
		p.gravity = Vector3(0.0, -5.0, 0.0)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.2
		var g := Gradient.new()
		g.set_color(0, Color(0.45, 0.4, 0.33, 0.8))
		g.set_color(1, Color(0.3, 0.28, 0.25, 0.0))
		p.color_ramp = g
		var q := QuadMesh.new()
		q.size = Vector2(0.12, 0.12)
		var pm := glow_mat(Color(1, 1, 1), true)
		pm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		q.material = pm
		p.mesh = q
		add_child(p)
		impacts.append(p)
	var ff := CPUParticles3D.new()
	ff.amount = 45
	ff.lifetime = 6.0
	ff.local_coords = false
	ff.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ff.emission_box_extents = Vector3(18.0, 1.2, 18.0)
	ff.direction = Vector3.UP
	ff.spread = 180.0
	ff.initial_velocity_min = 0.1
	ff.initial_velocity_max = 0.4
	ff.gravity = Vector3.ZERO
	var fg := Gradient.new()
	fg.set_color(0, Color(0.8, 1.0, 0.4, 0.0))
	fg.set_color(1, Color(0.8, 1.0, 0.4, 0.0))
	fg.add_point(0.5, Color(0.8, 1.0, 0.4, 1.0))
	ff.color_ramp = fg
	var fq := QuadMesh.new()
	fq.size = Vector2(0.06, 0.06)
	fq.material = glow_mat(Color(3.0, 4.0, 1.5), true)
	ff.mesh = fq
	ff.position = Vector3(0.0, 1.2, 0.0)
	player.add_child(ff)
	groups["particles"].append(ff)


func gun_box(mat: Material, sz: Vector3, pos: Vector3, rx: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.x = rx
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gun.add_child(mi)


func build_gun() -> void:
	cam.add_child(gun)
	gun.position = gun_base
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.06, 0.06, 0.07)
	metal.metallic = 0.55
	metal.roughness = 0.6
	var poly := StandardMaterial3D.new()
	poly.albedo_color = Color(0.05, 0.05, 0.05)
	poly.roughness = 0.75
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.17, 0.12, 0.08)
	glove.roughness = 0.8
	gun_box(metal, Vector3(0.034, 0.036, 0.21), Vector3(0.0, 0.0, 0.0), 0.0)
	gun_box(poly, Vector3(0.032, 0.026, 0.17), Vector3(0.0, -0.028, 0.01), 0.0)
	gun_box(poly, Vector3(0.03, 0.11, 0.05), Vector3(0.0, -0.085, 0.075), 0.28)
	gun_box(glove, Vector3(0.07, 0.075, 0.1), Vector3(0.005, -0.09, 0.085), 0.28)
	gun_box(glove, Vector3(0.06, 0.06, 0.09), Vector3(-0.035, -0.095, 0.06), 0.2)
	gun_box(metal, Vector3(0.02, 0.018, 0.04), Vector3(0.0, -0.045, -0.07), 0.0)
	gun_box(metal, Vector3(0.006, 0.008, 0.006), Vector3(0.0, 0.022, -0.095), 0.0)
	laser_origin.position = Vector3(0.0, -0.045, -0.092)
	gun.add_child(laser_origin)
	muzzle.position = Vector3(0.0, 0.0, -0.12)
	gun.add_child(muzzle)
	muzzle_light.light_color = Color(1.0, 0.7, 0.35)
	muzzle_light.omni_range = 8.0
	muzzle_light.light_energy = 0.0
	muzzle.add_child(muzzle_light)
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	var fm := glow_mat(Color(4.0, 2.6, 1.2), false)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = fm
	muzzle_flash.mesh = q
	muzzle_flash.visible = false
	muzzle_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle.add_child(muzzle_flash)


func reset_player() -> void:
	player.position = Vector3(path_x(12.0), height_at(path_x(12.0), 12.0), 12.0)
	player.rotation = Vector3.ZERO
	pitch = 0.0
	eye = 1.65
	clip = 12
	reserve = 36
	finished = false
	cam.position = Vector3(0.0, eye, 0.0)


# =====================================================================
# audio (generated, no files needed)
func make_sound(dur: float, kind: String) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var fall := pow(1.0 - float(i) / n, 2.5)
		var s := 0.0
		match kind:
			"shot":
				lp += (randf() * 2.0 - 1.0 - lp) * 0.4
				phase += TAU * lerpf(150.0, 38.0, t / dur) / rate
				s = (lp * 0.95 + sin(phase) * 0.6) * fall
			"step":
				lp += (randf() * 2.0 - 1.0 - lp) * 0.09
				s = lp * fall * 2.2
			"click":
				s = sin(TAU * 1100.0 * t) * fall * 0.5
			"reload":
				var k := 0.0
				if t < 0.05 or (t > 0.55 and t < 0.6):
					k = 1.0
				lp += (randf() * 2.0 - 1.0 - lp) * 0.5
				s = lp * k * 0.6
			"wind":
				lp += (randf() * 2.0 - 1.0 - lp) * 0.02
				lp2 += (lp - lp2) * 0.05
				s = lp2 * 6.0 * (0.65 + 0.35 * sin(TAU * t / dur))
			"crickets":
				var ph := fmod(t, 1.4)
				var chirp := 0.0
				if ph < 0.25 and fmod(ph, 0.06) < 0.035:
					chirp = 1.0
				s = sin(TAU * 4300.0 * t) * chirp * 0.12
			"bell":
				s = (sin(TAU * 220.0 * t) + sin(TAU * 440.0 * t) * 0.6 + sin(TAU * 662.0 * t) * 0.4 + sin(TAU * 1104.0 * t) * 0.25) * exp(-t * 1.2) * 0.35
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if kind == "wind" or kind == "crickets":
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


func build_audio() -> void:
	sounds["shot"] = make_sound(0.45, "shot")
	sounds["step"] = make_sound(0.09, "step")
	sounds["click"] = make_sound(0.05, "click")
	sounds["reload"] = make_sound(0.7, "reload")
	sounds["bell"] = make_sound(3.5, "bell")
	for i in 8:
		var ap := AudioStreamPlayer.new()
		add_child(ap)
		sfx_players.append(ap)
	var wind := AudioStreamPlayer.new()
	wind.stream = make_sound(4.0, "wind")
	wind.volume_db = -10.0
	add_child(wind)
	wind.play()
	var cr := AudioStreamPlayer.new()
	cr.stream = make_sound(2.8, "crickets")
	cr.volume_db = -16.0
	add_child(cr)
	cr.play()


func play_sfx(id: String, vol: float = 0.0, pit: float = 1.0) -> void:
	if not sounds.has(id):
		return
	for ap in sfx_players:
		var a: AudioStreamPlayer = ap
		if not a.playing:
			a.stream = sounds[id]
			a.volume_db = vol
			a.pitch_scale = pit
			a.play()
			return
	var a0: AudioStreamPlayer = sfx_players[0]
	a0.stream = sounds[id]
	a0.play()


# =====================================================================
# UI
func mk_label(txt: String, fsize: int) -> Label:
	var l := Label.new()
	l.text = txt
	var ls := LabelSettings.new()
	ls.font_size = fsize
	ls.font_color = INK
	ls.outline_size = 5
	ls.outline_color = Color(0, 0, 0, 0.85)
	if font != null:
		ls.font = font
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func mk_hud_button(id: String, txt: String, sz: Vector2, col: Color) -> Panel:
	var p := Panel.new()
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color(0.91, 0.86, 0.75, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(minf(sz.x, sz.y) * 0.5))
	p.add_theme_stylebox_override("panel", sb)
	var l := mk_label(txt, 20)
	l.size = sz
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	hud.add_child(p)
	buttons[id] = p
	return p


func set_btn_on(id: String, on: bool) -> void:
	var p: Panel = buttons[id]
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = Color(0.88, 0.63, 0.29, 0.45) if on else Color(0.07, 0.06, 0.05, 0.45)


func mk_menu_button(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(360, 42)
	b.add_theme_font_size_override("font_size", 22)
	if font != null:
		b.add_theme_font_override("font", font)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.07, 0.88)
	sb.border_color = Color(0.91, 0.86, 0.75, 0.4)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	var sp := sb.duplicate() as StyleBoxFlat
	sp.bg_color = Color(0.5, 0.1, 0.08, 0.95)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("focus", sb)
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.pressed.connect(cb)
	return b


func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(hud)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(menu)

	# HUD
	lbl_status = mk_label("", 18)
	hud.add_child(lbl_status)
	lbl_fps = mk_label("", 15)
	hud.add_child(lbl_fps)
	lbl_obj = mk_label("", 22)
	lbl_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(lbl_obj)
	arrow.polygon = PackedVector2Array([Vector2(0, -14), Vector2(10, 10), Vector2(0, 5), Vector2(-10, 10)])
	arrow.color = Color(0.88, 0.63, 0.29)
	hud.add_child(arrow)
	lbl_ammo = mk_label("", 30)
	lbl_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(lbl_ammo)
	lbl_msg = mk_label("", 36)
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(lbl_msg)
	joy_base = Panel.new()
	joy_knob = Panel.new()
	for pn in [[joy_base, 160.0, Color(0.07, 0.06, 0.05, 0.3)], [joy_knob, 70.0, Color(0.91, 0.86, 0.75, 0.35)]]:
		var p: Panel = pn[0]
		var sz: float = pn[1]
		p.size = Vector2(sz, sz)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = pn[2]
		sb.border_color = Color(0.91, 0.86, 0.75, 0.35)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(sz * 0.5))
		p.add_theme_stylebox_override("panel", sb)
		p.visible = false
		hud.add_child(p)
	mk_hud_button("fire", "FIRE", Vector2(124, 124), Color(0.35, 0.05, 0.04, 0.5))
	mk_hud_button("reload", "Reload", Vector2(80, 80), Color(0.07, 0.06, 0.05, 0.45))
	mk_hud_button("crouch", "Crouch", Vector2(80, 80), Color(0.07, 0.06, 0.05, 0.45))
	mk_hud_button("light", "Light", Vector2(80, 80), Color(0.07, 0.06, 0.05, 0.45))
	mk_hud_button("menu", "Menu", Vector2(110, 46), Color(0.07, 0.06, 0.05, 0.45))
	mk_hud_button("level", "Level view", Vector2(130, 46), Color(0.07, 0.06, 0.05, 0.45))

	# MENU
	menu_bg.color = Color(0.02, 0.02, 0.03, 0.55)
	menu_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(menu_bg)
	menu_box.add_theme_constant_override("separation", 48)
	menu.add_child(menu_box)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 7)
	menu_box.add_child(left)
	menu_box.add_child(right)
	var title := mk_label("DEAD VILLAGE", 64)
	title.label_settings.font_color = Color(0.93, 0.87, 0.76)
	title.label_settings.shadow_color = Color(0.6, 0.05, 0.03, 0.6)
	title.label_settings.shadow_size = 12
	left.add_child(title)
	var sub := mk_label("Stage 1: the journey to the bell tower.\nZombies and stealth arrive in the next update.", 19)
	left.add_child(sub)
	menu_btns["start"] = mk_menu_button("Start", start_game)
	left.add_child(menu_btns["start"])
	var help := mk_label("Left thumb: walk (push fully to run)\nMove the phone to look, or drag on the right\nFIRE shoots. Light is your flashlight.", 17)
	left.add_child(help)
	menu_btns["aim"] = mk_menu_button("", _toggle_aim)
	right.add_child(menu_btns["aim"])
	menu_btns["invx"] = mk_menu_button("", _toggle_invx)
	right.add_child(menu_btns["invx"])
	menu_btns["invy"] = mk_menu_button("", _toggle_invy)
	right.add_child(menu_btns["invy"])
	menu_btns["swap"] = mk_menu_button("", _toggle_swap)
	right.add_child(menu_btns["swap"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var minus := mk_menu_button("-", _sens_down)
	minus.custom_minimum_size = Vector2(70, 46)
	var plus := mk_menu_button("+", _sens_up)
	plus.custom_minimum_size = Vector2(70, 46)
	lbl_sens = mk_label("", 21)
	lbl_sens.custom_minimum_size = Vector2(200, 46)
	lbl_sens.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sens.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(minus)
	row.add_child(lbl_sens)
	row.add_child(plus)
	right.add_child(row)
	menu_btns["quality"] = mk_menu_button("", _cycle_quality)
	right.add_child(menu_btns["quality"])
	menu_btns["models"] = mk_menu_button("", _toggle_models)
	right.add_child(menu_btns["models"])
	menu_btns["test"] = mk_menu_button("Run speed test (25 s)", start_test)
	left.add_child(menu_btns["test"])
	lbl_results = mk_label("", 15)
	left.add_child(lbl_results)
	menu_btns["sky"] = mk_menu_button("", _toggle_sky)
	right.add_child(menu_btns["sky"])
	lbl_gyro = mk_label("", 16)
	lbl_gyro.custom_minimum_size = Vector2(360, 70)
	lbl_gyro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(lbl_gyro)
	refresh_menu()


func set_btn_text(id: String, t: String) -> void:
	var b: Button = menu_btns[id]
	b.text = t


func place(id: String, pos: Vector2) -> void:
	var c: Control = buttons[id]
	c.position = pos


func _toggle_aim() -> void:
	use_gyro = not use_gyro
	refresh_menu()


func _toggle_invx() -> void:
	inv_x = not inv_x
	refresh_menu()


func _toggle_invy() -> void:
	inv_y = not inv_y
	refresh_menu()


func _toggle_swap() -> void:
	swap_axes = not swap_axes
	refresh_menu()


func _sens_down() -> void:
	sens = maxf(0.3, sens - 0.1)
	refresh_menu()


func _sens_up() -> void:
	sens = minf(3.0, sens + 0.1)
	refresh_menu()


func _toggle_sky() -> void:
	sky_photo = not sky_photo
	apply_sky()
	refresh_menu()


func _toggle_models() -> void:
	show_models = not show_models
	for n in model_nodes:
		var mi: MeshInstance3D = n
		mi.visible = show_models
	refresh_menu()


func _cycle_quality() -> void:
	quality = (quality + 2) % 3
	fix_level = 0
	fixes_done = []
	apply_quality()
	refresh_menu()


func refresh_menu() -> void:
	set_btn_text("start", "Resume" if started else "Start")
	set_btn_text("aim", "Aim: " + ("Gyroscope + drag" if use_gyro else "Touch drag only"))
	set_btn_text("invx", "Invert turn: " + ("On" if inv_x else "Off"))
	set_btn_text("invy", "Invert tilt: " + ("On" if inv_y else "Off"))
	set_btn_text("swap", "Swap gyro axes: " + ("On" if swap_axes else "Off"))
	var qn: Array = ["Low (fastest)", "Medium (recommended)", "High"]
	set_btn_text("quality", "Graphics: " + str(qn[quality]))
	set_btn_text("models", "Scanned rocks/plants: " + ("On" if show_models else "Off"))
	var sky_txt := "Simple (fast)"
	if sky_photo:
		sky_txt = "Night photo" if sky_photo_mat != null else "Night photo (not available)"
	set_btn_text("sky", "Sky: " + sky_txt)
	lbl_sens.text = "Sensitivity %.1f" % sens
	save_settings()


func layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var ml := 24.0
	var mr := 24.0
	var mb := 20.0
	var ws := DisplayServer.window_get_size()
	if ws.x > 0:
		var sa := DisplayServer.get_display_safe_area()
		var k := vs.x / float(ws.x)
		ml = clampf(sa.position.x * k + 12.0, 24.0, 90.0)
		mr = clampf((ws.x - sa.end.x) * k + 12.0, 24.0, 90.0)
	var fire: Panel = buttons["fire"]
	fire.position = Vector2(vs.x - mr - 124.0, vs.y - mb - 124.0)
	place("reload", Vector2(vs.x - mr - 124.0 - 96.0, vs.y - mb - 80.0))
	place("crouch", Vector2(vs.x - mr - 124.0 - 96.0, vs.y - mb - 80.0 - 94.0))
	place("light", Vector2(vs.x - mr - 80.0 - 22.0, vs.y - mb - 124.0 - 96.0))
	place("menu", Vector2(vs.x - mr - 110.0, 18.0))
	place("level", Vector2(vs.x - mr - 130.0, 74.0))
	lbl_status.position = Vector2(ml, 18.0)
	lbl_fps.position = Vector2(ml, 50.0)
	lbl_obj.position = Vector2(0.0, 16.0)
	lbl_obj.size = Vector2(vs.x, 34.0)
	arrow.position = Vector2(vs.x * 0.5, 72.0)
	lbl_ammo.position = Vector2(vs.x - mr - 124.0 - 96.0 - 190.0, vs.y - mb - 56.0)
	lbl_ammo.size = Vector2(170.0, 44.0)
	lbl_msg.position = Vector2(vs.x * 0.1, vs.y * 0.22)
	lbl_msg.size = Vector2(vs.x * 0.8, 160.0)
	menu_box.reset_size()
	var ms := menu_box.get_combined_minimum_size()
	menu_box.position = (vs - ms) * 0.5


var groups: Dictionary = {"trees": [], "grass": [], "rocks": [], "terrain": [], "particles": []}
var cur_tag := ""
var testing := false
var skip_laser := false
var script_us := 0
var test_i := 0
var test_t := 0.0
var test_frames := 0
var test_time := 0.0
var test_script := 0.0
var test_lines: Array = []
var lbl_results: Label
const TESTS := ["All on", "No laser aim", "No trees", "No grass", "No rocks", "No terrain", "No shadows", "No fog", "No glow", "No lamps", "No particles", "Simple sky", "No sky", "Half resolution"]


func set_group(id: String, on: bool) -> void:
	for n in groups[id]:
		var nd: Node3D = n
		nd.visible = on


func test_apply(i: int, on: bool) -> void:
	match i:
		1:
			skip_laser = not on
			laser.visible = on
			dot.visible = on
		2:
			set_group("trees", on)
		3:
			set_group("grass", on)
		4:
			set_group("rocks", on)
		5:
			set_group("terrain", on)
		6:
			moon.shadow_enabled = on and quality > 0
		7:
			world_env.fog_enabled = on
		8:
			world_env.glow_enabled = on and quality > 0
		9:
			for fl in flicker:
				var l: OmniLight3D = fl[0]
				l.visible = on
		10:
			set_group("particles", on)
		11:
			if on:
				apply_sky()
			else:
				world_sky.sky_material = sky_simple_mat
		12:
			world_env.background_mode = Environment.BG_SKY if on else Environment.BG_COLOR
			world_env.background_color = Color(0.08, 0.09, 0.12)
		13:
			get_viewport().scaling_3d_scale = res_scale if on else 0.5


func start_test() -> void:
	started = true
	show_menu(false)
	playing = false
	testing = true
	reset_player()
	pitch = 0.06
	test_i = 0
	test_t = 0.0
	test_frames = 0
	test_time = 0.0
	test_script = 0.0
	test_lines = []
	lbl_msg.modulate.a = 1.0


func run_test(delta: float) -> void:
	player.rotation = Vector3.ZERO
	cam.position = Vector3(0.0, 1.65, 0.0)
	cam.rotation = Vector3(pitch, 0.0, 0.0)
	update_effects(delta)
	if not skip_laser:
		update_laser()
	update_hud()
	test_t += delta
	if test_t > 0.7:
		test_frames += 1
		test_time += delta
		test_script += script_us
	lbl_msg.text = "Speed test %d / %d\n%s" % [test_i + 1, TESTS.size(), TESTS[test_i]]
	msg_t = 2.0
	if test_t > 2.3:
		var fps := test_frames / maxf(0.001, test_time)
		var sms := test_script / maxf(1.0, float(test_frames)) / 1000.0
		test_lines.append("%s: %.0f fps (script %.1f ms)" % [TESTS[test_i], fps, sms])
		test_apply(test_i, true)
		test_i += 1
		test_t = 0.0
		test_frames = 0
		test_time = 0.0
		test_script = 0.0
		if test_i >= TESTS.size():
			testing = false
			lbl_msg.text = ""
			var half := int(ceil(test_lines.size() / 2.0))
			var txt := "Speed test (screenshot this):"
			for r in half:
				var row: String = test_lines[r]
				if r + half < test_lines.size():
					row += "      " + str(test_lines[r + half])
				txt += "\n" + row
			lbl_results.text = txt
			print(txt)
			show_menu(true)
			layout()
			return
		test_apply(test_i, false)


func show_menu(v: bool) -> void:
	menu.visible = v
	hud.visible = not v
	playing = (not v) and started
	joy_id = -1
	look_id = -1
	joy_vec = Vector2.ZERO
	joy_base.visible = false
	joy_knob.visible = false
	refresh_menu()


func start_game() -> void:
	started = true
	show_menu(false)
	show_msg("Reach the bell tower", 3.0)


func show_msg(t: String, dur: float) -> void:
	lbl_msg.text = t
	lbl_msg.modulate.a = 1.0
	msg_t = dur


func apply_quality() -> void:
	var vp := get_viewport()
	var f := 1.0
	vp.msaa_3d = Viewport.MSAA_DISABLED
	if quality == 0:
		res_scale = 0.6
		moon.shadow_enabled = false
		torch.shadow_enabled = false
		world_env.glow_enabled = false
		f = 0.6
	elif quality == 1:
		res_scale = 0.75
		moon.shadow_enabled = true
		torch.shadow_enabled = false
		world_env.glow_enabled = true
		f = 0.8
	else:
		res_scale = 0.9
		moon.shadow_enabled = true
		torch.shadow_enabled = true
		world_env.glow_enabled = true
		f = 1.0
	vp.scaling_3d_scale = res_scale
	for rg in ranged:
		var gi: GeometryInstance3D = rg[0]
		gi.visibility_range_end = float(rg[1]) * f
	for h in heavy:
		var g2: GeometryInstance3D = h
		if quality == 2:
			g2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		else:
			g2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


var terrain_mi: MeshInstance3D
var terrain_simple: ShaderMaterial
var aim_cache: Dictionary = {}
var aim_frame := 0
var fix_level := 0
var fixes_done: Array = []
var last_fps := 60.0
const FIX_NAMES := ["Shadows off", "Glow off", "Far trees hidden", "Grass reduced", "Simpler ground", "Height fog off", "Fireflies and fire off", "Sky off"]


func apply_fix(i: int) -> void:
	match i:
		0:
			moon.shadow_enabled = false
			torch.shadow_enabled = false
		1:
			world_env.glow_enabled = false
		2:
			for n in groups["trees"]:
				var g: GeometryInstance3D = n
				g.visibility_range_end = 35.0
		3:
			for n in groups["grass"]:
				var g: GeometryInstance3D = n
				g.visibility_range_end = 16.0
		4:
			terrain_mi.material_override = terrain_simple
		5:
			world_env.fog_height_density = 0.0
		6:
			set_group("particles", false)
		7:
			world_env.background_mode = Environment.BG_COLOR
			world_env.background_color = Color(0.08, 0.09, 0.12)


func adapt_resolution(delta: float) -> void:
	if not auto_res:
		return
	fps_acc += delta
	fps_frames += 1
	if fps_acc < 1.5:
		return
	var fps := fps_frames / fps_acc
	last_fps = fps
	if fps < 25.0 and fix_level < FIX_NAMES.size():
		slow_time += fps_acc
		if slow_time > 2.5:
			apply_fix(fix_level)
			fixes_done.append("%s (was %d fps)" % [FIX_NAMES[fix_level], int(fps)])
			show_msg("Speed fix: " + str(FIX_NAMES[fix_level]), 2.0)
			fix_level += 1
			slow_time = 0.0
	else:
		slow_time = 0.0
	fps_acc = 0.0
	fps_frames = 0
	var tops: Array = [0.7, 0.85, 1.0]
	var top: float = tops[quality]
	if fps < 28.0 and res_scale > 0.7:
		res_scale = maxf(0.7, res_scale - 0.05)
	elif fps > 50.0 and res_scale < top:
		res_scale = minf(top, res_scale + 0.05)
	get_viewport().scaling_3d_scale = res_scale


func load_settings() -> void:
	if cfg.load("user://settings.cfg") == OK and int(cfg.get_value("s", "v", 0)) >= 2:
		sens = cfg.get_value("s", "sens", 1.0)
		inv_x = cfg.get_value("s", "inv_x", false)
		inv_y = cfg.get_value("s", "inv_y", false)
		swap_axes = cfg.get_value("s", "swap", false)
		use_gyro = cfg.get_value("s", "gyro", true)
		quality = cfg.get_value("s", "quality", 1)
		sky_photo = cfg.get_value("s", "sky", true)


func save_settings() -> void:
	cfg.set_value("s", "sens", sens)
	cfg.set_value("s", "inv_x", inv_x)
	cfg.set_value("s", "inv_y", inv_y)
	cfg.set_value("s", "swap", swap_axes)
	cfg.set_value("s", "gyro", use_gyro)
	cfg.set_value("s", "quality", quality)
	cfg.set_value("s", "v", 2)
	cfg.set_value("s", "sky", sky_photo)
	cfg.save("user://settings.cfg")


# =====================================================================
# input
func button_at(pos: Vector2) -> String:
	for id in buttons:
		var c: Control = buttons[id]
		if c.visible and c.get_global_rect().grow(10.0).has_point(pos):
			return id
	return ""


func press_button(id: String) -> void:
	match id:
		"fire":
			fire()
		"reload":
			start_reload()
		"crouch":
			set_crouch(not crouching)
		"light":
			toggle_torch()
		"menu":
			show_menu(true)
		"level":
			pitch = 0.0


func _input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			var b := button_at(e.position)
			if b != "":
				press_button(b)
				return
			var vs := get_viewport().get_visible_rect().size
			if e.position.x < vs.x * 0.42 and joy_id == -1:
				joy_id = e.index
				joy_origin = e.position
				joy_base.position = e.position - joy_base.size * 0.5
				joy_knob.position = e.position - joy_knob.size * 0.5
				joy_base.visible = true
				joy_knob.visible = true
			elif look_id == -1:
				look_id = e.index
		else:
			if e.index == joy_id:
				joy_id = -1
				joy_vec = Vector2.ZERO
				joy_base.visible = false
				joy_knob.visible = false
			if e.index == look_id:
				look_id = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == joy_id:
			var v := (d.position - joy_origin).limit_length(70.0)
			joy_vec = v / 70.0
			joy_knob.position = joy_origin + v - joy_knob.size * 0.5
		elif d.index == look_id:
			player.rotation.y -= d.relative.x * 0.0045 * sens
			pitch -= d.relative.y * 0.0045 * sens
	elif event is InputEventMouseMotion and not DisplayServer.is_touchscreen_available():
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var mm := event as InputEventMouseMotion
			player.rotation.y -= mm.relative.x * 0.004 * sens
			pitch -= mm.relative.y * 0.004 * sens
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			match k.physical_keycode:
				KEY_SPACE:
					fire()
				KEY_R:
					start_reload()
				KEY_C:
					set_crouch(not crouching)
				KEY_L:
					toggle_torch()
				KEY_ESCAPE:
					show_menu(true)


func set_crouch(v: bool) -> void:
	crouching = v
	set_btn_on("crouch", v)


func toggle_torch() -> void:
	torch_on = not torch_on
	torch.light_energy = 3.0 if torch_on else 0.0
	set_btn_on("light", torch_on)
	play_sfx("click", -8.0, 0.8)


# =====================================================================
# shooting
func ray_box(o: Vector3, d: Vector3, ob: Dictionary) -> float:
	var mn: Vector2 = ob["min"]
	var mx: Vector2 = ob["max"]
	var bmin := Vector3(mn.x, ob["base"], mn.y)
	var bmax := Vector3(mx.x, ob["top"], mx.y)
	var tmin := 0.0
	var tmax := 1e9
	for i in 3:
		if absf(d[i]) < 1e-9:
			if o[i] < bmin[i] or o[i] > bmax[i]:
				return 1e9
			continue
		var t1: float = (bmin[i] - o[i]) / d[i]
		var t2: float = (bmax[i] - o[i]) / d[i]
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return 1e9
	return tmin


func aim() -> Dictionary:
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var best := 90.0
	var t := 0.5
	while t < best:
		var p := o + d * t
		if p.y < height_at(p.x, p.z):
			best = maxf(0.3, t - 0.2)
			break
		t += 0.5 if t < 15.0 else 1.2
	for ob in obstacles:
		var bt := ray_box(o, d, ob)
		if bt < best:
			best = bt
	var hd2 := d.x * d.x + d.z * d.z
	if hd2 > 1e-6:
		for tc in tree_col:
			var tv: Vector3 = tc
			var proj := ((tv.x - o.x) * d.x + (tv.y - o.z) * d.z) / hd2
			if proj < 0.0 or proj > best:
				continue
			var px := o.x + d.x * proj
			var pz := o.z + d.z * proj
			if Vector2(px - tv.x, pz - tv.y).length() < tv.z:
				var py := o.y + d.y * proj
				if py < height_at(tv.x, tv.y) + 4.0:
					best = proj
	return {"point": o + d * best, "dist": best, "sky": best >= 89.0}


func fire() -> void:
	if fire_cd > 0.0 or reloading > 0.0:
		return
	if clip <= 0:
		if reserve > 0:
			start_reload()
		else:
			play_sfx("click")
			show_msg("Out of ammo", 1.5)
		fire_cd = 0.3
		return
	clip -= 1
	fire_cd = 0.26
	recoil = 0.05
	play_sfx("shot", 0.0, randf_range(0.95, 1.05))
	Input.vibrate_handheld(30)
	muzzle_light.light_energy = 4.0
	muzzle_flash.visible = true
	flash_t = 0.05
	var h := aim()
	if not h["sky"]:
		var p: CPUParticles3D = impacts[impact_i % impacts.size()]
		impact_i += 1
		p.global_position = h["point"]
		p.restart()
	if clip == 0 and reserve > 0:
		start_reload()


func start_reload() -> void:
	if reloading > 0.0 or clip >= 12 or reserve <= 0:
		return
	reloading = 1.4
	play_sfx("reload", -4.0)


# =====================================================================
# per-frame
func collide(x: float, z: float, r: float) -> Vector2:
	for o in obstacles:
		var mn: Vector2 = o["min"]
		var mx: Vector2 = o["max"]
		var cx := clampf(x, mn.x, mx.x)
		var cz := clampf(z, mn.y, mx.y)
		var dx := x - cx
		var dz := z - cz
		var d2 := dx * dx + dz * dz
		if d2 < r * r:
			if d2 > 1e-8:
				var d := sqrt(d2)
				x = cx + dx / d * r
				z = cz + dz / d * r
			else:
				var pens := [x - mn.x, mx.x - x, z - mn.y, mx.y - z]
				var k := pens.find(pens.min())
				if k == 0:
					x = mn.x - r
				elif k == 1:
					x = mx.x + r
				elif k == 2:
					z = mn.y - r
				else:
					z = mx.y + r
	for tc in tree_col:
		var tv: Vector3 = tc
		var dx := x - tv.x
		var dz := z - tv.y
		var rr := r + tv.z
		var d2 := dx * dx + dz * dz
		if d2 < rr * rr and d2 > 1e-8:
			var d := sqrt(d2)
			x = tv.x + dx / d * rr
			z = tv.y + dz / d * rr
	z = clampf(z, -330.0, 28.0)
	var px := path_x(z)
	x = clampf(x, px - 40.0, px + 40.0)
	return Vector2(x, z)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if testing:
		run_test(delta)
	else:
		_frame(delta)
	script_us = Time.get_ticks_usec() - t0


func _frame(delta: float) -> void:
	gyro_now = Input.get_gyroscope()
	if gyro_now.length_squared() > 1e-7:
		gyro_seen = true
	if menu.visible:
		var g := "Gyroscope   x %.2f   y %.2f   z %.2f" % [gyro_now.x, gyro_now.y, gyro_now.z]
		if gyro_seen:
			g += "\nTurn left and right: one number should jump. If the view turns the wrong way in game, switch Invert or Swap."
		else:
			g += "\nNo data yet. Move the phone. If it stays at 0.00 your phone has no gyroscope; use touch drag."
		g += "\nScanned models: %d loaded, %d skipped (too heavy for a phone)" % [models_ok, models_skipped]
		lbl_gyro.text = g
		if not started:
			player.rotation.y = sin(Time.get_ticks_msec() * 0.0001) * 0.45
	if playing:
		update_player(delta)
	update_effects(delta)
	if playing:
		if not skip_laser:
			update_laser()
		update_hud()
		adapt_resolution(delta)
	laser.visible = playing
	dot.visible = dot.visible and playing
	gun.visible = started


func update_player(delta: float) -> void:
	if use_gyro:
		var yr: float = gyro_now.x if swap_axes else gyro_now.y
		var pr: float = gyro_now.y if swap_axes else gyro_now.x
		if absf(yr) < 0.008:
			yr = 0.0
		if absf(pr) < 0.008:
			pr = 0.0
		player.rotation.y += yr * delta * sens * (-1.0 if inv_x else 1.0)
		pitch += pr * delta * sens * (-1.0 if inv_y else 1.0)
	if Input.is_physical_key_pressed(KEY_LEFT):
		player.rotation.y += delta * 1.8
	if Input.is_physical_key_pressed(KEY_RIGHT):
		player.rotation.y -= delta * 1.8
	pitch = clampf(pitch, -1.25, 1.25)

	var fwd := -joy_vec.y
	var strafe := joy_vec.x
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		fwd += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		fwd -= 1.0
	if Input.is_physical_key_pressed(KEY_A):
		strafe -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		strafe += 1.0
	var mv2 := Vector2(strafe, fwd)
	if mv2.length() > 1.0:
		mv2 = mv2.normalized()
	var sprint := (joy_vec.length() > 0.92 or Input.is_physical_key_pressed(KEY_SHIFT)) and mv2.y > 0.3
	if sprint and crouching:
		set_crouch(false)
	var spd := 2.7
	if crouching:
		spd = 1.5
	elif sprint:
		spd = 5.0
	var yaw := player.rotation.y
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var rt := Vector3(cos(yaw), 0.0, -sin(yaw))
	var mv := (f * mv2.y + rt * mv2.x) * spd * delta
	var old := Vector2(player.position.x, player.position.z)
	var np := collide(old.x + mv.x, old.y + mv.z, 0.35)
	var moved := np.distance_to(old)
	player.position = Vector3(np.x, height_at(np.x, np.y), np.y)
	step_d += moved
	if step_d > (1.3 if sprint else 0.85):
		step_d = 0.0
		play_sfx("step", -16.0 if crouching else -7.0, randf_range(0.85, 1.15))
	bob += moved * (5.5 if sprint else 6.5)
	eye = lerpf(eye, 0.95 if crouching else 1.65, minf(1.0, delta * 8.0))
	var amp := 0.5 if crouching else 1.0
	cam.position = Vector3(cos(bob * 0.5) * 0.025 * amp, eye + sin(bob) * 0.04 * amp, 0.0)
	cam.rotation = Vector3(pitch + recoil, 0.0, 0.0)
	var rl := reloading > 0.0
	gun.position = gun_base + Vector3(cos(bob * 0.5) * 0.006, sin(bob) * 0.005 - (0.12 if rl else 0.0), recoil * 1.5)
	gun.rotation.x = -0.6 if rl else recoil * 2.0

	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			var n := mini(12 - clip, reserve)
			clip += n
			reserve -= n
	if not finished:
		var door := Vector2(tower_pos.x, tower_pos.z + 3.0)
		if Vector2(player.position.x, player.position.z).distance_to(door) < 5.0:
			finished = true
			play_sfx("bell", 2.0)
			Input.vibrate_handheld(400)
			show_msg("You reached the bell tower.\nStage 1 complete. Zombies arrive in the next update.", 8.0)


func update_effects(delta: float) -> void:
	if fire_cd > 0.0:
		fire_cd -= delta
	recoil *= pow(0.0004, delta)
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			muzzle_light.light_energy = 0.0
			muzzle_flash.visible = false
	for fl in flicker:
		var l: OmniLight3D = fl[0]
		var base: float = fl[1]
		if fl[2]:
			l.light_energy = base * (0.8 + sin(Time.get_ticks_msec() * 0.013) * 0.12 + randf() * 0.15)
		else:
			l.light_energy = base * (0.96 + randf() * 0.04)
	if msg_t > 0.0:
		msg_t -= delta
		if msg_t < 1.0:
			lbl_msg.modulate.a = maxf(0.0, msg_t)


func update_laser() -> void:
	aim_frame += 1
	if aim_cache.is_empty() or aim_frame % 2 == 0:
		aim_cache = aim()
	var h: Dictionary = aim_cache
	var a := laser_origin.global_position
	var b: Vector3 = h["point"]
	laser_mesh.clear_surfaces()
	laser_mesh.surface_begin(Mesh.PRIMITIVE_LINES, laser_mat)
	laser_mesh.surface_add_vertex(a)
	laser_mesh.surface_add_vertex(b)
	laser_mesh.surface_end()
	dot.global_position = b - (b - cam.global_position).normalized() * 0.03
	var ds: float = 0.6 + float(h["dist"]) * 0.12
	dot.scale = Vector3(ds, ds, ds)
	dot.visible = not h["sky"]


func update_hud() -> void:
	var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var cpu_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var info := "%d fps   %.1fM tris   %d draws   engine %.0f ms   script %.1f ms   res %d%%" % [Engine.get_frames_per_second(), tris, draws, cpu_ms, script_us / 1000.0, int(res_scale * 100.0)]
	if not fixes_done.is_empty():
		info += "\nSpeed fixes: " + ", ".join(PackedStringArray(fixes_done))
	lbl_fps.text = info
	var ammo := "%d / %d" % [clip, reserve]
	if reloading > 0.0:
		ammo = "Reloading"
	lbl_ammo.text = ammo
	var dx := tower_pos.x - player.position.x
	var dz := tower_pos.z - player.position.z
	lbl_obj.text = "Bell tower  %d m" % int(Vector2(dx, dz).length())
	var target := atan2(-dx, -dz)
	var rel := wrapf(target - player.rotation.y, -PI, PI)
	arrow.rotation = -rel
	var st := ""
	if use_gyro:
		st = "Gyro aim on" if gyro_seen else "Gyro: no sensor data, drag to look"
	else:
		st = "Touch aim"
	if crouching:
		st += "   Crouched"
	lbl_status.text = st
