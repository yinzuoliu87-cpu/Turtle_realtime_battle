// 斗龟场·实时版 —— ghost 快照交换所【腾讯云开发 CloudBase 云函数】
//
// 方案书: docs/plans/20260820-阵容上传后端.md
// 客户端: scripts/net/remote_pool.gd (POST /ghost, GET /ghosts?bracket=N&limit=M)
//
// ★★这份文件【还没有部署过】。它需要一个腾讯云开发环境, 而开通要实名认证。
//   所以这里交付的是**可直接粘贴的实现**, 不是"已上线的服务"。
//   但**逻辑已经在本地验过**: `server/local_host.js` 把 SDK 换成内存库,
//   `tools/server_logic_gate.py` 跑 13 条检查(进提交门禁)。
//
// ★本文件只负责【存储 + HTTP 外壳】。校验规则在 `../rules.mjs`, 与 Deno 版共用同一份 ——
//   两个宿主各写一份规则的话它们一定会漂, 而漂了的表现是静默的。
//
// 部署步骤见 server/README.md。上传时**三个文件都要传**:
//   index.js · ../rules.mjs(放同级或按下面的路径调整) · whitelist.json · package.json

const tcb = require('@cloudbase/node-sdk')
const app = tcb.init({ env: tcb.SYMBOL_CURRENT_ENV })
const db = app.database()
const COL = 'ghosts'

// 白名单由构建脚本生成(tools/gen_server_whitelist.py 从 turtle_stats / equip_stats 导出)。
// **不要手写** —— 新增龟/装备后忘了重跑, 服务端会把合法快照判成伪造, 而且是静默的。
const { TURTLE_IDS, EQUIP_IDS } = require('./whitelist.json')

// ★共用规则是 ESM, 本文件是 CJS(CloudBase 的 handler 约定) ⇒ 用动态 import 桥接。
//   只在首次调用时加载一次并缓存 —— 云函数实例会复用, 不会每次请求都 import。
let _rules = null
async function rules () {
  if (_rules === null) _rules = await import('../rules.mjs')
  return _rules
}

exports.main = async (event) => {
  const R = await rules()
  const method = (event.httpMethod || 'GET').toUpperCase()

  // ── POST /ghost: 收一份 ──────────────────────────────────
  if (method === 'POST') {
    const raw = String(event.body || '')
    if (raw.length > R.MAX_BODY) return json(413, { error: 'body 过大' })
    let snap
    try { snap = JSON.parse(raw) } catch (e) { return json(400, { error: 'JSON 解析失败' }) }

    const why = R.reject(snap, TURTLE_IDS, EQUIP_IDS)
    if (why) return json(400, { error: why })

    // ★去重: 同 ghost_id 覆盖旧的(一个逻辑对手 = 一条), 与客户端 pool_add 同规则。
    //   不这么做的话, 同一个人每打一局就往池里堆一条, "排除最近 3 场"形同虚设。
    const doc = R.stripForStore(snap)
    doc.created_at = Date.now()
    doc.bracket = Number(doc.bracket)

    const col = db.collection(COL)
    const dup = await col.where({ ghost_id: doc.ghost_id }).get()
    if (dup.data && dup.data.length > 0) {
      await col.doc(dup.data[0]._id).set(doc)
    } else {
      await col.add(doc)
      // 桶封顶: 该档超了就把最旧的挤出去(与客户端 BUCKET_CAP 同值)。
      const cnt = await col.where({ bracket: doc.bracket }).count()
      if (cnt.total > R.BUCKET_CAP) {
        const old = await col.where({ bracket: doc.bracket })
          .orderBy('created_at', 'asc').limit(cnt.total - R.BUCKET_CAP).get()
        for (const o of (old.data || [])) await col.doc(o._id).remove()
      }
    }
    return json(200, { ok: true })
  }

  // ── GET /ghosts?bracket=N&limit=M: 发一批 ────────────────
  const q = R.parseQuery(event.queryStringParameters || {})
  if (q.error) return json(400, { error: q.error })

  // 随机性: 客户端自己会 pool_find 随机抽, 这里按新鲜度给最新的一批即可。
  const r = await db.collection(COL).where({ bracket: q.bracket })
    .orderBy('created_at', 'desc').limit(q.limit).get()
  return json(200, { ghosts: (r.data || []).map(R.stripForWire) })
}

function json (code, body) {
  return {
    statusCode: code,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify(body)
  }
}
