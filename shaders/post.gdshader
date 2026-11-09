// The pixel look, ported from the Blender-video compositor. Runs on the 480x270 world
// render: heat-haze warp, toon banding, colour punch, warm grade, world-locked Bayer
// dither with a slow drift, hover shimmer, 40-colour palette snap, hover outline.
shader_type canvas_item;

uniform sampler2D scene_tex : filter_linear, repeat_disable;
uniform sampler2D mask_tex : filter_nearest, repeat_disable;
uniform vec3 palette[40];

uniform float frame = 0.0;            // 24 fps clock, like the video frames
uniform float cam_px = 0.0;           // camera pan in whole pixels (keeps the dither on the world)
uniform float noise_seed = 0.0;

uniform int target_id = 0;            // hovered group id, 0 = none
uniform float build = 0.0;            // shimmer build-up, 1 - e^(-t/10)
uniform vec2 cursor = vec2(240.0, 135.0);
uniform vec2 shimmer_off = vec2(0.0);
uniform int outline_px = 2;

uniform float heat = 0.0;
uniform float heat_focus = 1.0;
uniform float shutter = 0.0;
uniform vec2 window_px = vec2(240.0, 136.0);
uniform float dim = 0.0;              // darken behind panels
uniform float fade = 0.0;             // to black
uniform float pause_amount = 0.0;     // blur and dim behind the pause menu
uniform float brightness = 1.0;       // user setting, 0.5 .. 1.5
uniform float landing_amount = 0.0;   // cinematic title-screen grade and vignette

const vec2 SIZE = vec2(480.0, 270.0);
const int ID_OFFSET = 4;              // mask ids are stored 4 steps up (see toon.gdshader)
const float DITHER = 0.045;
const float DRIFT = 0.016;
const float SATURATION = 1.25;
const float CONTRAST = 1.08;
const float SHIMMER_RADIUS = 45.0;
const float BAND = 0.16;
const vec3 WTS = vec3(2.0, 4.0, 3.0);
const float BAYER[16] = float[](0., 8., 2., 10., 12., 4., 14., 6., 3., 11., 1., 9., 15., 7., 13., 5.);

float bayer(vec2 p) {
	ivec2 i = ivec2(mod(floor(p), 4.0));
	return BAYER[i.y * 4 + i.x] / 16.0 - 0.5;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 linear_to_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

// the Blender toon material: band brightness in perceptual space, keep the light's hue
vec3 toon_band(vec3 c) {
	vec3 lin = srgb_to_linear(c);
	float L = max(dot(lin, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
	float q = max(floor(pow(L, 0.45) / BAND) * BAND, BAND * 0.5);
	return linear_to_srgb(lin * pow(q, 1.0 / 0.45) / L);
}

int id_at(vec2 px) {
	return int(round(texture(mask_tex, px / SIZE).r * 255.0 / 12.0)) - ID_OFFSET;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233)) + noise_seed) * 43758.5453);
}

vec3 quantize(vec3 c) {
	vec3 best = palette[0];
	float bd = 1e9;
	for (int i = 0; i < 40; i++) {
		vec3 d = c - palette[i];
		float e = dot(d * d, WTS);
		if (e < bd) {
			bd = e;
			best = palette[i];
		}
	}
	return best;
}

void fragment() {
	vec2 pix = floor(UV * SIZE);              // integer pixel, like numpy's mgrid
	float x = pix.x, y = pix.y, f = frame;

	// heat haze displaces the scene and its mask together
	float near = exp(-dot(pix - window_px, pix - window_px) / (2.0 * 140.0 * 140.0));
	float env = heat * ((1.0 - heat_focus) + heat_focus * (0.35 + 0.65 * near));
	vec2 d = vec2(2.4 * env * sin(0.23 * y + 0.42 * f + 1.3 * sin(0.045 * x - 0.11 * f)),
	              0.9 * env * sin(0.19 * x + 0.31 * f + 0.7));
	vec2 src = pix + 0.5 + d;

	vec2 scene_uv = src / SIZE;
	vec3 px = texture(scene_tex, scene_uv).rgb;
	if (pause_amount > 0.001) {
		vec2 o = vec2(2.5 * pause_amount) / SIZE;
		vec3 blurred = px * 0.20;
		blurred += texture(scene_tex, scene_uv + vec2(o.x, 0.0)).rgb * 0.12;
		blurred += texture(scene_tex, scene_uv - vec2(o.x, 0.0)).rgb * 0.12;
		blurred += texture(scene_tex, scene_uv + vec2(0.0, o.y)).rgb * 0.12;
		blurred += texture(scene_tex, scene_uv - vec2(0.0, o.y)).rgb * 0.12;
		blurred += texture(scene_tex, scene_uv + o).rgb * 0.08;
		blurred += texture(scene_tex, scene_uv - o).rgb * 0.08;
		blurred += texture(scene_tex, scene_uv + vec2(o.x, -o.y)).rgb * 0.08;
		blurred += texture(scene_tex, scene_uv + vec2(-o.x, o.y)).rgb * 0.08;
		px = mix(px, blurred, pause_amount);
	}
	vec4 m = texture(mask_tex, src / SIZE);
	if (m.b > 0.5) {
		px = toon_band(px);
	}

	// colour punch
	float lum = dot(px, vec3(0.299, 0.587, 0.114));
	px = lum + (px - lum) * SATURATION;
	px = (px - 0.5) * CONTRAST + 0.5;

	if (heat > 0.005) {
		vec3 warm = px * vec3(1.16, 0.97, 0.80) + vec3(0.07, 0.025, -0.01);
		px = mix(px, warm, clamp(env, 0.0, 1.0));
		px += 0.30 * heat * min(shutter, 1.0) * near * near * vec3(1.0, 0.85, 0.6);
	}
	if (landing_amount > 0.001) {
		vec2 vp = (pix / SIZE - vec2(0.5)) * vec2(1.0, 0.72);
		float vignette = smoothstep(0.28, 0.60, length(vp));
		float breathe = 1.0 + 0.025 * sin(f * 0.035);
		float lightning = pow(max(sin(f * 0.019), 0.0), 32.0);
		px *= mix(1.0, breathe * (0.96 - 0.38 * vignette), landing_amount);
		px += landing_amount * lightning * vec3(0.10, 0.14, 0.20);
	}
	px *= brightness;
	px *= 1.0 - 0.55 * dim;
	px *= 1.0 - 0.38 * pause_amount;
	px *= 1.0 - fade;

	// living dither: Bayer locked to the world, nudged by a slow drifting field
	float wx = x + cam_px;
	float drift = DRIFT * sin(0.09 * wx + 0.05 * y + 0.21 * f) * sin(0.06 * y - 0.07 * wx + 0.13 * f + 1.3);
	float thr = bayer(vec2(wx, y)) * DITHER + drift + (hash(pix + floor(f)) - 0.5) * 0.010;

	int id = int(round(m.r * 255.0 / 12.0)) - ID_OFFSET;
	bool on_target = target_id > 0 && id == target_id;
	if (on_target) {
		float nearc = exp(-dot(pix - cursor, pix - cursor) / (2.0 * SHIMMER_RADIUS * SHIMMER_RADIUS));
		float area = nearc * build;
		thr = mix(thr, bayer(vec2(wx, y) + shimmer_off) * DITHER * 2.4, area);
		px *= 1.0 + 0.10 * area;
	}
	if (heat > 0.3) {                         // heat makes the dither boil a little
		thr += 0.012 * heat * sin(0.8 * x + 1.1 * y + 0.9 * f);
	}
	vec3 outc = quantize(px + thr);

	// thick white outline just outside the hovered object
	if (target_id > 0 && !on_target) {
		int r = outline_px;
		for (int dy = -r; dy <= r && !on_target; dy++) {
			for (int dx = -r; dx <= r; dx++) {
				if (dx * dx + dy * dy <= r * r + r && id_at(src + vec2(float(dx), float(dy))) == target_id) {
					outc = vec3(1.0);
					on_target = true;
					break;
				}
			}
		}
	}
	COLOR = vec4(outc, 1.0);
}
