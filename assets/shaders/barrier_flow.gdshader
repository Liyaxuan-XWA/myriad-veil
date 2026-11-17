shader_type canvas_item;
// 主城四周能量墙（2026-10-22）
//
// 目的：让 Line2D 画出来的边界不像「一根发光的直线」，而是有
//   ① 能量流转：噪声沿墙流动，慢速、方向略微斜切，避免「匀速平移」的机械感
//   ② 灵力波动：低频一呼一吸，相位按世界坐标打散，整圈不同步才不假
//   ③ 纵向柔和：能量边缘向外衰减，而不是硬边
//
// ⚠ 不要用 UV 做「纵向柔边」：Line2D 在没有贴图时 UV 的取值不可靠（实测 UV.y 不是 0~1，
//   会把 alpha 直接算成 0，整面墙消失）。纵向的辉光改由 primordial_realm 里
//   **多条不同宽度的线叠加**实现，本 shader 只负责颜色流动与灵力呼吸。
//
// ⚠ 时间项必须**有界**（2026-10-23 修）：
//   旧写法把 `t * flow_speed` 直接加到噪声输入上，t 只增不减，
//   hash21 里 `sin(dot(p, ·))` 的自变量会涨到几万甚至几十万 ——
//   float32 的 sin 在大数上精度崩坏，hash 退化成同一个值，花纹就整片消失（剩一根纯色亮线）。
//   改成把时间放进**圆周相位**：偏移量 |spin| ≤ 半径，永远不越界，而且严格循环。
//   角速度取「线速度 / 半径」，保证观感流速和原来的 flow_speed 像素/秒一致。

uniform vec4 core_color : source_color = vec4(0.80, 0.97, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.28, 0.72, 0.96, 1.0);
// 能量流转速度（世界像素/秒）
uniform float flow_speed = 22.0;
// 噪声尺度：越大花纹越碎
uniform float turbulence = 0.020;
// 灵力起伏频率与幅度
uniform float pulse_speed = 1.05;
uniform float pulse_amount = 0.30;
// 整体不透明度
uniform float base_alpha = 0.9;
// 花纹对比：越大，亮暗拉得越开
uniform float flow_contrast = 1.35;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 值噪声（一阶平滑插值，够用且便宜）
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// ⚠ canvas_item 里没有 MODEL_MATRIX（那是 spatial 的），用 VERTEX 的本地坐标即可：
	//   光墙节点（BarrierGlow）挂在场景原点、无旋转缩放，本地坐标 = 世界坐标。
	//   如果以后把光墙挪了位置/缩放了，这里的花纹会跟着走（视觉上也说得通）。
	vec2 world = VERTEX;
	float t = TIME;

	// ① 能量流转：两层噪声，各沿一个**圆周**路径漂移（有界 → 不退化、严格循环）
	//   半径越大，一个周期里扫过的噪声格越多、花纹变化越丰富
	const float R1 = 2.2;
	const float R2 = 1.4;
	float w1 = flow_speed * turbulence / R1;
	float w2 = flow_speed * turbulence * 2.3 * 0.70 / R2;
	vec2 spin1 = vec2(cos(t * w1), sin(t * w1)) * R1;
	// 次级流反向 + 相位错开 1.7，避免两层同步成一个花样
	vec2 spin2 = vec2(cos(-t * w2 + 1.7), sin(-t * w2 + 1.7)) * R2;
	float n1 = vnoise(world * turbulence + spin1);
	float n2 = vnoise(world * turbulence * 2.3 + spin2);
	float flow = clamp(n1 * 0.68 + n2 * 0.32, 0.0, 1.0);
	flow = clamp(pow(flow, flow_contrast), 0.0, 1.0);

	// ② 灵力波动：相位按世界坐标错开，同一圈墙不会一起亮暗
	// mod 到 2π 保证相位也不随时间无限增长（虽然 sin 本身不易崩，但取模后严格循环）
	float phase = mod(t * pulse_speed, 6.2831853) + world.x * 0.006 + world.y * 0.0045;
	float pulse = 1.0 - pulse_amount + pulse_amount * (0.5 + 0.5 * sin(phase));

	// ③ 亮度：流动花纹 + 呼吸（纵向柔边交给多层线，见文件头说明）
	float a = base_alpha * pulse * (0.45 + 0.85 * flow);
	vec3 col = mix(glow_color.rgb, core_color.rgb, smoothstep(0.35, 0.9, flow));
	COLOR = vec4(col, clamp(a, 0.0, 1.0));
}
