shader_type canvas_item;
// 满剑意「一剑开天」蓄力期的压暗暗角：压暗战场四周，让巨剑与剑客成为唯一亮部。
// strength 由驱动节点补间（0 → 1 → 0）；挂在 HUD 层 z=-50，HUD 文字/血条在它上面，不受影响。

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.02, 0.018, 0.03, 1.0);
uniform float dim : hint_range(0.0, 0.4) = 0.12;
uniform float inner_radius : hint_range(0.05, 0.8) = 0.30;
uniform float outer_radius : hint_range(0.2, 1.2) = 0.78;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float aspect = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.00001);
	p.x *= aspect;
	float d = length(p);
	float v = smoothstep(inner_radius, outer_radius, d);
	float a = (dim + v * 0.72) * strength;
	COLOR = vec4(tint.rgb, a);
}
