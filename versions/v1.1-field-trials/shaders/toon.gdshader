shader_type spatial;
// Mossback toon: two-tone lighting with a painterly, noise-broken terminator.
// Shadow colour comes from the environment ambient (cool violet); lit areas add warm sun.
// ROUGHNESS is used as a material tag read by the post shader:
//   >= 0.5 -> draw ink outlines, < 0.5 -> no outlines (foliage, grass).

uniform vec4 albedo : source_color = vec4(1.0);
uniform float band_softness : hint_range(0.0, 0.5) = 0.05;
uniform float breakup : hint_range(0.0, 1.0) = 0.22;
uniform float breakup_scale = 1.6;
uniform float rim = 0.18;
uniform float outline_tag : hint_range(0.0, 1.0) = 1.0;
uniform float emission_strength = 0.0;
uniform float wind = 0.0;          // vertex sway amount (foliage)
uniform float wind_height = 2.0;   // sway grows with local height
global uniform vec3 gale;          // world-space push from gusts (set by Ambient)

varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
	               mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
	               mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	if (wind > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float h = clamp(VERTEX.y / wind_height, 0.0, 1.5);
		float t = TIME * 1.3 + wp.x * 0.15 + wp.z * 0.11;
		VERTEX.x += sin(t) * wind * h * h;
		VERTEX.z += cos(t * 0.8) * wind * 0.6 * h * h;
		vec3 push = inverse(mat3(MODEL_MATRIX)) * gale;
		VERTEX += push * h * h * (0.75 + 0.25 * sin(t * 3.1));
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = albedo.rgb * COLOR.rgb;
	ROUGHNESS = outline_tag;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	EMISSION = ALBEDO * emission_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float n = (vnoise(world_pos * breakup_scale) + vnoise(world_pos * breakup_scale * 2.7) * 0.5 - 0.75) * breakup;
	float lit = smoothstep(0.0, band_softness + 0.001, ndl + n);
	float shadow = smoothstep(0.35, 0.55, ATTENUATION);
	lit *= shadow;
	DIFFUSE_LIGHT += LIGHT_COLOR * lit * 0.32;
	float r = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	SPECULAR_LIGHT += LIGHT_COLOR * smoothstep(0.45, 0.6, r) * rim * lit * 0.1;
}
