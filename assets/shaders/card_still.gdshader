shader_type canvas_item;
render_mode blend_mix;

// 普通卡：静态原画，只做与华彩卡一致的圆角遮罩，不参与视差 / 箔光。
// ⚠ canvas_item 里 texture() 拿到的是**线性色**，不编码就写 COLOR 会明显发暗
//   （2026-10-30 实测：同一张原画在卡里只剩 0.2~0.55 倍亮度，用户在卡包里看到
//   「普通卡还是那么暗」就是这个）。这里显式 linear_to_srgb，原画什么亮度就显示什么亮度，
//   也不要在后面再叠 exposure / gamma —— 那会把整张卡压暗一档。
uniform vec2 card_px = vec2(300.0, 450.0);
uniform float corner_px = 14.0;

// 手写 sRGB 编码：这个引擎版本没有 linear_to_srgb()（2026-10-30 实测编译失败）
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

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(srgb_encode(c.rgb), c.a * card_mask(UV));
}
