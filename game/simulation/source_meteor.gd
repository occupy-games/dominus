extends RefCounted
## Original Meteor Strike swipe, flight, crater and land field routines.

const Terrain = preload("res://simulation/source_terrain.gd")
const Fields = preload("res://simulation/source_map_fields.gd")


static func swipe(delta: Vector2,viewport: Vector2,seconds: float,rules: Dictionary) -> Dictionary:
	var span:=minf(viewport.x,viewport.y)
	var minimum:=Terrain.f32(span*float(rules["swipe_min"]))
	var maximum:=Terrain.f32(span*float(rules["swipe_max"]))
	if float(delta.x)*delta.x+float(delta.y)*delta.y<=minimum*minimum: return {}
	# The source takes atan2(horizontal, vertical), measured from screen down.
	var angle:=Terrain.f32(atan2(delta.x,delta.y)*float(rules["angle_scale"]))
	if angle<float(rules["angle_min"]) or angle>float(rules["angle_max"]): return {}
	var fastest: float=rules["max_time"]
	var slowest: float=rules["min_time"]
	var factor: float
	if float(rules["speed_from_length"])!=0.0:
		var length:=sqrt(float(delta.x)*delta.x+float(delta.y)*delta.y)
		var fraction:=clampf((length-minimum)/maxf(0.000001,maximum-minimum),0.0,1.0)
		factor=Terrain.f32(lerpf(slowest,fastest,fraction))
	else:
		factor=clampf((fastest-seconds)/(fastest-slowest),0.0,1.0)
	var speed:=Terrain.f32(lerpf(rules["min_speed"],rules["max_speed"],factor))
	return {"angle":angle,"speed":Terrain.f32(speed*float(rules["speed_scale"]))}


static func launch(point: Vector3,heading: Vector2,quote: Dictionary,rules: Dictionary) -> Dictionary:
	var angle:=Terrain.f32(float(quote["angle"])*float(rules["radians_per_degree"]))
	var facing:=heading.normalized()*sin(angle)
	var direction:=Vector3(facing.x,-cos(angle),facing.y).normalized()
	var speed: float=quote["speed"]
	var strength:=Terrain.f32(speed/(float(rules["max_speed"])*float(rules["speed_scale"])))
	strength=Terrain.f32(strength*float(rules["strength"]))
	var target:=point
	target.y+=Terrain.f32(strength*float(rules["depth_scale"])*Terrain.HEIGHT_SCALE)
	return {"position":components(target-direction*float(rules["distance"])),"target":components(target),
		"velocity":components(direction*speed),"strength":strength,"phase":"flight","blast":0.0,"hits":{}}


static func components(value: Vector3) -> Array:
	return [value.x,value.y,value.z]


static func vector(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])


static func advance(flight: Dictionary,ground_at: Callable,delta: float,rules: Dictionary) -> Dictionary:
	var velocity:=vector(flight["velocity"])
	var position:=vector(flight["position"])
	if flight["phase"]=="flight":
		position+=velocity*delta
		flight["position"]=components(position)
		var ground:=Terrain.f32(float(ground_at.call(position.x,position.z))+float(rules["ground_skin"]))
		var target:=vector(flight["target"])
		if (target-position).dot(velocity)>=0.0 and position.y>=ground:
			if position.y>=float(rules["sea_height"]): return {}
			flight["velocity"]=components(velocity*float(rules["water_slowdown"]))
			flight["phase"]="splash"
			return {"splash":position}
		if position.y<ground: target=Vector3(position.x,ground,position.z)
		target.y-=float(rules["impact_drop"])
		flight["target"]=components(target)
		flight["velocity"]=components(Vector3.ZERO)
		flight["phase"]="blast"
		return {"impact":target,"position":position}

	var outcome := {"wave":2.0*lerpf(rules["blast_size_start"],rules["blast_size_end"],minf(1.0,float(flight["blast"])/float(rules["blast_max"])))}
	if flight["phase"]=="splash":
		velocity.x*=float(rules["drag"])
		velocity.z*=float(rules["drag"])
		if position.y<float(rules["sea_height"]): velocity.y*=float(rules["water_drag"])
		var planar:=float(velocity.x)*velocity.x+float(velocity.z)*velocity.z
		if planar>float(rules["trail_squared"]): outcome["trail"]=position
		elif planar<float(rules["rest_squared"]): flight["phase"]="blast"
	position+=velocity*delta
	var above:=position.y-float(ground_at.call(position.x,position.z))-float(rules["ground_skin"])
	velocity.y=velocity.y-float(rules["gravity"])*delta if above>0.0 else 0.0
	flight["position"]=components(position)
	flight["velocity"]=components(velocity)
	flight["blast"]=Terrain.f32(float(flight["blast"])+float(rules["blast_speed"])*delta)
	outcome["finished"]=flight["phase"]=="blast" and float(flight["blast"])>float(rules["blast_max"]) and above<float(rules["end_height"])
	return outcome


static func crater(center: Vector3,radius: float,depth: float,width: int,rules: Dictionary,height_at: Callable,floor_at: Callable) -> Array:
	# 0x10143a80 lowers the absolute surface toward a paraboloid. Each
	# vertex is compared to its old raw height before rounding the write.
	var edits: Array=[]
	var radius_squared:=Terrain.f32(radius*radius)
	var base:=Terrain.f32(center.y/Terrain.HEIGHT_SCALE)
	var margin: float=rules["bounds_margin"]
	for z in range(maxi(0,int(center.z-radius)),mini(width-1,int(center.z+radius+margin))+1):
		var dz:=Terrain.f32(center.z-z)
		for x in range(maxi(0,int(center.x-radius)),mini(width-1,int(center.x+radius+margin))+1):
			var dx:=Terrain.f32(center.x-x)
			var squared:=Terrain.f32(dx*dx+dz*dz)
			if squared>=radius_squared: continue
			var offset:=Terrain.f32((1.0-squared/radius_squared)*depth)
			var target:=maxf(maxf(0.0,Terrain.f32(base+offset)),float(floor_at.call(x,z)))
			if target<float(height_at.call(x,z)):
				edits.append({"cell":z*width+x,"height":maxi(0,int(target)-19),"raw_height":int(target)})
	return edits


static func write_fields(raster: Dictionary,center: Vector3,radius: float,blight: float,width: int) -> void:
	var span:=int(radius+0.5)
	var cx:=int(center.x)
	var cz:=int(center.z)
	# The original unsigned bounds skip the entire field if a lower bound
	# wraps. The geometry routine has separate bounds and can reach the edge.
	if cx<span or cz<span: return
	for kind in [1,2]:
		var target:=0.0 if kind==1 else clampf(blight,0.0,1.0)
		for z in range(cz-span,mini(width,cz+span+1)):
			for x in range(cx-span,mini(width,cx+span+1)):
				var squared: int=(x-cx)*(x-cx)+(z-cz)*(z-cz)
				if squared>=span*span: continue
				var coverage:=minf(1.0,Terrain.f32(span-Terrain.f32(sqrt(squared))))
				var previous:=Fields.read(raster,kind,x,z)
				Fields.overwrite(raster,kind,x,z,Terrain.f32(lerpf(previous,target,coverage)))
