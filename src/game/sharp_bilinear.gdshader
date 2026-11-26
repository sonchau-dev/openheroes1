shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Sharp-bilinear upscale of the 640x480 frame (see sharp_scaler.gd). Each
// source texel stays flat and blends into its neighbour over one screen pixel
// at its edge, which is what a screen pixel straddling two texels should show:
// its share of each. At a whole-number scale no screen pixel straddles and the
// result is plain nearest-neighbour.
//
// The blend is done here, from four texels read at their centres, and not by
// the texture's linear filter: the Compatibility renderer (Android) samples
// this viewport texture nearest whatever filter the canvas item asks for,
// which left every fractional scale with texels of uneven width.

// Presented size over source size, per axis.
uniform vec2 scale = vec2(1.0);

void fragment() {
	vec2 texel = UV / TEXTURE_PIXEL_SIZE;
	vec2 prescale = max(scale, vec2(1.0));
	// How far from the texel centre the colour stays flat.
	vec2 flat_half = 0.5 - 0.5 / prescale;
	vec2 from_centre = fract(texel) - 0.5;
	vec2 blend = (from_centre - clamp(from_centre, -flat_half, flat_half)) * prescale + 0.5;
	// The sample point between texel centres: `corner` is the centre of the
	// upper-left of the four texels around it, `weight` the way to the next.
	vec2 point = floor(texel) + blend - 0.5;
	vec2 weight = fract(point);
	vec2 corner = floor(point) + 0.5;
	vec2 last = 1.0 / TEXTURE_PIXEL_SIZE - 0.5;
	vec2 a = clamp(corner, vec2(0.5), last) * TEXTURE_PIXEL_SIZE;
	vec2 b = clamp(corner + 1.0, vec2(0.5), last) * TEXTURE_PIXEL_SIZE;
	COLOR = mix(
		mix(texture(TEXTURE, a), texture(TEXTURE, vec2(b.x, a.y)), weight.x),
		mix(texture(TEXTURE, vec2(a.x, b.y)), texture(TEXTURE, b), weight.x),
		weight.y);
}
