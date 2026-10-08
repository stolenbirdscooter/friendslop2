shader_type spatial;
// Grass clumps (MultiMesh). Opaque, double-sided, no ink lines (roughness tag 0).
render_mode cull_disabled;

uniform vec4 base_color : source_color = vec4(0.36, 0.48, 0.24, 1.0);
uniform float wind_strength = 0.25;
uniform float bend_radius = 2.2;
uniform vec3 pusher0 = vec3(0.0, -999.0, 0.0);
uniform vec3 pusher1 = vec3(0.0, -999.0, 0.0);
uniform float push_radius = 6.0;

varying float tipness;
varying vec3 inst_col;

void vertex() {
	tipness = clamp(VERTEX.y / 0.9, 0.0, 1.0);
	inst_col = INSTANCE_CUSTOM.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.6 + wp.x * 0.21 + wp.z * 0.17;
	float gust = sin(TIME * 0.4 + wp.x * 0.02) * 0.5 + 0.5;
	float sway = (sin(t) * 0.6 + sin(t * 2.3) * 0.2) * wind_strength * (0.5 + gust);
	vec3 off = vec3(sway, 0.0, sway * 0.4) * tipness * tipness;
	// flatten under big feet / bodies
	vec3 d0 = wp - pusher0; d0.y = 0.0;
	float k0 = (1.0 - smoothstep(push_radius * 0.5, push_radius, length(d0))) * (1.0 - smoothstep(1.5, 3.0, abs(wp.y - pusher0.y)));
	vec3 d1 = wp - pusher1; d1.y = 0.0;
	float k1 = (1.0 - smoothstep(0.6, 1.4, length(d1))) * (1.0 - smoothstep(0.8, 1.6, abs(wp.y - pusher1.y)));
	off.xz += normalize(d0.xz + 0.001) * k0 * tipness * 0.8 + normalize(d1.xz + 0.001) * k1 * tipness * 0.7;
	off.y -= (k0 + k1) * tipness * 0.4;
	vec4 local_off = inverse(MODEL_MATRIX) * vec4(off, 0.0);
	VERTEX += local_off.xyz;
}

void fragment() {
	vec3 c = mix(base_color.rgb * 0.62, inst_col, smoothstep(0.0, 1.0, tipness));
	ALBEDO = c;
	ROUGHNESS = 0.0;
	SPECULAR = 0.0;
	BACKLIGHT = vec3(0.2);
}

void light() {
	float ndl = abs(dot(NORMAL, LIGHT)) * 0.5 + 0.5;
	float lit = smoothstep(0.35, 0.55, ATTENUATION) * smoothstep(0.2, 0.4, ndl);
	DIFFUSE_LIGHT += LIGHT_COLOR * lit * 0.32;
}
