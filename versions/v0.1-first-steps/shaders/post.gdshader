shader_type spatial;
// Full-screen "printed field guide" pass: ink outlines from depth + normals,
// paper grain, warm/cool grade and a soft vignette.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform vec3 ink : source_color = vec3(0.165, 0.133, 0.22);
uniform float line_px = 1.5;
uniform float depth_sens = 0.06;
uniform float normal_sens = 0.55;
uniform float line_fade_start = 40.0;
uniform float line_fade_end = 320.0;
uniform float grain = 0.045;
uniform float vignette = 0.28;
uniform vec3 shadow_lift : source_color = vec3(0.17, 0.15, 0.25);
uniform float lift_amount = 0.10;
uniform int debug_mode = 0;
uniform float flash = 0.0;          // white flash for big moments
uniform vec3 flash_color : source_color = vec3(1.0, 0.97, 0.88);

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec4 nr(vec2 uv) {
	vec4 t = texture(normal_tex, uv);
	// alpha holds ROUGHNESS, which our materials use as an "ink me" tag
	return vec4(t.xyz * 2.0 - 1.0, t.w);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = line_px / VIEWPORT_SIZE;
	vec3 col = texture(screen_tex, uv).rgb;

	float dc = lin_depth(uv, INV_PROJECTION_MATRIX);
	vec4 nc = nr(uv);
	float edge = 0.0;
	if (nc.w > 0.45) {
		vec2 offs[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
		float dsum = 0.0;
		float nsum = 0.0;
		for (int i = 0; i < 4; i++) {
			vec2 o = uv + offs[i];
			float d = lin_depth(o, INV_PROJECTION_MATRIX);
			vec4 nn = nr(o);
			// only draw where the neighbour is *behind* -> lines sit on the near object
			dsum += max(d - dc, 0.0) / max(dc, 0.5);
			nsum += (1.0 - clamp(dot(nc.xyz, nn.xyz), 0.0, 1.0)) * step(0.45, nn.w);
		}
		float de = smoothstep(depth_sens, depth_sens * 2.0, dsum);
		float ne = smoothstep(normal_sens, normal_sens + 0.4, nsum);
		edge = max(de, ne);
		float fade = 1.0 - smoothstep(line_fade_start, line_fade_end, dc);
		edge *= fade;
	}
	// a little tooth to the line, like a nib on paper
	float tooth = hash12(floor(FRAGCOORD.xy * 0.5));
	edge *= 0.8 + 0.2 * tooth;
	col = mix(col, ink, clamp(edge, 0.0, 1.0) * 0.92);

	// grade: lift shadows toward ink-violet, keep highlights warm
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, col + shadow_lift * (1.0 - lum), lift_amount);
	// paper grain (static, like printed stock)
	float g = hash12(FRAGCOORD.xy) - 0.5;
	float g2 = hash12(floor(FRAGCOORD.xy / 3.0) + 17.0) - 0.5;
	col += (g * 0.6 + g2 * 0.4) * grain;
	// vignette
	vec2 vc = uv - 0.5;
	col *= 1.0 - dot(vc, vc) * vignette;
	col = mix(col, flash_color, flash);
	ALBEDO = col;
	if (debug_mode == 1) { ALBEDO = vec3(edge); }
	if (debug_mode == 2) { ALBEDO = nc.xyz * 0.5 + 0.5; }
	if (debug_mode == 3) { ALBEDO = vec3(nc.w); }
	if (debug_mode == 5) { ALBEDO = vec3(texture(normal_tex, uv).w); }
	if (debug_mode == 9) { ALBEDO = vec3(1.0, 0.0, 0.0); }
	if (debug_mode == 4) { ALBEDO = vec3(fract(dc / 20.0)); }
}
