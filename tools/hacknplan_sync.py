# -*- coding: utf-8 -*-
"""HacknPlan 云端知识库同步工具 (实时版)。
把 docs/design/28龟技能设计-权威.md 的结构化内容推到 HacknPlan GDM。

幂等: 每个元素按 name 在父下查找, 存在则 PATCH 更新, 不存在则 POST 创建 → 可反复跑不重复。
★所有输出写文件 (控制台 GBK 会崩 emoji)。key 在 ~/.hacknplan_key。

用法(供 sync round 脚本 import):
    from hacknplan_sync import HP
    hp = HP()
    root = hp.upsert(0, "🐢 实时版 …", "desc", 13)         # 顶层文件夹
    hp.upsert(root, "1. 小龟 (basic)", "desc…", 11)          # 角色

设计元素类型: 1Chapter 2World 3Zone 4Level 5Stage 6Location 7Menu 8Cutscene
             9System 10Mechanic 11Character 12Object 13Folder
"""
import json, io, os, urllib.request, urllib.error, time

PROJECT = 238168
BASE = "https://api.hacknplan.com/v0/projects/%d" % PROJECT


class HP:
    def __init__(self):
        self.key = io.open(os.path.expanduser("~/.hacknplan_key")).read().strip()
        self._children = {}   # parentId -> {name: element}

    def _req(self, path, body=None, method="GET"):
        data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
        r = urllib.request.Request(BASE + path, data=data, method=method,
                                   headers={"Authorization": "ApiKey " + self.key,
                                            "Content-Type": "application/json"})
        for attempt in range(4):
            try:
                resp = urllib.request.urlopen(r, timeout=40)
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw.strip() else {}
            except urllib.error.HTTPError as e:
                # 移动/PATCH 有时返 500 但已生效; 429 限流退避
                if e.code in (429, 500, 503) and attempt < 3:
                    time.sleep(1.5 * (attempt + 1))
                    continue
                raise

    def children(self, parent_id):
        # ★2026-07-11 修真bug: `?parentId=N` 端点【不按父过滤, 返回整个项目扁平列表】。
        #   旧实现拿它当"某父的子元素"→ 幂等按名字在【全项目】查(名字唯一时侥幸对), 且无法判断真实归属。
        #   真实父子关系只在 tree(parentId=0) 的 children 字段里 → 用 tree 递归找 parent_id 的直接 children。
        if parent_id not in self._children:
            self._children[parent_id] = {}
            if parent_id == 0:
                for e in self._req("/designelements?parentId=0"):
                    self._children[0][e["name"]] = e
            else:
                tree = self._req("/designelements?parentId=0")
                node = self._find(tree, parent_id)
                for c in (node.get("children", []) if node else []):
                    self._children[parent_id][c["name"]] = c
        return self._children[parent_id]

    def _find(self, els, tid):
        for e in els:
            if e.get("designElementId") == tid:
                return e
            r = self._find(e.get("children", []), tid)
            if r:
                return r
        return None

    def move(self, eid, parent_id):
        """把元素移到 parent_id 下 (创建时 parentId 可能不生效, 需单独 PATCH)。"""
        self._req("/designelements/%d" % eid, {"parentId": parent_id}, method="PATCH")

    def upsert(self, parent_id, name, description, type_id):
        """按 name 在 parent 下查找; 存在→PATCH description, 否则→POST 创建。返回 designElementId。"""
        existing = self.children(parent_id).get(name)
        if existing:
            eid = existing["designElementId"]
            if existing.get("description", "") != description:
                self._req("/designelements/%d" % eid,
                          {"name": name, "description": description}, method="PATCH")
            return eid
        el = self._req("/designelements",
                       {"name": name, "description": description,
                        "designElementTypeId": type_id, "parentId": parent_id},
                       method="POST")
        eid = el["designElementId"]
        # ★创建时的 parentId 不一定生效(实测新元素会飘到顶层) → 无条件补一次 move 保证归位。
        if parent_id != 0:
            self.move(eid, parent_id)
        self._children[parent_id][name] = el   # 缓存, 避免同轮重复创建
        return eid
