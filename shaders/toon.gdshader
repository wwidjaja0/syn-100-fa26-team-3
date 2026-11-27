// Every surface in the room. Two jobs, picked by which camera is drawing:
//  * the world camera: plain lit Lambert (the post shader bands it into toon steps,
//    like the Blender material did), emissive bits, the inverted-hull outline, the sky;
//  * the mask camera (layer 20 in its cull mask): flat object id, Cryptomatte-style,
//    so the post shader knows what is under the cursor and where to draw the outline.
shader_type spatial;
render_mode specular_disabled, cull_back, depth_prepass_alpha;

const uint MASK_LAYER = 524288u;      // 1 << 19, render layer 20
const int ID_OFFSET = 4;              // keep in step with post.gdshader and scripts/room/object_picker.gd
const float ID_STEP = 8.0;            // ids are (id + ID_OFFSET) * ID_STEP / 255: room for 27 groups

// geometry about to cross the near plane dissolves with the same 4x4 Bayer the post pass uses,
// instead of slicing off on a hard line. The close-up swing stays under the ceiling
// (scripts/views/close_view.gd); this catches whatever the lens still meets. Both the beauty and
// the mask pass discard the same pixels, so the id under a hole is whatever is behind it.
// The band sits just outside the cameras' near plane (0.05). Anything merely near the framing,
// like a rafter the swing passes under, stays solid. The mat is 2m below and the radio panel
// is 1.2m away, so a settled close-up never reaches it.
const float NEAR_FADE_IN = 0.07;
const float NEAR_FADE_OUT = 0.16;
const float BAYER[16] = float[](0., 8., 2., 10., 12., 4., 14., 6., 3., 11., 1., 9., 15., 7., 13., 5.);

// 0 toon (lit), 1 emissive, 2 outline hull, 3 the window: the view outside under its weather,
// 4 spinning globe screen (microfiche idle)
uniform int kind = 0;
uniform vec3 albedo = vec3(0.8);      // linear, straight from Blender
uniform bool use_tex = false;
// no source_color: decoded by hand below, because Compatibility (web) skips that decode
uniform sampler2D albedo_tex : filter_linear_mipmap, hint_default_white;
uniform vec3 emission = vec3(0.0);
uniform float emission_energy = 1.0;

// storm sky: Blender noise -> two colour ramps (day 1 blue, day 2 bruised orange)
uniform float sky_w = 0.0;            // animated 4th noise dimension
uniform float sky_day2 = 0.0;
uniform float sky_energy = 2.5;

// the view out of the window (pipeline/scene/make_window_view.py): a cylindrical panorama from the
// cabin's summit, sky transparent, alpha = how much shows through the haze, plus a depth image
// (log distance, ground height, water). The room camera is orthographic, so the panorama is looked
// into from the camera's position as a virtual eye, angles scaled up by view_zoom: panning the
// room swings the view like looking out of a real window. Set up by scripts/room/room_materials.gd.
uniform bool use_view = false;
uniform sampler2D window_view : filter_linear, repeat_disable, hint_default_transparent;
uniform sampler2D window_depth : filter_linear, repeat_disable, hint_default_white;
uniform vec3 view_window = vec3(0.0);  // the window's centre (world)
uniform float view_zoom = 3.5;
uniform float view_yaw = 0.0;          // radians added after zooming (+ is right, towards the sea)
uniform float view_pitch = -0.1;       // radians: where the window's centre looks
uniform vec3 view_frame = vec3(2.79, 0.349, -0.611);   // the panorama: across, top, bottom (radians)
uniform vec3 view_depth = vec3(15.0, 120000.0, 1000.0); // depth image: near, far (m), top height (m)
uniform float view_haze = 0.5;        // the storm haze's brightness, as a share of the sky's
uniform float view_haze_m = 30000.0;  // the distance the panorama's alpha was hazed over

// the weather outside (scripts/room/weather.gd blends these between its presets). All colours linear.
uniform float w_cover = 1.0;          // cloud cover 0..1
uniform float w_storm = 1.0;          // 1: the clouds are the storm's (blue / orange ramp), 0: plain w_cloud
uniform vec3 w_cloud = vec3(0.3);     // plain clouds' colour
uniform vec3 w_sky_top = vec3(0.1, 0.3, 0.8);   // the clear sky, up high...
uniform vec3 w_sky_low = vec3(0.5, 0.7, 0.9);   // ... and at the horizon
uniform float w_vis = 30000.0;        // m: the haze takes ~63% over this
uniform vec3 w_haze = vec3(0.3);      // the haze's colour (blended with the storm's middle by w_storm)
uniform vec3 w_land = vec3(1.0);      // light on the land and sea
uniform float w_fog = 0.0;            // marine layer 0..1: a sea of cloud below the summit
uniform float w_fog_top = 350.0;      // m: its top
uniform vec3 w_fog_col = vec3(0.7);
uniform float w_rain = 0.0;           // rain streaks down the glass 0..1
uniform float w_flash = 0.0;          // lightning 0..1, this frame

// globe screen: albedo_tex is a full equirectangular world map (lat 90..-90); the screen's
// world-space centre and size map each fragment to a point on it (see scripts/room/room_materials.gd)
uniform vec3 screen_center = vec3(0.0);
uniform vec2 screen_size = vec2(1.0);
uniform float globe_spin = 0.12;      // radians per second

uniform bool status_light = false;       // an LED: the post shader may use its LED colours here
uniform int group_id = 0;                // object group, written by the mask pass
uniform float direct_light = 1.0;        // < 1 on outlined props (PROP_DIRECT_LIGHT in scripts/room/room_materials.gd)
// Compatibility (the web renderer) reads ALBEDO/EMISSION as sRGB and linearises them itself,
// where Forward+ takes them linear. When true, colours are handed over sRGB-encoded so both
// renderers light the same values (see `compat` in scripts/main.gd).
uniform bool srgb_io = false;

// outline hulls (kind 2): scripts/room/room_materials.gd moves each shell vertex back onto its part
// and keeps the push in NORMAL (direction) and UV2.x (metres), so the push is redone here, scaled.
// The room view pushes the full amount (outline_scale 1). A close-up magnifies the room; there the
// shell shrinks with the zoom, so its rim stays about as wide on screen as in the room. It is never
// thinner than outline_min_px pixels (outline_px_m metres each), so it doesn't break up.
uniform float outline_scale = 1.0;
uniform float outline_px_m = 0.0;
uniform float outline_min_px = 1.0;

varying vec3 local_pos;
varying vec3 world_pos;

void vertex() {
	if (kind == 2 && UV2.x > 0.0) {
		float w = min(UV2.x, max(UV2.x * outline_scale, outline_px_m * outline_min_px));
		VERTEX += NORMAL * w;
	}
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 linear_to_srgb(vec3 c) {
	c = max(c, vec3(0.0));               // no upper clamp: emission goes past 1
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

// a linear colour, in whatever space this renderer wants ALBEDO / EMISSION in
vec3 io(vec3 c) {
	return srgb_io ? linear_to_srgb(c) : c;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// --- 4D-ish value noise fbm standing in for Blender's Noise Texture
float hash(vec4 p) {
	p = fract(p * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p += dot(p, p.wzxy + 33.33);
	return fract((p.x + p.y) * (p.z + p.w));
}

float vnoise(vec4 p) {
	vec4 i = floor(p);
	vec4 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float acc = 0.0;
	for (int k = 0; k < 16; k++) {
		vec4 o = vec4(float(k & 1), float((k >> 1) & 1), float((k >> 2) & 1), float((k >> 3) & 1));
		vec4 w = mix(1.0 - f, f, o);
		acc += hash(i + o) * w.x * w.y * w.z * w.w;
	}
	return acc;
}

float fbm(vec4 p) {
	float a = 0.5, s = 0.0, n = 0.0;
	for (int o = 0; o < 6; o++) {
		s += a * vnoise(p);
		n += a;
		p = p * 2.0 + 17.0;
		a *= 0.5;
	}
	return s / n;
}

vec3 ramp3(float t, float p0, vec3 c0, float p1, vec3 c1, float p2, vec3 c2) {
	if (t < p1) return mix(c0, c1, clamp((t - p0) / (p1 - p0), 0.0, 1.0));
	return mix(c1, c2, clamp((t - p1) / (p2 - p1), 0.0, 1.0));
}

// the storm's colour at noise value n
vec3 storm_ramp(float n) {
	vec3 day1 = ramp3(n, 0.35, vec3(0.03, 0.12, 0.40), 0.55, vec3(0.10, 0.42, 0.95), 0.75, vec3(0.80, 0.95, 1.0));
	vec3 day2 = ramp3(n, 0.30, vec3(0.04, 0.012, 0.012), 0.55, vec3(0.42, 0.10, 0.03), 0.80, vec3(1.0, 0.62, 0.25));
	return mix(day1, day2, sky_day2) * sky_energy;
}

// the cloud noise behind the window. Blender: Object coords, scale 3.5, detail 6, distortion 2.5
float sky_noise() {
	vec4 p = vec4(local_pos.x, local_pos.y, local_pos.z, sky_w) * 3.5;
	vec4 warp = vec4(fbm(p + 5.2), fbm(p + 1.3), fbm(p + 9.1), fbm(p + 3.7)) - 0.5;
	return fbm(p + warp * 2.5);
}

vec3 storm_sky() {
	return storm_ramp(sky_noise());
}

// the sky for the weather: a clear gradient (h: 0 at the horizon, 1 high up) under clouds
vec3 weather_sky(float n, float h) {
	vec3 clear = mix(w_sky_low, w_sky_top, sqrt(clamp(h, 0.0, 1.0)));
	vec3 grey = w_cloud * (0.55 + 1.1 * clamp((n - 0.3) / 0.4, 0.0, 1.0));
	vec3 cloud = mix(grey, storm_ramp(n), w_storm);
	float nn = clamp((n - 0.32) / 0.36, 0.0, 1.0);
	float mask = w_cover >= 0.99 ? 1.0 : smoothstep(1.0 - w_cover - 0.12, 1.0 - w_cover + 0.12, nn);
	return mix(clear, cloud, mask);
}

// the view through the window for this fragment, with its weather
vec3 window_view_col(vec3 cam) {
	vec3 d = world_pos - cam;
	vec3 c = view_window - cam;
	float yaw = atan(d.x, -d.z) * view_zoom + view_yaw;
	float pitch = view_pitch + (atan(d.y, length(d.xz)) - atan(c.y, length(c.xz))) * view_zoom;
	vec2 uv = clamp(vec2(0.5 + yaw / view_frame.x, (view_frame.y - pitch) / (view_frame.y - view_frame.z)), vec2(0.0), vec2(1.0));
	vec4 v = texture(window_view, uv);
	float n = sky_noise();
	vec3 sky = weather_sky(n, pitch / view_frame.y);
	if (v.a > 0.0) {
		vec3 dep = texture(window_depth, uv).rgb;
		float dist = view_depth.x * pow(view_depth.y / view_depth.x, dep.r);
		float height = dep.g * view_depth.z;
		// day 2's heat turns the land the colour of its sky
		vec3 land = srgb_to_linear(v.rgb) * w_land * mix(vec3(1.0), vec3(1.5, 0.7, 0.45), sky_day2);
		// the marine layer: everything below its billowing top, past the summit's own slopes
		float billow = (vnoise(vec4(uv * vec2(90.0, 30.0), sky_w * 0.6, 0.0)) - 0.5) * 70.0;
		float fog = w_fog * smoothstep(w_fog_top + billow + 12.0, w_fog_top + billow - 12.0, height)
				* smoothstep(250.0, 600.0, dist);
		// lumpy tops: bright crowns, shadowed troughs, finer near the window
		float lump = vnoise(vec4(uv * vec2(70.0, 22.0), sky_w * 0.8, 3.0)) * 0.65 + vnoise(vec4(uv * vec2(220.0, 70.0), sky_w, 5.0)) * 0.35;
		vec3 fog_col = w_fog_col * (0.45 + 0.95 * lump);
		land = mix(land, fog_col, fog);
		// the haze, as thick as the weather makes it (the panorama's alpha is exp(-d / view_haze_m))
		float a = pow(v.a, view_haze_m / w_vis);
		vec3 haze = mix(w_haze, storm_ramp(0.5) * view_haze, w_storm);
		sky = mix(haze, land, max(a, fog * exp(-dist / (w_vis * 3.0))));
	}
	sky += w_flash * vec3(1.6, 1.7, 2.0);
	// rain: 1 px streaks running down the glass, a little slanted, in world pixels on the window
	if (w_rain > 0.0) {
		vec2 q = world_pos.xy * 72.7;
		float col = floor(q.x + q.y * 0.2);
		float h1 = fract(sin(col * 12.9898) * 43758.5453);
		float h2 = fract(sin(col * 78.233) * 12543.1234);
		float fall = q.y + TIME * (90.0 + 60.0 * h2) + h2 * 300.0;
		float streak = step(1.0 - 0.55 * w_rain, h1) * step(fract(fall / (24.0 + 30.0 * h1)), 0.16);
		sky = mix(sky, vec3(0.55, 0.65, 0.75) * sky_energy * 0.35, streak * 0.6);
	}
	return sky;
}

// an orthographic globe filling 84% of the screen's height, tilted 20 degrees, slowly turning
vec3 globe_screen(float t) {
	vec2 uv = vec2((world_pos.x - screen_center.x) / screen_size.x, (screen_center.y - world_pos.y) / screen_size.y);
	vec2 p = uv * vec2(screen_size.x / screen_size.y, 1.0) * 2.0 / 0.84;
	float r2 = dot(p, p);
	float scan = 0.85 + 0.15 * step(0.5, fract(uv.y * 40.0));
	vec3 col = vec3(0.010, 0.035, 0.045) * scan;
	if (r2 < 1.0) {
		vec3 n = vec3(p.x, -p.y, sqrt(1.0 - r2));
		float tilt = 0.35;
		n = vec3(n.x, n.y * cos(tilt) - n.z * sin(tilt), n.y * sin(tilt) + n.z * cos(tilt));
		float lon = atan(n.x, n.z) + t * globe_spin;
		float lat = asin(clamp(n.y, -1.0, 1.0));
		vec3 c = srgb_to_linear(texture(albedo_tex, vec2(fract(lon / TAU + 0.5), 0.5 - lat / PI)).rgb);
		col = c * (0.35 + 0.65 * sqrt(1.0 - r2)) * scan;
	}
	col += vec3(0.05, 0.25, 0.30) * smoothstep(0.06, 0.0, abs(sqrt(r2) - 1.0));   // atmosphere rim
	return col;
}

void fragment() {
	// alpha scissor (not a bare discard) so the depth prepass drops the same pixels and the
	// room behind a dissolving rafter or cord actually shows through
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA = 1.0;
	float depth = -VERTEX.z;
	if (depth < NEAR_FADE_OUT) {
		ivec2 cell = ivec2(mod(floor(FRAGCOORD.xy), 4.0));
		if (smoothstep(NEAR_FADE_IN, NEAR_FADE_OUT, depth) < BAYER[cell.y * 4 + cell.x] / 16.0)
			ALPHA = 0.0;
	}
	if ((CAMERA_VISIBLE_LAYERS & MASK_LAYER) != 0u) {
		// id in red: steps of 12 so rounding never confuses neighbours, offset by 4 steps because
		// Compatibility loses precision near black; status-light flag in green, toon flag in blue
		ALBEDO = vec3(0.0);
		// stored as-is in the 8-bit target, so pass the inverse of what the renderer will do to it
		vec3 id = vec3(float(group_id + ID_OFFSET) * ID_STEP / 255.0, status_light ? 1.0 : 0.0, kind == 0 ? 1.0 : 0.0);
		EMISSION = srgb_io ? id : srgb_to_linear(id);
	} else if (kind == 0) {
		ALBEDO = io(use_tex ? srgb_to_linear(texture(albedo_tex, UV).rgb) * albedo : albedo);
	} else if (kind == 3) {
		ALBEDO = vec3(0.0);
		EMISSION = io(use_view ? window_view_col(CAMERA_POSITION_WORLD) : storm_sky());
	} else if (kind == 4) {
		ALBEDO = vec3(0.0);
		EMISSION = io(globe_screen(TIME) * emission_energy);
	} else {
		ALBEDO = vec3(0.0);
		EMISSION = io(emission * emission_energy);
	}
}

void light() {
	// Lambert (LIGHT_COLOR carries energy * PI), dimmed on outlined props
	DIFFUSE_LIGHT += direct_light * max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR / PI;
}
