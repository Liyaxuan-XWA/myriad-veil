shader_type canvas_item;
render_mode blend_mix;

// ============================================================
// 练气区（青岚野）地面（2026-10-26）
//
// 三套哑光手绘 tile 按**低频地貌遮罩**加权混合，再叠地面贴花。
// 遮罩由 tools/bake_region_mask.py 从 SecretWorldDB 的航点烘出来：
//   R = 草   G = 土路   B = 林缘裸土   A = 贴花强度
// 三通道在烘焙时已归一化成和为 1，线性过滤之后仍然是 1（插值的和 = 和的插值），
// 这里再除一次只是防浮点漂移。
//
// 为什么不是「一张整幅大地图」：6000×4000 的整图要么糊（贴图不够大）要么占内存
// （够大就 90MB）。低频遮罩 + 可平铺 tile 让全图任意位置都是原生分辨率。
//
// ⚠ 格网必须打散，但**不能用逐格镜像**。试过：每格按哈希随机翻转，数学上对无缝
//   tile 是连续的（四种翻转组合逐一验算过，tile 左边=右边、上边=下边），实机却在
//   每条格边界上多出一条 1px 直线 —— 把 tile_world 512→500，直线跟着挪到新边界，
//   说明是「翻折」本身而不是素材：折点处采样坐标取极值，跨格的 2×2 quad 里导数反号。
//   同批对照：关镜像后差分比 2.0→1.2；jitter / 贴花 / 大尺度明暗关掉都没变化。
//   所以换成连续域扭曲：坐标处处缓变，折不出棱角，规则格网照样散架。
//
// ⚠ 亮度扰动的周期不能和 tile 网格重合。jitter 用 vnoise(grid) 时周期刚好一格，
//   等于给刚推散的格网又描了一遍暗框；这里用 grid*0.7。同理逐格乘常数绝对不行 ——
//   常数在格边界跳变，那就是把格子网用明暗直接画出来。
//
// ⚠ 镜像折线 + 自动 mipmap 会雪上加霜：GPU 用 2×2 quad 的屏幕空间差分算 LOD，
//   跨格 quad 里两个像素落在不同朝向，差分看到将近一整格（≈900 texel）的跳变 →
//   挑到最深那级 mip → 那一列被糊成一条比周围更暗更平的线。顶视平面缩放均匀，
//   本来就不需要靠差分猜 LOD，所以改成 textureLod + 脚本喂进来的 tile_lod
//   （见 secret_world.gd 的 _sync_terrain_lod）。
//   （想在 shader 里自己算的话走不通：canvas_item 的 fragment 没有 MATRIX，
//    vertex 有 CANVAS_MATRIX/SCREEN_MATRIX 但没有 VIEWPORT_SIZE —— 4.7 实测。）
// ============================================================

uniform sampler2D grass_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D road_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D forest_tex : filter_linear_mipmap, repeat_enable;
// 遮罩不 repeat、不用 mipmap：它是被放大 8 倍用的低频场，mipmap 会把它抹平掉。
uniform sampler2D mask_tex : filter_linear, repeat_disable;

/// 区域矩形的世界尺寸（练气区 6000×4000）
uniform vec2 world_size = vec2(6000.0, 4000.0);
/// 一张 tile 盖多少世界像素：896 texel / 512 px = 1.75 texel/px
uniform float tile_world : hint_range(128.0, 2048.0) = 512.0;
/// 贴花的 tile 放大倍率（比地面本体大一圈，才不像「同一张草皮重复」）
uniform float decal_scale : hint_range(1.2, 6.0) = 2.6;
uniform float decal_strength : hint_range(0.0, 1.0) = 0.72;
/// 显式 mipmap 层级，由脚本按「一个 texel 占几个屏幕像素」算出来喂进来（见顶部 ⚠）
uniform float tile_lod : hint_range(0.0, 8.0) = 0.8;
/// 贴花底色：把草压暗并往土色偏一点，读作一丛丛低矮灌丛 / 盘根裸土
uniform vec4 decal_tint : source_color = vec4(0.62, 0.60, 0.52, 1.0);
/// 逐格亮度扰动的半幅（±）
uniform float jitter_amount : hint_range(0.0, 0.35) = 0.085;
/// 大尺度明暗的尺度（世界像素）与半幅
uniform float macro_scale : hint_range(400.0, 4000.0) = 1450.0;
uniform float macro_amount : hint_range(0.0, 0.35) = 0.10;
/// 域扭曲的半幅（单位：格）与噪声周期（单位：格）。
/// 0.62 / 4.0 → 局部缩放约 0.77~1.23，够把格网推散，又不会把草叶拧出漩涡。
uniform float warp_amp : hint_range(0.0, 1.5) = 0.62;
uniform float warp_period : hint_range(1.0, 12.0) = 4.0;


float _hash21(vec2 p) {
	// 不用 sin(dot)：见 barrier_flow 里那条精度警告。fract+dot 版自变量始终在 0~1。
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = _hash21(i);
	float b = _hash21(i + vec2(1.0, 0.0));
	float c = _hash21(i + vec2(0.0, 1.0));
	float d = _hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


/// 把 tile 坐标推离规则格网：按低频噪声给每一点一个缓变的偏移。
/// seed 让三套地貌各自歪向不同方向，不然它们的格线会叠成同一条。
vec2 _spread(vec2 p, vec2 seed) {
	vec2 q = p / warp_period + seed;
	vec2 n = vec2(_vnoise(q), _vnoise(q + 31.71)) - 0.5;
	return p + n * warp_amp;
}


void fragment() {
	vec2 world = UV * world_size;
	vec4 mask = texture(mask_tex, UV);
	vec3 t = mask.rgb / max(mask.r + mask.g + mask.b, 1e-4);

	vec2 grid = world / tile_world;
	vec3 col = textureLod(grass_tex, _spread(grid, vec2(0.0, 0.0)), tile_lod).rgb * t.r
		+ textureLod(road_tex, _spread(grid, vec2(7.31, 2.19)), tile_lod).rgb * t.g
		+ textureLod(forest_tex, _spread(grid, vec2(41.77, 13.05)), tile_lod).rgb * t.b;

	// 贴花：只在 A 高的地方出现，采样放大版的草皮压暗 —— 不新增美术也有一块块的着地物。
	// 放大 decal_scale 倍意味着同等屏幕面积吃进的 texel 少 decal_scale 倍，LOD 跟着降。
	vec3 decal = textureLod(grass_tex, _spread(grid / decal_scale, vec2(73.09, 5.4)),
		max(0.0, tile_lod - log2(decal_scale))).rgb * decal_tint.rgb;
	col = mix(col, decal, clamp(mask.a * decal_strength, 0.0, 1.0));

	col *= mix(1.0 - jitter_amount, 1.0 + jitter_amount, _vnoise(grid * 0.7 + 11.0));
	col *= mix(1.0 - macro_amount, 1.0 + macro_amount, _vnoise(world / macro_scale + 3.7));

	COLOR = vec4(col, 1.0);
}
