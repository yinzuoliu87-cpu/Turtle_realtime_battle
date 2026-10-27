class_name PixelKey
extends RefCounted
## 叠在画面上的像素控制键(回放操作条 / 观赛退出 / 闯关排队的取消)—— docs/plans/20261027-UI美术规矩.md §4.6-6:
##   「叠在战斗画面上的控制键照同类商业游戏做小方形图标键, 素材为这几屏专门新做, 不套商店卡片按钮, 也不借别屏的框」。
##   素材: tools/build_replay_queue_ui.py 生成的 1 倍源图(assets/sprites/ui/replay_bar/、queue_wait/)。
## ★为什么要在运行时放大: StyleBoxTexture / Button.icon 只会按贴图原尺寸画(九宫格边距也是贴图像素), 没有「×3」这个参数;
##   存一份 ×3 的图就是同一张素材两份副本。⇒ 仓库只存 1 倍源图, 这里最近邻放大成 ImageTexture(整数倍、硬边), 按路径缓存。
## ★键看起来 60×60(20 源像素 ×3), 可点范围 84×84(用户 10-27 定: 看起来 60, 能点的范围放大到 84, 看不见)—— `HitButton._has_point`。

const SCALE := 3
const KEY_PX := 60.0               # 20 源像素 × 3
const HIT_PX := 84.0               # 可点范围(看不见)
## 键底座的九宫格边距(源像素; 与 build_replay_queue_ui.key_base 的头注同一组): 常态 左 上 右 下 / 按下
const MARGIN_UP := [4, 4, 3, 4]
const MARGIN_DOWN := [2, 4, 2, 2]
## 内容区(图标 / 字)的上 / 下边距: 常态 上 0 / 下 bottom; 按下整个面下沉 2 源像素 ⇒ 上 12 / 下 bottom。
##   20 高的图标键 bottom = 9 ⇒ 中心 25.5(奇数高的图标连落影居中, 与风格稿逐像素相同);
##   18 高的宽键(取消)bottom = 6 ⇒ 中心 24 = 键面(第 1~14 行)正中。
const ICON_KEY_BOTTOM := 9.0
## 门禁按它认出「这颗键现在画的是哪个图标」(暂停 / 播放、x1 / x2 / x4、退出)
const META_ICON := "key_icon"

static var _cache: Dictionary = {}


## 1 倍源图 → ×k 最近邻放大后的贴图(缓存)。源图不在 ⇒ null。
static func up(path: String, k: int = SCALE) -> Texture2D:
	var key := "%s@%d" % [path, k]
	if _cache.has(key):
		return _cache[key]
	var t := load(path) as Texture2D if ResourceLoader.exists(path) else null
	if t == null:
		return null
	var img := t.get_image()
	if img == null:
		return null
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.resize(img.get_width() * k, img.get_height() * k, Image.INTERPOLATE_NEAREST)
	var it := ImageTexture.create_from_image(img)
	_cache[key] = it
	return it


## 一张 1 倍源图按 ×k 画成 TextureRect(尺寸 = 源图 × k, 最近邻, 不吃点击)。
static func sprite(path: String, k: int = SCALE) -> TextureRect:
	var tr := TextureRect.new()
	var t := load(path) as Texture2D if ResourceLoader.exists(path) else null
	tr.texture = t
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if t != null:
		tr.size = t.get_size() * k
	return tr


## 可点范围比看起来大一圈的按钮(四周各扩 pad 像素)。
class HitButton extends Button:
	var pad := 0.0

	func _has_point(p: Vector2) -> bool:
		return Rect2(Vector2(-pad, -pad), size + Vector2(pad, pad) * 2.0).has_point(p)


static func _box(path: String, margin: Array, content: Array, modulate := Color.WHITE) -> StyleBox:
	var tex := up(path)
	if tex == null:
		return StyleBoxEmpty.new()
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = float(margin[0] * SCALE)
	sb.texture_margin_top = float(margin[1] * SCALE)
	sb.texture_margin_right = float(margin[2] * SCALE)
	sb.texture_margin_bottom = float(margin[3] * SCALE)
	sb.content_margin_left = float(content[0])
	sb.content_margin_top = float(content[1])
	sb.content_margin_right = float(content[2])
	sb.content_margin_bottom = float(content[3])
	sb.modulate_color = modulate
	return sb


## 给按钮套上键底座皮: 常态 / 悬停 = up; 按下 = down(面下沉 2 源像素, 图标与字跟着下沉); 禁用 = up 压灰; 无焦点框。
##   `content_lr` = 左右内容边距(宽键里放图标 + 字时用); `bottom` 见 ICON_KEY_BOTTOM 的注释。
static func skin(b: Button, up_path: String, down_path: String, content_lr: float = 0.0, bottom: float = ICON_KEY_BOTTOM) -> void:
	var cu: Array = [content_lr, 0.0, content_lr, bottom]
	var cd: Array = [content_lr, 2.0 * SCALE * 2.0, content_lr, bottom]
	b.add_theme_stylebox_override("normal", _box(up_path, MARGIN_UP, cu))
	b.add_theme_stylebox_override("hover", _box(up_path, MARGIN_UP, cu))
	b.add_theme_stylebox_override("pressed", _box(down_path, MARGIN_DOWN, cd))
	b.add_theme_stylebox_override("hover_pressed", _box(down_path, MARGIN_DOWN, cd))
	b.add_theme_stylebox_override("disabled", _box(up_path, MARGIN_UP, cu, Color(0.62, 0.62, 0.66)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 小方形图标键: 看起来 60×60, 可点 84×84。图标是 1 倍源图(宽偶数 / 高奇数, ×3 后在键面上正好居中落在整像素上)。
static func icon_key(node_name: String, up_path: String, down_path: String, icon_path: String) -> Button:
	var b := HitButton.new()
	b.name = node_name
	b.pad = (HIT_PX - KEY_PX) / 2.0
	b.text = ""
	b.custom_minimum_size = Vector2(KEY_PX, KEY_PX)
	b.size = Vector2(KEY_PX, KEY_PX)
	skin(b, up_path, down_path)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.expand_icon = false
	set_icon(b, icon_path)
	return b


## 换图标(暂停 ↔ 播放、x1 → x2 → x4)。图标 id = 文件名去掉 icon- 与 .png。
static func set_icon(b: Button, icon_path: String) -> void:
	b.icon = up(icon_path)
	b.set_meta(META_ICON, icon_path.get_file().trim_prefix("icon-").trim_suffix(".png"))


## 这颗键现在画的是哪个图标(没设过 = "")。
static func icon_of(b: Button) -> String:
	return str(b.get_meta(META_ICON, "")) if b != null else ""
