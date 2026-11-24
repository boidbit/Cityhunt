// Roof Run street: asphalt with dashed lane lines and solid edge lines, drawn from the plane's UV (x across the
// road, y along it) scaled to metres by the instance uniforms.
shader_type spatial;
render_mode diffuse_burley;

instance uniform float len = 100.0;     // metres along
uniform float width = 9.0;              // metres across
uniform float lane = 2.4;
uniform vec3 asphalt : source_color = vec3(0.16, 0.16, 0.17);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float x = (UV.x - 0.5) * width;
	float y = UV.y * len;
	float grain = hash(floor(vec2(x, y) * 7.0)) * 0.05;
	vec3 c = asphalt * (1.0 - grain);
	// dashed lines between the lanes, solid ones at the edges
	float dash = step(fract(y / 6.0), 0.55);
	float l1 = 1.0 - smoothstep(0.06, 0.09, abs(abs(x) - lane * 0.5));
	float edge = 1.0 - smoothstep(0.07, 0.1, abs(abs(x) - (width * 0.5 - 0.35)));
	float paint = max(l1 * dash, edge);
	ALBEDO = mix(c, vec3(0.86, 0.86, 0.82), paint);
	ROUGHNESS = mix(0.88, 0.7, paint);
}
