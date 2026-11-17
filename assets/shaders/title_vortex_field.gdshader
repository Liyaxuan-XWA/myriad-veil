shader_type canvas_item;
render_mode blend_add;

// 开始界面大漩涡的程序化能量场：
// 用极坐标扭曲 + 两层 fbm 噪声生成旋转的星云丝缕，而不是几何线条。
// 不依赖贴图，Sprite2D 只提供四边形与 UV。

uniform float intensity : hint_range(0.0, 2.5) = 0.0;
uniform float spin : hint_range(0.0, 3.0) = 0.7;
uniform float core_boost : hint_range(0.0, 2.0) = 0.0;
uniform vec3 deep_color : source_color = vec3(0.01, 0.05, 0.20);
uniform vec3 mid_color : source_color = vec3(0.05, 0.30, 0.82);
uniform vec3 hot_color : source_color = vec3(0.40, 0.84, 1.0);

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += vnoise(p) * a;
		p = p * 2.07 + vec2(13.7, 27.1);
		a *= 0.5;
	}
	return v / 0.875;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float radial = smoothstep(1.0, 0.28, r) * smoothstep(0.01, 0.16, r);
	float ang = atan(p.y, p.x);

	// 第一层：大尺度旋臂
	float spiral = ang + TIME * spin + r * 5.4;
	vec2 q1 = vec2(cos(spiral), sin(spiral)) * (0.55 + r * 2.15);
	float n1 = fbm(q1 * 2.0 + vec2(TIME * 0.04, -TIME * 0.10));

	// 第二层：更细、更快的内圈星尘
	float spiral2 = ang * 2.0 - TIME * spin * 0.62 + r * 9.5;
	vec2 q2 = vec2(cos(spiral2), sin(spiral2)) * (0.9 + r * 4.2);
	float n2 = fbm(q2 * 1.7 + vec2(-TIME * 0.13, TIME * 0.06));

	float wisps = pow(clamp(n1 * 1.22, 0.0, 1.0), 3.2) * 0.85;
	wisps += pow(clamp(n2, 0.0, 1.0), 5.0) * 0.42;

	// 柔和的能量带（不是硬边圆环）
	float band_t = (r - 0.66) / 0.16;
	float band = exp(-band_t * band_t);
	float spokes = pow(0.5 + 0.5 * sin(ang * 10.0 + TIME * 0.32 + n2 * 2.4), 8.0);
	float stream = wisps + band * 0.12
		+ spokes * 0.05 * smoothstep(0.88, 0.24, r) * (1.0 - smoothstep(0.22, 0.06, r));
	float energy = clamp(stream * radial, 0.0, 1.0);

	// 中心核光：只留一点，主要亮度交给漩涡中心与独立柔光层
	float core = exp(-r * r * 120.0) * (0.88 + 0.12 * sin(TIME * 7.0));
	vec3 col = mix(deep_color, mid_color, smoothstep(0.02, 0.60, energy));
	col = mix(col, hot_color, smoothstep(0.50, 1.0, energy));
	col += hot_color * core * (0.32 + core_boost);

	float amount = clamp(energy * 0.85 + core * 0.30, 0.0, 1.15);
	COLOR = vec4(col * amount * intensity, 1.0);
}
