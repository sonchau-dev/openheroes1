shader_type canvas_item;

// Armageddon's palette drain: every colour loses `drain` from its green and
// blue while its red holds, clamped at zero. The exe steps the 6-bit palette
// down one unit at a time, so full drain is 32 units, 128/255.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float drain = 0.0;

void fragment() {
	vec4 c = textureLod(screen_tex, SCREEN_UV, 0.0);
	COLOR = vec4(c.r, max(c.g - drain, 0.0), max(c.b - drain, 0.0), 1.0);
}
