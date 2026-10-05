extends RefCounted
## menu_arena_layout.gd —— 【生成文件, 别手改】由 tools/build_menu_arena_bg.py 写出。
## 主菜单擂台背景的分层排布(原生 390x180 坐标), 读它的是 scripts/scenes/menu_arena_backdrop.gd。
## 改排布/换素材: 改生成器重跑, 再 --import。tools/menu_arena_sync_audit.py 守着两边一致。

const LAYOUT := {
	"native": [
		390,
		180
	],
	"base": {
		"tex": "res://assets/sprites/menu/arena/baked/base.png",
		"x": 0,
		"y": 0,
		"w": 390,
		"h": 180
	},
	"lights": [
		{
			"tex": "res://assets/sprites/menu/arena/baked/lights_0.png",
			"x": 85,
			"y": 0,
			"w": 265,
			"h": 41,
			"base": 0.82,
			"amp": 0.16,
			"period": 2.3,
			"phase": 5.69
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/lights_1.png",
			"x": 158,
			"y": 11,
			"w": 166,
			"h": 34,
			"base": 0.88,
			"amp": 0.16,
			"period": 3.2,
			"phase": 1.15
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/lights_2.png",
			"x": 135,
			"y": 31,
			"w": 126,
			"h": 13,
			"base": 0.94,
			"amp": 0.16,
			"period": 4.1,
			"phase": 4.74
		}
	],
	"crowd": [
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_00_0.png",
			"x": 39,
			"y": 24,
			"w": 315,
			"h": 33,
			"period": 1.34,
			"duty": 0.29,
			"phase": 0.262
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_00_1.png",
			"x": 49,
			"y": 28,
			"w": 300,
			"h": 29,
			"period": 1.4,
			"duty": 0.44,
			"phase": 0.423
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_01_0.png",
			"x": 0,
			"y": 32,
			"w": 384,
			"h": 33,
			"period": 1.07,
			"duty": 0.43,
			"phase": 0.612
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_01_1.png",
			"x": 13,
			"y": 34,
			"w": 358,
			"h": 33,
			"period": 1.22,
			"duty": 0.31,
			"phase": 0.001
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_02_0.png",
			"x": 11,
			"y": 46,
			"w": 379,
			"h": 29,
			"period": 1.32,
			"duty": 0.25,
			"phase": 0.26
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_02_1.png",
			"x": 15,
			"y": 47,
			"w": 375,
			"h": 28,
			"period": 1.38,
			"duty": 0.33,
			"phase": 0.464
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_03_0.png",
			"x": 0,
			"y": 58,
			"w": 390,
			"h": 27,
			"period": 1.38,
			"duty": 0.36,
			"phase": 0.966
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_03_1.png",
			"x": 3,
			"y": 60,
			"w": 387,
			"h": 25,
			"period": 0.92,
			"duty": 0.32,
			"phase": 0.516
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_04_0.png",
			"x": 0,
			"y": 81,
			"w": 378,
			"h": 27,
			"period": 1.4,
			"duty": 0.38,
			"phase": 0.549
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_04_1.png",
			"x": 4,
			"y": 78,
			"w": 386,
			"h": 29,
			"period": 1.88,
			"duty": 0.33,
			"phase": 0.741
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_05_0.png",
			"x": 1,
			"y": 92,
			"w": 383,
			"h": 31,
			"period": 1.81,
			"duty": 0.45,
			"phase": 0.463
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_05_1.png",
			"x": 26,
			"y": 92,
			"w": 364,
			"h": 29,
			"period": 1.43,
			"duty": 0.39,
			"phase": 0.252
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_06_0.png",
			"x": 6,
			"y": 106,
			"w": 376,
			"h": 28,
			"period": 1.74,
			"duty": 0.28,
			"phase": 0.374
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_06_1.png",
			"x": 22,
			"y": 107,
			"w": 368,
			"h": 30,
			"period": 1.89,
			"duty": 0.43,
			"phase": 0.562
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_07_0.png",
			"x": 4,
			"y": 138,
			"w": 379,
			"h": 42,
			"period": 1.81,
			"duty": 0.35,
			"phase": 0.88
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_07_1.png",
			"x": 17,
			"y": 135,
			"w": 348,
			"h": 45,
			"period": 1.75,
			"duty": 0.26,
			"phase": 0.652
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_08_0.png",
			"x": 58,
			"y": 152,
			"w": 283,
			"h": 28,
			"period": 1.56,
			"duty": 0.43,
			"phase": 0.899
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/crowd_08_1.png",
			"x": 85,
			"y": 149,
			"w": 237,
			"h": 31,
			"period": 1.63,
			"duty": 0.34,
			"phase": 0.74
		}
	],
	"front": [
		{
			"tex": "res://assets/sprites/menu/arena/baked/front_0.png",
			"x": 0,
			"y": 155,
			"w": 390,
			"h": 25,
			"period": 1.71,
			"duty": 0.3,
			"phase": 0.032
		},
		{
			"tex": "res://assets/sprites/menu/arena/baked/front_1.png",
			"x": 14,
			"y": 157,
			"w": 375,
			"h": 23,
			"period": 1.62,
			"duty": 0.3,
			"phase": 0.078
		}
	],
	"flames": [
		[
			{
				"tex": "res://assets/sprites/menu/arena/baked/flame_0_0.png",
				"x": 6,
				"y": 113,
				"w": 24,
				"h": 25
			},
			{
				"tex": "res://assets/sprites/menu/arena/baked/flame_0_1.png",
				"x": 6,
				"y": 113,
				"w": 24,
				"h": 25
			},
			{
				"tex": "res://assets/sprites/menu/arena/baked/flame_0_2.png",
				"x": 6,
				"y": 113,
				"w": 24,
				"h": 25
			},
			{
				"tex": "res://assets/sprites/menu/arena/baked/flame_0_3.png",
				"x": 6,
				"y": 117,
				"w": 24,
				"h": 21
			}
		],
		[
			{
				"tex": "res://assets/sprites/menu/arena/baked/flame_1_0.png",
				"x": 360,
				"y": 113,
				"w": 24,
				"h": 25
			},
			{
				"tex": "res://assets/sprites/menu/arena/baked/flame_1_1.png",
				"x": 360,
				"y": 113,
				"w": 24,
				"h": 25
			},
			{
				"tex": "res://assets/sprites/menu/arena/baked/flame_1_2.png",
				"x": 360,
				"y": 113,
				"w": 24,
				"h": 25
			},
			{
				"tex": "res://assets/sprites/menu/arena/baked/flame_1_3.png",
				"x": 360,
				"y": 117,
				"w": 24,
				"h": 21
			}
		]
	],
	"glows": [
		{
			"cx": 18,
			"cy": 128,
			"r": 30
		},
		{
			"cx": 372,
			"cy": 128,
			"r": 30
		}
	],
	"banner": {
		"tex": "res://assets/sprites/menu/arena/baked/banner.png",
		"x": 185,
		"y": 57,
		"w": 32,
		"h": 46
	},
	"fighters": {
		"atk": {
			"stance": {
				"tex": "res://assets/sprites/menu/arena/baked/fighter_atk_stance.png",
				"x": 146,
				"y": 108,
				"w": 38,
				"h": 36
			},
			"windup": {
				"tex": "res://assets/sprites/menu/arena/baked/fighter_atk_windup.png",
				"x": 151,
				"y": 106,
				"w": 27,
				"h": 38
			},
			"thrust": {
				"tex": "res://assets/sprites/menu/arena/baked/fighter_atk_thrust.png",
				"x": 146,
				"y": 106,
				"w": 38,
				"h": 38
			}
		},
		"def": {
			"guard": {
				"tex": "res://assets/sprites/menu/arena/baked/fighter_def_guard.png",
				"x": 183,
				"y": 109,
				"w": 32,
				"h": 35
			},
			"brace": {
				"tex": "res://assets/sprites/menu/arena/baked/fighter_def_brace.png",
				"x": 182,
				"y": 114,
				"w": 33,
				"h": 30
			}
		}
	}
}
