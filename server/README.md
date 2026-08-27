# 阵容交换所 · 运维手册

> 方案书：[docs/plans/20260820-阵容上传后端.md](../docs/plans/20260820-阵容上传后端.md)
> 客户端：[scripts/net/remote_pool.gd](../scripts/net/remote_pool.gd)

---

## 现在跑在哪

| 项 | 值 |
|---|---|
| 平台 | **Deno Deploy**（2026-08-27 上线。GitHub 登录，**免实名、免信用卡**） |
| 组织 / 应用 | `yinzuoliu87-cpu` / `turtle-ghost` |
| **生产地址** | `https://turtle-ghost.yinzuoliu87-cpu.deno.net` |
| 入口文件 | `server/deno/main.ts` |
| 存储 | Deno KV（控制台 → Databases → Provision Deno KV Database） |
| 客户端开关 | `project.godot` → `[turtle] backend_url` |

**部署方式是「关联 GitHub 仓库」** —— push 到 `main` 之后，在 Deno Deploy 控制台
点一次部署即可（或按其自动触发设置）。不需要 token，不需要本地 CLI。

### ⚠ App Directory 必须留在 **root**

入口 `server/deno/main.ts` 要 import **上一级**的两个文件：

```
../rules.mjs                  ← 两个宿主共用的校验规则
../cloudbase/whitelist.json   ← 龟 28 只 / 装备 95 件白名单
```

把 App Directory 改成 `server/deno` 会让这两个 `../` 跳出根目录，**构建直接失败**。

---

## 验证到哪一步了

| 项 | 状态 |
|---|---|
| 客户端整层（校验/并池/传输/失败静默） | ✅ `verify_remote_pool.gd` 23 条 |
| 服务端**逻辑**（六类伪造拒绝 / V2 往返 / 去重） | ✅ `tools/server_logic_gate.py`，**两个宿主各 13 条** |
| 服务端规则 ↔ 客户端事实源 一致性 | ✅ `tools/server_rule_sync.py` |
| **云上真部署** | ✅ 对着真云端跑 `backend_smoke.py` **13 条全过** |
| **两台真手机 A→B** | ⏳ **只剩这一条** —— 地址已进配置，出包即可验 |

```bash
# 真机验收(部署后 / 改完服务端后都跑一次)
python tools/backend_smoke.py https://turtle-ghost.yinzuoliu87-cpu.deno.net

# 本地调试, 不碰云端
deno run -A --unstable-kv server/deno/main.ts 8790
python tools/backend_smoke.py http://127.0.0.1:8790
```

---

## 架构：一份规则，两个宿主

```
server/
  rules.mjs          ← 校验规则(零依赖零 I/O)。两个宿主 import 同一份
  deno/main.ts       ← Deno Deploy: 存储 Deno KV          【当前在用】
  cloudbase/index.js ← 腾讯云 CloudBase: 存储文档库        【写好了, 没部署】
  local_host.js      ← 本地宿主(内存库 + HTTP 外壳), 供门禁跑真 index.js
```

**规则只留一份**是硬约束：两个宿主各写一份的话它们**一定会漂**，而漂了的表现是静默的
—— 一边收的另一边拒，玩家只看到"我的阵容有时候传得上去有时候传不上去"。
门禁两个宿主跑同一套 13 条：改坏共享规则**两边一起红**，只改坏某一边的存储**只有那边红**。

**要迁回国内（腾讯云）时**：`cloudbase/index.js` 已经写好并在本地验过逻辑，
只差开通环境（**要实名**）+ 部署，然后把 `backend_url` 换成新地址。规则一个字都不用动。

---

## 四个必须记住的坑

**① `Deno.openKv()` 不带参数会开磁盘持久库。**
本地跑门禁会**累积脏数据**，出现"代码还原了门禁照样红""跑第二遍结果就变"。
`main.ts` 按有没有端口参数区分：本地一律 `:memory:`，Deploy 上用平台的 KV。

**② 门禁进程必须停用整层。**
`run-tests.sh` 里带 `TURTLE_BACKEND=" "`。否则每个调 `find_opponent` 的测试都会真发一次拉取，
而拉取成功会 `save_pool()` **写本地池文件** —— 250 项门禁中途改写共享状态就是不确定性来源
（这条比"会不会报错"更要紧：报错看得见，数据被改看不见）。

**③ `_http()` 必须判 `is_inside_tree()`。**
建树 / 拆场景的时刻触发上传或拉取，会刷 `Condition "!is_inside_tree()" is true`（实测一次三条）。
**这不只是测试问题 —— 出包后玩家真机上同样会刷。**

**④ 本机的 `HTTP_PROXY` 会改写 POST body。**
`http://127.0.0.1:18081` 会让到达服务端的内容**开头多一个 CRLF CRLF、末尾截掉 4 字节**
⇒ JSON 全部解析失败 ⇒ 服务端把**所有**快照（包括合法的）判成非法。
`curl` 与 `urllib` 都读这个环境变量，所以两边现象一致，极易误判成服务端逻辑坏了。
`backend_smoke.py` 已**默认绕开系统代理**（`USE_PROXY=1` 可反悔）。

---

## 冒烟数据不会污染玩家

`backend_smoke.py` 会往**真的生产池**传一条快照来验 V2 往返，而**服务端故意没有公开的删除接口**
（那是攻击面）。所以：**客户端认 `__smoke__` 前缀并拒绝入池** ——
那条测试数据永远不会变成谁的对手。

放客户端不放服务端，是因为服务端一旦拒收，V2「传上去能拉回来」就没法验了。

---

## 出问题先看哪

| 现象 | 多半是 |
|---|---|
| 游戏里完全没反应 | `backend_url` 是空的，或环境里残留了空的 `TURTLE_BACKEND`（**空地址 = 整层停用**，这是有意的） |
| 合法快照被拒 | 本机代理改写 body（见坑④），或 `whitelist.json` 过期 |
| 拉回来一条都不入池 | `schema_ver` 对不上（升过 `Backend.SCHEMA_VER` 但服务端没跟上，`server_rule_sync` 会红） |
| 上传没报错但别人打不到 | 看云函数日志有没有 400；多半是新增龟/装备后没重跑 `python tools/gen_server_whitelist.py` |
| 构建失败说找不到 `../rules.mjs` | App Directory 被改成了 `server/deno`，改回 root |

---

## 换回腾讯云的话（备选，需要实名）

1. 控制台 https://console.cloud.tencent.com/tcb ，**实名认证** → 新建环境
   > ⚠ **开通后第一件事设消费上限**（费用中心 → 费用预警）。方案书 §风险 4 写着
   > 「免费额度用完是静默降级还是扣费，未核实」——在核实之前，上限是唯一的保险。
2. 数据库新建集合 `ghosts`，索引 `bracket`(升序) + `created_at`(降序)
3. 云函数粘贴 `cloudbase/index.js`，同时上传 `rules.mjs` / `whitelist.json` / `package.json`
4. 开 HTTP 访问服务 → 拿到 `*.service.tcloudbase.com` 地址（**默认域名免备案**，只有自定义域名才要 ICP）
5. `python tools/backend_smoke.py <新地址>` 绿了再把 `backend_url` 换过去
