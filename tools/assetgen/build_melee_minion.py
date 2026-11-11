# -*- coding: utf-8 -*-
"""tools/assetgen/build_melee_minion.py — 近战小将(珊瑚骑士, 2026-11-11 重做)的全部帧条 / 立绘 / 链头。

用户 11-11 定稿形象「这个吧，就以这个为创作吧」(PixelLab 珊瑚骑士); 武器手 = 前臂甲壳 + 手腕三根尖刺收拢成一个刺
(取《虐杀原形》鞭臂「三根尖刺绕中心成三角形」), 刃臂 = 它自己的左臂(朝左站, 画面右侧、大珊瑚肩甲下那只)。
逐帧标准(用户 11-11「你生产东西你自己看一遍再汇报」「4、5 没区别…7~10 完全一样」「待机…走路…需要这么多帧吗」):
  每帧两条腿 · 刃在左臂 · 相邻格姿势看得出变化(停顿 = 同一张图重复几格, 不放几张几乎一样的 AI 图, 那会纹理闪)
  · 不画进去的特效(拖影 / 烟尘 / 链子) · 空中帧脚对齐地面线(跳多高由代码管)。
源帧: tools/assetgen/minion_seq/melee/<段>/f_NN.png(只存不同的图, 192×192, 脚底行 176, 身体中心 x≈100);
  由 .out 里的一次性处理脚本(PixelLab 出图 → 删碎块 / 烟尘 / 画进去的链子 → 对齐 → 手做挥动帧)产出, 处理记录见
  docs/plans/20261111-忍者普攻与小将铁链与灵物统计.md §8。
本脚本只做排格 + 烘刀光 + 裁切(无缩放、无重采样), 重跑逐字节相同。
产出:
  assets/sprites/pets/animations/melee/{idle,run,attack,leap,throw,dive,surf,land}.png  横排方帧(192)
  assets/sprites/pets/minion.png        UI 用全身立绘(待机第 0 帧裁到本体 + 2 像素边)
  assets/sprites/vfx/melee-chain-head.png  链头 = 手上那个三刺头原图(朝左)
跑法: python tools/assetgen/build_melee_minion.py [--check]
"""
import glob
import io
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEQ = os.path.join(ROOT, "tools", "assetgen", "minion_seq", "melee")
ANIM = os.path.join(ROOT, "assets", "sprites", "pets", "animations", "melee")
PETS = os.path.join(ROOT, "assets", "sprites", "pets")
VFX = os.path.join(ROOT, "assets", "sprites", "vfx")
F = 192

## 段 → 格(下标 = 该段源帧按文件名排序后的序号)。节拍(秒)写在旁边, 帧率在 RealtimeBattle3DScene.ACTION_MELEE / ACTION_ATTACK。
SLOTS = {
	## 待机: 一张图 + 腰带以上下沉 0/1/2/1 像素(呼吸), 每格 0.2 s
	"idle": [0, 1, 2, 3],
	## 跑: 6 帧一个完整步态(两步), 12 帧/秒
	"run": [0, 1, 2, 3, 4, 5],
	## 普攻 13 格: 站(刃下垂) / 刃水平朝后 / 斜上 45° / 举过头 / 斜前上 / ★命中(正前, 停 3 格) / 收回 ×2 / 收回 ×2 / 站
	##   命中格 = 5(AttackHits.BY_PATH); 前摇 0.255 s ⇒ 19.6 帧/秒
	"attack": [0, 1, 2, 3, 4, 5, 5, 5, 6, 6, 7, 7, 0],
	## 起跳 0~0.68 s(10 格, 14.7 帧/秒): 蹲 ×4(0~0.30 蓄力) / 蹬地 / 离地 / 上升(刃垂身后) / 身体转过来刃到前下 / 刃正前 ×2
	"leap": [0, 0, 0, 0, 1, 2, 3, 4, 5, 5],
	## 出链悬停 0.68~1.28 s(6 格, 10 帧/秒): 刺头已射出、手腕空着, 一张图停住(链子由特效画)
	"throw": [0, 0, 0, 0, 0, 0],
	## 被拉过去(8 格, 播放速度 = 8 ÷ 拉人秒数): 猛一拽 / 前倾 / 拉平保持到撞上 —— 前两格过在「先快」那段
	"dive": [0, 1, 2, 2, 2, 2, 2, 2],
	## 踩在敌人身上滑 0.833 s(4 格, 4.8 帧/秒): 一张蹲稳姿势 + 呼吸
	"surf": [0, 1, 2, 3],
	## 侧跳落地 0.30 s(4 格, 13.3 帧/秒): 蹬离 ×2 / 下落 / 触地(专属动作播完前挡普攻动作 ⇒ 不能比 0.30 s 长)
	"land": [0, 0, 1, 2],
}
## 普攻刀光(单独画的一层, 烘在人物后面): 格号 → 源文件(attack_trail/f_NN.png, 文件号 = 格号)
TRAIL_SLOTS = (2, 3, 4, 5, 6, 7)
## 链头: 起跳「刃正前」那张(leap 源帧第 5 张)里手腕前那截三刺头; 护手从 x=64 起(对齐后), 刺头在它左边
HEAD_BOX = (28, 110, 64, 145)


def src_frames(seg):
	fs = sorted(glob.glob(os.path.join(SEQ, seg, "f_*.png")))
	if not fs:
		raise SystemExit("缺源帧 " + seg)
	return [Image.open(f).convert("RGBA") for f in fs]


def strip(seg):
	src = src_frames(seg if seg != "throw" else "release")
	slots = SLOTS[seg]
	out = Image.new("RGBA", (F * len(slots), F), (0, 0, 0, 0))
	for k, i in enumerate(slots):
		fr = src[i]
		if seg == "attack" and k in TRAIL_SLOTS:
			lay = Image.new("RGBA", (F, F), (0, 0, 0, 0))
			lay.alpha_composite(Image.open(os.path.join(SEQ, "attack_trail", "f_%02d.png" % k)).convert("RGBA"))
			lay.alpha_composite(fr)
			fr = lay
		out.alpha_composite(fr, (k * F, 0))
	return out


def portrait():
	"""待机第 0 帧裁到本体 + 2 像素边, 再补成正方形(脚底贴底边; 门禁 verify_elite_anim 按「帧宽 = 帧高」读第 0 帧)"""
	im = src_frames("idle")[0]
	bb = im.getbbox()
	c = im.crop((bb[0] - 2, bb[1] - 2, bb[2] + 2, bb[3] + 2))
	s = max(c.width, c.height)
	sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
	sq.alpha_composite(c, ((s - c.width) // 2, s - c.height))
	return sq


def chain_head():
	im = src_frames("leap")[5].crop(HEAD_BOX)
	return im.crop(im.getbbox())


def png_bytes(im):
	b = io.BytesIO()
	im.save(b, format="PNG", optimize=False)
	return b.getvalue()


def outputs():
	out = {}
	for seg in SLOTS:
		out[os.path.join(ANIM, seg + ".png")] = strip(seg)
	out[os.path.join(PETS, "minion.png")] = portrait()
	out[os.path.join(VFX, "melee-chain-head.png")] = chain_head()
	return out


def main():
	sys.stdout.reconfigure(encoding="utf-8")
	check = "--check" in sys.argv
	bad = 0
	for p, im in outputs().items():
		data = png_bytes(im)
		if check:
			ok = os.path.exists(p) and open(p, "rb").read() == data
			bad += 0 if ok else 1
			print(("OK   " if ok else "DIFF ") + os.path.relpath(p, ROOT))
		else:
			os.makedirs(os.path.dirname(p), exist_ok=True)
			open(p, "wb").write(data)
			print("写出 %s  %dx%d" % (os.path.relpath(p, ROOT), im.width, im.height))
	if check:
		print("ALL OK" if bad == 0 else "有 %d 个文件与脚本输出不一致" % bad)
		return 1 if bad else 0
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
