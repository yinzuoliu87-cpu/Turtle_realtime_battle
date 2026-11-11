"""赌神龟 11-10 修图(用户 11-10「赌神龟这个眼睛到底怎么回事」「什么动作到哪一帧的时候，它手上的牌才发出去」)。

一、眼睛。11-07 的 gambler_eye.py 只贴「新旧定稿有差异的像素」, 原画里本来有表情的帧(眨眼 / 斜眼 / 阵亡瞪眼…)
    没被覆盖的像素留着原表情 ⇒ 新眼睛和旧表情叠在一起, 中间露出一条皮肤(待机第 6、7 帧每秒闪一次)。
    逐帧量过(容差比对眼框), 96 帧里坏 30 帧, 分两类处理:
    · RESTORE —— 本来就是表情的帧, 整帧还原成补丁前(ea45d85a^):
        待机 6~7 眨眼 / 阵亡 2~3 瞪眼(与没贴的阵亡 1、4 连成一段) / 赌注 7 狂笑收尾(与没贴的 1~6 连成一段) /
        连击 6~7 回头斜眼(与没贴的 5 连成一段)
    · FULL —— 原画是半眯眼(正是 11-06 用户说「不要限制他的眼神」的那种), 眼框整块换成新定稿的眼睛:
        抽牌 1~4、命运之轮 1~19
二、普攻出牌。普攻 10 帧: 0 待机 → 1 从牌扇抽一张 → 2 举到胸前 → 3 往肩后蓄力 → 4 手臂甩直(命中帧 = 游戏里飞牌生成、
    伤害结算的那一刻) → 5、6 定住 → 7 收手 → 8、9 回待机。原画第 4~6 帧牌还捏在手里, 第 7 帧才凭空消失,
    而飞牌在第 4 帧就从胸口飞出去 ⇒ 0.3 秒里一张在手上、一张在飞。改: 第 4~6 帧去掉手上的牌, 补成张开的指尖;
    飞牌起点挪到这张牌原来的位置(battle_ballistics.gd, 只改画面)。
确定性: 输入只读 git 里的补丁前帧 + 两张定稿, 重跑逐字节相同(对已修过的帧再跑一次结果不变)。
用法: python tools/oneoff/gambler_1110/gambler_fix_1110.py
"""
import io
import os
import subprocess
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SEQ = os.path.join(ROOT, "tools", "assetgen", "pet_seq", "gambler")
REF = os.path.join(ROOT, "tools", "oneoff", "turtle_seq_1107")
PRE_REV = "ea45d85a^"   # 11-07 眼睛补丁之前

RESTORE = {"idle": [6, 7], "death": [2, 3], "cast_gamblerBet": [7], "form_multi": [6, 7]}
FULL = {"cast_gamblerDraw": [1, 2, 3, 4], "cast_gamblerFateWheel": list(range(1, 20))}
CARD_FRAMES = [4, 5, 6]


def pre_patch(seg: str, i: int) -> Image.Image:
	rel = "tools/assetgen/pet_seq/gambler/%s/f_%02d.png" % (seg, i)
	raw = subprocess.run(["git", "-C", ROOT, "show", "%s:%s" % (PRE_REV, rel)], capture_output=True, check=True).stdout
	return Image.open(io.BytesIO(raw)).convert("RGBA")


def save(im: Image.Image, seg: str, i: int) -> None:
	im.save(os.path.join(SEQ, seg, "f_%02d.png" % i), optimize=False)


old = Image.open(os.path.join(REF, "gambler_eye_old.png")).convert("RGBA")
new = Image.open(os.path.join(REF, "gambler_eye_new.png")).convert("RGBA")
op, np_ = old.load(), new.load()
FACE = (50, 56, 86, 78)   # 与 gambler_eye.py 同一块
diff = [(x, y) for y in range(FACE[1], FACE[3]) for x in range(FACE[0], FACE[2]) if sum(abs(op[x, y][k] - np_[x, y][k]) for k in range(4)) > 30]
x0, x1 = min(p[0] for p in diff), max(p[0] for p in diff)
y0, y1 = min(p[1] for p in diff), max(p[1] for p in diff)
BOX = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]


def eye_offset(px) -> tuple:
	"""在补丁前的帧上找旧定稿眼周的位置(与 gambler_eye.py 的 find 同一判据)"""
	PAD = 3
	tmpl = [(x, y) for y in range(y0 - PAD, y1 + PAD + 1) for x in range(x0 - PAD, x1 + PAD + 1) if op[x, y][3]]
	best, at = -1.0, (0, 0)
	for dy in range(-8, 9):
		for dx in range(-10, 11):
			ok = 0
			for x, y in tmpl:
				X, Y = x + dx, y + dy
				if 0 <= X < 128 and 0 <= Y < 128:
					p = px[X, Y]
					q = op[x, y]
					if p[3] and abs(p[0] - q[0]) + abs(p[1] - q[1]) + abs(p[2] - q[2]) < 36:
						ok += 1
			r = ok / float(len(tmpl))
			if r > best:
				best, at = r, (dx, dy)
	return at


n_restore = n_full = 0
for seg, idx in sorted(RESTORE.items()):
	for i in idx:
		save(pre_patch(seg, i), seg, i)
		n_restore += 1
for seg, idx in sorted(FULL.items()):
	for i in idx:
		im = pre_patch(seg, i)
		px = im.load()
		dx, dy = eye_offset(px)
		w = 0
		for x, y in BOX:
			X, Y = x + dx, y + dy
			if np_[x, y][3] and px[X, Y][3]:
				px[X, Y] = np_[x, y]
				w += 1
		save(im, seg, i)
		n_full += 1
		print("  整眼替换 %-22s f_%02d 偏移 (%+d,%+d) 写 %d 像素" % (seg, i, dx, dy, w))

## 普攻第 4~6 帧: 去掉捏在指尖的牌(x32~43, y84~93), 补指尖。这三帧原本逐字节相同。
A = (6, 3, 2, 255)        # 描边
K = (238, 175, 41, 255)   # 皮肤
O = (172, 102, 48, 255)   # 皮肤暗部
CLEAR = (0, 0, 0, 0)
## 牌在 x32~43、y84~93; x≥44 是手臂和拇指根, 不动。x42~43 里保留食指的上下沿描边与指肚, 其余清空。
KEEP = {(42, 86), (43, 86), (43, 87), (43, 88), (42, 89), (43, 89)}
HAND = {
	(41, 87): A, (41, 88): A, (42, 87): K, (42, 88): O,   # 食指指尖(圆角: 上下沿从 x42 起)
	(43, 90): A, (43, 91): A, (44, 90): K, (44, 91): O,   # 拇指指尖; x44 两格原来压着牌角(灰 / 黑)
}
src_path = os.path.join(SEQ, "attack", "f_04.png")
src = Image.open(src_path).convert("RGBA")
if any(src.tobytes() != Image.open(os.path.join(SEQ, "attack", "f_%02d.png" % i)).convert("RGBA").tobytes() for i in CARD_FRAMES):
	raise SystemExit("普攻第 4~6 帧不再逐字节相同, 先看看是谁改过")
spx = src.load()
card = 0
for y in range(84, 94):
	for x in range(30, 44):
		if (x, y) in KEEP or (x, y) in HAND:
			continue
		if spx[x, y][3]:
			card += 1
		spx[x, y] = CLEAR
for (x, y), c in HAND.items():
	spx[x, y] = c
for i in CARD_FRAMES:
	save(src, "attack", i)
print("眼睛: 还原 %d 帧 · 整眼替换 %d 帧; 普攻第 4~6 帧去牌 %d 像素" % (n_restore, n_full, card))
