shader_type canvas_item;
render_mode blend_mix, unshaded;

// 水墨卡：纸面、留白、卡框完全不动，只有墨迹按烘焙的局部笔势缓慢滑移。
// flow_tex RGBA：RG=方向编码，B=局部相位，A=流动权重；guard_tex.r=保护强度。
// 视角只负责：反向轻带偏方向、增大游移幅度与由 GDScript 推进的流相位速度。
uniform sampler2D ink_tex : filter_linear, repeat_disable;
uniform sampler2D flow_tex : filter_linear, repeat_disable;
uniform sampler2D guard_tex : filter_linear, repeat_disable;
uniform vec2 view = vec2(0.0);
uniform vec2 card_px = vec2(320.0, 480.0);
uniform vec2 ink_px = vec2(640.0, 960.0);
uniform float corner_px = 14.0;
uniform float ink_phase = 0.0;
uniform float ink_strength = 1.0;

float card_mask(vec2 uv) {
	vec2 half_px = card_px * 0.5;
	vec2 d = abs(uv * card_px - half_px) - (half_px - vec2(corner_px));
	float dist = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - corner_px;
	return 1.0 - smoothstep(-1.2, 0.8, dist);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 p = UV;
	float mask = card_mask(p);
	if (mask < 0.002) {
		COLOR = vec4(0.0);
	} else {
		vec4 base = texture(ink_tex, p);
		float lum = luma(base.rgb);
		// 纸面约 0.93、淡墨 0.8、浓墨 < 0.5；纸面权重为 0，保证纸纹静止
		float ink = 1.0 - smoothstep(0.56, 0.93, lum);
		ink = smoothstep(0.06, 0.38, ink);

		vec4 flow = texture(flow_tex, p);
		float guard = smoothstep(0.06, 0.80, texture(guard_tex, p).r);
		float weight = flow.a;

		vec2 dir = flow.rg * 2.0 - 1.0;
		float dl = length(dir);
		dir = dl > 0.001 ? dir / dl : vec2(0.0, 1.0);

		// 笔势为主，拖动时朝拖动反方向轻带偏（湿墨惯性），最多约 20°
		vec2 flow_dir = dir;
		float drag = clamp(length(view), 0.0, 1.0);
		if (drag > 0.001) {
			vec2 target = -view / max(length(view), 0.001);
			float cross_v = dir.x * target.y - dir.y * target.x;
			float dot_v = clamp(dot(dir, target), -1.0, 1.0);
			float rot = clamp(atan(cross_v, dot_v), -0.35 * drag, 0.35 * drag);
			float cr = cos(rot);
			float sr = sin(rot);
			flow_dir = vec2(dir.x * cr - dir.y * sr, dir.x * sr + dir.y * cr);
		}
		float amp_px = (5.5 + 3.5 * drag) * ink_strength;
		float flow_amt = ink * weight * (1.0 - guard * 0.97);
		float phase = flow.b * 6.2831853 + ink_phase;
		float wave = sin(phase);
		// 次级细流：更快、更碎的一层，让笔触不是整块同步呼吸
		float wave2 = sin(phase * 2.0 + flow.b * 9.0 + p.y * 3.2);
		vec2 perp = vec2(-flow_dir.y, flow_dir.x);
		vec2 offset = flow_dir * (amp_px / ink_px) * (wave + 0.22 * wave2) * flow_amt;
		offset += perp * (amp_px / ink_px) * (0.12 * cos(phase * 2.0 + p.x * 2.1)) * flow_amt;
		vec4 moved = texture(ink_tex, clamp(p + offset, vec2(0.0), vec2(1.0)));

		float moved_lum = luma(moved.rgb);
		float mix_amt = clamp(flow_amt * 0.78, 0.0, 0.78);
		vec3 col = mix(base.rgb, moved.rgb, mix_amt);
		// 笔触在走时，浓淡也顺着墨缘轻微变化，但纸面/保护区权重为 0
		float tone = (moved_lum - lum) * flow_amt * 0.30;
		col *= (1.0 + tone);
		float breathe = 0.5 + 0.5 * sin(phase * 2.0 + p.x * 2.4 + p.y * 1.3);
		col *= 1.0 + (breathe - 0.5) * 0.08 * flow_amt;
		// 墨缘再取一层更远的样本，只让浓淡交界有一点点湿边
		float edge = smoothstep(0.015, 0.10, abs(moved_lum - lum)) * flow_amt;
		vec4 wet = texture(ink_tex, clamp(p + offset * 1.8, vec2(0.0), vec2(1.0)));
		col = mix(col, wet.rgb, edge * 0.22);

		COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), mask);
	}
}
