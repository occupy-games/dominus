shader_type spatial;
render_mode unshaded, cull_disabled;
// Source shdrImpostersWithDiscard: R is trunk, G is foliage, A is coverage.
#include "res://presentation/world/influence.gdshaderinc"
uniform sampler2D source_texture : filter_linear_mipmap;
uniform vec4 foliage_color : source_color;
uniform vec4 trunk_color : source_color;
varying vec3 source_position;
void vertex() {
    vec3 origin=(MODEL_MATRIX*vec4(0.0,0.0,0.0,1.0)).xyz;
    source_position=origin;
    vec3 right=INV_VIEW_MATRIX[0].xyz;
    vec3 up=INV_VIEW_MATRIX[1].xyz;
    vec2 size_=vec2(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz));
    vec3 world=origin+right*VERTEX.x*size_.x+up*VERTEX.y*size_.y;
    POSITION=PROJECTION_MATRIX*VIEW_MATRIX*vec4(world,1.0);
    UV=INSTANCE_CUSTOM.xy+UV*INSTANCE_CUSTOM.zw;
}
void fragment() {
    vec4 sample_=texture(source_texture,UV);
    if(sample_.a<0.65) discard;
    vec3 color=(trunk_color.rgb*sample_.r+foliage_color.rgb*sample_.g)*2.4;
    ALBEDO=god_influence_color(color*COLOR.rgb,source_position.xz);
}
