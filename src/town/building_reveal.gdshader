shader_type canvas_item;
render_mode unshaded;

uniform float reveal_progress : hint_range(0.0, 1.0) = 1.0;
uniform vec2 pattern_offset = vec2(0.0);
uniform float block_size : hint_range(1.0, 8.0) = 2.0;
// Pickups on the DOS adventure map lose pixels in a scattered order, not a
// screen-door grid: measured from the supplied campaign recording, the order is
// uncorrelated with the neighbours above and below, and the whole pile is gone
// in about 8 video frames. noise_steps > 0 selects that order and quantizes it.
uniform float noise_steps : hint_range(0.0, 32.0) = 0.0;

// Recursive 8x8 Bayer screen-door pattern. This reveals whole source pixels
// across the building footprint, matching the DOS palette-era construction
// dissolve without blending or moving the sprite.
float bayer2(vec2 pixel) {
	vec2 p = mod(pixel, 2.0);
	if (p.y < 1.0) {
		return p.x < 1.0 ? 0.0 : 2.0;
	}
	return p.x < 1.0 ? 3.0 : 1.0;
}

float bayer4(vec2 pixel) {
	return 4.0 * bayer2(mod(pixel, 2.0)) + bayer2(floor(pixel / 2.0));
}

float bayer8(vec2 pixel) {
	return 4.0 * bayer4(mod(pixel, 4.0)) + bayer2(floor(pixel / 4.0));
}

float scatter(vec2 pixel) {
	return fract(sin(dot(pixel, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 source_pixel = floor((floor(UV / TEXTURE_PIXEL_SIZE) + pattern_offset) / max(block_size, 1.0));
	float threshold = (bayer8(source_pixel) + 0.5) / 64.0;
	if (noise_steps > 0.0) {
		threshold = (floor(scatter(source_pixel) * noise_steps) + 0.5) / noise_steps;
	}
	// COLOR already holds the texture times modulate. Multiplying the texture in
	// again squares every channel and draws the sprite darker than it is.
	if (reveal_progress < threshold) {
		discard;
	}
}
