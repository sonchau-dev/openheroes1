shader_type canvas_item;

// Traces a flat outline around the sprite's silhouette (the HOMM1 active-unit glow).
// Draws outline_color in the transparent ring just outside opaque pixels.
uniform vec4 outline_color : source_color = vec4(1.0, 0.85, 0.1, 1.0);
uniform float outline_width = 1.0;

float inside_texture(vec2 uv) {
	return step(0.0, uv.x) * step(uv.x, 1.0)
			* step(0.0, uv.y) * step(uv.y, 1.0);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (col.a > 0.5) {
		COLOR = col;   // keep the body itself untouched
	} else {
		vec2 ps = TEXTURE_PIXEL_SIZE * outline_width;
		float n = 0.0;
		vec2 sample_uv = UV + vec2(ps.x, 0.0);
		n = max(n, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
		sample_uv = UV + vec2(-ps.x, 0.0);
		n = max(n, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
		sample_uv = UV + vec2(0.0, ps.y);
		n = max(n, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
		sample_uv = UV + vec2(0.0, -ps.y);
		n = max(n, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
		sample_uv = UV + vec2(ps.x, ps.y);
		n = max(n, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
		sample_uv = UV + vec2(-ps.x, ps.y);
		n = max(n, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
		sample_uv = UV + vec2(ps.x, -ps.y);
		n = max(n, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
		sample_uv = UV + vec2(-ps.x, -ps.y);
		n = max(n, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
		COLOR = vec4(outline_color.rgb, outline_color.a * step(0.5, n));
	}
}
