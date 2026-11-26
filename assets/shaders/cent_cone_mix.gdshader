// cent_cone_mix.gdshader —— 普攻冲击罩: 普通混合的层(暗层 / 主亮层 / 流动填充 / 流光)。片段见 cent_cone.gdshaderinc。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://assets/shaders/cent_cone.gdshaderinc"
