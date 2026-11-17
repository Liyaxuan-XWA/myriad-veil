shader_type canvas_item;
render_mode blend_mix;

// ============================================================
// 区域边界的林带 / 接缝地面条（2026-10-26 建，2026-11-01 改）
//
// 地图南边是**侧视**树墙、东边是**俯视**密冠，两条都只在一条轴上重复。
// 用一张长条贴图 + UV 缩放平铺，而不是逐棵树摆 Node2D：
// 树与树之间的疏密、遮挡、地面投影是出图时一体的，拆成单棵树反而拼不出那个味道。
//
// 为什么不用 TextureRect 的 STRETCH_TILE：那个模式按贴图**原生像素尺寸**铺，
// 没法把 896 的图缩到 512 世界像素的密度上，只能再套一层节点缩放。这里一个
// UV * repeat_count 就把「平铺」和「缩放到世界密度」两件事一起办了。
//
// 2026-11-01 边界整改：
//   · mirror：奇偶周期镜像。林带一张贴图 878 世界像素就重复一次，实机一眼能
//     数出同一块崖壁/同一棵树；镜像后视觉周期翻倍。镜像在格边界处取样连续
//     （奇格 f→1-f，边界两侧都落在贴图 0/1 端），不会多出接缝线。
//   · carve_low/high：内缘按长轴上的双频噪声咬出不规则舌形。原先贴图自带
//     alpha 羽化是一条直边，崖脚/树线实机读成一条线；这里只减不增，把边缘
//     往内咬 10~15% 深度，底色透出来，直线就断了。
//   · end_fade_low/high：长轴两端的收口。原先贴图端点 alpha 0.4~0.96，
//     两块林带在区域交界处直接对撞成一条竖线。脚本把端点向邻区多铺 220
//     世界像素，并在这里按半叠宽淡出，使交界线两侧各约 50% 叠化。
//     贴图本身**不能**烘端部淡出：长轴是 repeat 方向，烘进去会变成每周期
//     一条透明竖缝。
//   · shade_jitter：沿长轴的连续低频明暗（±3%）。注意不能用「逐周期常数」——
//     常数在格边界跳变，等于把重复周期用明暗画出来（同 region_terrain 的教训）。
// ============================================================

uniform sampler2D band_tex : filter_linear_mipmap, repeat_enable;
/// 沿 rect 长边重复几次；短边恒为 1（整条带子的高度就是贴图的高度，不重复）。
uniform float repeat_count : hint_range(0.5, 32.0) = 4.0;
/// 长边是 x 还是 y：南带沿 x 铺，东带沿 y 铺。
uniform bool along_y = false;
/// 奇偶周期镜像，打散「一张图重复到底」的读感。
uniform bool mirror = true;
/// 连续低频明暗半幅（0 = 关闭）。
uniform float shade_jitter : hint_range(0.0, 0.2) = 0.0;
/// 长轴平铺去重复：格内缓变位移（贴图两端收敛到 0，不破坏镜像边界）。
uniform float warp_amp : hint_range(0.0, 0.25) = 0.14;
/// 短轴低端 / 高端的内缘咬边深度（UV，0 = 不咬）。
uniform float carve_low : hint_range(0.0, 0.4) = 0.0;
uniform float carve_high : hint_range(0.0, 0.4) = 0.0;
/// 长轴低端 / 高端的淡出宽度（UV，0 = 不淡出）。
uniform float end_fade_low : hint_range(0.0, 0.3) = 0.0;
uniform float end_fade_high : hint_range(0.0, 0.3) = 0.0;


float _hash21(vec2 p) {
	// 不用 sin(dot)：精度在大坐标下会碎。fract+dot 版自变量始终在 0~1。
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = _hash21(i);
	float b = _hash21(i + vec2(1.0, 0.0));
	float c = _hash21(i + vec2(0.0, 1.0));
	float d = _hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


/// 内缘舌形：t 是离该边的距离（UV），cut 前 alpha 逐渐吃掉。
float _bite(float t, float cut, float phase) {
	if (cut <= 0.0) {
		return 1.0;
	}
	float n = _vnoise(vec2(phase * 2.1, 17.3)) * 0.65
		+ _vnoise(vec2(phase * 5.3, 41.9)) * 0.35;
	return smoothstep(0.0, cut, t - n * cut * 0.85);
}


void fragment() {
	vec2 uv = UV;
	float along = along_y ? uv.y : uv.x;
	float across = along_y ? uv.x : uv.y;
	float a = along * repeat_count;
	float cell = floor(a);
	float f = fract(a);
	if (mirror && mod(cell, 2.0) > 0.5) {
		f = 1.0 - f;
	}
	if (warp_amp > 0.0) {
		// sin(πf) 在格两端为 0：位移只在格内发生，镜像边界仍然连续。
		float w = (_vnoise(vec2(along * 9.0, 8.7)) - 0.5) * 2.0 * warp_amp;
		f = clamp(f + w * sin(3.14159265 * f), 0.0, 1.0);
	}
	// 长轴按原生密度平铺：一格 = 一个贴图周期（878 世界像素）。
	// ⚠ 不能写 (cell + f) / repeat_count —— 那会把整张图拉伸到整条带子上，
	//   再把拉伸后的图按格折 7 次，实机表现为格子边界上一条硬折痕 + 全带糊掉。
	vec2 tuv = along_y ? vec2(across, f) : vec2(f, across);
	vec4 col = texture(band_tex, tuv);

	if (shade_jitter > 0.0) {
		// 0.37 倍周期 → 约 2.7 张图一轮，跨格连续，不会画出格子。
		float h = _vnoise(vec2(along * repeat_count * 0.37, 4.5));
		col.rgb *= 1.0 + (h - 0.5) * 2.0 * shade_jitter;
	}

	float phase = along * repeat_count;
	col.a *= _bite(across, carve_low, phase);
	col.a *= _bite(1.0 - across, carve_high, phase + 7.7);

	if (end_fade_low > 0.0) {
		float n = _vnoise(vec2(across * 3.7 + 3.1, 9.7));
		col.a *= smoothstep(0.0, end_fade_low, along - n * end_fade_low * 0.55);
	}
	if (end_fade_high > 0.0) {
		float n = _vnoise(vec2(across * 3.7 + 8.9, 27.3));
		col.a *= smoothstep(0.0, end_fade_high, (1.0 - along) - n * end_fade_high * 0.55);
	}

	COLOR = col;
}
