global uniform bool god_influence_enabled;
global uniform vec4 god_influence_bounds;
global uniform sampler2D god_influence_regions : filter_nearest, repeat_disable;
global uniform int god_influence_count;
global uniform float god_world_center;
global uniform vec3 god_out_of_range;
float god_influence(vec2 position) {
    if (!god_influence_enabled) return 1.0;
    vec2 point=position+vec2(god_world_center);
    if(point.x<god_influence_bounds.x || point.y<god_influence_bounds.y || point.x>god_influence_bounds.z || point.y>god_influence_bounds.w) return 0.0;
    float edge=100000.0;
    for(int i=0;i<32;i++) {
        if(i>=god_influence_count) break;
        vec4 area=texelFetch(god_influence_regions,ivec2(i,0),0);
        edge=min(edge,distance(point,area.xy)-area.z);
    }
    return 1.0-smoothstep(-0.35,0.0,edge);
}
vec3 god_influence_color(vec3 color,vec2 position) {
    float shade=dot(color,vec3(0.2126,0.7152,0.0722));
    vec3 grey=god_out_of_range*clamp(shade/0.72,0.3,1.15);
    return mix(grey,color,god_influence(position));
}
