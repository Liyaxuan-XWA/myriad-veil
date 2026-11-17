// 功法 / 符箓图标的「资源不足」灰化（2026-11-09 用户要求）
// 只作用于格子里的图标本身，不改贴图资源 —— 后替换正式图标时自动生效。
// ⚠ CanvasItem 的 material **不向子节点继承**：必须挂到真正绘制贴图的那层 TextureRect，
//   给 CenterContainer 挂是没效果的（见 combat_arena._icon_paint_target）。
// ⚠ canvas_item 的 fragment 里 COLOR 进来时**已经乘过 TEXTURE × 顶点色 × modulate**，
//   千万别再 texture(TEXTURE, UV) 一次 —— 平方后彩色会重新透出来（只剩变暗、不去色）。
shader_type canvas_item;

uniform float gray_mix : hint_range(0.0, 1.0) = 0.0;  // 0 = 原色，1 = 完全灰阶
uniform float dim : hint_range(0.0, 1.0) = 0.0;       // 额外压暗：灰了还要辨得出是哪个技能

void fragment() {
	vec4 c = COLOR;
	float lum = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	c.rgb = mix(c.rgb, vec3(lum), gray_mix) * (1.0 - dim);
	COLOR = c;
}
