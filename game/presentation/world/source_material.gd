extends RefCounted
## Tree tint math ported from shdrTree in the supplied shaders.group.bin.
## Textures and tint colors are source data; no replacement artwork is generated.
static var materials: Dictionary = {}
static var crop_materials: Dictionary = {}
static var source_light := Vector3(0.45,0.45,0.45)
static var source_ambient := Vector3(0.9,0.9,0.9)


static func crops(data: Dictionary) -> ShaderMaterial:
	var texture: Texture2D = data.get("texture_resource")
	var key := texture.resource_path if texture!=null else ""
	if crop_materials.has(key): return crop_materials[key]
	var material := ShaderMaterial.new()
	material.shader=preload("res://presentation/world/source_crops.gdshader")
	material.set_shader_parameter("original_texture",texture)
	material.set_shader_parameter("source_light",source_light)
	material.set_shader_parameter("source_ambient",source_ambient)
	crop_materials[key]=material
	return material


static func crop_lighting(light: Vector3,ambient: Vector3) -> void:
	source_light=light
	source_ambient=ambient
	for material: ShaderMaterial in crop_materials.values():
		material.set_shader_parameter("source_light",light)
		material.set_shader_parameter("source_ambient",ambient)


static func tree(data: Dictionary) -> ShaderMaterial:
	var texture: Texture2D = data.get("texture_resource")
	var key := texture.resource_path if texture != null else ""
	if materials.has(key): return materials[key]
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
#include "res://presentation/world/influence.gdshaderinc"
varying vec3 source_position;
void vertex() { source_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
uniform sampler2D source_texture : filter_linear, repeat_enable;
uniform vec4 tint1 : source_color;
uniform vec4 tint2 : source_color;
vec3 linearTint(float base, vec3 tintCol) {
    return (base < 0.5) ? tintCol * min(base * 2.0, 1.0)
        : 1.0 - ((1.0 - tintCol) * min((1.0 - base) * 2.0, 1.0));
}
void fragment() {
    vec4 diffMap = texture(source_texture, UV);
    vec3 tintOutput = mix(vec3(0.5), tint1.rgb, diffMap.g);
    tintOutput = mix(tintOutput, tint2.rgb, diffMap.b);
    ALBEDO = god_influence_color(linearTint(diffMap.r, tintOutput),source_position.xz);
    ROUGHNESS = 1.0;
}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("source_texture", data.get("texture_resource"))
	var palette: Image = (load("res://assets/extracted/sprites/colours_DNA.png") as Texture2D).get_image()
	material.set_shader_parameter("tint1", palette.get_pixel(10, 20))
	material.set_shader_parameter("tint2", palette.get_pixel(16, 20))
	materials[key] = material
	return material
