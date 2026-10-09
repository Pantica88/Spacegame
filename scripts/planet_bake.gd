extends Resource
## Immutable render data saved with a planet. LOD 0 also supplies collision.
@export var signature := ""
@export var layers: Array[ArrayMesh] = []
@export var preview: ArrayMesh
@export var surface_texture: Texture2D
## Body-space normals (RGB) and normalized elevation (A), shared by every LOD.
@export var topography_texture: Texture2D
