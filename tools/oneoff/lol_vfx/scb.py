# 只读解析 LoL 静态网格 .scb(r3d2Mesh), 量顶点/面数/包围盒, 画俯视 + 侧视线框
import struct
import sys

from PIL import Image, ImageDraw


def parse(b):
	assert b[:8] == b"r3d2Mesh", b[:8]
	p = 8
	major, minor = struct.unpack_from("<HH", b, p); p += 4
	name = b[p:p + 128].split(b"\0")[0].decode("latin1"); p += 128
	nv, nf, flags = struct.unpack_from("<III", b, p); p += 12
	bbox = struct.unpack_from("<6f", b, p); p += 24
	vctype = 0
	if (major, minor) >= (3, 2):
		vctype = struct.unpack_from("<I", b, p)[0]; p += 4
	verts = [struct.unpack_from("<3f", b, p + 12 * i) for i in range(nv)]
	p += 12 * nv
	if vctype == 1:
		p += 4 * nv
	elif vctype == 2:
		p += 16 * nv
	p += 12  # central point
	faces, uvs, mats = [], [], set()
	for i in range(nf):
		a, c, d = struct.unpack_from("<3I", b, p); p += 12
		mat = b[p:p + 64].split(b"\0")[0].decode("latin1"); p += 64
		uv = struct.unpack_from("<6f", b, p); p += 24
		faces.append((a, c, d)); uvs.append(uv); mats.add(mat)
	return dict(ver="%d.%d" % (major, minor), name=name, nv=nv, nf=nf, bbox=bbox, verts=verts, faces=faces, uvs=uvs, mats=mats)


def draw(m, ax1, ax2, W=480, H=300, label=""):
	im = Image.new("RGB", (W, H), (20, 22, 28)); d = ImageDraw.Draw(im)
	a = [v[ax1] for v in m["verts"]]; b = [v[ax2] for v in m["verts"]]
	s = min((W - 20) / ((max(a) - min(a)) or 1), (H - 30) / ((max(b) - min(b)) or 1))
	P = [(10 + (v[ax1] - min(a)) * s, H - 10 - (v[ax2] - min(b)) * s) for v in m["verts"]]
	for f in m["faces"]:
		d.line([P[f[0]], P[f[1]], P[f[2]], P[f[0]]], fill=(80, 200, 220), width=1)
	d.text((6, 4), label, fill=(255, 230, 120))
	return im


if __name__ == "__main__":
	out = []
	for fn in sys.argv[1:]:
		m = parse(open(fn, "rb").read())
		bb = m["bbox"]
		print("%s  v%s  顶点 %d  三角 %d  尺寸 x %.0f  y %.0f  z %.0f  材质 %s" % (fn.split("/")[-1], m["ver"], m["nv"], m["nf"],
			bb[3] - bb[0], bb[4] - bb[1], bb[5] - bb[2], sorted(m["mats"])))
		row = Image.new("RGB", (980, 300), (0, 0, 0))
		row.paste(draw(m, 0, 2, label=fn.split("/")[-1] + "  俯视(x-z)"), (0, 0))
		row.paste(draw(m, 0, 1, label="侧视(x-y)"), (500, 0))
		out.append(row)
	sheet = Image.new("RGB", (980, 310 * len(out)), (0, 0, 0))
	for i, r in enumerate(out):
		sheet.paste(r, (0, i * 310))
	sheet.save("meshes.png")
