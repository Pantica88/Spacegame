extends Resource
## Recorded landing collapse of the parachute cloth and cap tether, in their
## own local spaces. Baked by tools/bake_chute_collapse.gd from the real cloth
## simulation so landings replay it instead of simulating while it fades.
@export var frame_seconds := 1.0 / 30.0
@export var canopy_frames: Array[PackedVector3Array] = []
@export var rope_frames: Array[PackedVector3Array] = []

func duration() -> float:
	return frame_seconds * maxi(canopy_frames.size() - 1, 0)

## Linearly interpolated frame at a time from touchdown.
static func sample(frames: Array[PackedVector3Array], frame_seconds: float, time: float) -> PackedVector3Array:
	var position := clampf(time / frame_seconds, 0.0, frames.size() - 1.0)
	var index := mini(int(position), frames.size() - 2)
	var weight := position - index
	var a: PackedVector3Array = frames[index]
	var b: PackedVector3Array = frames[index + 1]
	var result := PackedVector3Array()
	result.resize(a.size())
	for i in range(a.size()):
		result[i] = a[i].lerp(b[i], weight)
	return result
