shader_type canvas_item;
// Crisp pixel-art terrain. Every tile is split into `sub` x `sub` square pixels. Each pixel takes
// the exact colour of one tile (no blending), but pixels close to a tile border pick a
// neighbouring tile at random, so biome edges come out as ragged, dithered pixel edges instead of
// a blur. `sub` is set from the camera zoom so a terrain pixel never gets smaller than ~2 screen
// pixels (no shimmering or mush when zoomed out).

uniform sampler2D height_tex : filter_linear, repeat_disable;   // R = land height 0..1, G = water mask
uniform vec2 map_size = vec2(256.0, 256.0);
uniform float sub = 4.0;
uniform float shade_strength = 7.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 cells = map_size * sub;
	vec2 cell = floor(UV * cells);
	vec2 q = (cell + 0.5) / cells;
	// ragged borders: jitter the lookup by up to ~0.45 tile, quantised to the pixel grid
	vec2 jit = vec2(hash(cell), hash(cell + 17.31)) - 0.5;
	jit *= (sub > 1.5) ? 0.9 : 0.0;
	vec2 tp = q * map_size + jit;
	ivec2 ti = ivec2(clamp(floor(tp), vec2(0.0), map_size - 1.0));
	vec3 c = texelFetch(TEXTURE, ti, 0).rgb;
	vec2 tx = 1.0 / map_size;
	vec2 hw = texture(height_tex, q).rg;
	float hl = texture(height_tex, q - vec2(tx.x, 0.0)).r;
	float hr = texture(height_tex, q + vec2(tx.x, 0.0)).r;
	float hu = texture(height_tex, q - vec2(0.0, tx.y)).r;
	float hd = texture(height_tex, q + vec2(0.0, tx.y)).r;
	// light from the top-left, stepped into a few bands for a pixel-art look
	float shade = 1.0 + ((hr - hl) + (hd - hu)) * shade_strength;
	shade = floor(clamp(shade, 0.62, 1.32) * 12.0 + 0.5) / 12.0;
	float water = texelFetch(height_tex, ti, 0).g;
	c *= mix(shade, 1.0, water);
	// per-pixel grain (stable, never blurred)
	c *= 0.96 + hash(cell + 3.7) * 0.08;
	// water: gentle shimmer of individual pixels
	float tw = step(0.985, hash(cell + floor(TIME * 0.7)));
	c += vec3(0.05, 0.07, 0.08) * tw * water;
	// coastline foam: pixels of water next to land
	float edge = 1.0 - abs(hw.g - 0.5) * 2.0;
	float foam = step(0.62, edge + (hash(cell + 9.1) - 0.5) * 0.3) * water;
	c = mix(c, vec3(0.84, 0.89, 0.92), foam * 0.45);
	COLOR = vec4(c, 1.0);
}
