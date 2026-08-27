// 快照校验规则 —— **所有服务端实现共用这一份**。
//
// 为什么单独拆出来: 现在有两个宿主(腾讯云 CloudBase / Deno Deploy), 以后可能更多。
// 规则要是各写一份, 它们**一定会漂**, 而漂了的表现是静默的:
// 一边收的另一边拒, 玩家只看到"我的阵容有时候传得上去有时候传不上去"。
// 本项目对"手抄的副本必然落后"有明确教训, 所以从第二个宿主出现的第一天就只留一份。
//
// ★本文件【零依赖、零 I/O】: 不读文件、不碰数据库、不认识 HTTP。
//   白名单由调用方传进来 —— 因为各宿主载入 JSON 的方式不同(Node 的 require / Deno 的
//   `with { type: "json" }`), 让规则去适配宿主就等于又把宿主细节掺进规则里。
//
// ★与客户端的一致性由 `tools/server_rule_sync.py` 逐条对账焊死(进提交门禁):
//   下面四个常量必须与 GDScript 那边逐个相等, 对不上直接红。

// ── 必须与客户端保持一致的四个数 ──────────────────────────────
export const SCHEMA_VER = 2      // ← Backend.SCHEMA_VER
export const MAX_LEVEL = 10      // ← P2Config.MAX_LEVEL
export const UNIT_EQUIP_CAP = 3  // ← P2Config.UNIT_EQUIP_CAP
export const BUCKET_CAP = 50     // ← Backend.BUCKET_CAP (每档保留多少份)

// 一份快照实测 1~3 KB; 16 KB 已是宽松上限, 超了必是垃圾。
export const MAX_BODY = 16 * 1024

/**
 * 一份快照能不能收。返回 null = 合法; 返回字符串 = 拒绝理由。
 *
 * **与客户端 `RemotePool.snapshot_valid()` 是同一份规则。**
 * 服务端这一侧是"别人别塞脏数据", 客户端那一侧是"塞进来了我也不能崩" ——
 * 两边各跑一次是冗余不是重复: 谁都控制不了服务器什么时候被绕过。
 *
 * @param d 待校验的快照
 * @param turtleIds 合法龟 id 数组(由宿主载入 whitelist.json 传入)
 * @param equipIds  合法装备 id 数组
 */
export function reject (d, turtleIds, equipIds) {
  if (!d || typeof d !== 'object' || Array.isArray(d)) return '不是对象'
  if (Number(d.schema_ver) !== SCHEMA_VER) return `schema_ver=${d.schema_ver} ≠ ${SCHEMA_VER}`
  if (!d.ghost_id || typeof d.ghost_id !== 'string') return '缺 ghost_id'
  const br = Number(d.bracket)
  if (!Number.isInteger(br) || br < 0 || br > 8) return `bracket=${d.bracket} 越界`

  if (!Array.isArray(d.leaders) || d.leaders.length < 1 || d.leaders.length > 3) return 'leaders 不是 1~3 只'
  for (const pid of d.leaders) {
    if (!turtleIds.includes(String(pid))) return `龟 id \`${pid}\` 不在白名单`
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
        if (!equipIds.includes(eid)) return `装备 id \`${eid}\` 不在白名单`
      }
    }
  }
  return null
}

/**
 * GET /ghosts 的参数校验与归一。返回 {bracket, limit} 或 {error}。
 * 放进共用规则是因为它同样两边都要, 而且 limit 的钳制上限一旦两边不同,
 * "拉回来几份"就会随服务器而变 —— 那种差异查起来极其费劲。
 */
export function parseQuery (q) {
  const bracket = Number((q && q.bracket) ?? NaN)
  if (!Number.isInteger(bracket) || bracket < 0 || bracket > 8) {
    return { error: 'bracket 越界' }
  }
  const limit = Math.min(Math.max(Number((q && q.limit)) || 20, 1), 50)
  return { bracket, limit }
}

/** 服务端存储时要剥掉的字段 —— origin 是"相对谁"的概念, 由客户端拉回时自己盖章。 */
export function stripForStore (snap) {
  const out = Object.assign({}, snap)
  delete out.origin
  return out
}

/** 返回给客户端前要剥掉的字段(数据库内部字段不该出现在协议里)。 */
export function stripForWire (row) {
  const out = Object.assign({}, row)
  delete out._id
  delete out.created_at
  delete out.origin
  return out
}
