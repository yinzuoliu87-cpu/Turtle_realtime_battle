extends ColorRect
## 新手引导高亮的亮边框 —— 在目标矩形四周画一圈黄色发光边框(不填充, 洞内可见底下的控件)。


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# 双层边框: 外粗淡 + 内细亮 = 有点发光感
	draw_rect(r.grow(3.0), Color(1, 0.85, 0.25, 0.35), false, 6.0)
	draw_rect(r, Color(1, 0.87, 0.3, 0.95), false, 3.0)
