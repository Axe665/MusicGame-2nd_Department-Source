shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// 判定环的实体底盘。UV.y: 0 = 外缘, 1 = 内缘。
// 中间是深色带体，内外各一条 1px 高光，边缘用 fwidth 抗锯齿——环看起来像一段有厚度的轨道。
uniform vec4 body_color : source_color = vec4(0.03, 0.04, 0.06, 0.55);
uniform vec4 rim_color : source_color = vec4(0.85, 0.92, 0.95, 0.55);
uniform float rim_pos : hint_range(0.0, 0.5) = 0.045;
uniform float rim_soft : hint_range(0.004, 0.2) = 0.022;

void fragment() {
	float v = UV.y;
	float aa = max(fwidth(v), 0.0005);
	float body = smoothstep(0.0, aa, v) * (1.0 - smoothstep(1.0 - aa, 1.0, v));
	float outer_rim = 1.0 - smoothstep(rim_pos - rim_soft, rim_pos + rim_soft, abs(v - rim_pos));
	float inner_rim = 1.0 - smoothstep(rim_pos - rim_soft, rim_pos + rim_soft, abs(v - (1.0 - rim_pos)));
	float rim = max(outer_rim, inner_rim) * body;
	ALBEDO = mix(body_color.rgb, rim_color.rgb, rim);
	ALPHA = body * mix(body_color.a, rim_color.a, rim);
}
