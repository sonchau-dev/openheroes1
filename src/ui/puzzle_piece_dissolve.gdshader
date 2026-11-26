shader_type canvas_item;

// The DOS reference removes every newly earned wooden piece with one random
// dissolve over 3 seconds. Measured on the DOS campaign recording
// (26:07 onward): each dot is a 2x2 block of
// native pixels aligned to even screen coordinates, the reveal order is
// uncorrelated between neighbouring blocks, and coverage rises linearly.
// Blocks are keyed to screen position, so pieces sharing an edge share one grid.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float block_size : hint_range(1.0, 8.0) = 2.0;

varying vec2 screen_pos;

float block_noise(vec2 block) {
	vec3 p3 = fract(vec3(block.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	screen_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// COLOR already holds the texture times modulate; sampling it again
	// would square every channel and darken the piece.
	vec2 block = floor(floor(screen_pos) / max(block_size, 1.0));
	if (block_noise(block) < progress) {
		COLOR.a = 0.0;
	}
}
