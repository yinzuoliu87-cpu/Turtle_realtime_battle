# 阵容交换所 · 部署手册

> 方案书：[docs/plans/20260820-阵容上传后端.md](../docs/plans/20260820-阵容上传后端.md)
> 客户端：[scripts/net/remote_pool.gd](../scripts/net/remote_pool.gd)

**这一层默认是关的。** `project.godot` 的 `turtle/backend_url` 为空 ⇒ 整层 no-op，
游戏行为与接网络前逐字节相同。填上地址才开始同步。

---

## 现在是什么状态

| 项 | 状态 |
|---|---|
| 客户端整层（校验/并池/传输/失败静默） | ✅ 已做，门禁 `verify_remote_pool.gd` 21 条 |
| 服务端云函数代码 | ✅ 已写 `cloudbase/index.js` |
| 服务端**逻辑**（六类伪造拒绝 / V2 往返 / 去重） | ✅ **已验**，门禁 `tools/server_logic_gate.py`（本地跑真 index.js） |
| 服务端规则 ↔ 客户端事实源 一致性 | ✅ 已焊死，门禁 `tools/server_rule_sync.py` |
| **云上真部署** | ❌ **没做** —— 需要腾讯云账号，只能你本人办 |
| 真·两台手机互相打到 | ❌ 卡在上一条 |

---

## 只有你能做的四步（大约 20 分钟）

### 1. 开通腾讯云开发（CloudBase）

- 去 https://console.cloud.tencent.com/tcb
- **要实名认证**（身份证 + 人脸或银行卡），这一步没有任何绕过办法
- 新建环境，**计费方式选「按量计费」**，记下**环境 ID**（形如 `turtle-3xxxxxxx`）

> ⚠ **开通后第一件事：设消费上限。**
> 控制台 →「费用中心 → 费用预警」，设一个你能接受的月度上限（比如 10 元）。
> 方案书 §风险 4 写着「免费额度用完是静默降级还是扣费，未核实」——
> 在没核实之前，上限是唯一的保险。

### 2. 建数据库集合

- 控制台 →「数据库 → 集合」→ 新建集合，名字必须是 **`ghosts`**
- 建索引（不建也能跑，但数据一多会变慢）：
  - `bracket` 升序
  - `created_at` 降序

### 3. 部署云函数

- 控制台 →「云函数 → 新建」，运行环境 **Node.js 16 或更高**
- 把 [`cloudbase/index.js`](cloudbase/index.js) 的内容粘进去
- 同目录再传两个文件：
  - [`cloudbase/whitelist.json`](cloudbase/whitelist.json)（龟 28 只 / 装备 95 件的白名单）
  - [`cloudbase/package.json`](cloudbase/package.json)（声明依赖 `@cloudbase/node-sdk`）
- 保存并**安装依赖**（控制台里有按钮，或用 CloudBase CLI）

> `whitelist.json` 是**生成的，不要手写**：`python tools/gen_server_whitelist.py`。
> 新增龟/装备后忘了重跑，服务端会把**合法快照判成伪造**，而且是静默的 ——
> `tools/server_rule_sync.py` 进了提交门禁就是防这个。

### 4. 开 HTTP 访问服务，拿到地址

- 云函数 →「触发管理 / HTTP 访问服务」→ 新建
- 得到形如 `https://<环境ID>.service.tcloudbase.com/<路径>` 的地址
- **默认域名免备案**（官方文档确认过；只有绑自己的域名才要 ICP 备案）

---

## 拿到地址之后（这部分我来）

```bash
# 1. 真机冒烟 —— 13 条检查, 验的是"服务端真按规则办事"不是"能连上"
python tools/backend_smoke.py https://你的地址

# 2. 绿了就把地址填进 project.godot
#    [turtle]
#    backend_url="https://你的地址"

# 3. 出包给测试者, V2 就能用真手机验了
```

冒烟绿 = 方案书 V2 / V3-服务端 那两条 ⏳ 可以改成 ✅。

---

## 本地怎么调（不需要云账号）

```bash
node server/local_host.js 8790                      # 起本地宿主, 跑的是真 index.js
python tools/backend_smoke.py http://127.0.0.1:8790 # 13 条全过
```

`local_host.js` 只提供内存数据库 + HTTP 外壳，**一行 index.js 的逻辑都没有复制** ——
否则就变成自己验自己了。

> ⚠ **这台机器上有 `HTTP_PROXY=http://127.0.0.1:18081`，而它会改写 POST 的 body**
> （实测：开头多一个 CRLF CRLF、末尾截掉 4 字节 ⇒ JSON 全部解析失败 ⇒
> 服务端把**所有**快照包括合法的判成非法）。`backend_smoke.py` 对本机地址已经绕开代理。
> 如果哪天打真实云地址也出现"合法快照被拒"，先怀疑这个代理。

---

## 出了问题先看哪

| 现象 | 多半是 |
|---|---|
| 游戏里完全没反应 | `backend_url` 没填 / 填了但没重启 —— 这一层空 URL 就整体停用 |
| 上传没报错但别人打不到 | 看云函数日志有没有 400；多半是白名单过期（新增龟/装备后没重跑生成器） |
| 拉回来一条都不入池 | `schema_ver` 对不上（升过 `Backend.SCHEMA_VER` 但服务端那份没跟着改，`server_rule_sync` 会红） |
| 合法快照被拒 | 代理改写 body（见上），或 `whitelist.json` 没上传到云函数目录 |
