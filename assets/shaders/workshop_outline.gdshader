shader_type spatial;
render_mode unshaded, cull_front;
#include "res://assets/shaders/renderer_color.gdshaderinc"
uniform vec4 edge_color : source_color = vec4(0.2, 1.0, 0.72, 0.92);
uniform float width = 0.045;
void vertex() {
	float camera_scale = clamp(abs((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z) * 0.055, 1.0, 3.2);
	VERTEX += NORMAL * width * camera_scale;
}
void fragment() {
	ALBEDO = authored_color(edge_color.rgb);
	ALPHA = edge_color.a;
	ALBEDO = material_output(ALBEDO);
}
