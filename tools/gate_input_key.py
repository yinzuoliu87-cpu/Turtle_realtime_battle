"""gate_input_key.py —— 门禁「测试输入」哈希（2026-11-04，用户「改」：只改文档的提交复用上次全绿）。

run-tests.sh 开头调它算一个 key；与上次全绿时记下的 key 相同（且没过期）⇒ 自证测试 + 冒烟复用上次结果，
只跑审计器（审计器读文档，文档改了它们照样把关）。key 不同 ⇒ 照旧跑全套。

key 覆盖（= Godot 测试与游戏可能读到的一切）：
  · git 跟踪的全部文件（按工作区内容：已改未暂存的、已删的都算）+ 未跟踪且没被 .gitignore 的文件
  · Godot 可执行文件（路径 + 大小 + 修改时间）
  · KEY_VER（改了本脚本的口径就 +1，旧记录自动作废）
只排除：docs/ 下与根目录的 .md —— **但凡被 Godot 侧代码（tests / scripts / autoload / scenes 里的 .gd .tscn .tres，
  project.godot，export_presets.cfg）用 "res://<路径>" 点名的，一律算输入**（例：CHANGELOG.md 被 verify_version 读，
  docs/隐私政策.md 被 verify_contact_email 读）。名单每次现扫，不手写。

用法：
  python tools/gate_input_key.py              # 打印 key（一行）
  python tools/gate_input_key.py --explain    # 另打印分母：算进去几个文件、排除几个、被点名而保留的文档
"""
import hashlib, os, re, subprocess, sys

KEY_VER = "1"
ROOT = os.environ.get("GATE_KEY_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT_SIDE_DIRS = ("tests/", "scripts/", "autoload/", "scenes/")
GODOT_SIDE_EXT = (".gd", ".tscn", ".tres")
GODOT_SIDE_FILES = ("project.godot", "export_presets.cfg")
RES_REF = re.compile(r"res://([^\"'\s)]+)")


def git(*args: str) -> bytes:
    return subprocess.run(["git", "-C", ROOT, *args], capture_output=True, check=True).stdout


def hash_paths(paths: list) -> dict:
    """git hash-object 批量算工作区内容的 blob 哈希（与 ls-files -s 同一口径）。"""
    if not paths:
        return {}
    out = subprocess.run(["git", "-C", ROOT, "hash-object", "--stdin-paths"], input="\n".join(paths).encode("utf-8"),
                         capture_output=True, check=True).stdout.decode().split()
    return dict(zip(paths, out))


def is_doc_candidate(p: str) -> bool:
    return p.startswith("docs/") or ("/" not in p and p.lower().endswith(".md"))


def referenced(files: list) -> set:
    refs = set()
    for p in files:
        if not ((p.startswith(GODOT_SIDE_DIRS) and p.endswith(GODOT_SIDE_EXT)) or p in GODOT_SIDE_FILES):
            continue
        try:
            s = open(os.path.join(ROOT, p), encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for m in RES_REF.finditer(s):
            refs.add(m.group(1))
    return refs


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    entries = {}
    for rec in git("ls-files", "-s", "-z").split(b"\0"):
        if not rec:
            continue
        meta, path = rec.split(b"\t", 1)
        entries[path.decode("utf-8")] = meta.split()[1].decode()
    changed = [p.decode("utf-8") for p in git("diff", "--name-only", "-z").split(b"\0") if p]
    untracked = [p.decode("utf-8") for p in git("ls-files", "-o", "--exclude-standard", "-z").split(b"\0") if p]
    live = [p for p in changed + untracked if os.path.isfile(os.path.join(ROOT, p))]
    for p in changed:
        if p not in live:
            entries[p] = "DELETED"
    entries.update(hash_paths(live))
    refs = referenced(sorted(entries))
    ## 点名的是目录前缀(例 "res://docs/" + 拼出来的文件名)⇒ 那个目录下的文档全部保守地算输入
    prefixes = tuple(r.rstrip("/") + "/" for r in refs)

    def named(p: str) -> bool:
        return p in refs or p.startswith(prefixes)
    kept_docs = sorted(p for p in entries if is_doc_candidate(p) and named(p))
    excluded = sorted(p for p in entries if is_doc_candidate(p) and not named(p))
    h = hashlib.sha256()
    h.update(("KEY_VER=" + KEY_VER + "\n").encode())
    for p in sorted(entries):
        if p in excluded:
            continue
        h.update(p.encode("utf-8") + b"\0" + entries[p].encode() + b"\n")
    godot = os.environ.get("GODOT", "")
    if godot:
        gp = godot
        if os.name == "nt" and re.match(r"^/[a-zA-Z]/", gp):
            gp = gp[1].upper() + ":" + gp[2:]
        try:
            st = os.stat(gp)
            h.update(("GODOT=%s|%d|%d\n" % (os.path.basename(gp), st.st_size, int(st.st_mtime))).encode())
        except OSError:
            h.update(("GODOT=%s|missing\n" % godot).encode())
    print(h.hexdigest())
    if "--explain" in sys.argv:
        n_in = len(entries) - len(excluded)
        print("算进 key 的文件 %d 个（未跟踪 %d / 工作区改动 %d）· 排除的文档 %d 个 · 被 Godot 侧点名而保留的文档 %d 个:"
              % (n_in, len(untracked), len(changed), len(excluded), len(kept_docs)))
        for p in kept_docs:
            print("  保留 " + p)


if __name__ == "__main__":
    main()
