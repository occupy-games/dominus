// Original shdrSeabed50 flow/caustics plus shdrSeaSimple surface glints.
uniform sampler2D ocean : repeat_enable, filter_linear_mipmap;
uniform sampler2D palette : filter_nearest;
uniform float opacity = 1.0;
uniform float depth = 0.7;
uniform bool use_terrain_depth = false;
uniform sampler2D terrain_field : filter_linear, repeat_disable;
uniform float terrain_width = 1024.0;
#include "res://presentation/world/influence.gdshaderinc"
varying vec2 world_uv;
varying vec4 water_times;
vec3 srgb_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
float edge_thresh(float base, float intensity, float m) {
    return clamp((base-intensity+m)/(m+m),0.0,1.0);
}
void vertex() {
    world_uv = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
    float t=mod(TIME,256.0);
    water_times=vec4(t,abs(mod(t/5.33333*2.0,2.0)-1.0),mod(t,5.33333),mod(t+5.33333/2.0,5.33333));
}
void fragment() {
    float t = water_times.x;
    float flow_alpha = water_times.y;
    vec2 flow = vec2(-0.7,0.7);
    vec3 a = texture(ocean, (world_uv + flow * water_times.z) * 0.18).rgb;
    vec3 b = texture(ocean, (world_uv + flow * water_times.w) * 0.18).rgb;
    vec3 flowmap = mix(a,b,flow_alpha);
    vec3 shallow = texture(palette, (vec2(10.0,45.0)+0.5)/128.0).rgb;
    vec3 deep = texture(palette, (vec2(10.0,50.0)+0.5)/128.0).rgb;
    float edge_distance = min(min(UV.x,1.0-UV.x),min(UV.y,1.0-UV.y));
    float sea = mix(0.4, depth, smoothstep(0.0,0.18,edge_distance));
    vec3 base = mix(shallow,deep,sea);
    float height = 0.0;
    if (use_terrain_depth) {
        height = texture(terrain_field,(world_uv+vec2(terrain_width*0.5))/terrain_width).r*255.0;
        float row = clamp(63.0-height,44.0,63.0);
        base = texture(palette,(vec2(10.0,row)+0.5)/128.0).rgb;
        sea = clamp((19.0-height)/14.0,0.05,1.0);
    }
    float caustic = flowmap.b * 3.5 * max(0.0, -sea*sea*0.5+sea*1.125-0.4);
    base = min(base / max(vec3(0.01), vec3(1.0-caustic)),vec3(1.0));
    if (use_terrain_depth) {
        float shelf = smoothstep(0.78,1.0,fract(height));
        base *= 1.0-shelf*0.16*(1.0-sea);
    }
    float footprint=max(length(dFdx(world_uv)),length(dFdy(world_uv)));
    float glint=0.0;
    if(footprint<0.8) {
        float raw1=texture(ocean,world_uv*0.1+vec2(0.125,-0.0625)*t).a*0.75;
        float raw2=texture(ocean,world_uv*0.12+vec2(-0.125,0.0625)*t).a*0.75;
        glint=edge_thresh((raw1+raw2)*0.99,1.18,0.16)*2.75;
        glint+=edge_thresh((raw1+raw2)*0.99,1.19,0.5)*0.2;
        glint*=1.0-smoothstep(0.15,0.8,footprint);
    }
    base += vec3(0.8,0.9,1.0)*glint;
    base = clamp(base,vec3(0.0),vec3(1.0));
    base = god_influence_color(base,world_uv);
    ALBEDO = OUTPUT_IS_SRGB ? base : srgb_linear(base);
    #ifdef GODUS_TRANSLUCENT
    ALPHA = opacity;
    #endif
}
