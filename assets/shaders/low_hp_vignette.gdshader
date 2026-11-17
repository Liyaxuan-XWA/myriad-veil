shader_type canvas_item;
// 低血量屏幕泛红：屏幕四边的柔和红晕 + 缓慢脉动。
//
// ⚠ 2026-10-27 换掉原来「四条 60px 红色直边」的做法：硬边矩形贴在水墨画面上很像 UI 框，
//   而且尺寸是建的时候量一次视口，窗口比例一变就错位。这里全用 UV 算，任何分辨率都对。
// ⚠ 只做「边缘压暗泛红」，画面中心必须始终透明 —— 否则会盖住刀光和判定范围。

uniform vec4 tint : source_color = vec4(0.58, 0.04, 0.05, 1.0);
uniform vec4 tint_deep : source_color = vec4(0.24, 0.02, 0.03, 1.0);
// 0 = 不显示，1 = 满血警示（由 player.gd 按血量比例喂）
uniform float danger : hint_range(0.0, 1.0) = 0.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.62;
// 脉动频率与幅度：低血时心跳感，但不许闪（幅度压在 0.22 以内）
uniform float pulse_hz : hint_range(0.0, 4.0) = 1.1;
uniform float pulse_amount : hint_range(0.0, 0.6) = 0.22;
// 红晕从屏幕半径的哪个位置开始 / 到哪里到顶（0~1 是边中点，1.41 是角）
uniform float inner : hint_range(0.0, 1.2) = 0.40;
uniform float outer : hint_range(0.6, 1.8) = 1.30;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	// 竖向压一点：16:9 上纯圆会把上下两侧吃得太窄，看着像个椭圆圈
	float r = length(p * vec2(1.0, 0.92));
	float edge = smoothstep(inner, outer, r);
	// 四角比四边更深，避免整圈同色像贴片
	vec3 col = mix(tint.rgb, tint_deep.rgb, smoothstep(0.86, 1.46, r));
	float pulse = 1.0 + pulse_amount * sin(TIME * 6.2831853 * pulse_hz);
	COLOR = vec4(col, clamp(danger * edge * max_alpha * pulse, 0.0, 1.0));
}
