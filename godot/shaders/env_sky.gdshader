// What shiny surfaces reflect: a panorama of distant lit windows and lamps at street level.
shader_type sky;
uniform sampler2D pano : source_color, filter_linear;
global uniform float daylight;
global uniform float rain_amount;
void sky() {
	// by day: an overcast sky over grey streets
	vec3 day = mix(mix(vec3(0.5, 0.62, 0.8), vec3(0.55, 0.57, 0.6), rain_amount), vec3(0.16, 0.16, 0.16), smoothstep(0.52, 0.48, SKY_COORDS.y));
	COLOR = mix(texture(pano, SKY_COORDS).rgb, day, daylight);
}
