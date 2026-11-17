shader_type canvas_item;
// 符卡边缘：给方形卡面切出一圈手工撕纸边，避免整张卡像 UI 方框。
// 只作用于卡面贴图本身；叠纸 / 印章仍由 talisman_card_view.gd 负责。

uniform float ragged : hint_range(0.0, 0.08) = 0.022;
uniform float seed = 0.0;
// 卡面对着亮背景/浅色外框时，把最外圈压成墨边，避免出现一圈白边
uniform float edge_dark : hint_range(0.0, 0.8) = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	// 极轻微的纸面起伏：连卡面内框也一起软掉，避免只剩「方框里再套一个方框」
	vec2 uv = UV + vec2(sin(UV.y * 9.0 + seed) * 0.0035,
		sin(UV.x * 7.0 + seed * 1.7) * 0.0045);
	vec4 c = texture(TEXTURE, uv);
	float nx = hash12(vec2(floor(uv.y * 88.0), seed));
	float ny = hash12(vec2(floor(uv.x * 64.0), seed + 7.0));
	float left = 0.003 + nx * ragged;
	float right = 0.003 + hash12(vec2(floor(uv.y * 74.0), seed + 13.0)) * ragged;
	float top = 0.004 + ny * ragged;
	float bottom = 0.004 + hash12(vec2(floor(uv.x * 58.0), seed + 23.0)) * ragged;
	float a = smoothstep(0.0, 0.006, uv.x - left)
		* smoothstep(0.0, 0.006, 1.0 - uv.x - right)
		* smoothstep(0.0, 0.006, uv.y - top)
		* smoothstep(0.0, 0.006, 1.0 - uv.y - bottom);
	c.a *= a;
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float shade = smoothstep(0.0, 0.048, edge);
	c.rgb *= mix(edge_dark, 1.0, shade);
	COLOR = c;
}
