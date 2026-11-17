shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.88, 0.96, 1.0, 1.0);
uniform float density = 0.55;
uniform float flow = 0.6;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(11.7, 5.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec4 base = COLOR;
	vec2 uv = UV;
	// 云体轮廓用径向柔边（不是贴图里的细弧），内部再叠噪声流转
	float radial = smoothstep(0.52, 0.06, length(uv - vec2(0.5)));
	vec2 p = uv * vec2(2.1, 1.8);
	float t = TIME * (0.12 + flow * 0.10);
	vec2 warp = vec2(
		fbm(p + vec2(t, -t * 0.65)),
		fbm(p + vec2(4.7, 2.3) + vec2(-t * 0.75, t)));
	float n = fbm(p + warp * 1.7 + vec2(t * 0.45, 0.0));
	// 2026-10-28 修可见度：原来颜色压到灰蓝、alpha 又被 modulate 乘第二遍，
	// 在暗底上整团云几乎看不见。现在：稀薄处保底不透明、亮部往白提、alpha 只吃一半 modulate。
	float a = radial * max(smoothstep(0.16, 0.58, n), 0.20) * density;
	vec3 col = mix(tint.rgb * 0.72, mix(tint.rgb, vec3(1.0), 0.45), smoothstep(0.28, 0.82, n));
	col += tint.rgb * 0.12;
	COLOR = vec4(col, a * (0.55 + 0.45 * base.a)) * vec4(1.0, 1.0, 1.0, 1.0);
}
