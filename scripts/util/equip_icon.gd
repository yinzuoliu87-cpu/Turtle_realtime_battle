class_name EquipIcon
extends RefCounted
## equip_icon.gd — 装备图标的【唯一出口】(2026-08-10)
##
## ══════════════════════════════════════════════════════════════════
##  ★为什么要有这个文件
## ══════════════════════════════════════════════════════════════════
## 2026-08-10 用户问「能正确在背包显示吗」。查下来: **不能**。
## `data/phase2-equipment.json` 里 060~095 共 **36 件的 `img` 字段是空的**,
## 而背包/商店的画法一律是:
##
##     if img != "" and ResourceLoader.exists(...):
##         <画 TextureRect>
##     # ← 没有 else
##
## ⇒ 那 36 件在背包大格里只剩一行字, 装到龟身上的小格**完全空白**(一个空框),
##   商店卡片也是空的。图鉴那边有 emoji 兜底所以看得见 —— **同一件事在 7 处各写了一遍,
##   只有其中 2 处写了兜底**。这正是 memory [[fb-hand-rolled-copies-drift]] 那条:
##   手抄的副本必然落后, 抄一次就永远落后一次。
##
## ⇒ 收口成一个函数。以后加装备忘了配图, 也只会退化成 emoji, 不会开天窗。
##
## ══════════════════════════════════════════════════════════════════
##  用法
## ══════════════════════════════════════════════════════════════════
##     var ic := EquipIcon.make(edef, Vector2(44, 36))
##     ic.position = Vector2(x, y)
##     box.add_child(ic)
##
## 返回的永远是一个 `Control`(不会是 null), 尺寸已按 `size` 设好:
##   · 有图 ⇒ `TextureRect`(NEAREST, 保持比例居中) —— 与改动前逐处手写的参数**逐项一致**
##   · 无图 ⇒ `Label`(emoji, 居中, 字号按格子高度算) —— 图鉴一直是这么兜的

## emoji 字号 = 格子高 × 这个系数。0.72 是让 emoji 在格子里"满而不溢"的经验值:
## 再大在 36px 的小格里会被裁掉上下缘, 再小就读不出是什么。
const EMOJI_K := 0.72
## 连 emoji 都没有时的最后兜底(与图鉴 `detail_views.gd` 用的同一个字符)。
const EMOJI_FALLBACK := "📦"


## 装备定义 → 一个可直接 add_child 的图标节点。
## `edef` = `DataRegistry.phase2_equipment_by_id[id]`(缺字段也不会崩)。
static func make(edef: Dictionary, size: Vector2, ignore_mouse: bool = false) -> Control:
	var img: String = str(edef.get("img", ""))
	var node: Control
	if img != "" and ResourceLoader.exists("res://assets/sprites/" + img):
		var ic := TextureRect.new()
		ic.texture = load("res://assets/sprites/" + img)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		## ★像素图必须 NEAREST —— 默认的线性过滤会把 64×64 的图糊成一团
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		node = ic
	else:
		var lb := Label.new()
		var em: String = str(edef.get("emoji", ""))
		lb.text = em if em != "" else EMOJI_FALLBACK
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.add_theme_font_size_override("font_size", maxi(9, int(size.y * EMOJI_K)))
		node = lb
	node.size = size
	if ignore_mouse:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node
