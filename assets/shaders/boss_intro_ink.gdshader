shader_type canvas_item;
// 入场卡两侧的淡墨烟：低频 fbm 噪声做絮状，中心向外淡出。
// 只做气氛，不参与判定；两块错开 seed 缓慢飘动即可。

uniform vec4 tint : source_color = vec4(0.72, 0.66, 0.55, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.14;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += vnoise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float d = length(uv - 0.5) * 2.0;
	vec2 drift = vec2(seed * 7.0, TIME * 0.025);
	float f = fbm(uv * 3.2 + drift);
	float body = smoothstep(1.0, 0.15, d + (f - 0.5) * 0.9);
	COLOR = vec4(tint.rgb, body * alpha);
}
