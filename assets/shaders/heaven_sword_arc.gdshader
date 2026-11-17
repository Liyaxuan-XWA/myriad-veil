shader_type canvas_item;
render_mode blend_add;
// 巨剑劈落的扇形残光：从竖直向上（0°）扫到当前角度 head_angle，越靠后越淡。
// 本地 UV 以画布中心为剑柄，r=1 是剑尖扫过的轨迹半径；角度以「向上」为 0，顺时针为正。

uniform float head_angle = 0.0;
uniform float tail_span = 1.15;
uniform float alpha : hint_range(0.0, 2.0) = 0.45;
uniform float inner : hint_range(0.0, 0.95) = 0.42;
uniform vec4 tint : source_color = vec4(1.0, 0.70, 0.16, 1.0);

void fragment() {
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float ang = atan(d.x, -d.y);
	float sgn = sign(head_angle + 0.0001);
	float swept = (head_angle - ang) * sgn;   // > 0 = 已经扫过
	float from_start = ang * sgn;             // > 0 = 已在起始角之外
	if (swept < 0.0 || from_start < 0.0) {
		COLOR = vec4(0.0);
	} else {
		float fade = 1.0 - smoothstep(tail_span * 0.35, tail_span, swept);
		float band = smoothstep(inner - 0.05, inner + 0.05, r)
			* (1.0 - smoothstep(0.93, 1.0, r));
		float lead = exp(-pow(swept / 0.06, 2.0)) * band * 0.8;
		// 能量流动：沿弧向的亮带 + 径向涟漪；head_angle 停下后仍继续流
		float flow = 0.5 + 0.5 * sin(swept * 24.0 - TIME * 3.2 + r * 8.0);
		float ripple = 0.5 + 0.5 * sin(r * 34.0 - TIME * 2.4);
		float vein = exp(-pow((r - 0.80) / 0.035, 2.0)) * fade * (0.18 + 0.22 * flow);
		float pulse = 0.85 + 0.15 * sin(TIME * 4.0);
		float a = (band * 0.55 * fade * (0.82 + 0.18 * flow) * (0.92 + 0.08 * ripple)
			+ lead * pulse + vein * band) * alpha;
		vec3 col = mix(tint.rgb, vec3(1.0, 0.95, 0.70), lead);
		col = mix(col, vec3(1.0, 0.86, 0.45), (0.35 + 0.65 * flow) * 0.35);
		COLOR = vec4(col, a);
	}
}
