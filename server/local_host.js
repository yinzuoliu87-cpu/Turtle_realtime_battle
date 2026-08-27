// 本地宿主 —— 把【真的 index.js】跑起来, 不需要腾讯云账号。
//
// 为什么要有它: 方案书 20260820 的 V3-服务端 一直标着「代码写好了, 没部署过所以没验」。
// 但"没部署"挡住的只是**部署**, 挡不住**逻辑** —— 云函数无非是
//   exports.main(event) → {statusCode, body}
// 把 `@cloudbase/node-sdk` 换成一个内存库、把 HTTP 请求翻译成 event, 真代码就能原样跑。
// ⇒ V3 的六类拒绝规则可以在本地逐条验完, 只剩"云上真部署"这一件事还没验。
//
// ★关键纪律: **不许复制 index.js 的逻辑到这里**。这里只提供 db 和 HTTP 外壳,
//   一旦开始"照抄一份等价实现"就变成了自己验自己(本项目踩过很多次)。
//
// 跑法:
//   node server/local_host.js 8787
//   python tools/backend_smoke.py http://127.0.0.1:8787

const http = require('http')
const path = require('path')
const Module = require('module')

// ── 把 @cloudbase/node-sdk 换成内存实现 ──────────────────────
const store = []          // 每条 = 一份快照 (带 _id / created_at)
let seq = 1

function makeQuery (filter) {
  const match = (d) => Object.entries(filter || {}).every(([k, v]) => d[k] === v)
  let order = null
  let lim = 0
  const q = {
    where: (f) => makeQuery(Object.assign({}, filter, f)),
    orderBy: (field, dir) => { order = [field, dir]; return q },
    limit: (n) => { lim = n; return q },
    get: async () => {
      let rows = store.filter(match)
      if (order) {
        const [f, dir] = order
        rows = rows.slice().sort((a, b) => dir === 'asc' ? a[f] - b[f] : b[f] - a[f])
      }
      if (lim) rows = rows.slice(0, lim)
      return { data: rows.map(r => Object.assign({}, r)) }
    },
    count: async () => ({ total: store.filter(match).length }),
  }
  return q
}

function collection () {
  return Object.assign(makeQuery(null), {
    add: async (doc) => {
      const rec = Object.assign({}, doc, { _id: 'id' + (seq++) })
      store.push(rec)
      return { id: rec._id }
    },
    doc: (id) => ({
      set: async (doc) => {
        const i = store.findIndex(r => r._id === id)
        if (i >= 0) store[i] = Object.assign({}, doc, { _id: id })
        return { updated: 1 }
      },
      remove: async () => {
        const i = store.findIndex(r => r._id === id)
        if (i >= 0) store.splice(i, 1)
        return { deleted: 1 }
      },
    }),
  })
}

const fakeSdk = {
  SYMBOL_CURRENT_ENV: 'local',
  init: () => ({ database: () => ({ collection }) }),
}

// 拦截 require('@cloudbase/node-sdk') —— index.js 本身一个字都不用改
const origResolve = Module._resolveFilename
Module._resolveFilename = function (request, ...rest) {
  if (request === '@cloudbase/node-sdk') return '__fake_tcb__'
  return origResolve.call(this, request, ...rest)
}
require.cache['__fake_tcb__'] = { id: '__fake_tcb__', filename: '__fake_tcb__', loaded: true, exports: fakeSdk }

// ── 加载【真的】云函数 ──────────────────────────────────────
const fn = require(path.join(__dirname, 'cloudbase', 'index.js'))

// ── HTTP 外壳: 把请求翻译成云函数的 event ────────────────────
const port = parseInt(process.argv[2] || '8787', 10)
http.createServer((req, res) => {
  let body = ''
  req.on('data', c => { body += c })
  req.on('end', async () => {
    const u = new URL(req.url, 'http://x')
    const qs = {}
    u.searchParams.forEach((v, k) => { qs[k] = v })
    const event = {
      httpMethod: req.method,
      path: u.pathname,
      body,
      queryStringParameters: qs,
    }
    let out
    if (process.env.HOST_DEBUG) {
      console.log('[event]', JSON.stringify({m: event.httpMethod, p: event.path, blen: body.length, qs}))
    }
    try {
      out = await fn.main(event)
    } catch (e) {
      out = { statusCode: 500, headers: {}, body: JSON.stringify({ error: String(e && e.stack || e) }) }
    }
    if (process.env.HOST_DEBUG) {
      console.log('[out]', JSON.stringify(out).slice(0, 200))
    }
    res.writeHead(out.statusCode || 200, out.headers || { 'Content-Type': 'application/json' })
    res.end(out.body || '')
  })
}).listen(port, '127.0.0.1', () => {
  console.log('本地宿主已起: http://127.0.0.1:' + port + '  (跑的是真的 cloudbase/index.js)')
})
