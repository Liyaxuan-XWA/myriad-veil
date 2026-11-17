shader_type canvas_item;
render_mode blend_mix, unshaded;

// 纸本水墨卡：纸面/墨迹保持原图；单卡打开时按 reveal 顺序从主笔触向外渗开。
// 鼠标快速晃动触发墨环：真实扰动卡面取样坐标，画面内容随波前弯折；倾斜只给墨缘一点湿影。
uniform vec2 card_px = vec2(300.0, 450.0);
uniform float corner_px = 14.0;
uniform sampler2D reveal_tex : filter_linear, repeat_disable;
uniform sampler2D flow_tex : filter_linear, repeat_disable;
uniform sampler2D guard_tex : filter_linear, repeat_disable;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform vec2 art_px = vec2(640.0, 960.0);
uniform float flow_strength : hint_range(0.0, 2.0) = 1.0;
uniform float flow_speed = 0.6;
uniform vec2 tilt = vec2(0.0);
uniform vec2 ripple_center = vec2(0.5);
uniform float ripple_age = 99.0;
uniform float ripple_strength = 0.0;
uniform vec4 paper_color : source_color = vec4(0.93, 0.91, 0.86, 1.0);

vec3 srgb_encode(vec3 c) {
	vec3 lo = c * 12.92;
	vec3 hi = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(hi, lo, step(c, vec3(0.0031308)));
}

float card_mask(vec2 uv) {
	vec2 half_px = card_px * 0.5;
	vec2 d = abs(uv * card_px - half_px) - (half_px - vec2(corner_px));
	float dist = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - corner_px;
	return 1.0 - smoothstep(-1.2, 0.8, dist);
}

// 纸 / 墨 / 落墨状态 → 最终颜色；取样在 fragment 里做（TEXTURE 内置变量只在 fragment 可用）
vec3 paper_tone(vec4 c, float order) {
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float ink = 1.0 - smoothstep(0.55, 0.90, lum);
	float shown = smoothstep(order - 0.01, order + 0.06, reveal);
	// 从种子向外渗开：未到的地方仍是纸，到了才显出墨
	vec3 col = mix(paper_color.rgb, c.rgb, mix(0.03, 1.0, shown));
	float front = exp(-pow((order - reveal) / 0.03, 2.0)) * ink;
	front *= 1.0 - smoothstep(0.96, 1.0, reveal);
	col *= 1.0 - front * 0.12;
	return col;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	// 墨环/倾斜也吃浅墨和被笔触带过的白毛，但不碰纸面
	float wet_ink = 1.0 - smoothstep(0.64, 0.94, lum);
	vec3 col = paper_tone(c, texture(reveal_tex, UV).r);

	// 常驻水墨流转：沿笔势做笔触内部的慢速游移；纸面与保护区（眼/牙/耳/爪）不动
	vec4 fl = texture(flow_tex, UV);
	vec2 fdir = fl.rg * 2.0 - 1.0;
	float dl = length(fdir);
	fdir = dl > 0.001 ? fdir / dl : vec2(0.0, 1.0);
	float guard = smoothstep(0.06, 0.80, texture(guard_tex, UV).r);
	float ink_mask = 1.0 - smoothstep(0.56, 0.93, lum);
	ink_mask = smoothstep(0.06, 0.38, ink_mask);
	float flow_amt = ink_mask * fl.a * (1.0 - guard * 0.97) * flow_strength;
	float fph = fl.b * 6.2831853 + TIME * flow_speed;
	float fw1 = sin(fph);
	float fw2 = sin(fph * 2.0 + fl.b * 9.0);
	vec2 fperp = vec2(-fdir.y, fdir.x);
	vec2 foff = fdir * (36.0 / art_px) * (fw1 + 0.28 * fw2) * flow_amt;
	foff += fperp * (6.0 / art_px) * cos(fph * 2.0 + fl.b * 5.0) * flow_amt;

	// 鼠标快速晃动：一圈水波从光标向外扩，取样坐标沿径向被推 / 拉
	vec2 rv = UV - ripple_center;
	vec2 rdir = normalize(rv + vec2(0.0001));
	float dist = length(vec2(rv.x * 0.6667, rv.y));
	float radius = 0.02 + ripple_age * 0.27;
	float life = ripple_strength * exp(-ripple_age * 1.6);
	float band = exp(-pow((dist - radius) / 0.075, 2.0));
	float slope = ((dist - radius) / 0.075) * band;
	vec2 wuv = clamp(UV + foff + rdir * (slope * life * 0.035), vec2(0.0), vec2(1.0));
	col = paper_tone(texture(TEXTURE, wuv) * COLOR, texture(reveal_tex, wuv).r);
	// 墨色呼吸 + 一层缓慢掠过笔触的湿光，纸面权重为 0
	float breathe = 0.5 + 0.5 * sin(fph * 1.6 + fl.b * 11.0);
	col *= 1.0 + (breathe - 0.5) * 0.10 * flow_amt;
	float sheen = sin(fph * 0.75 - dot(UV, vec2(7.0, 3.5)) + fl.b * 5.0);
	col *= 1.0 + sheen * 0.05 * flow_amt;
	// 波前湿痕：墨上略深，纸面几乎不动
	col = mix(col, vec3(0.07), clamp(band * life * wet_ink * 0.16, 0.0, 0.15));

	// 卡面倾斜：只让墨缘朝倾斜侧多一层湿影，纸面不整体位移
	float edge = smoothstep(0.35, 0.92, wet_ink);
	float side_x = smoothstep(0.12, 1.0, abs(UV.x - 0.5) * 2.0);
	float side_y = smoothstep(0.30, 1.0, abs(UV.y - 0.5) * 2.0);
	col *= 1.0 - edge * side_x * abs(tilt.x) * 0.055;
	col *= 1.0 - edge * side_y * abs(tilt.y) * 0.040;

	COLOR = vec4(srgb_encode(clamp(col, vec3(0.0), vec3(1.0))),
		c.a * card_mask(UV));
}
