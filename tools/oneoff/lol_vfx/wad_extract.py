# 只读解 LoL 的 .wad.client(v3): 按路径哈希(xxh64 小写路径)找条目, 解压出来存到 out/
import json
import os
import struct
import sys

import xxhash
import zstandard

WAD = sys.argv[1]
OUT = sys.argv[2]
NAMES = sys.argv[3:]           # 想要的路径(会算哈希); 传 "--scan" 则把所有含 Nami_Base_R 的 bin 都存下来
os.makedirs(OUT, exist_ok=True)
f = open(WAD, "rb")
data = f.read()
assert data[:2] == b"RW", data[:4]
major, minor = data[2], data[3]
if major == 3:
	pos = 4 + 256 + 8
else:
	raise SystemExit("wad v%d.%d 不支持" % (major, minor))
count = struct.unpack_from("<I", data, pos)[0]
pos += 4
entries = []
for i in range(count):
	h, off, csize, size, tb, dup, sub, chk = struct.unpack_from("<QIIIBBHQ", data, pos)
	pos += 32
	entries.append((h, off, csize, size, tb & 0x0F, tb >> 4))
print("wad v%d.%d, %d 条" % (major, minor, count))
dctx = zstandard.ZstdDecompressor()


def unpack(e):
	h, off, csize, size, typ, nsub = e
	raw = data[off:off + csize]
	if typ == 0:
		return raw
	if typ == 3:
		return dctx.decompress(raw, max_output_size=size)
	if typ == 4:
		i = raw.find(b"\x28\xb5\x2f\xfd")
		out = raw[:i] if i > 0 else b""
		return out + dctx.decompressobj().decompress(raw[i:]) if i >= 0 else raw
	return None


want = {xxhash.xxh64(n.lower().encode()).intdigest(): n for n in NAMES if n != "--scan"}
scan = "--scan" in NAMES
got = {}
for e in entries:
	if e[0] in want or scan:
		try:
			b = unpack(e)
		except Exception as ex:
			b = None
		if b is None:
			continue
		if e[0] in want:
			name = want[e[0]].replace("/", "_")
		elif b[:4] == b"PROP" and (b"Nami_Base_R" in b or b"nami_base_r" in b):
			name = "%016x.bin" % e[0]
		else:
			continue
		open(os.path.join(OUT, name), "wb").write(b)
		got[name] = len(b)
print(json.dumps(got, ensure_ascii=False, indent=1))
