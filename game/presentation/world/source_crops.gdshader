shader_type spatial;
render_mode unshaded, cull_disabled;
// Healthy-crop branch of shaders.group.bin:shdrCropsGrain. Source texture alpha
// is the tint mask, not transparency. The palette and ripeness curve are original.
uniform sampler2D original_texture : filter_linear, repeat_enable;
uniform vec3 source_light = vec3(0.45);
uniform vec3 source_ambient = vec3(0.9);
#include "res://presentation/world/influence.gdshaderinc"
varying vec3 source_position;
varying vec3 source_normal;
varying float crop_progress;

vec3 linear_tint(float base, vec3 tint_color) {
    return base < 0.5 ? tint_color * min(base * 2.0, 1.0)
        : 1.0 - (1.0 - tint_color) * min((1.0 - base) * 2.0, 1.0);
}
vec3 srgb_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
void vertex() {
    source_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    source_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
    crop_progress = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
}
void fragment() {
    float ripeness = crop_progress * 0.3 + 0.7 * pow(crop_progress, 12.0);
    vec3 grain = mix(vec3(125.0, 163.0, 48.0), vec3(207.0, 168.0, 101.0), ripeness) / 255.0;
    vec3 pumpkin = mix(vec3(174.0, 175.0, 71.0), vec3(255.0, 138.0, 0.0), ripeness) / 255.0;
    vec3 ripe_color = mix(pumpkin, grain, step(UV.y, 2.0));
    vec4 original = texture(original_texture, UV);
    vec3 color = mix(original.rgb, linear_tint(original.g, ripe_color), original.a);
    float diffuse = clamp(dot(source_normal, normalize(vec3(-0.5, 0.8, 0.4))), 0.0, 1.0);
    color *= source_light * diffuse + source_ambient;
    color = god_influence_color(clamp(color, vec3(0.0), vec3(1.0)), source_position.xz);
    ALBEDO = OUTPUT_IS_SRGB ? color : srgb_linear(color);
}
