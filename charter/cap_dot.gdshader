shader_type canvas_item;

// 音符端点的圆形贴片：一层贴图 + 每实例颜色，避免每颗音符画 9 次 draw_circle。
// 贴图本身是白/黑/透明的灰度图，实例颜色只负责染色与整体透明度。
uniform sampler2D dot_tex : source_color, filter_linear_mipmap;

void fragment() {
	vec4 t = texture(dot_tex, UV);
	COLOR = vec4(COLOR.rgb * t.rgb, COLOR.a * t.a);
}
