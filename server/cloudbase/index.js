// 斗龟场·实时版 —— ghost 快照交换所 (腾讯云开发 CloudBase 云函数)
//
// 方案书: docs/plans/20260820-阵容上传后端.md
// 客户端: scripts/net/remote_pool.gd (POST /ghost, GET /ghosts?bracket=N&limit=M)
//
// ★★这份文件【还没有部署过】。它需要一个腾讯云开发环境, 而开通要实名认证 ——
//   用户 2026-08-25 拍板「先不管」。所以这里交付的是**可直接粘贴的实现**,
//   不是"已上线的服务"。方案书 V2/V3 的服务端半边因此仍标着「未验」, 没有假装做完。
//
// 部署(等真要开的时候):
//   1. 云开发控制台 → 云函数 → 新建 → Node.js → 把本文件粘进去
//   2. 数据库新建集合 `ghosts`, 建索引: bracket(升序) + created_at(降序)
//   3. 云函数 → 触发器 → HTTP 访问服务 → 拿到 *.service.tcloudbase.com 的地址
//   4. 客户端: ProjectSettings `turtle/backend_url` 填那个地址(或环境变量 TURTLE_BACKEND)
//   ⚠ 开通前先看计费页并**设消费上限**(方案书 风险 4: 免费额度用完是静默降级还是扣费, 未核实)

const tcb = require('@cloudbase/node-sdk')
const app = tcb.init({ env: tcb.SYMBOL_CURRENT_ENV })
const db = app.database()
const COL = 'ghosts'

// ── 必须与客户端保持一致的三个数 ──────────────────────────────
// ★这三个是**手抄自客户端**, 而手抄的副本必然落后(本项目踩过很多次)。
//   ⇒ 客户端侧有 `verify_remote_pool.gd` 从产品自己的表取值来验;
//     这一侧靠 `tools/server_rule_sync.py` 逐条对账(进门禁), 对不上直接红。
//   千万不要只改一边。
const SCHEMA_VER = 2      // ← Backend.SCHEMA_VER
const MAX_LEVEL = 10      // ← P2Config.MAX_LEVEL
const UNIT_EQUIP_CAP = 3  // ← P2Config.UNIT_EQUIP_CAP
const BUCKET_CAP = 50     // ← Backend.BUCKET_CAP (每档保留多少份)
const MAX_BODY = 16 * 1024 // 一份快照实测 1~3 KB; 16 KB 已是宽松上限, 超了必是垃圾

// 白名单由构建脚本生成(tools/gen_server_whitelist.py 从 turtle_stats / equip_stats 导出)。
const { TURTLE_IDS, EQUIP_IDS } = require('./whitelist.json')

/**
 * 一份快照能不能收 —— **与 RemotePool.snapshot_valid() 是同一份规则**。
 * 返回 null = 合法; 返回字符串 = 拒绝理由。
 *
 * ★服务端这一侧是"别人别塞脏数据", 客户端那一侧是"塞进来了我也不能崩"。
 *   两边各跑一次是冗余不是重复 —— 我控制不了服务器什么时候被绕过。
 */
function reject (d) {
  if (!d || typeof d !== 'object' || Array.isArray(d)) return '不是对象'
  if (Number(d.schema_ver) !== SCHEMA_VER) return `schema_ver=${d.schema_ver} ≠ ${SCHEMA_VER}`
  if (!d.ghost_id || typeof d.ghost_id !== 'string') return '缺 ghost_id'
  const br = Number(d.bracket)
  if (!Number.isInteger(br) || br < 0 || br > 8) return `bracket=${d.bracket} 越界`

  if (!Array.isArray(d.leaders) || d.leaders.length < 1 || d.leaders.length > 3) return 'leaders 不是 1~3 只'
  for (const pid of d.leaders) {
    if (!TURTLE_IDS.includes(String(pid))) return `龟 id \`${pid}\` 不在白名单`
  }
  if (d.pet_levels && typeof d.pet_levels === 'object') {
    for (const [k, v] of Object.entries(d.pet_levels)) {
      const lv = Number(v)
      if (!Number.isInteger(lv) || lv < 1 || lv > MAX_LEVEL) return `${k} 等级 ${v} 越界(1~${MAX_LEVEL})`
    }
  }
  if (d.equipped && typeof d.equipped === 'object') {
    for (const [k, arr] of Object.entries(d.equipped)) {
      if (!Array.isArray(arr)) return `${k} 的 equipped 不是数组`
      if (arr.length > UNIT_EQUIP_CAP) return `${k} 带了 ${arr.length} 件装备(上限 ${UNIT_EQUIP_CAP})`
      for (const e of arr) {
        const eid = (e && typeof e === 'object') ? String(e.id) : String(e)
        if (!EQUIP_IDS.includes(eid)) return `装备 id \`${eid}\` 不在白名单`
      }
    }
  }
  return null
}

exports.main = async (event) => {
  const method = (event.httpMethod || 'GET').toUpperCase()
  const path = String(event.path || '')

  // ── POST /ghost: 收一份 ──────────────────────────────────
  if (method === 'POST') {
    const raw = String(event.body || '')
    if (raw.length > MAX_BODY) return json(413, { error: 'body 过大' })
    let snap
    try { snap = JSON.parse(raw) } catch (e) { return json(400, { error: 'JSON 解析失败' }) }

    const why = reject(snap)
    if (why) return json(400, { error: why })

    // ★去重: 同 ghost_id 覆盖旧的(一个逻辑对手 = 一条), 与客户端 pool_add 同规则。
    //   不这么做的话, 同一个人每打一局就往池里堆一条, "排除最近 3 场"形同虚设。
    // ★origin 由**客户端拉回来时盖章**, 服务端存的不带它 —— 它是"相对谁"的概念,
    //   A 传上来那份在 A 那儿是 local, 到了 B 手里就是 remote, 服务端无权定这件事。
    delete snap.origin
    snap.created_at = Date.now()
    snap.bracket = Number(snap.bracket)

    const col = db.collection(COL)
    const dup = await col.where({ ghost_id: snap.ghost_id }).get()
    if (dup.data && dup.data.length > 0) {
      await col.doc(dup.data[0]._id).set(snap)
    } else {
      await col.add(snap)
      // 桶封顶: 该档超了就把最旧的挤出去(与客户端 BUCKET_CAP 同值)。
      const cnt = await col.where({ bracket: snap.bracket }).count()
      if (cnt.total > BUCKET_CAP) {
        const old = await col.where({ bracket: snap.bracket })
          .orderBy('created_at', 'asc').limit(cnt.total - BUCKET_CAP).get()
        for (const o of (old.data || [])) await col.doc(o._id).remove()
      }
    }
    return json(200, { ok: true })
  }

  // ── GET /ghosts?bracket=N&limit=M: 发一批 ────────────────
  const q = event.queryStringParameters || {}
  const bracket = Number(q.bracket)
  const limit = Math.min(Math.max(Number(q.limit) || 20, 1), 50)
  if (!Number.isInteger(bracket) || bracket < 0 || bracket > 8) {
    return json(400, { error: 'bracket 越界' })
  }
  // 随机性: 客户端自己会 pool_find 随机抽, 这里按新鲜度给最新的一批即可。
  const r = await db.collection(COL).where({ bracket })
    .orderBy('created_at', 'desc').limit(limit).get()
  const ghosts = (r.data || []).map(g => {
    const { _id, created_at, ...rest } = g
    return rest
  })
  return json(200, { ghosts })
}

function json (code, body) {
  return {
    statusCode: code,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify(body)
  }
}
