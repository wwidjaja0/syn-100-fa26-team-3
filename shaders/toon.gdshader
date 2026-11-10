// Every surface in the room. Two jobs, picked by which camera is drawing:
//  * the world camera: plain lit Lambert (the post shader bands it into toon steps,
//    like the Blender material did), emissive bits, the inverted-hull outline, the sky;
//  * the mask camera (layer 20 in its cull mask): flat object id, Cryptomatte-style,
//    so the post shader knows what is under the cursor and where to draw the outline.
shader_type spatial;
render_mode specular_disabled, cull_back;

const uint MASK_LAYER = 524288u;      // 1 << 19, render layer 20
const int ID_OFFSET = 4;              // keep in step with post.gdshader and scripts/room/object_picker.gd

// 0 toon (lit), 1 emissive, 2 outline hull, 3 storm sky, 4 spinning globe screen (microfiche idle)
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

// globe screen: albedo_tex is a full equirectangular world map (lat 90..-90); the screen's
// world-space centre and size map each fragment to a point on it (see scripts/room/room_materials.gd)
uniform vec3 screen_center = vec3(0.0);
uniform vec2 screen_size = vec2(1.0);
uniform float globe_spin = 0.12;      // radians per second

uniform int group_id = 0;                // object group, written by the mask pass
uniform float direct_light = 1.0;        // < 1 on outlined props (PROP_DIRECT_LIGHT in scripts/room/room_materials.gd)
// Compatibility (the web renderer) reads ALBEDO/EMISSION as sRGB and linearises them itself,
// where Forward+ takes them linear. When true, colours are handed over sRGB-encoded so both
// renderers light the same values (see `compat` in scripts/main.gd).
uniform bool srgb_io = false;

varying vec3 local_pos;
varying vec3 world_pos;

void vertex() {
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

vec3 storm_sky() {
	// Blender: Object coords, scale 3.5, detail 6, distortion 2.5
	vec4 p = vec4(local_pos.x, local_pos.y, local_pos.z, sky_w) * 3.5;
	vec4 warp = vec4(fbm(p + 5.2), fbm(p + 1.3), fbm(p + 9.1), fbm(p + 3.7)) - 0.5;
	float n = fbm(p + warp * 2.5);
	vec3 day1 = ramp3(n, 0.35, vec3(0.03, 0.12, 0.40), 0.55, vec3(0.10, 0.42, 0.95), 0.75, vec3(0.80, 0.95, 1.0));
	vec3 day2 = ramp3(n, 0.30, vec3(0.04, 0.012, 0.012), 0.55, vec3(0.42, 0.10, 0.03), 0.80, vec3(1.0, 0.62, 0.25));
	return mix(day1, day2, sky_day2) * sky_energy;
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
	if ((CAMERA_VISIBLE_LAYERS & MASK_LAYER) != 0u) {
		// id in red: steps of 12 so rounding never confuses neighbours, offset by 4 steps because
		// Compatibility loses precision near black; toon flag in blue
		ALBEDO = vec3(0.0);
		// stored as-is in the 8-bit target, so pass the inverse of what the renderer will do to it
		vec3 id = vec3(float(group_id + ID_OFFSET) * 12.0 / 255.0, 0.0, kind == 0 ? 1.0 : 0.0);
		EMISSION = srgb_io ? id : srgb_to_linear(id);
	} else if (kind == 0) {
		ALBEDO = io(use_tex ? srgb_to_linear(texture(albedo_tex, UV).rgb) * albedo : albedo);
	} else if (kind == 3) {
		ALBEDO = vec3(0.0);
		EMISSION = io(storm_sky());
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
