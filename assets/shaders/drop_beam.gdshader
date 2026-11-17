shader_type canvas_item;
render_mode blend_add;
// 掉落物品品质光柱：柔和的圆柱光，没有直边。
// 横向：宽光晕 + 柱身 + 亮芯，全部高斯衰减，在画到边界前就归零；
// 纵向：底部厚实、向上化开，贴地处再软收一段，融进地面光晕。
// 颜色由物品品阶/稀有度注入；TIME 只做很轻的呼吸。

uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 0.72;

void fragment() {
	vec2 uv = UV;
	float x = abs(uv.x - 0.5) * 2.0;  // 0 中轴 → 1 左右边缘
	float y = uv.y;                   // 0 顶部 → 1 底部

	float halo = exp(-pow(x / 0.50, 2.0)) * 0.16;
	float body = exp(-pow(x / 0.34, 2.0)) * 0.58;
	float core = exp(-pow(x / 0.15, 2.0)) * 0.30;
	float lit = (halo + body + core) * (1.0 - smoothstep(0.62, 0.97, x));

	float rise = smoothstep(0.0, 0.55, y);
	float foot = 1.0 - smoothstep(0.86, 1.0, y);
	float dense = mix(0.46, 1.0, pow(y, 0.65));
	float v = rise * foot * dense;

	float shimmer = 0.9 + 0.1 * sin(TIME * 1.6 + y * 4.0);
	COLOR = vec4(tint.rgb, tint.a * lit * v * strength * shimmer);
}
