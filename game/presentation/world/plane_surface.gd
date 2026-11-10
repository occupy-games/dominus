extends RefCounted
## Base-surface contract: coordinates, local tangent frame and world position.
## Only a plane is implemented. Other geographies must supply their own mapping.

var origin := Vector3.ZERO
var orientation := Basis.IDENTITY


func frame_at(uv: Vector2) -> Transform3D:
	return Transform3D(orientation, origin + orientation * Vector3(uv.x, 0, uv.y))


func coordinates(point: Vector3) -> Vector2:
	var local := orientation.inverse() * (point - origin)
	return Vector2(local.x, local.z)
