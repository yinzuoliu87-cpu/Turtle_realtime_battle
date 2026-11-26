p = "scripts/systems/equip/eq_mask_batch.gd"
raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
a = '\tif not (src as Dictionary).get("alive", false):\n\t\treturn\n\tvar amt: float = float(u.get("def", 0.0)) * float(PAPER_COUNTER[si])\n'
assert s.count(a) == 1
b = '\tif not (src as Dictionary).get("alive", false) or battle._is_untouchable(src):   # §UNTOUCHABLE: 训龟大师扔石头砸到携带者也不回敬(verify_trainer_untouchable S8 抓到)\n\t\treturn\n\tvar amt: float = float(u.get("def", 0.0)) * float(PAPER_COUNTER[si])\n'
s = s.replace(a, b)
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
