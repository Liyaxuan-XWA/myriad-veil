shader_type canvas_item;

// 雾隐残影：只保留轮廓，统一压成冷蓝色雾影。
// 直接复制 BOSS 贴图再调 modulate 的话，深色石身会消失在暗地里，只剩苔角像一串水草。
uniform vec4 fog_color : source_color = vec4(0.58, 0.74, 0.88, 1.0);
uniform float fog_alpha : hint_range(0.0, 1.0) = 0.26;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(fog_color.rgb, tex.a * fog_alpha);
}
