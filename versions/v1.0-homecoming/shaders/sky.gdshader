shader_type sky;
// Flat, graphic sky: banded gradient, a crisp sun disc, and cut-paper clouds
// with a single shadow tone. Colours are driven from script for the day cycle.

uniform vec3 top_color : source_color = vec3(0.56, 0.72, 0.79);
uniform vec3 horizon_color : source_color = vec3(0.95, 0.91, 0.80);
uniform vec3 ground_color : source_color = vec3(0.78, 0.76, 0.64);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.84);
uniform vec3 cloud_color : source_color = vec3(0.99, 0.97, 0.92);
uniform vec3 cloud_shadow : source_color = vec3(0.78, 0.78, 0.86);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.48;
uniform float sun_size = 0.9994;
uniform float stars = 0.0;
uniform vec3 moon_dir = vec3(0.3, 0.6, -0.7);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += noise(p) * a; p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	// stepped gradient: three soft bands read as printed ink layers
	float t = smoothstep(-0.02, 0.55, h);
	t = floor(t * 6.0 + 0.5) / 6.0 * 0.35 + t * 0.65;
	vec3 col = mix(horizon_color, top_color, t);
	col = mix(col, ground_color, smoothstep(0.0, -0.12, h));

	// sun
	vec3 sd = LIGHT0_DIRECTION;
	float sdot = dot(d, sd);
	col += sun_color * pow(max(sdot, 0.0), 24.0) * 0.18;
	col = mix(col, sun_color, smoothstep(sun_size, sun_size + 0.0002, sdot));

	// moon & stars at night
	if (stars > 0.0) {
		float md = dot(d, normalize(moon_dir));
		col = mix(col, vec3(0.95, 0.93, 0.85), smoothstep(0.9992, 0.9994, md) * stars);
		vec2 sp = d.xz / (abs(h) + 0.3) * 120.0;
		float s = step(0.996, hash(floor(sp))) * smoothstep(0.0, 0.2, h);
		col += vec3(s) * stars * 0.8;
	}

	// cut-paper clouds on a virtual plane
	if (h > 0.0) {
		vec2 p = d.xz / (h + 0.12) * 1.4;
		p += vec2(TIME * 0.006, TIME * 0.002);
		float n = fbm(p);
		float n_s = fbm(p + sd.xz * 0.12);
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.006, n);
		float lit = smoothstep(0.0, 0.006, n - n_s + 0.012);
		vec3 cc = mix(cloud_shadow, cloud_color, lit);
		float fade = smoothstep(0.0, 0.18, h);
		col = mix(col, cc, c * fade);
	}
	COLOR = col;
}
