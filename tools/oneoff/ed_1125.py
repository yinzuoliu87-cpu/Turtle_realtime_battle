"""ed_1125.py —— 按原行尾做字符串替换(2026-11-25 魔法书批接入收尾用)。ed(path, [(旧, 新), ...]) 旧串必须存在。"""
def ed(p, pairs, count=1):
    b = open(p, "rb").read().decode("utf-8")
    nl = "\r\n" if "\r\n" in b else "\n"
    t = b.replace("\r\n", "\n")
    for o, n in pairs:
        assert o in t, (p, o[:70])
        t = t.replace(o, n, count)
    open(p, "wb").write(t.replace("\n", nl).encode("utf-8"))
