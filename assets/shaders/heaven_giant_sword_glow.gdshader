shader_type canvas_item;
render_mode blend_add;
// 满剑意一剑开天的巨剑·光层：叠在本体上的加法光。
// 只有刃口、中脊、尖端、外侧柔光和一道向下流动的能量带被点亮。
// 尺寸/UV 与本体完全一致，两层共用同一个轴心。

uniform float alpha : hint_range(0.0, 2.0) = 0.55;
uniform vec4 warm_color : source_color = vec4(1.0, 0.58, 0.15, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.86, 0.48, 1.0);

const float BLADE_TOP = 0.095;
const float BLADE_TIP = 0.992;
const float BLADE_HALF_MAX = 0.30;

void fragment() {
	vec2 uv = UV;
	float x = uv.x - 0.5;
	float y = 1.0 - uv.y;
	float ax = abs(x);

	float t = clamp((y - BLADE_TOP) / (BLADE_TIP - BLADE_TOP), 0.0, 1.0);
	float tip_fade = 1.0 - smoothstep(0.74, 0.985, t);
	float hw = BLADE_HALF_MAX * (0.90 + 0.10 * t) * tip_fade;
	float blade_y = smoothstep(BLADE_TOP - 0.012, BLADE_TOP + 0.004, y)
		* (1.0 - smoothstep(BLADE_TIP - 0.014, BLADE_TIP + 0.002, y));

	// 刃口光也放宽过渡，和本体的羽化边对齐
	float edge = (1.0 - smoothstep(0.0, 0.085, abs(ax - hw * 0.90))) * blade_y;
	float ridge = exp(-pow(x / 0.012, 2.0)) * blade_y;
	float tip = exp(-pow((y - 0.965) / 0.05, 2.0)) * exp(-pow(x / 0.10, 2.0));
	float halo = exp(-pow(max(ax - hw, 0.0) / 0.10, 2.0)) * blade_y * 0.18;
	// 能量带：沿着剑身慢慢往下流
	float band = exp(-pow((y - fract(TIME * 0.20) * 1.15) / 0.05, 2.0)) * blade_y;
	float flow = 0.85 + 0.15 * sin(y * 26.0 - TIME * 2.6);

	float a = (edge * 0.58 + ridge * 0.55 + tip * 0.80 + halo * 0.90
		+ band * 0.35) * flow * alpha;
	vec3 col = mix(warm_color.rgb, core_color.rgb,
		clamp(edge * 0.80 + ridge + tip * 0.90 + band * 0.50, 0.0, 1.0));
	COLOR = vec4(col, a);
}
