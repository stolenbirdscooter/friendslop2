shader_type spatial;
// Opaque toon water: flat colour with drifting printed ripple lines.
// (Opaque on purpose: the post pass reads the screen before transparents.)

uniform vec3 deep : source_color = vec3(0.30, 0.55, 0.60);
uniform vec3 lines : source_color = vec3(0.80, 0.90, 0.86);
uniform float line_scale = 0.11;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz * line_scale;
	float n = noise(p * 0.5 + TIME * 0.05) * 2.0 + noise(p * 1.3 - TIME * 0.08);
	float band = abs(fract(n * 1.5) - 0.5);
	float l = 1.0 - smoothstep(0.012, 0.03, band);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	l *= 1.0 - smoothstep(25.0, 90.0, dist);
	l *= step(0.45, noise(p * 0.25 + 3.0));
	ALBEDO = mix(deep, lines, l * 0.5);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float lit = smoothstep(0.35, 0.55, ATTENUATION);
	DIFFUSE_LIGHT += LIGHT_COLOR * (0.55 + 0.45 * lit) * 0.32;
	vec3 h = normalize(LIGHT + VIEW);
	float s = pow(max(dot(NORMAL, h), 0.0), 220.0);
	SPECULAR_LIGHT += LIGHT_COLOR * step(0.5, s) * lit * 0.3;
}
