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
uniform bool voyage_hazards_enabled = false;
uniform sampler2D voyage_hazards : filter_linear, repeat_disable;
uniform sampler2D blight_gradient : filter_linear, repeat_disable;
uniform float voyage_width = 1.0;
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
    float ao = 1.0 - 0.45 * pow(1.0 - fract(source_pos.y / layer_height),2.0);
    if(source_normal.y > 0.1) ao = 1.0;
    float diffuse = clamp(dot(source_normal, normalize(vec3(-0.5,0.8,0.4))),0.0,1.0);
    vec3 color = base * (source_light * diffuse + source_ambient * ao);
    color /= source_light * normalize(vec3(-0.5,0.8,0.4)).y + source_ambient;
    color = clamp(color, vec3(0.0), vec3(1.0));
    color = god_influence_color(color,source_pos.xz);
    ALBEDO = OUTPUT_IS_SRGB ? color : srgb_linear(color);
}
