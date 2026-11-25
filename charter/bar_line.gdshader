shader_type canvas_item;

// 实例化小节线：每个实例是一段细长四边形，沿 UV.y 做约 1px 的抗锯齿。
// 实例的 Y 缩放固定为 3px（见 preview_3d._add_bar_segment），
// half_width=0.2 表示中间 0.6px 全不透明、向外淡到 1.2px。
uniform float half_width : hint_range(0.05, 0.49) = 0.2;

void fragment() {
	float d = abs(UV.y - 0.5);
	COLOR.a *= 1.0 - smoothstep(half_width, 0.5, d);
}
