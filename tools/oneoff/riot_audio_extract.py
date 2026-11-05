# -*- coding: utf-8 -*-
"""tools/oneoff/riot_audio_extract.py — 从本机 LoL / 云顶游戏文件取原版音效当参考尺子(2026-11-05)。
由来: 用户 11-05「我让你参考云顶，你压根没参考啊！云顶音效怎么做的？每个技能怎么做的这个音效？」
  只当量尺, 产物落 .out/riot_audio/(不进仓库、不进游戏)。
做什么:
  1. 解 WAD v3(.wad.client): 条目表 → zstd / zstd 分块 解压
  2. 按内容魔数挑出 BNK(BKHD) / WPK(r3d2) / BIN(PROP|PTCH)
  3. BIN 里抓明文事件名(Play_sfx_* / Play_vo_*), FNV-1 32 位哈希 → 对上 BNK HIRC 里的事件 ID
  4. HIRC: 事件 → 动作 → 声音 / 随机容器 → WEM 媒体 ID; WPK / BNK DATA 里取 WEM
  5. vgmstream-cli 解成 wav, 文件名 = 事件名 [+ 变体序号]
用法: python tools/oneoff/riot_audio_extract.py <wad 路径> [<wad 路径> ...] --out .out/riot_audio/<名>
"""
import argparse
import os
import re
import struct
import subprocess
import sys

import zstandard

sys.stdout.reconfigure(encoding="utf-8")
VGM = os.environ.get("VGMSTREAM", "C:/tmp/vgm/bin/vgmstream-cli.exe")


def read_wad(path):
	f = open(path, "rb")
	hdr = f.read(4)
	assert hdr[:2] == b"RW", path
	major = hdr[2]
	if major >= 3:
		f.read(256 + 8)
	elif major == 2:
		ecd_len = struct.unpack("<B", f.read(1))[0]
		f.read(83 + 8 + 2 + 2 - 1)
	count = struct.unpack("<I", f.read(4))[0]
	ents = []
	for _ in range(count):
		h, off, csz, sz, typ, dup, sub, chk = struct.unpack("<QIIIBBHQ", f.read(32))
		ents.append((h, off, csz, sz, typ))
	return f, ents


_dctx = zstandard.ZstdDecompressor()


def entry_data(f, e):
	h, off, csz, sz, typ = e
	f.seek(off)
	raw = f.read(csz)
	t = typ & 0xF
	if t == 0:
		return raw
	if t == 3:
		return _dctx.decompress(raw, max_output_size=sz)
	if t == 4:
		# 分块: 每块要么 zstd 帧要么原样; 逐帧扫
		out = bytearray()
		i = 0
		while i < len(raw) and len(out) < sz:
			if raw[i:i + 4] == b"\x28\xb5\x2f\xfd":
				dobj = zstandard.ZstdDecompressor().decompressobj()
				chunk = dobj.decompress(raw[i:])
				out += chunk
				used = len(raw[i:]) - len(dobj.unused_data)
				i += used
			else:
				# 原样块: 到下一个 zstd 帧魔数为止
				j = raw.find(b"\x28\xb5\x2f\xfd", i + 1)
				j = len(raw) if j < 0 else j
				out += raw[i:j]
				i = j
		return bytes(out[:sz])
	return None


def fnv1_32(s: str) -> int:
	h = 0x811C9DC5
	for c in s.lower().encode("ascii", "ignore"):
		h = (h * 0x01000193) & 0xFFFFFFFF
		h ^= c
	return h


def parse_bnk(data):
	"""返回 (hirc 对象 dict id -> (type, payload), data 段 wem dict id -> bytes)"""
	objs = {}
	wems = {}
	didx = {}
	dsec = None
	i = 0
	while i + 8 <= len(data):
		tag = data[i:i + 4]
		ln = struct.unpack("<I", data[i + 4:i + 8])[0]
		body = data[i + 8:i + 8 + ln]
		if tag == b"HIRC":
			n = struct.unpack("<I", body[:4])[0]
			j = 4
			for _ in range(n):
				ty = body[j]
				l2 = struct.unpack("<I", body[j + 1:j + 5])[0]
				oid = struct.unpack("<I", body[j + 5:j + 9])[0]
				objs[oid] = (ty, body[j + 9:j + 5 + l2])
				j += 5 + l2
		elif tag == b"DIDX":
			for k in range(0, ln, 12):
				wid, off, sz = struct.unpack("<III", body[k:k + 12])
				didx[wid] = (off, sz)
		elif tag == b"DATA":
			dsec = body
		i += 8 + ln
	if dsec is not None:
		for wid, (off, sz) in didx.items():
			wems[wid] = dsec[off:off + sz]
	return objs, wems


def parse_wpk(data):
	assert data[:4] == b"r3d2"
	n = struct.unpack("<I", data[8:12])[0]
	offs = struct.unpack("<%dI" % n, data[12:12 + 4 * n])
	wems = {}
	for o in offs:
		if o == 0:
			continue
		doff, dsz, nlen = struct.unpack("<III", data[o:o + 12])
		name = data[o + 12:o + 12 + nlen * 2].decode("utf-16-le")
		m = re.match(r"(\d+)", name)
		if m:
			wems[int(m.group(1))] = data[doff:doff + dsz]
	return wems


def event_to_sources(objs, eid, depth=0):
	"""事件 → 动作(type 3) → 目标对象 → 递归到声音(type 2)的媒体 id。返回 [(容器路径, 媒体 id)]"""
	out = []
	if eid not in objs or depth > 12:
		return out
	ty, p = objs[eid]
	if ty == 4:  # 事件: u8 动作数(新版) 或 u32
		# 新版 Wwise(v>=125): var-len count u8
		n = p[0]
		ids = []
		if 4 * n + 1 <= len(p):
			ids = list(struct.unpack("<%dI" % n, p[1:1 + 4 * n]))
		if not ids or any(x not in objs for x in ids):
			n = struct.unpack("<I", p[:4])[0]
			ids = list(struct.unpack("<%dI" % n, p[4:4 + 4 * n])) if 4 + 4 * n <= len(p) else []
		for a in ids:
			out += event_to_sources(objs, a, depth + 1)
	elif ty == 3:  # 动作: u16 动作类型, u32 目标 id
		at = struct.unpack("<H", p[:2])[0]
		tid = struct.unpack("<I", p[2:6])[0]
		if (at >> 8) == 0x04:  # Play
			out += event_to_sources(objs, tid, depth + 1)
	elif ty == 2:  # 声音: 插件 u32, 流类型 u8, 源 id u32
		src = struct.unpack("<I", p[5:9])[0]
		out.append(src)
	elif ty in (5, 6, 7):  # 随机/顺序 · 切换 · 混合容器
		for c in container_children(objs, eid, p, ty):
			out += event_to_sources(objs, c, depth + 1)
	return out


def _is_node(objs, v, eid):
	return v in objs and v != eid and objs[v][0] in (2, 5, 6, 7)


def container_children(objs, eid, p, ty):
	"""随机/顺序容器(5): 负载末尾是播放表 u16 N + N×(u32 id, s32 权重); 从尾部认。
	切换/混合(6/7) 或认不出: 找「u32 N 后紧跟 N 个都存在的节点 id」的最后一处。"""
	if ty == 5:
		for n in range(1, 200):
			st = len(p) - 2 - 8 * n
			if st < 0:
				break
			if struct.unpack("<H", p[st:st + 2])[0] == n:
				ids = [struct.unpack("<I", p[st + 2 + 8 * k:st + 6 + 8 * k])[0] for k in range(n)]
				if all(_is_node(objs, v, eid) for v in ids):
					return ids
	best = []
	for k in range(0, len(p) - 4):
		n = struct.unpack("<I", p[k:k + 4])[0]
		if 1 <= n <= 64 and k + 4 + 4 * n <= len(p):
			ids = list(struct.unpack("<%dI" % n, p[k + 4:k + 4 + 4 * n]))
			if all(_is_node(objs, v, eid) for v in ids):
				best = ids
	return best


def event_layers(objs, eid):
	"""事件 → [层, ...], 每层 = 该动作播放对象展开后的媒体 id 列表(随机容器 = 变体; 混合容器 = 同时响的几层)。"""
	if eid not in objs:
		return []
	ty, p = objs[eid]
	if len(p) < 5:
		return []
	n = p[0]
	ids = list(struct.unpack("<%dI" % n, p[1:1 + 4 * n])) if 4 * n + 1 <= len(p) else []
	if not ids or any(x not in objs for x in ids):
		n = struct.unpack("<I", p[:4])[0]
		ids = list(struct.unpack("<%dI" % n, p[4:4 + 4 * n])) if 4 + 4 * n <= len(p) else []
	layers = []
	for a in ids:
		aty, ap = objs[a]
		if aty != 3:
			continue
		at = struct.unpack("<H", ap[:2])[0]
		if (at >> 8) != 0x04:
			continue
		tid = struct.unpack("<I", ap[2:6])[0]
		if tid not in objs:
			continue
		tty, tp = objs[tid]
		if tty == 7:  # 混合容器: 每个子对象各算一层
			for c in container_children(objs, tid, tp, tty):
				layers.append(dedup(event_to_sources(objs, c, 1)))
		else:
			layers.append(dedup(event_to_sources(objs, tid, 1)))
	return [l for l in layers if l]


def dedup(xs):
	o = []
	for x in xs:
		if x not in o:
			o.append(x)
	return o


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("wads", nargs="+")
	ap.add_argument("--out", required=True)
	ap.add_argument("--filter", default="", help="事件名正则(小写匹配), 空 = 全部")
	ap.add_argument("--extra-names", default="", help="额外事件名文件(每行一个)")
	a = ap.parse_args()
	os.makedirs(a.out, exist_ok=True)
	names = set()
	bnks = []
	wems = {}
	for w in a.wads:
		f, ents = read_wad(w)
		for e in ents:
			if (e[4] & 0xF) not in (0, 3, 4):
				continue
			if e[3] > 80_000_000:
				continue
			try:
				d = entry_data(f, e)
			except Exception:
				continue
			if not d:
				continue
			m4 = d[:4]
			if m4 == b"BKHD":
				bnks.append(d)
			elif m4 == b"r3d2" and d[4:8] == b"\x01\x00\x00\x00":
				# 只认 WPK(版本 1); r3d2anmd / r3d2Mesh 是动画与网格
				wems.update(parse_wpk(d))
			elif m4 in (b"PROP", b"PTCH"):
				for s in re.findall(rb"(Play_[A-Za-z0-9_]{4,120})", d):
					names.add(s.decode())
	if a.extra_names:
		for l in open(a.extra_names, encoding="utf-8"):
			if l.strip():
				names.add(l.strip())
	objs = {}
	for b in bnks:
		o, wm = parse_bnk(b)
		objs.update(o)
		wems.update(wm)
	byhash = {fnv1_32(n): n for n in names}
	evs = [(oid, byhash[oid]) for oid, (ty, _) in objs.items() if ty == 4 and oid in byhash]
	print("WAD 数 %d · BNK %d · WEM %d · 明文事件名 %d · 对上的事件 %d · HIRC 事件总数 %d" % (
		len(a.wads), len(bnks), len(wems), len(names), len(evs), sum(1 for v in objs.values() if v[0] == 4)))
	rx = re.compile(a.filter) if a.filter else None
	man = []
	for oid, nm in sorted(evs, key=lambda x: x[1].lower()):
		if rx and not rx.search(nm.lower()):
			continue
		layers = event_layers(objs, oid)
		got = 0
		for li, srcs in enumerate(layers):
			for vi, s in enumerate(srcs):
				if s not in wems:
					continue
				wem = os.path.join(a.out, "_tmp.wem")
				open(wem, "wb").write(wems[s])
				wav = os.path.join(a.out, "%s__L%d_v%d.wav" % (nm, li + 1, vi + 1))
				r = subprocess.run([VGM, "-o", wav, wem], capture_output=True)
				got += r.returncode == 0
		man.append("%s\t%d\t%s\t%d" % (nm, len(layers), ",".join(str(len(l)) for l in layers), got))
	open(os.path.join(a.out, "manifest.tsv"), "w", encoding="utf-8").write("事件\t层数\t每层变体数\t解出\n" + "\n".join(man) + "\n")
	print("写出 %d 个事件 → %s" % (len(man), a.out))


if __name__ == "__main__":
	main()
