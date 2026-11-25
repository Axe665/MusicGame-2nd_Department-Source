shader_type canvas_item;

// 实例化小节线：每个实例是一段 3px 高的细长四边形（见 preview_3d._update_bar_multimesh）。
// 渲染成 1px 实体白线，两侧各留 1px 做抗锯齿；线宽不随四边形长度变化。
void fragment() {
	float half_px = 0.5 / 3.0;
	float d = abs(UV.y - 0.5);
	float aa = max(fwidth(UV.y) * 0.75, 0.0005);
	COLOR.a *= 1.0 - smoothstep(half_px - aa, half_px + aa, d);
}
