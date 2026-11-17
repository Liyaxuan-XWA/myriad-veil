shader_type canvas_item;
// 满剑意一剑开天·巨剑本体：整体一块浓琥珀 / 琉璃（普通混合、半透明）。
// 剑身、剑格、剑柄、剑首同色同材质；不做金属高光、拉丝、深色刃口。
// 体积来自“厚度”：越靠轮廓越深（吸收），中脊透出柔和光芯，里面裹着缓慢流动的金色流丝。
// UV：x 居中，y=0 剑柄（画布底边）→ 1 剑尖（画布顶边）。

uniform float alpha : hint_range(0.0, 1.0) = 0.92;
uniform vec4 amber_deep : source_color = vec4(0.46, 0.21, 0.04, 1.0);
uniform vec4 amber_mid : source_color = vec4(1.0, 0.57, 0.15, 1.0);
uniform vec4 amber_light : source_color = vec4(1.0, 0.78, 0.34, 1.0);
uniform vec4 amber_core : source_color = vec4(1.0, 0.91, 0.60, 1.0);

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
	// 刃口羽化：向轮廓外多留一圈软过渡，不再是一刀切的硬边
	float blade = (1.0 - smoothstep(hw - 0.065, hw + 0.004, ax)) * blade_y;

	float guard = (1.0 - smoothstep(0.0165, 0.0260, abs(y - 0.078)))
		* (1.0 - smoothstep(0.46, 0.535, ax));
	float hilt = (1.0 - smoothstep(0.024, 0.036, abs(y - 0.048)))
		* (1.0 - smoothstep(0.036, 0.049, ax));
	float pommel_d = length(vec2(x / 0.075, (y - 0.018) / 0.017));
	float pommel = 1.0 - smoothstep(0.72, 1.10, pommel_d);

	float sx = x / max(hw, 0.0001);
	// 厚度：0 = 中脊、1 = 刃口；越靠外越深
	float thick = smoothstep(0.30, 1.0, abs(sx));
	// 中脊内的柔和光芯（不刺眼）
	float core = exp(-pow(x / 0.19, 2.0)) * (0.55 + 0.45 * sin(y * 7.0 - TIME * 1.4));
	// 金色流丝：缓慢蜿蜒的两三股细亮纹，不是拉丝
	float wobble = sin(y * 5.0 + TIME * 0.55 + x * 6.0) * 2.2;
	float strand = pow(0.5 + 0.5 * sin(y * 13.0 - TIME * 1.5 + wobble + x * 26.0), 10.0);
	float strand2 = pow(0.5 + 0.5 * sin(y * 21.0 + TIME * 1.1 - wobble * 0.7 + x * 40.0), 14.0) * 0.6;

	vec3 col = mix(amber_mid.rgb, amber_deep.rgb, thick * 0.52);
	col = mix(col, amber_light.rgb, clamp(core * 0.55 + (strand + strand2) * 0.50, 0.0, 1.0));
	col = mix(col, amber_core.rgb, clamp(core * 0.22, 0.0, 1.0));

	// 同色琥珀的剑格 / 剑柄 / 剑首：靠更深的厚度和一条亮边区分结构
	float guard_rim = smoothstep(0.0140, 0.0162, abs(y - 0.078)) * guard;
	float hilt_rim = smoothstep(0.0215, 0.0238, abs(y - 0.048)) * hilt;
	float pommel_rim = smoothstep(0.86, 1.02, pommel_d) * pommel;
	vec3 metal_col = mix(amber_mid.rgb * 0.82, amber_deep.rgb, 0.38);
	metal_col = mix(metal_col, amber_light.rgb, clamp(guard_rim + hilt_rim + pommel_rim, 0.0, 1.0) * 0.65);

	float blade_a = blade * (0.80 + 0.12 * thick);
	float metal_a = max(guard * 0.82, max(hilt * 0.76, pommel * 0.78));
	float a = clamp(max(blade_a, metal_a), 0.0, 1.0);
	vec3 out_col = mix(metal_col, col, clamp(blade, 0.0, 1.0));
	COLOR = vec4(out_col, a * alpha);
}
