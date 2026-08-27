// 斗龟场·实时版 —— ghost 快照交换所【Deno Deploy 版】
//
// 方案书: docs/plans/20260820-阵容上传后端.md
// 客户端: scripts/net/remote_pool.gd (POST /ghost, GET /ghosts?bracket=N&limit=M)
//
// ★为什么有两个宿主: 腾讯云(国内节点·要实名) 与 Deno Deploy(免实名·海外)。
//   实测(2026-08-27, 从国内直连): `*.deno.dev` / `*.deno.net` 通 3/3 约 1.3s;
//   而 `*.workers.dev`(Cloudflare) 与 `fly.dev` 都是 **0/3 超时**, 所以只剩这一家海外的可用。
//
// ★★校验规则不在本文件里 —— 在 `../rules.mjs`, 与腾讯云版**共用同一份**。
//   两个宿主各写一份规则的话它们一定会漂, 而漂了的表现是静默的:
//   一边收的另一边拒, 玩家只看到"我的阵容有时候传得上去有时候传不上去"。
//   本文件只负责【存储(Deno KV) + HTTP 外壳】。
//
// 本地跑: deno run -A --unstable-kv server/deno/main.ts 8790
// 部署:   Deno Deploy 关联 GitHub 仓库, 入口填 server/deno/main.ts

import {
  BUCKET_CAP,
  MAX_BODY,
  parseQuery,
  reject,
  stripForStore,
  stripForWire,
} from "../rules.mjs";

// ★白名单用【静态 JSON import】而不是 require —— Deno Deploy 按模块图打包,
//   静态 import 的 JSON 会被一起带上去; 运行时读文件在 Deploy 上是没有的。
import whitelist from "../cloudbase/whitelist.json" with { type: "json" };

const TURTLE_IDS: string[] = whitelist.TURTLE_IDS;
const EQUIP_IDS: string[] = whitelist.EQUIP_IDS;

// ★★本地跑用【内存库】, 线上用平台托管的 KV。
//
// 由来(2026-08-27, 是门禁自己抓出来的): `Deno.openKv()` 不带参数时会在磁盘上开一个
// **持久化**数据库。于是本地跑门禁 ⇒ 数据留在盘上 ⇒ 下一次跑接着累积。
// 具体现象: 我做反向验证(故意让去重失效)造出 5 条重复, **把代码还原之后门禁照样红** ——
// 因为脏数据还在盘里。一个"跑第二遍结果就变"的门禁是不可信的。
// ⇒ 本地(带端口参数)一律 `:memory:`, 每次从零开始; Deploy 上不带参数, 用平台的 KV。
const _localPort = Number(Deno.args[0] || 0);
const kv = await Deno.openKv(_localPort > 0 ? ":memory:" : undefined);

/**
 * KV 的键设计: ["ghosts", bracket, ghost_id] → 快照
 *
 * ★为什么把 bracket 放进键而不是存字段里: KV 只能按键前缀列举, 没有"按字段查询"。
 *   把 bracket 放进前缀, "取某一档的全部"就是一次 list, 而不是全表扫。
 * ★ghost_id 放末段 ⇒ **同 id 重传天然覆盖**, 不需要先查后删
 *   (腾讯云那版要先 where 再 set, 因为它是文档库)。去重语义两边一致。
 */
const NS = "ghosts";

type Snap = Record<string, unknown>;

function json(code: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: code,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

async function handlePost(req: Request): Promise<Response> {
  const raw = await req.text();
  if (raw.length > MAX_BODY) return json(413, { error: "body 过大" });
  let snap: Snap;
  try {
    snap = JSON.parse(raw);
  } catch {
    return json(400, { error: "JSON 解析失败" });
  }

  const why = reject(snap, TURTLE_IDS, EQUIP_IDS);
  if (why) return json(400, { error: why });

  const doc = stripForStore(snap) as Snap;
  doc.created_at = Date.now();
  doc.bracket = Number(doc.bracket);
  const br = doc.bracket as number;
  const gid = String(doc.ghost_id);

  await kv.set([NS, br, gid], doc);

  // 桶封顶: 该档超了就把【最旧的】挤出去(与客户端 BUCKET_CAP 同值)。
  // ★按 created_at 排序而不是按键序 —— 键是 ghost_id, 与新旧无关,
  //   按键序删会随机删掉活跃玩家的那条。
  const rows: Snap[] = [];
  for await (const e of kv.list<Snap>({ prefix: [NS, br] })) rows.push(e.value);
  if (rows.length > BUCKET_CAP) {
    rows.sort((a, b) => Number(a.created_at) - Number(b.created_at));
    for (const old of rows.slice(0, rows.length - BUCKET_CAP)) {
      await kv.delete([NS, br, String(old.ghost_id)]);
    }
  }
  return json(200, { ok: true });
}

async function handleGet(url: URL): Promise<Response> {
  const q = parseQuery(Object.fromEntries(url.searchParams));
  if (q.error) return json(400, { error: q.error });

  const rows: Snap[] = [];
  for await (const e of kv.list<Snap>({ prefix: [NS, q.bracket] })) {
    rows.push(e.value);
  }
  // 按新鲜度给最新的一批 —— 客户端自己会 pool_find 随机抽。
  rows.sort((a, b) => Number(b.created_at) - Number(a.created_at));
  return json(200, { ghosts: rows.slice(0, q.limit).map(stripForWire) });
}

async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  try {
    if (req.method.toUpperCase() === "POST") return await handlePost(req);
    return await handleGet(url);
  } catch (e) {
    // ★不许把异常吞掉变成 200 —— 客户端对失败是免疫的(静默忽略),
    //   但"服务端出错却报成功"会让脏数据看起来像入库了。
    return json(500, { error: String(e) });
  }
}

// 本地带端口参数跑; Deno Deploy 上不传参数, 由平台接管监听。
const port = _localPort;
if (port > 0) {
  Deno.serve({ port, hostname: "127.0.0.1" }, handler);
} else {
  Deno.serve(handler);
}
