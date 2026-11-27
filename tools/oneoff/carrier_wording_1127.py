# -*- coding: utf-8 -*-
"""carrier_wording_1127.py —— 装备文案「自身」统一改成「携带者」(用户 11-27「肯定是改成携带者嘛…我们这边肯定是不同的人带这个装备啊，所以我们用携带者」)。

现状(11-27 探针): data/phase2-equipment.json 71 件装备的 effectDesc1 / effectBrief / effectDesc3 共 124 句用「自身」指戴装备的龟,
  而羁绊文案一律用「携带者」—— 同一个意思两种叫法; 远古炮塔「自身位于炮台附近时」还容易读成炮台自己。
例外(「自身」指的不是携带者, 不换):
  · FPGA 板(040)「持枪者…每次攻击对自身造成」—— 拿枪的敌人自己;
  · 小木斧(096)「【斧头】…回复自身 / 转为自身的护盾 / 以自身…复活」—— 斧头这个召唤物自己;
  · 永恒之枪(145)「永恒之枪自身的伤害不计入」—— 那把枪。
同一句里连着出现几次的顺一下(第二次起用「其」), 见 POLISH。
en.po 按中文原句对照: 改了的句子把 msgid 换成新句, 英文 msgstr 不动(英文本来就写 max health / gains, 没有「自身」这个词)。
用法: python tools/oneoff/carrier_wording_1127.py [--dry]
"""
import io, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "data", "phase2-equipment.json")
PO = os.path.join(ROOT, "locale", "en.po")
FIELDS = ("effectDesc1", "effectDesc2", "effectDesc3", "effectBrief")
KEEP = ("持枪者", "【斧头】", "永恒之枪自身")      # 句子里有这些 ⇒ 这句的「自身」不是携带者, 整句不动
POLISH = [
	("转由携带者承受，不受携带者护甲与魔抗影响，可被携带者护盾吸收", "转由携带者承受，不受其护甲与魔抗影响，可被其护盾吸收"),
	("携带者位于炮台 {C:EquipSystem.TURRET_BUFF_R} 码内时，携带者获得", "携带者位于炮台 {C:EquipSystem.TURRET_BUFF_R} 码内时，获得"),
	("携带者每累计受到相当于携带者最大生命值", "携带者每累计受到相当于其最大生命值"),
	("拥有携带者 20/40/100% 最大生命值", "拥有其 20/40/100% 最大生命值"),
	("回复携带者最大生命值的 5/7/10%，并附带携带者 100% 魔抗", "回复其最大生命值的 5/7/10%，并附带其 100% 魔抗"),
	("并使携带者最大生命值永久提升", "并使其最大生命值永久提升"),
]


def convert(s: str) -> str:
	parts = re.split(r"(?<=[。\n])", s)
	out = []
	for p in parts:
		if "自身" in p and not any(k in p for k in KEEP):
			p = p.replace("自身", "携带者")
		out.append(p)
	r = "".join(out)
	for a, c in POLISH:
		r = r.replace(a, c)
	return r


def po_esc(s: str) -> str:
	return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main():
	dry = "--dry" in sys.argv
	raw = io.open(DATA, encoding="utf-8", newline="").read()
	data = json.loads(raw)
	items = data if isinstance(data, list) else data.get("equipment", list(data.values()))
	changes = []
	for e in items:
		if not isinstance(e, dict):
			continue
		for f in FIELDS:
			v = e.get(f)
			if isinstance(v, str) and "自身" in v:
				nv = convert(v)
				if nv != v:
					changes.append((e.get("id"), f, v, nv))
	## 数据文件: 按原 JSON 字符串字面量逐个替换(不整份重排格式)
	for _id, _f, v, nv in changes:
		a, c = json.dumps(v, ensure_ascii=False), json.dumps(nv, ensure_ascii=False)
		if a not in raw and c in raw:
			continue          # 同一句在别的字段已经换过(047 战锤简述 = 正文)
		assert raw.count(a) >= 1, (_id, _f)
		raw = raw.replace(a, c)
	json.loads(raw)
	## en.po: msgid 换成新句
	po = io.open(PO, encoding="utf-8", newline="").read()
	po_hit = po_miss = 0
	for _id, _f, v, nv in changes:
		a, c = 'msgid "%s"' % po_esc(v), 'msgid "%s"' % po_esc(nv)
		if a in po:
			po = po.replace(a, c)
			po_hit += 1
		else:
			po_miss += 1
			print("  en.po 没有这句(稍后补英文):", _id, _f)
	left = sum(nv.count("自身") for *_x, nv in changes)
	print("改了 %d 个字段(%d 件装备) · en.po 对上 %d / 没对上 %d · 改完仍保留「自身」%d 处(例外句)"
		% (len(changes), len({c[0] for c in changes}), po_hit, po_miss, left))
	if not dry:
		io.open(DATA, "w", encoding="utf-8", newline="").write(raw)
		io.open(PO, "w", encoding="utf-8", newline="").write(po)


if __name__ == "__main__":
	main()
