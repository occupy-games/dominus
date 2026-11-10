extends RefCounted
## Builds CPU mesh arrays from detached terrain data; safe for a worker thread.

const STEP := 0.3
const POLYGONS := [[], [[0,4,7]], [[4,1,5]], [[0,1,5,7]], [[5,2,6]],
	[[0,4,7],[5,2,6]], [[4,1,2,6]], [[0,1,2,6,7]], [[7,6,3]],
	[[0,4,6,3]], [[4,1,5],[7,6,3]], [[0,1,5,6,3]], [[7,5,2,3]],
	[[0,4,5,2,3]], [[4,1,2,3,7]], [[0,1,2,3]]]


static func build(state: Dictionary, view_region: Rect2i, colors: Array[Color], bevel_segments: int = 4, stride: int = 1) -> Array:
	var width: int = state["width"]
	var heights: Variant = state["terrain"]
	var center := (width - 1) * 0.5
	var region := Rect2i(0, 0, width-1, width-1)
	var output_region := region.intersection(view_region) if view_region.has_area() else region
	region = output_region.grow(stride).intersection(region)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces: Array = []
	var caps: Dictionary = {}
	var edge_normals := {}
	var edge_radii := {}
	for z in range(region.position.y, region.end.y, stride):
		for x in range(region.position.x, region.end.x, stride):
			var ex := mini(x+stride,width-1)
			var ez := mini(z+stride,width-1)
			var values := [float(heights[z*width+x]),float(heights[z*width+ex]),float(heights[ez*width+ex]),float(heights[ez*width+x])]
			var low := int(values.min())
			var high := int(values.max())
			# Buried terrace caps are invisible. Only the local height interval
			# contributes geometry, including on the original 1024-square map.
			for level in range(maxi(1, low), high+1):
				var threshold := level - 0.5
				var mask := 0
				var points := [Vector2(x-center,z-center),Vector2(ex-center,z-center),Vector2(ex-center,ez-center),Vector2(x-center,ez-center)]
				for i in range(4):
					if values[i] >= threshold: mask |= 1 << i
				if mask == 0: continue
				if mask==15 and output_region.has_point(Vector2i(x,z)):
					if not caps.has(level): caps[level]={}
					caps[level][z*width+x]=true
					continue
				for i in range(4):
					var j := (i+1)%4
					var weight := clampf((threshold-values[i])/(values[j]-values[i]),0,1) if values[j]!=values[i] else 0.5
					points.append(points[i].lerp(points[j],weight))
				var radius := minf(0.08,0.2/maxf(1,high-low))
				for polygon: Array in POLYGONS[mask]:
					if output_region.has_point(Vector2i(x,z)):
						faces.append({"points": points,"polygon": polygon,"level": level})
					for i in range(polygon.size()):
						var a: int = polygon[i]
						var b: int = polygon[(i+1)%polygon.size()]
						if a < 4 or b < 4: continue
						var edge: Vector2 = points[b]-points[a]
						var normal := Vector3(edge.y,0,-edge.x).normalized()
						for index: int in [a,b]:
							var key := edge_key(points[index],level)
							edge_normals[key] = edge_normals.get(key,Vector3.ZERO)+normal
							edge_radii[key] = minf(edge_radii.get(key,radius),radius)
	# Greedy coplanar caps retain the same terrace boundary and source colors,
	# avoiding thousands of redundant quads on flat land.
	for level: int in caps:
		var cells: Dictionary=caps[level]
		var color: Color=colors[mini(level-1,colors.size()-1)] if not colors.is_empty() else Color.WHITE
		for z in range(output_region.position.y,output_region.end.y,stride):
			var x: int=output_region.position.x
			while x<output_region.end.x:
				if not cells.has(z*width+x): x+=stride; continue
				var end_x := x+stride
				while end_x<output_region.end.x and cells.has(z*width+end_x): end_x+=stride
				var end_z := z+stride
				while end_z<output_region.end.y:
					var full := true
					for cx in range(x,end_x,stride):
						if not cells.has(end_z*width+cx): full=false; break
					if not full: break
					end_z+=stride
				for cz in range(z,end_z,stride):
					for cx in range(x,end_x,stride): cells.erase(cz*width+cx)
				var quad := [Vector2(x-center,z-center),Vector2(mini(end_x,width-1)-center,z-center),Vector2(mini(end_x,width-1)-center,mini(end_z,width-1)-center),Vector2(x-center,mini(end_z,width-1)-center)]
				for corner: int in [0,1,2,0,2,3]: _vertex(surface,quad[corner],level*STEP,Vector3.UP,color)
				x=end_x
	for face: Dictionary in faces:
		var points: Array = face["points"]
		var polygon: Array = face["polygon"]
		var level: int = face["level"]
		var color: Color = colors[mini(level-1,colors.size()-1)] if not colors.is_empty() else Color.WHITE
		for i in range(1,polygon.size()-1):
			for index: int in [polygon[0],polygon[i],polygon[i+1]]:
				var point: Vector2 = points[index]
				if index >= 4:
					var key := edge_key(point,level)
					var normal: Vector3 = edge_normals.get(key,Vector3.ZERO).normalized()
					point -= Vector2(normal.x,normal.z)*edge_radii.get(key,0.0)
				_vertex(surface,point,level*STEP,Vector3.UP,color)
		for i in range(polygon.size()):
			var a: int = polygon[i]
			var b: int = polygon[(i+1)%polygon.size()]
			if a < 4 or b < 4: continue
			var rings: Array = []
			for segment in range(bevel_segments+1):
				var theta := segment*PI/(2*bevel_segments)
				var ring: Array = []
				for index: int in [a,b]:
					var point: Vector2 = points[index]
					var key := edge_key(point,level)
					var normal: Vector3 = edge_normals[key].normalized()
					var radius: float = edge_radii[key]
					ring.append({"point":point-Vector2(normal.x,normal.z)*radius*(1-sin(theta)),"height":level*STEP-radius*(1-cos(theta)),"normal":Vector3.UP*cos(theta)+normal*sin(theta)})
				rings.append(ring)
			var bottom: Array = []
			for index: int in [a,b]:
				bottom.append({"point":points[index],"height":(level-1)*STEP,"normal":edge_normals[edge_key(points[index],level)].normalized()})
			rings.append(bottom)
			for ring in range(rings.size()-1):
				for pair in [Vector2i(ring,0),Vector2i(ring,1),Vector2i(ring+1,1),Vector2i(ring,0),Vector2i(ring+1,1),Vector2i(ring+1,0)]:
					var vertex: Dictionary = rings[pair.x][pair.y]
					_vertex(surface,vertex["point"],vertex["height"],vertex["normal"],color)
	return surface.commit_to_arrays() if not faces.is_empty() or not caps.is_empty() else []


static func edge_key(point: Vector2, level: int) -> Vector3i:
	return Vector3i(roundi(point.x*10000),level,roundi(point.y*10000))


static func _vertex(surface: SurfaceTool, point: Vector2, height: float, normal: Vector3, color: Color) -> void:
	surface.set_normal(normal)
	surface.set_color(color)
	surface.set_uv(point)
	surface.add_vertex(Vector3(point.x,height,point.y))
