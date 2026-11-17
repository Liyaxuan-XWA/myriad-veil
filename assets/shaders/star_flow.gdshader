shader_type canvas_item;
render_mode blend_mix;

// ============================================================
// 地图星点流动（2026-10-22）
// 作用对象：**原初位面地面贴图本身**（bg_primordial_realm），不是额外特效。
//
// 做法：不加粒子、不加节点，只改这张贴图的采样方式 ——
//   ① `star_mask` 是**由美术图派生**出来的星点权重图（tools/gen_star_mask.py，
//      把灵脉/光团整片排除，只留孤立小亮点的位置）
//   ② 按 TIME 沿 flow 方向偏移采样：mask=1 的位置改用「偏移之后那里的颜色」
//   ③ 于是星点被画到偏移后的位置、旧位置换成偏移处的底色 → 星在流动；
//      地形与灵脉不进 mask，完全不动
//
// 参数由 ArtDB.VISUALS["bg_primordial_realm"] 的 shader_params 传入。
//
// ⚠ 循环（2026-10-23 修）：偏移必须**按纹理尺寸取模**，不能无限累加。
//   旧写法 `uv_alt = UV - flow_px * TIME / tex_size` 里 TIME 只增不减，
//   uv_alt 会一路跑出 [0,1]；贴图与 mask 都是 clamp 采样（repeat_disable），
//   越界后采到的是边缘像素 —— mask 采到边缘的 0（没有星点到达）、
//   底色也变成边缘那一列的颜色，于是**星点整片消失、地面出现色带**。
//   按当前 flow_px = (9,-4)、2730×1536 估算，约 30 秒就开始从边角退化、5 分钟内基本没了。
//   取模后偏移永远落在 [0,1)，流动严格循环，跑多久都一个样。
// ============================================================

// 贴图尺寸（纹理像素）—— 把「每秒多少像素」换算成 UV 偏移
uniform vec2 tex_size = vec2(2730.0, 1536.0);
// 星点漂移速度（纹理像素 / 秒），负值反向
uniform vec2 flow_px = vec2(7.0, -3.0);
// 星点权重图（由美术图派生；缺图时整片不生效，画面等于原图）
uniform sampler2D star_mask : hint_default_black, filter_linear, repeat_disable;
// 新位置星点亮度增益（>1 抵消缩放/插值损失，让流动的星更醒目）
uniform float star_gain = 1.18;
// 整体强度（0 = 完全关闭，1 = 正常）
uniform float strength = 1.0;

void fragment() {
	// fract() 把偏移收进 [0,1)：负方向也能正确回绕（fract(x) = x - floor(x)）
	vec2 uv_alt = fract(UV - (flow_px * TIME) / tex_size);
	vec4 base = texture(TEXTURE, UV);
	vec4 alt = texture(TEXTURE, uv_alt);

	float m_here = texture(star_mask, UV).r;
	float m_alt = texture(star_mask, uv_alt).r;

	// ① 旧位置的星：用偏移采样到的底色顶替 → 星「离开」
	vec3 col = mix(base.rgb, alt.rgb, m_here * strength);
	// ② 偏移位置的星：画到当前位置 → 星「到达」
	col = mix(col, alt.rgb * star_gain, m_alt * strength);

	// ⚠ 透明度沿用原图：地面本身不透明，这里不要引入额外 alpha
	COLOR = vec4(col, base.a);
}
