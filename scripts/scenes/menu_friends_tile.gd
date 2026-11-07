extends RefCounted
## 主菜单右上「好友」小图标键(2026-11-06)。
##
## 用户 2026-11-06:「我们现在好友是放在这个左边，对吧？但我想你想你把这个好友做成一个简单的这个小图标，
##   放在这个我们就以我们这个设置，啊、呃，这右上角这边就设置的这个呃左边吧，左边的左边，你看怎么找位置去适合放。
##   就是像下游戏一样…左边就是保持，就是四个这个框框嘛。」
## ⇒ 右上一排从右往左: [⚙ 设置][? 教程][好友] · 货币条; 左列方键只留 4 颗(背包 / 商店 / 图鉴 / 排行榜)。
##   照手游大厅通行做法: 社交入口是角上的小图标键, 不占主列(荒野乱斗 / 英雄联盟手游右上同位)。
## ★画法与 ? / ⚙ 同一个 `_icon_button`(同暗槽、同点击区 81、同间距 CUR_GAP), 图标 = 同一套 38×38 像素
##   (tools/assetgen/build_friends_icon.py, 与 build_gear_icon.py 同配色同描边) —— 一排三颗是一家人。
## ★放在独立文件而不进 MainMenuScene.gd: 那个文件正好 3000 行(tools/arch_budget.py 上限)。

const TEX := "res://assets/sprites/menu/hud/ic-friends-s.png"
const NAME := "FriendsTile"


## 在 ? 键左边建好友键, 返回它的 x(货币条接着往左排)。`host` = 主菜单。
static func add(host: Node, help_x: float, uy: float) -> float:
	var x: float = help_x - float(host.ICON_VIS) - float(host.CUR_GAP)
	var t: Control = host._icon_button(TEX, 30, Color("#d8d4cc"), func(): host._go("Friends"), Vector2(x, uy))
	t.name = NAME
	host.content_root.add_child(t)
	host._slide_in(t, 2)
	return x
