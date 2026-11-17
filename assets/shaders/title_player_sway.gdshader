shader_type canvas_item;
render_mode blend_mix;

// 登录界面主角的待机风摆：
//   头发 → 更快、带一点上下飘；衣袖/下摆 → 更慢、幅度更明显。
// 通过 UV 区域 + 明暗遮罩，把脸、手和脚底排除在强位移之外。

uniform float hair_strength : hint_range(0.0, 0.03) = 0.013;
uniform float cloth_strength : hint_range(0.0, 0.03) = 0.0085;
uniform float sway_speed : hint_range(0.1, 4.0) = 1.35;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float charge : hint_range(0.0, 2.0) = 0.0;
uniform vec4 dissolve_color : source_color = vec4(0.55, 0.94, 1.0, 1.0);

float band(float x, float lo0, float lo1, float hi0, float hi1) {
	return smoothstep(lo0, lo1, x) * (1.0 - smoothstep(hi0, hi1, x));
}

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
	vec2 uv = UV;
	vec4 base = texture(TEXTURE, uv);

	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float dark = 1.0 - smoothstep(0.08, 0.24, lum);

	// 脸部安全区：眼睛、五官所在的矩形不做强位移
	float face = band(UV.x, 0.50, 0.55, 0.84, 0.90)
		* band(UV.y, 0.05, 0.09, 0.20, 0.24);

	// 头发：头顶 + 左侧垂发；避开脸部
	float hair_top = dark * (1.0 - smoothstep(0.25, 0.34, UV.y))
		* smoothstep(0.20, 0.28, UV.x);
	float hair_left = dark * (1.0 - smoothstep(0.34, 0.55, UV.x))
		* band(UV.y, 0.08, 0.16, 0.38, 0.48);
	float hair = clamp(hair_top + hair_left * 0.8, 0.0, 1.0) * (1.0 - face);

	// 衣服：下摆 + 左右宽袖，脚底保持不动
	float lower = smoothstep(0.40, 0.57, UV.y) * (1.0 - smoothstep(0.86, 0.94, UV.y));
	float sleeve_left = band(UV.x, 0.05, 0.11, 0.40, 0.48)
		* band(UV.y, 0.29, 0.35, 0.56, 0.63);
	float sleeve_right = band(UV.x, 0.79, 0.85, 0.96, 1.0)
		* band(UV.y, 0.39, 0.45, 0.58, 0.65);
	float cloth = clamp(lower + sleeve_left * 0.85 + sleeve_right * 0.75, 0.0, 1.0);

	// 头发：双频快速摆动 + 轻微纵向飘动
	float hair_wave = sin(TIME * sway_speed * 1.65 + UV.y * 20.0 + UV.x * 2.0)
		+ 0.38 * sin(TIME * sway_speed * 2.8 - UV.y * 11.0);
	vec2 shift = vec2(hair_wave * hair_strength * hair,
		hair_wave * 0.22 * hair_strength * hair);

	// 衣服：低频主摆 + 一点布褶细波，再叠一层很轻的纵向波纹
	float cloth_wave = sin(TIME * sway_speed + UV.y * 12.0 + UV.x * 1.5)
		+ 0.35 * sin(TIME * sway_speed * 1.7 + UV.x * 4.0);
	shift.x += cloth_wave * cloth_strength * cloth;
	shift.y += sin(TIME * sway_speed * 1.3 + UV.y * 9.0) * 0.0012 * cloth;

	vec4 col = texture(TEXTURE, uv + shift);

	// 攒能阶段：轮廓泛青 + 体内流动的灵力光纹
	if (charge > 0.001) {
		vec2 tap = vec2(0.0040, 0.0016);
		float around = 0.0;
		around = max(around, texture(TEXTURE, uv + vec2(tap.x, 0.0)).a);
		around = max(around, texture(TEXTURE, uv - vec2(tap.x, 0.0)).a);
		around = max(around, texture(TEXTURE, uv + vec2(0.0, tap.y)).a);
		around = max(around, texture(TEXTURE, uv - vec2(0.0, tap.y)).a);
		around = max(around, texture(TEXTURE, uv + tap).a);
		around = max(around, texture(TEXTURE, uv - tap).a);
		float charge_rim = clamp(around - base.a, 0.0, 1.0) * charge;

		// 轻微压暗身形，让青色轮廓与灵纹更清晰，不至于被漩涡吞成白团
		col.rgb *= 1.0 - min(charge, 1.5) * 0.10;
		float vein = smoothstep(0.52, 0.92,
			fbm(UV * vec2(16.0, 34.0) + vec2(TIME * 0.12, -TIME * 0.8)));
		col.rgb += dissolve_color.rgb * vein * 0.30 * min(charge, 1.5) * base.a;
		col.rgb += dissolve_color.rgb * 0.05 * min(charge, 1.5) * base.a;
		col.rgb = mix(col.rgb, dissolve_color.rgb, clamp(charge_rim * 1.15, 0.0, 0.85));
		col.rgb += dissolve_color.rgb * charge_rim * 0.30;
		col.a = max(col.a, charge_rim * 0.50);
	}

	// 被吸入时的丝缕溶解：竖向拉长的流动噪声，让身形化成向上升腾的青色光丝
	if (dissolve_amount > 0.001) {
		float flow = TIME * 0.25;
		vec2 np = vec2(UV.x * 26.0, UV.y * 12.0 + flow);
		float n = fbm(np) * 0.72 + fbm(UV * vec2(62.0, 34.0) - flow * 0.6) * 0.28;
		n = smoothstep(0.18, 0.82, n);

		float threshold = dissolve_amount * 1.04 - 0.02;
		float mask = smoothstep(threshold - 0.060, threshold + 0.030, n);
		float edge = smoothstep(threshold - 0.160, threshold - 0.020, n)
			* (1.0 - smoothstep(threshold - 0.020, threshold + 0.050, n));
		edge *= smoothstep(threshold - 0.030, threshold + 0.010, n);

		// 溶解前先让身形透出灵力青光，避免「白衣服直接消失」
		float glow = smoothstep(0.0, 0.35, dissolve_amount);
		col.rgb = mix(col.rgb, dissolve_color.rgb, glow * 0.22);

		col.a *= mask;
		col.rgb = mix(col.rgb, dissolve_color.rgb, clamp(edge * 0.9, 0.0, 0.8));
		col.rgb += dissolve_color.rgb * edge * 0.5;
		col.a = max(col.a, edge * 0.45);

		// 轮廓外泛起的青色灵光，让整个人像被能量包裹
		vec2 tap = vec2(0.0040, 0.0016);
		float around = 0.0;
		around = max(around, texture(TEXTURE, uv + vec2(tap.x, 0.0)).a);
		around = max(around, texture(TEXTURE, uv - vec2(tap.x, 0.0)).a);
		around = max(around, texture(TEXTURE, uv + vec2(0.0, tap.y)).a);
		around = max(around, texture(TEXTURE, uv - vec2(0.0, tap.y)).a);
		around = max(around, texture(TEXTURE, uv + tap).a);
		around = max(around, texture(TEXTURE, uv - tap).a);
		float rim = clamp(around - base.a, 0.0, 1.0)
			* smoothstep(0.02, 0.22, dissolve_amount);
		col.rgb = mix(col.rgb, dissolve_color.rgb, clamp(rim * 1.3, 0.0, 1.0));
		col.rgb += dissolve_color.rgb * rim * 0.35;
		col.a = max(col.a, rim * 0.5);
	}

	// 乘以顶点 COLOR，让节点的 modulate 淡出/染色继续生效
	COLOR = col * COLOR;
}
