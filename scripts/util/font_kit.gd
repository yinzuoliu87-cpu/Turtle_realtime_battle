class_name FontKit
extends RefCounted
## font_kit.gd — 系统字体能不能用(2026-10-13 内测)。
##
## ★由来: iOS 内测玩家每开一个界面就上报几十条
##   `FreeType: Error loading font: '' (face_index=0)`(10-13 两个 iOS 号 3 小时 161 次)。
##   全局主题的回退链是「m6x11 → 打包 Noto SC → SystemFont(雅黑 / 苹方…) → 打包 Noto Emoji」,
##   Noto SC 里没有的字形(emoji / 部分符号)往下找到 SystemFont, 而 iOS 上 Godot 取系统字体拿到空路径 ⇒
##   每个字号报一次错再落到 Noto Emoji。画面一直是对的(系统字体在 iOS 上本来就没取到), 只是报错刷屏。
## ⇒ iOS 上把 SystemFont 从回退链里拿掉, 直接用打包字体: **画面不变**, 报错没了。
##   其余平台(桌面取得到雅黑 / 苹方与彩色 emoji)一个字不改。

## 门禁用: 冒充某个平台(空 = 用真实平台)。产品代码从不写它。
static var platform_override := ""


## 这个平台能用系统字体吗。
static func system_fonts_ok() -> bool:
	var plat: String = platform_override if platform_override != "" else OS.get_name()
	return plat != "iOS"


## 启动时调一次: 不能用系统字体的平台, 把全局主题默认字体回退链里的 SystemFont 去掉。返回去掉了几个。
static func strip_theme_system_fonts() -> int:
	if system_fonts_ok():
		return 0
	var th: Theme = ThemeDB.get_project_theme()
	if th == null:
		return 0
	return strip_from(th.default_font)


## 把某个字体(FontVariation / FontFile 等带 fallbacks 的)回退链里的 SystemFont 去掉(不管平台; 门禁直接调)。
static func strip_from(f: Font) -> int:
	if f == null:
		return 0
	var kept: Array[Font] = []
	var n := 0
	for fb in f.fallbacks:
		if fb is SystemFont:
			n += 1
		else:
			kept.append(fb)
	if n > 0:
		f.fallbacks = kept
	if f is FontVariation and (f as FontVariation).base_font != null:
		n += strip_from((f as FontVariation).base_font)
	return n
