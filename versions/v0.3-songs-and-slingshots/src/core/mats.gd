class_name Mats
## Shared material factory. Vertex colours carry most colour; materials carry style.

static var _toon_shader: Shader = preload("res://shaders/toon.gdshader")
static var _cache := {}

## Standard toon material. albedo tints vertex colours (white = use vertex colour as-is).
static func toon(albedo := Color.WHITE, outline := true, softness := 0.05) -> ShaderMaterial:
	var key := "t%s%s%s" % [albedo.to_html(), outline, softness]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _toon_shader
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("outline_tag", 1.0 if outline else 0.0)
	m.set_shader_parameter("band_softness", softness)
	_cache[key] = m
	return m

## Foliage: swaying, no outline, softer band.
static func foliage(sway := 0.15, height := 3.0) -> ShaderMaterial:
	var key := "f%s%s" % [sway, height]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _toon_shader
	m.set_shader_parameter("outline_tag", 1.0)
	m.set_shader_parameter("band_softness", 0.12)
	m.set_shader_parameter("breakup", 0.45)
	m.set_shader_parameter("wind", sway)
	m.set_shader_parameter("wind_height", height)
	_cache[key] = m
	return m

static func glow(albedo: Color, strength := 1.2) -> ShaderMaterial:
	var key := "g%s%s" % [albedo.to_html(), strength]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _toon_shader
	m.set_shader_parameter("albedo", albedo)
	m.set_shader_parameter("emission_strength", strength)
	_cache[key] = m
	return m

static func mesh_instance(mesh: Mesh, mat: Material = null, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat else toon()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
