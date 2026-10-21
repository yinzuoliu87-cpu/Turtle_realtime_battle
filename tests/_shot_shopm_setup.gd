extends Node
## 商店 / 背包手机比例实拍的种子(2026-10-21·方案书 20261018-商店背包合一.md「手机优先重排」)。
## = App Store 那份种子(同一个玩家) + 按环境变量模拟真机安全区:
##   SHOPM_INSETS="左,上,右,下"(逻辑像素)。iPhone 6.1" 横屏 = 111,0,111,38(62pt/21pt × 720/402);
##   iPad = 0,0,0,25(底部横条 20pt × 960/768)。无头 / 桌面进程拿不到真机安全区, 只能这样喂。
const _AS := preload("res://tests/_setup_appstore.gd")

static func run() -> void:
	_AS.run()
	var s := OS.get_environment("SHOPM_INSETS")
	var p := s.split(",")
	if p.size() == 4:
		SafeArea.override_insets = Vector4(float(p[0]), float(p[1]), float(p[2]), float(p[3]))
