shader_type spatial;
render_mode unshaded, cull_disabled;
// Smooth terrain treatment matched to the original 2.4 reference. Original palette
// and cliff-lighting branch; no diffuse grain or repeating surface texture.
uniform sampler2D palette : filter_nearest;
uniform bool use_vertex_color = false;
uniform vec2 palette_pixel = vec2(54.0, 41.0);
uniform vec3 source_light = vec3(0.45);
uniform vec3 source_ambient = vec3(0.9);
uniform float layer_height = 0.3;
uniform bool beautify_enabled = false;
uniform sampler2D beauty_field : filter_linear, repeat_disable;
uniform sampler2D beautify_detail : filter_linear, repeat_enable;
uniform float beauty_width = 1.0;
uniform bool voyage_hazards_enabled = false;
uniform sampler2D voyage_hazards : filter_linear, repeat_disable;
uniform sampler2D blight_gradient : filter_linear, repeat_disable;
uniform float voyage_width = 1.0;
uniform bool blight_enabled = false;
uniform sampler2D blight_field : filter_linear, repeat_disable;
uniform float blight_width = 1.0;
#include "res://presentation/world/influence.gdshaderinc"
varying vec3 source_pos;
varying vec3 source_normal;
vec3 srgb_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void vertex() {
    source_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    source_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}
void fragment() {
    vec3 base = use_vertex_color ? COLOR.rgb : texture(palette, (palette_pixel + 0.5) / 128.0).rgb;
    if (voyage_hazards_enabled) {
        vec2 field_uv = (source_pos.xz + (voyage_width - 1.0) * 0.5 + 0.5) / voyage_width;
        vec3 fields = texture(voyage_hazards, field_uv).rgb;
        vec3 blighted = texture(blight_gradient, vec2(max(fields.r, fields.g), 0.5)).rgb;
        base = mix(base, blighted, max(fields.r, fields.g));
        base = mix(base, texture(palette, (vec2(2.0,38.0)+0.5)/128.0).rgb, fields.b);
    }
    if (blight_enabled) {
        vec2 field_uv = (source_pos.xz + blight_width * 0.5) / blight_width;
        float blight = min(1.0, texture(blight_field, field_uv).r * (255.0 / 128.0));
        base = mix(base, texture(blight_gradient, vec2(blight, 0.5)).rgb, blight);
    }
    if (beautify_enabled) {
        vec2 grid = source_pos.xz + (beauty_width - 1.0) * 0.5;
        float beauty = texture(beauty_field, (grid + 0.5) / beauty_width).r;
        if (beauty > 0.0 && god_influence(source_pos.xz) >= 0.5) {
            // shdrTerrain50 uses GemDiffuse in sampler 3 for both masks.
            float phase = mod(TIME,256.0);
            vec2 crack_uv = grid * 0.25;
            vec2 moving_uv = crack_uv + vec2(phase * 0.5, phase * 0.25);
            vec3 mask = texture(beautify_detail, crack_uv * 0.5).rgb;
            vec3 moving_mask = texture(beautify_detail, moving_uv * 0.625).rgb;
            float reveal = mask.g - 0.25 + moving_mask.b * 0.2;
            reveal *= (clamp(mask.b,0.2,0.4) - 0.2) * 5.0;
            float dots = smoothstep(0.5,1.0,reveal * (moving_mask.b * 2.0)) * source_normal.y;
            vec3 saturated = mix(base,vec3(dot(base,vec3(0.3,0.59,0.11))),-0.3);
            base = mix(base,saturated,dots) + dots * 0.5;
        }
    }
    float ao = 1.0 - 0.45 * pow(1.0 - fract(source_pos.y / layer_height),2.0);
    if(source_normal.y > 0.1) ao = 1.0;
    float diffuse = clamp(dot(source_normal, normalize(vec3(-0.5,0.8,0.4))),0.0,1.0);
    vec3 color = base * (source_light * diffuse + source_ambient * ao);
    color /= source_light * normalize(vec3(-0.5,0.8,0.4)).y + source_ambient;
    color = clamp(color, vec3(0.0), vec3(1.0));
    color = god_influence_color(color,source_pos.xz);
    ALBEDO = OUTPUT_IS_SRGB ? color : srgb_linear(color);
}
