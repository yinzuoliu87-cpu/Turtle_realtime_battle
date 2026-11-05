// tools/assetgen/spine_ref_dump.mjs — 用 Spine 官方运行库(spine-core)当尺子, 给自写求值器 spine_eval.py 对账(2026-11-05)。
//
// 为什么要它: 画师只交了静态原画(乌龟N.png)当金标, 只能标定 setup 姿势; 动起来对不对(IK、约束、曲线)没有尺子。
//   官方运行库算出来的骨骼世界变换 / 顶点世界坐标就是「Spine 编辑器里看到的」, 逐帧逐根对上才算求值器对。
// 运行库不进仓库: 先装到任意临时目录
//   npm install --ignore-scripts @esotericsoftware/spine-core@4.3.13     (json 是 4.3.10 / 4.3.17 导出的)
// 用法:
//   node tools/assetgen/spine_ref_dump.mjs <spine-core 包目录> <turtleNN.json> <输出.json> [时刻秒 ...]
//   不给时刻 = 0 到动画长度每 1/15 秒一个(与 build_spine_idle.py 的 FPS 相同)。
// 输出: {times:[...], frames:[{t, bones:{名:[a,b,c,d,worldX,worldY]}, slots:{名:{att, region, color:[r,g,b,a](插槽色×部件色), verts:[x0,y0,...]}}}]}
import fs from "fs";
import path from "path";
import { pathToFileURL } from "url";

const [, , pkgDir, jsonPath, outPath, ...tArgs] = process.argv;
if (!pkgDir || !jsonPath || !outPath) {
	console.error("用法: node spine_ref_dump.mjs <spine-core 包目录> <turtleNN.json> <输出.json> [时刻秒 ...]");
	process.exit(2);
}
const S = await import(pathToFileURL(path.join(pkgDir, "dist", "index.js")).href);
const atlasText = fs.readFileSync(jsonPath.replace(/\.json$/, ".atlas"), "utf8");
const atlas = new S.TextureAtlas(atlasText);
const sj = new S.SkeletonJson(new S.AtlasAttachmentLoader(atlas));
const data = sj.readSkeletonData(fs.readFileSync(jsonPath, "utf8"));
const anim = data.findAnimation("animation");
const FPS = 15;
let times = tArgs.map(Number);
if (times.length === 0) {
	const n = Math.max(1, Math.round(anim.duration * FPS));
	for (let k = 0; k < n; k++) times.push(k / FPS);
}

const frames = [];
for (const t of times) {
	const sk = new S.Skeleton(data);
	sk.setupPose();
	const st = new S.AnimationState(new S.AnimationStateData(data));
	st.setAnimation(0, "animation", true);
	st.update(t);
	st.apply(sk);
	sk.updateWorldTransform(S.Physics.update);
	const bones = {};
	for (const b of sk.bones) {
		const p = b.appliedPose;
		bones[b.data.name] = [p.a, p.b, p.c, p.d, p.worldX, p.worldY];
	}
	const slots = {};
	for (const s of sk.slots) {
		const att = s.appliedPose.getAttachment();
		if (!att) continue;
		let verts = null;
		if (att instanceof S.RegionAttachment) {
			verts = new Array(8).fill(0);
			att.computeWorldVertices(s, att.getOffsets(s.appliedPose), verts, 0, 2);
		} else if (att instanceof S.VertexAttachment) {
			const n = att.worldVerticesLength;
			verts = new Array(n).fill(0);
			att.computeWorldVertices(sk, s, 0, n, verts, 0, 2);
		}
		let region = att.path || att.name;
		if (att.sequence) region = att.sequence.getPath(region, att.sequence.resolveIndex(s.appliedPose));
		const c = s.appliedPose.color;
		const ac = att.color || { r: 1, g: 1, b: 1, a: 1 };
		slots[s.data.name] = { att: att.name, region, color: [c.r * ac.r, c.g * ac.g, c.b * ac.b, c.a * ac.a], verts };
	}
	frames.push({ t, bones, slots });
}
fs.writeFileSync(outPath, JSON.stringify({ times, frames }));
console.log("写出", outPath, "帧数", frames.length);
