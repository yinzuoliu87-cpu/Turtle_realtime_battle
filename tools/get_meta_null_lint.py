"""get_meta_null_lint.py — 禁止 `obj.get_meta("k", null)`(2026-10-13 内测)。

Godot 4: `get_meta(name, default)` 的 default 是 null 时等于「没给默认值」, 键不存在就打印
`The object does not have any 'meta' values with the key 'k'` —— 内测里选龟页 / 匹配页就这样
往生产报错表里刷(4 个号 8 条 + 1 位安卓玩家)。
写法一律: `(obj.get_meta("k") if obj.has_meta("k") else null)` 或给一个非 null 默认值。

自证: `--selftest` 拿一段坏样本证明本扫描器会报。
"""
import re, sys, pathlib
sys.stdout.reconfigure(encoding="utf-8")

ROOT = pathlib.Path(__file__).resolve().parent.parent
RX = re.compile(r'\.get_meta\(\s*("[^"]*"|\'[^\']*\'|&?"[^"]*")\s*,\s*null\s*\)')


def scan_text(text):
    return [i + 1 for i, line in enumerate(text.splitlines()) if RX.search(line.split('#', 1)[0])]


def main():
    if '--selftest' in sys.argv:
        bad = 'var t = av.get_meta("idle_tw", null)\nvar ok = (av.get_meta("x") if av.has_meta("x") else null)\n'
        hits = scan_text(bad)
        print('selftest 命中行:', hits)
        sys.exit(0 if hits == [1] else 1)
    files = [p for d in ('scripts', 'autoload') for p in (ROOT / d).rglob('*.gd')]
    bad = []
    for p in files:
        for ln in scan_text(p.read_text(encoding='utf-8', errors='replace')):
            bad.append(f'{p.relative_to(ROOT)}:{ln}')
    print(f'分母: 扫了 {len(files)} 个 .gd')
    for b in bad:
        print('  [BAD]', b)
    if bad:
        print(f'FAIL — {len(bad)} 处 get_meta(k, null)')
        sys.exit(1)
    print('ALL OK — 没有 get_meta(k, null)')


if __name__ == '__main__':
    main()
