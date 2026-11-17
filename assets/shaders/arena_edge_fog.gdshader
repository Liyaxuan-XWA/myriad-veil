shader_type canvas_item;
render_mode blend_mix, unshaded;

// 战场外圈边界雾：只在竞技场墙外出现，向内完全不遮。
// 近墙处是一条被低频噪声揉散的淡雾边，再往外压成与暗角同色的浓雾，
// 让相机越界看到的那一圈"场外"读成雾，而不是空白或硬边。
uniform vec2 rect_px = vec2(6960.0, 5388.0);
uniform vec2 arena_half = vec2(1760.0, 974.0);
uniform float band_px = 280.0;
uniform vec4 fog_color : source_color = vec4(0.02, 0.035, 0.06, 1.0);
uniform vec4 mist_color : source_color = vec4(0.36, 0.40, 0.46, 1.0);
uniform float mist_strength : hint_range(0.0, 1.0) = 0.55;
uniform float drift_speed = 0.045;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(11.7, 5.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_px;
	vec2 q = abs(p) - arena_half;
	// 方形距离：d=0 正好落在隐形墙外沿，场内 d<0 完全不着色
	float d = max(q.x, q.y);
	vec4 out_col = vec4(0.0);
	// 场内大部分像素直接跳过噪声：这层雾的矩形盖着整个战场，不能每帧跑满全屏
	if (d >= -90.0) {
		vec2 np = p * 0.0028;
		float t = TIME * drift_speed;
		float n1 = fbm(np + vec2(t * 0.30, -t * 0.18));
		float n2 = fbm(np * 2.3 + vec2(-t * 0.22, t * 0.27) + 11.7);
		// 雾边被两层噪声揉开，避免出现一条笔直的矩形边
		float d2 = d + (n1 - 0.5) * band_px * 0.36;
		float fill = smoothstep(0.0, band_px, d2);
		fill = max(fill, smoothstep(band_px * 0.85, band_px * 1.25, d));
		// 淡雾从墙内约 60px 起、到墙外 45px 就看得见：走到墙边本身有可读的边界，
		// 而不是撞到一堵看不见的墙。最外 60px 只有很薄一层，不遮人也不遮招。
		float mist_rise = smoothstep(-band_px * 0.22, band_px * 0.16, d);
		float mist_band = exp(-pow((d2 - band_px * 0.55) / (band_px * 0.55), 2.0));
		float mist_amt = mist_rise * mist_band * mist_strength * (0.55 + 0.75 * n2);
		vec3 col = mix(fog_color.rgb, mist_color.rgb, clamp(mist_amt * 1.7, 0.0, 0.78));
		// 远处的浓雾再叠一层更慢、更大的雾团，避免整片读成一张纯色黑幕
		float n3 = fbm(np * 0.55 + vec2(-t * 0.12, t * 0.09) + 23.0);
		float far_mist = smoothstep(band_px * 0.65, band_px * 2.2, d);
		col = mix(col, mist_color.rgb * 0.78, far_mist * 0.13 * (0.35 + 0.95 * n3));
		col *= 0.80 + 0.40 * n1;
		float a = max(fill, mist_amt);
		// 只在最外侧 90px 内淡入；再往里严格为 0，避免雾压暗可走区域
		a *= smoothstep(-90.0, -50.0, d);
		out_col = vec4(col, a);
	}
	COLOR = out_col;
}
