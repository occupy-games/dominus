shader_type spatial;
render_mode cull_disabled;
// Original texture, one opaque pass. Colored and out-of-range pixels share depth.
#include "res://presentation/world/influence.gdshaderinc"
uniform sampler2D original_texture : source_color, filter_linear_mipmap;
uniform bool alpha_scissor = false;
varying vec3 source_world_position;
void vertex() { source_world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec4 source=texture(original_texture,UV);
    if(alpha_scissor && source.a<0.5) discard;
    float influence=god_influence(source_world_position.xz);
    float shade=dot(source.rgb,vec3(0.2126,0.7152,0.0722));
    float light=0.35+0.65*max(dot(normalize(NORMAL),normalize(vec3(-0.5,0.8,0.4))),0.0);
    ALBEDO=source.rgb*influence;
    EMISSION=god_out_of_range*clamp(shade*light/0.72,0.25,1.15)*(1.0-influence);
    ROUGHNESS=1.0;
}
