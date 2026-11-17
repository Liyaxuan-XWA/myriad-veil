shader_type canvas_item;
// 加色混合：灵气团是**发光体**，不是贴在地上的纸片。
// 出图本身就是纯黑底（见 tools/prep_world_props.py 的 prep_orb），加色下黑等于不存在，
// 所以这张图根本不需要 alpha 通道 —— 硬要抠反而会把羽化边抠成锯齿。
render_mode blend_add;

/// 自转速度（弧度/秒）。取 0.35 ≈ 18 秒一圈：慢到看不出在转，但盯着看会觉得它在涌。
/// 灵气团同时还有 WorldResource 的缩放脉动（1.0↔1.25，2.8 秒一轮），两个周期不互整数倍，
/// 所以不会走出「转一圈正好胀一次」的拍频。
uniform float spin_speed : hint_range(-2.0, 2.0) = 0.35;
/// 亮度呼吸的频率（Hz）与半幅。和缩放脉动错开频率，避免同相。
uniform float breathe_hz : hint_range(0.0, 3.0) = 0.31;
uniform float breathe_amount : hint_range(0.0, 0.8) = 0.20;
/// 整体亮度。加色是「往上叠」，所以这个数直接决定它在深色草地上有多抢眼，
/// 也决定它会不会盖过技能特效（特效辉光亮度 0.506~0.562 是天花板）。
uniform float brightness : hint_range(0.0, 3.0) = 1.0;


void fragment() {
	vec2 uv = UV - 0.5;
	float a = TIME * spin_speed;
	// ⚠ Godot 的着色器语言不认 mat2(四个 float) 这个写法（报 Invalid arguments），
	//    只认按列构造 —— 两列 (cos,sin) 和 (-sin,cos) 就是标准二维旋转。
	uv = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * uv + 0.5;
	// 转出画布的部分 clamp 到边缘像素 —— 边缘就是黑的，加色下自然消失，不用特判。
	vec3 c = texture(TEXTURE, uv).rgb;
	float pulse = 1.0 + breathe_amount * sin(TIME * 6.2831853 * breathe_hz);
	COLOR = vec4(c * brightness * pulse, 1.0);
}
