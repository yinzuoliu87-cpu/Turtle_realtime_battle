// cent_cone_add.gdshader —— 普攻冲击罩: 叠加发光的层(中层)。片段见 cent_cone.gdshaderinc。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://assets/shaders/cent_cone.gdshaderinc"
