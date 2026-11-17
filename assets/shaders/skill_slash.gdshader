shader_type canvas_item;
render_mode blend_add;

// 玩家技能的高质量月牙/爪痕刀光。
// 不用任何 Line2D / draw_polyline：整片光刃由极坐标 + fbm 噪声在 shader 内生成，
// 有体积、有碎裂边缘、有前缘高光，能按 progress 从左到右扫出。
// 参数由 scripts/visual/skill_fx.gd 根据 ArtDB.SKILL_FX 注入。

uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float arc_half : hint_range(0.08, 3.15) = 1.0;
uniform float inner : hint_range(0.0, 0.98) = 0.68;
uniform float outer : hint_range(0.55, 1.15) = 1.0;
uniform vec3 core_color : source_color = vec3(1.0, 0.93, 0.76);
uniform vec3 glow_color : source_color = vec3(1.0, 0.42, 0.10);
uniform float noise_amount : hint_range(0.0, 1.0) = 0.5;
uniform float seed = 0.0;
uniform float heat : hint_range(0.0, 1.0) = 0.35;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

float fbm2(vec2 p) {
	float v = vnoise(p) * 0.62;
	v += vnoise(p * 2.07 + vec2(17.3, 9.1)) * 0.38;
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float u = (ang + arc_half) / (2.0 * arc_half);
	if (u < 0.0 || u > 1.0) {
		COLOR = vec4(0.0);
	} else {
		float head = clamp(progress, 0.0, 1.0);
		// 扫过的部分保持可见，前缘有一小段柔和高光
		float show = 1.0 - smoothstep(head - 0.045, head + 0.012, u);
		float trail = smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.94, 1.0, u));
		float lead = exp(-pow((u - head) / 0.055, 2.0))
			* (1.0 - smoothstep(head + 0.02, head + 0.08, u));

		float n = fbm2(vec2(u * 7.0 + seed * 3.7, r * 3.4 - TIME * 2.6));
		float n2 = fbm2(vec2(u * 19.0 - seed * 2.1, r * 7.0 + TIME * 1.4));
		float end = abs(u * 2.0 - 1.0);
		float rr = r + (n - 0.5) * 0.10 * noise_amount;
		// 中间厚、两端收尖，才像刀光而不是一截圆环
		float inner_taper = inner + 0.21 * pow(end, 2.6);
		float inner_eff = inner_taper + (n2 - 0.5) * 0.030 * noise_amount;
		float band = smoothstep(inner_eff - 0.035, inner_eff + 0.025, rr)
			* (1.0 - smoothstep(outer - 0.10, outer - 0.005, rr));
		float filaments = smoothstep(0.25, 0.80, n2);
		float body = band * (0.45 + 0.65 * n) * (0.55 + 0.65 * filaments);
		// 细而不断的热边；只在靠近前缘时最亮，避免整条白描边
		float core = exp(-pow((rr - outer * 0.94) / 0.018, 2.0))
			* smoothstep(inner_eff - 0.02, inner_eff + 0.10, rr)
			* (0.35 + 0.65 * smoothstep(0.05, 0.35, u))
			* (0.55 + 0.45 * filaments);
		float glow = exp(-pow((rr - (inner_eff + outer) * 0.48) / 0.20, 2.0)) * 0.40;
		float needle = pow(0.5 + 0.5 * sin(u * 70.0 + n * 10.0), 6.0) * band * 0.16;

		float energy = (body * 0.62 + glow * 0.42 + core * (0.9 + heat * 0.4) + needle) * show * trail;
		energy += lead * band * 0.22 * show;
		energy *= opacity;

		vec3 col = mix(glow_color, core_color, clamp(core * 1.2 + lead * 0.30, 0.0, 1.0));
		col += core_color * core * heat * 0.35;
		col *= 0.92 + 0.08 * sin(TIME * 24.0 + u * 12.0 + seed * 4.0);
		COLOR = vec4(col * energy, 1.0);
	}
}
