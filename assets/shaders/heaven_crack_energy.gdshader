shader_type canvas_item;
render_mode blend_add;
// 满剑意一剑开天·地面劈痕的能量层：叠在劈痕贴图上的流动金光。
// UV.x = 裂纹长度方向（落点 → 前方），UV.y = 裂纹宽度方向。
// 劈痕贴图本身保持不变，这层只往上加「还在流动」的能量。

uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform vec4 tint : source_color = vec4(1.0, 0.70, 0.22, 1.0);

void fragment() {
	vec2 uv = UV;
	// 能量集中在裂纹中线附近
	float center = exp(-pow((uv.y - 0.5) / 0.22, 2.0));
	// 沿长度流动的亮带 + 一道循环推进的脉冲
	float flow = 0.5 + 0.5 * sin(uv.x * 46.0 - TIME * 3.6 + uv.y * 7.0);
	float streak = pow(flow, 3.0);
	float pulse = exp(-pow((uv.x - fract(TIME * 0.22)) / 0.07, 2.0));
	float ends = smoothstep(0.0, 0.04, uv.x) * (1.0 - smoothstep(0.90, 1.0, uv.x));
	float flicker = 0.88 + 0.12 * sin(TIME * 5.0 + uv.x * 12.0);
	float a = (center * 0.36 + streak * center * 0.55 + pulse * center * 0.60)
		* ends * strength * flicker;
	vec3 col = mix(tint.rgb, vec3(1.0, 0.95, 0.75), pulse);
	COLOR = vec4(col, a);
}
