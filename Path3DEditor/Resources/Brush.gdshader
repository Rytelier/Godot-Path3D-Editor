shader_type spatial;
render_mode wireframe, unshaded, cull_disabled, shadows_disabled;

uniform vec4 color : source_color;

void fragment() {
	ALBEDO = color.rgb;
}
 