shader_type canvas_item;
// BOSS 入场卡：全屏压暗 + 去色 + 墨迹从中心晕开。
// 用屏幕纹理取「这张全屏矩形之前画完的画面」，所以必须放在卡片下层、HUD 上层。
// progress 0→1 同时推进压暗与去色；ink_* 只控制那团墨，动画结束后墨迹淡到 0。

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float max_dim : hint_range(0.0, 1.0) = 0.64;
uniform float max_desat : hint_range(0.0, 1.0) = 0.85;
uniform float ink_radius = 0.20;
uniform float ink_alpha : hint_range(0.0, 1.0) = 0.95;
uniform float ink_edge = 0.30;
uniform vec4 ink_color : source_color = vec4(0.035, 0.028, 0.022, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 base = texture(screen_texture, SCREEN_UV).rgb;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(base, vec3(lum), max_desat * progress);
	col *= 1.0 - max_dim * progress;

	// 暗角：把视线收向卡片，同时不把 BOSS 剪影压没
	vec2 vp = SCREEN_UV - 0.5;
	vp.x *= 1.78;
	float vig = 1.0 - smoothstep(0.30, 0.88, length(vp));
	col *= mix(0.78, 1.0, vig);

	// 墨迹：半径越大铺得越开；边缘用两层噪声打碎，避免机械圆边
	vec2 p = SCREEN_UV - 0.5;
	p.x *= 1.78;
	float d = length(p);
	float n = (vnoise(SCREEN_UV * 9.0) - 0.5) * 0.70
		+ (vnoise(SCREEN_UV * 23.0) - 0.5) * 0.25;
	float ink = 1.0 - smoothstep(ink_radius - ink_edge, ink_radius + ink_edge, d + n);
	COLOR = vec4(mix(col, ink_color.rgb, clamp(ink * ink_alpha, 0.0, 1.0)), 1.0);
}
