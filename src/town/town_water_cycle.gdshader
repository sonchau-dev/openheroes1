shader_type canvas_item;
render_mode unshaded;

// Authentic HOMM1 hardware VGA DAC palette cycling (RAMDAC cycling).
// In heroes.exe, timer interrupt routine 0xdc6d3 (at ~6.32 Hz) writes 32 color entries
// starting at DAC index 224 (0xe0) via port 0x3c8/0x3c9 (routine 0xe9482).
//
// Palette entries 240..244 form a 5-color water ramp, rotated forward by 1 index per tick.
// Palette entries 247..250 form a 4-color foam/ripple band, rotated forward by 1 index per tick.
// In the Knight town screen, farmcast.icn frame 0 contains 80 water pixels in the castle moat
// at y in [107..119] plus 11 foam pixels, and townbkg0.png contains 51 water pixels.
// Because the DOS VGA hardware shifted the color registers in RAMDAC, the water flowed
// globally with zero CPU sprite overdraw.

uniform int cycle_step : hint_range(0, 19) = 0;

// Authentic kb.pal water ramp (indices 240..244):
// 240: (96, 104, 252), 241: (64, 88, 240), 242: (40, 80, 228), 243: (16, 72, 216), 244: (0, 72, 204)
const vec3 WATER[5] = vec3[5](
	vec3(96.0 / 255.0, 104.0 / 255.0, 252.0 / 255.0),
	vec3(64.0 / 255.0,  88.0 / 255.0, 240.0 / 255.0),
	vec3(40.0 / 255.0,  80.0 / 255.0, 228.0 / 255.0),
	vec3(16.0 / 255.0,  72.0 / 255.0, 216.0 / 255.0),
	vec3( 0.0 / 255.0,  72.0 / 255.0, 204.0 / 255.0)
);

// Authentic kb.pal foam/ripple band (indices 247..250):
// 247: (132, 224, 252), 248: (0, 152, 252), 249: (0, 80, 228), 250: (0, 0, 164)
const vec3 FOAM[4] = vec3[4](
	vec3(132.0 / 255.0, 224.0 / 255.0, 252.0 / 255.0),
	vec3(  0.0 / 255.0, 152.0 / 255.0, 252.0 / 255.0),
	vec3(  0.0 / 255.0,  80.0 / 255.0, 228.0 / 255.0),
	vec3(  0.0 / 255.0,   0.0 / 255.0, 164.0 / 255.0)
);

void fragment() {
	if (COLOR.a > 0.0) {
		ivec3 c = ivec3(round(COLOR.rgb * 255.0));
		if (c == ivec3(96, 104, 252)) {
			COLOR.rgb = WATER[(0 + cycle_step) % 5];
		} else if (c == ivec3(64, 88, 240)) {
			COLOR.rgb = WATER[(1 + cycle_step) % 5];
		} else if (c == ivec3(40, 80, 228)) {
			COLOR.rgb = WATER[(2 + cycle_step) % 5];
		} else if (c == ivec3(16, 72, 216)) {
			COLOR.rgb = WATER[(3 + cycle_step) % 5];
		} else if (c == ivec3(0, 72, 204)) {
			COLOR.rgb = WATER[(4 + cycle_step) % 5];
		} else if (c == ivec3(132, 224, 252)) {
			COLOR.rgb = FOAM[(0 + cycle_step) % 4];
		} else if (c == ivec3(0, 152, 252)) {
			COLOR.rgb = FOAM[(1 + cycle_step) % 4];
		} else if (c == ivec3(0, 80, 228)) {
			COLOR.rgb = FOAM[(2 + cycle_step) % 4];
		} else if (c == ivec3(0, 0, 164)) {
			COLOR.rgb = FOAM[(3 + cycle_step) % 4];
		}
	}
}
