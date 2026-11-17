shader_type canvas_item;
// 战场整体灯光调色：读屏幕纹理做分级（曝光/对比/饱和/抬灰/分离色调/方向光/暗角）。
// 只调世界（地面 + 人物 + 特效），HUD 在它之后绘制，不受影响。
// 规矩：**不改地面纹理**，所有氛围都来自这张分级表（ArtDB 的 bg_*_arena.grade）。

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float exposure : hint_range(0.5, 1.6) = 1.0;
uniform float contrast : hint_range(0.5, 1.8) = 1.0;
uniform float saturation : hint_range(0.0, 1.6) = 1.0;
uniform float lift : hint_range(-0.1, 0.2) = 0.0;
uniform float gamma : hint_range(0.6, 1.6) = 1.0;
uniform vec4 shadow_tint : source_color = vec4(1.0);
uniform vec4 highlight_tint : source_color = vec4(1.0);
uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec2 light_dir = vec2(0.0, -1.0);
uniform float light_strength : hint_range(0.0, 0.5) = 0.0;

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;

	c *= exposure;
	c = (c - 0.5) * contrast + 0.5;
	c = pow(clamp(c + lift, 0.0, 1.0), vec3(1.0 / max(gamma, 0.01)));

	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);

	// 分离色调：暗部与亮部各染一层，做出「月光 / 暖灯 / 云海」的底色
	float lum = clamp(dot(c, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	vec3 toned = mix(c * shadow_tint.rgb, c * highlight_tint.rgb, smoothstep(0.12, 0.86, lum));

	// 方向光：沿 light_dir 的一侧更亮，另一侧压暗（很轻，只做体积感）
	vec2 ld = normalize(light_dir + vec2(0.0001, 0.0001));
	float d = dot(SCREEN_UV - vec2(0.5), ld);
	toned *= 1.0 + d * light_strength;

	// 暗角
	vec2 p = SCREEN_UV - vec2(0.5);
	p.x *= 1.7778;
	float v = smoothstep(0.32, 0.86, length(p));
	toned = mix(toned, vignette_color.rgb, v * vignette);

	COLOR = vec4(clamp(toned, 0.0, 1.0), 1.0);
}
