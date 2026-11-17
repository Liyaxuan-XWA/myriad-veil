shader_type canvas_item;
render_mode blend_mix, unshaded;

// 万界图鉴·华彩卡：背景 2× 取样随视角平移，角色 / 描边同坐标；
// 描边辉光只取结构线覆盖 × 角色 alpha，不向场景或角色内部溢光。
// legacy=1 走旧版 HTML 的 HDR 发光 + 双尺度 bloom + 色调映射，用于「第一版无背景」标准卡。

uniform sampler2D bg_tex : filter_linear, repeat_disable;
uniform sampler2D art_tex : filter_linear, repeat_disable;
uniform sampler2D line_tex : filter_linear, repeat_disable;
uniform vec2 view = vec2(0.0);
uniform float depth = 0.0;
uniform float contour = 0.15;
uniform vec2 card_px = vec2(320.0, 480.0);
uniform float corner_px = 14.0;
uniform float bg_scale = 0.5;
uniform float bg_shift = 0.25;
uniform float prism = 0.22;
uniform float emission_gain = 1.5;
uniform float wide_glow = 0.0;
uniform float aura = 0.0;
uniform float legacy = 0.0;

float card_mask(vec2 uv) {
	vec2 half_px = card_px * 0.5;
	vec2 d = abs(uv * card_px - half_px) - (half_px - vec2(corner_px));
	float dist = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - corner_px;
	return 1.0 - smoothstep(-1.2, 0.8, dist);
}

vec3 spectrum(float t) {
	return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

vec3 spectrum_legacy(float t) {
	return 0.52 + 0.48 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV;
	float mask = card_mask(p);
	if (mask < 0.002) {
		COLOR = vec4(0.0);
	} else {
		// 背景独立视差；带地面的卡用 1:1，避免石径/接触影被放大移位
		vec2 b = (p - 0.5) * bg_scale + 0.5 - view * bg_shift;
		vec3 base = texture(bg_tex, clamp(b, vec2(0.0), vec2(1.0))).rgb;

		// 角色与描边共用同一坐标；depth 改变前景视差量，不改叠加顺序
		float fg_k = depth < 0.0 ? 0.06 : 0.08;
		vec2 a = p - view * fg_k * depth;
		vec4 ch = texture(art_tex, a);
		float inb = step(0.0, a.x) * step(a.x, 1.0) * step(0.0, a.y) * step(a.y, 1.0);
		ch.a *= inb * mask;
		vec3 col = base * (1.0 - ch.a) + ch.rgb * ch.a;
		float line = texture(line_tex, a).r * ch.a;

		if (legacy > 0.5) {
			// 第一版 HTML 的完整公式：HDR 发光 + 两级 bloom + 色调映射
			float phase = p.x * 0.62 + p.y * 0.36 + view.x * 1.9 + view.y * 0.8;
			vec3 spec = spectrum_legacy(phase * 2.2);
			float f = p.x * 0.65 + p.y * 0.4 + view.x * 1.9 + view.y * 0.85;
			float light = pow(max(0.0, 1.0 - abs(fract(f + 0.16) - 0.5) * 2.0), 3.0);
			// 背景上的箔光压低，保持第一版「暗底衬亮线」的对比
			float foil = light * 0.48 * mix(0.35, 1.0, ch.a);
			col = mix(col, col * (0.64 + spec * 0.7) + spec * 0.07, foil);

			vec2 cell = fract(p * vec2(24.0, 34.0)) - 0.5;
			float seed = hash21(floor(p * vec2(24.0, 34.0)));
			float star = pow(max(0.0, 1.0 - abs(cell.x) * 18.0), 14.0)
				* pow(max(0.0, 1.0 - abs(cell.y) * 2.0), 6.0)
				+ pow(max(0.0, 1.0 - abs(cell.y) * 18.0), 14.0)
				* pow(max(0.0, 1.0 - abs(cell.x) * 2.0), 6.0);
			float micro = pow(hash21(floor(p * vec2(620.0, 868.0))), 28.0);
			col += spec * (star * step(0.965, seed) * light * 0.65 + micro * light * 0.12)
				* (1.0 - ch.a);

			float glare = pow(max(0.0, 1.0 - length(
				(p - vec2(0.5 + view.x, 0.6 + view.y)) * vec2(1.0, 0.75))), 5.0);
			col += vec3(glare * 0.12);

			float envelope = smoothstep(0.025, 0.42, light);
			vec3 emis_col = spec * 0.85 + vec3(0.15);
			float emis_scale = 40.0 * contour * emission_gain;
			vec3 emission = emis_col * line * envelope * emis_scale;

			// 旧版 bloom 是半分辨率/四分之一分辨率的两次高斯；这里用 8 向双半径近似
			vec2 px = vec2(1.0) / card_px;
			vec2 o1 = px * 2.2;
			vec2 o2 = px * 9.0;
			float bn = 0.0;
			bn += texture(line_tex, a + vec2(o1.x, 0.0)).r * texture(art_tex, a + vec2(o1.x, 0.0)).a;
			bn += texture(line_tex, a - vec2(o1.x, 0.0)).r * texture(art_tex, a - vec2(o1.x, 0.0)).a;
			bn += texture(line_tex, a + vec2(0.0, o1.y)).r * texture(art_tex, a + vec2(0.0, o1.y)).a;
			bn += texture(line_tex, a - vec2(0.0, o1.y)).r * texture(art_tex, a - vec2(0.0, o1.y)).a;
			bn += texture(line_tex, a + o1 * 0.7071).r * texture(art_tex, a + o1 * 0.7071).a;
			bn += texture(line_tex, a - o1 * 0.7071).r * texture(art_tex, a - o1 * 0.7071).a;
			bn += texture(line_tex, a + vec2(o1.x, -o1.y) * 0.7071).r * texture(art_tex, a + vec2(o1.x, -o1.y) * 0.7071).a;
			bn += texture(line_tex, a - vec2(o1.x, -o1.y) * 0.7071).r * texture(art_tex, a - vec2(o1.x, -o1.y) * 0.7071).a;
			float bw = 0.0;
			bw += texture(line_tex, a + vec2(o2.x, 0.0)).r * texture(art_tex, a + vec2(o2.x, 0.0)).a;
			bw += texture(line_tex, a - vec2(o2.x, 0.0)).r * texture(art_tex, a - vec2(o2.x, 0.0)).a;
			bw += texture(line_tex, a + vec2(0.0, o2.y)).r * texture(art_tex, a + vec2(0.0, o2.y)).a;
			bw += texture(line_tex, a - vec2(0.0, o2.y)).r * texture(art_tex, a - vec2(0.0, o2.y)).a;
			bw += texture(line_tex, a + o2 * 0.7071).r * texture(art_tex, a + o2 * 0.7071).a;
			bw += texture(line_tex, a - o2 * 0.7071).r * texture(art_tex, a - o2 * 0.7071).a;
			bw += texture(line_tex, a + vec2(o2.x, -o2.y) * 0.7071).r * texture(art_tex, a + vec2(o2.x, -o2.y) * 0.7071).a;
			bw += texture(line_tex, a - vec2(o2.x, -o2.y) * 0.7071).r * texture(art_tex, a - vec2(o2.x, -o2.y) * 0.7071).a;
			bn /= 8.0;
			bw /= 8.0;
			// 旧版 bloom 只来自过曝的 emission，并受同一箔光包络控制
			float peak = max(emission.r, max(emission.g, emission.b));
			vec3 bloom = emis_col * (bn * 0.55 + bw * 0.8) * line * emis_scale
				* envelope * smoothstep(0.6, 1.4, peak);

			vec3 linear = pow(clamp(col, vec3(0.0), vec3(1.0)), vec3(2.2));
			vec3 combined = 1.0 - (1.0 - linear) * exp(-(emission * 0.38 + bloom * 0.85));
			COLOR = vec4(pow(clamp(combined, vec3(0.0), vec3(1.0)), vec3(1.0 / 2.2)), mask);
		} else {
			// 全息箔光带：随视角流动
			float phase = p.x * 0.62 + p.y * 0.36 + view.x * 1.9 + view.y * 0.8;
			float light = pow(max(0.0, 1.0 - abs(fract(phase + 0.16) - 0.5) * 2.0), 3.0);
			vec3 spec = spectrum(phase * 2.2);
			col = mix(col, col * (0.7 + spec * 0.55) + spec * 0.045, light * 0.30);

			float glare = pow(max(0.0, 1.0 - length((p - vec2(0.5 - view.x * 0.4, 0.6 - view.y * 0.4)) * vec2(1.0, 0.75))), 5.0);
			col += vec3(glare * 0.10);

			vec2 px = vec2(1.0) / card_px;
			vec2 o2 = px * 2.0;
			vec2 o5 = px * 5.0;
			float glow = 0.0;
			glow += texture(line_tex, a + vec2(o2.x, 0.0)).r;
			glow += texture(line_tex, a - vec2(o2.x, 0.0)).r;
			glow += texture(line_tex, a + vec2(0.0, o2.y)).r;
			glow += texture(line_tex, a - vec2(0.0, o2.y)).r;
			glow += texture(line_tex, a + o2 * vec2(0.7071, 0.7071)).r;
			glow += texture(line_tex, a - o2 * vec2(0.7071, 0.7071)).r;
			glow += texture(line_tex, a + o2 * vec2(0.7071, -0.7071)).r;
			glow += texture(line_tex, a - o2 * vec2(0.7071, -0.7071)).r;
			glow += texture(line_tex, a + vec2(o5.x, 0.0)).r * 0.6;
			glow += texture(line_tex, a - vec2(o5.x, 0.0)).r * 0.6;
			glow += texture(line_tex, a + vec2(0.0, o5.y)).r * 0.6;
			glow += texture(line_tex, a - vec2(0.0, o5.y)).r * 0.6;
			glow = glow / 9.6 * ch.a;

			// 宽域辉光：近似旧 HTML 的 bloom，让密线在 330 尺寸下仍能晕开
			float wide = 0.0;
			if (wide_glow > 0.001) {
				vec2 o10 = px * 10.0;
				vec2 o18 = px * 18.0;
				wide += texture(line_tex, a + vec2(o10.x, 0.0)).r;
				wide += texture(line_tex, a - vec2(o10.x, 0.0)).r;
				wide += texture(line_tex, a + vec2(0.0, o10.y)).r;
				wide += texture(line_tex, a - vec2(0.0, o10.y)).r;
				wide += texture(line_tex, a + o10 * 0.7071).r;
				wide += texture(line_tex, a - o10 * 0.7071).r;
				wide += texture(line_tex, a + vec2(o10.x, -o10.y) * 0.7071).r;
				wide += texture(line_tex, a - vec2(o10.x, -o10.y) * 0.7071).r;
				wide += texture(line_tex, a + vec2(o18.x, 0.0)).r * 0.5;
				wide += texture(line_tex, a - vec2(o18.x, 0.0)).r * 0.5;
				wide += texture(line_tex, a + vec2(0.0, o18.y)).r * 0.5;
				wide += texture(line_tex, a - vec2(0.0, o18.y)).r * 0.5;
				wide = wide / 10.0 * ch.a;
			}

			// 轮廓外晕：从角色 alpha 取一圈，只加在剪影外，把角色从背景里拉出来
			float halo = 0.0;
			if (aura > 0.001) {
				vec2 o12 = px * 12.0;
				float aa = 0.0;
				aa += texture(art_tex, a + vec2(o12.x, 0.0)).a;
				aa += texture(art_tex, a - vec2(o12.x, 0.0)).a;
				aa += texture(art_tex, a + vec2(0.0, o12.y)).a;
				aa += texture(art_tex, a - vec2(0.0, o12.y)).a;
				aa += texture(art_tex, a + o12 * 0.7071).a;
				aa += texture(art_tex, a - o12 * 0.7071).a;
				aa += texture(art_tex, a + vec2(o12.x, -o12.y) * 0.7071).a;
				aa += texture(art_tex, a - vec2(o12.x, -o12.y) * 0.7071).a;
				halo = clamp(aa * 0.3125, 0.0, 1.0) * (1.0 - ch.a);
			}

			float env = smoothstep(0.03, 0.42, light);
			// prism=1 时走旧虎妖的密线彩虹，默认只掺一点棱镜色
			vec3 emis_col = mix(vec3(1.0, 0.86, 0.58), spec, prism);
			vec3 emission = emis_col * (line * 0.9 + glow * 0.5 + wide * wide_glow)
				* env * contour * emission_gain;
			emission += emis_col * halo * aura * (0.3 + 0.7 * env) * contour * emission_gain;
			col += emission;

			COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), mask);
		}
	}
}
