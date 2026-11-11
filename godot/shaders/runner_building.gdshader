// Roof Run buildings: plain boxes; the windows, floor lines and the roof surface are drawn here from the world
// position (no textures, so it stays cheap on a phone). Each building's wall colour is an instance uniform, so
// every building shares the one material.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

instance uniform vec3 wall : source_color = vec3(0.62, 0.55, 0.48);
instance uniform float seed = 0.0;
uniform vec3 roof_col : source_color = vec3(0.52, 0.52, 0.5);
uniform float win_w = 3.1;     // window bay (m)
uniform float win_h = 3.3;     // storey (m)

varying vec3 wp;
varying vec3 wn;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.3) * 43758.5453);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (wn.y > 0.5) {
		// the roof: concrete slabs with dark joints, a little dirt
		vec2 g = fract(wp.xz / 2.4);
		float joint = 1.0 - step(0.035, g.x) * step(0.035, g.y);
		float dirt = hash(floor(wp.xz / 2.4)) * 0.08;
		ALBEDO = roof_col * (1.0 - joint * 0.28 - dirt);
		ROUGHNESS = 0.92;
	} else if (wn.y < -0.5) {
		ALBEDO = wall * 0.5;
		ROUGHNESS = 0.9;
	} else {
		float u = abs(wn.x) > 0.5 ? wp.z : wp.x;
		vec2 cell = vec2(u / win_w, wp.y / win_h);
		vec2 f = fract(cell);
		vec2 id = floor(cell);
		float win = step(0.2, f.x) * step(f.x, 0.8) * step(0.28, f.y) * step(f.y, 0.86);
		// no windows at street level: a darker base
		float base = step(wp.y, 3.2);
		win *= 1.0 - base;
		float h = hash(id);
		// glass reflects the sky: lighter towards the top of each pane, some panes darker (blinds, rooms)
		vec3 glass = mix(vec3(0.1, 0.14, 0.2), vec3(0.42, 0.55, 0.68), clamp(f.y * 0.7 + h * 0.45 - 0.15, 0.0, 1.0));
		// floor lines and the sill under each window
		float band = 1.0 - step(0.06, f.y);
		vec3 w = wall * (1.0 - band * 0.25) * mix(1.0, 0.62, base);
		ALBEDO = mix(w, glass, win);
		ROUGHNESS = mix(0.85, 0.12, win);
		METALLIC = mix(0.0, 0.35, win);
	}
}
