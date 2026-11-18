class_name Lang
extends RefCounted
## 游戏语言(2026-11-18 · 方案书 docs/plans/20261118c-语言选项.md)。
##
## 用户 11-18:「第一次进入应该是英文去显示，或者是跟随你的机子的那个系统语言。然后在设置里面应该是有语言的切换按钮，
##   点击一下游戏的整个语言都会被切换。」
##
## ★机制 = Godot 自带翻译: 译文表 `locale/en.po`(msgid = 中文原文), 控件显示时自动按当前语言换字(Label / Button 的 atr)。
##   ⇒ 游戏内部照旧拿中文做判断 / 当键, 只有【显示】那一刻换成英文 —— 不用先拆几十处中文判断。
##   代码里拼出来的字(带数字的模板)要先 `tr("模板") % 值` 再显示, 否则拼好的整句在表里查不到。
## ★存在设备上(`user://lang.cfg`), 不进 GameState 存档: 语言是这台设备的偏好(同音量 / 全屏), 换号不跟着走。
## ★第一次(没存过): 系统语言是中文(简 / 繁)⇒ 中文, 其余一律英文。
##   无头进程(门禁 / CI / 裁判机 / 陪练号)一律中文: CI 机器是英文系统, 跟了系统语言几百条中文门禁全红; 那些进程不给人看。
##   环境变量 TURTLE_LANG=zh|en 覆盖一切(英文版截图走查用)。

const CFG := "user://lang.cfg"
const CODES := ["zh", "en"]
## 设置页那颗按钮上的字(每种语言用它自己的话写, 不走翻译)。
const BUTTON := {"zh": "语言：简体中文", "en": "Language: English"}

static var code := "zh"


## 系统语言 → 我们支持的语言。
static func system_default() -> String:
	return "zh" if OS.get_locale_language() == "zh" else "en"


## 开机定语言(由 autoload `LangBoot` 在其它 autoload 之前调)。
static func boot() -> void:
	var c := OS.get_environment("TURTLE_LANG")
	if not c in CODES:
		var cf := ConfigFile.new()
		if cf.load(CFG) == OK:
			c = str(cf.get_value("lang", "code", ""))
	if not c in CODES:
		c = "zh" if DisplayServer.get_name() == "headless" else system_default()
	apply(c)


static func apply(c: String) -> void:
	code = c if c in CODES else "zh"
	TranslationServer.set_locale(code)


## 玩家在设置里切换: 立刻生效 + 记到设备上。门禁 / 台子进程在默认目录上不写(同 GameState.save 的拒写闸)。
static func set_lang(c: String) -> void:
	apply(c)
	if SaveIso.blocks_save():
		return
	var cf := ConfigFile.new()
	cf.set_value("lang", "code", code)
	cf.save(CFG)


## 两种语言来回切(设置页按钮)。返回切过去的那种。
static func toggle() -> String:
	set_lang("en" if code == "zh" else "zh")
	return code


static func is_en() -> bool:
	return code == "en"
