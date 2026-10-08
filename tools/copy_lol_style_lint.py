# -*- coding: utf-8 -*-
"""copy_lol_style_lint.py — 技能 / 装备 / 小将 / 名词解释文案的体例门禁(2026-10-08 建, 硬零)。

由来(用户 2026-10-08, 截图指着图鉴被动那一行):
  「这个描述语言还没学明白吗，都算？哪个游戏这么说，我已经让你学过很多游戏了，任然解决不了这个问题」
  ⇒ 10-07 的去口语化清单**跳过了技能/装备机制描述**; 2026-09-30 的 LoL 体例研究只焊了 4 个口语动词进门禁。
     于是正文里的「（普攻、技能、真实伤害都算）」这类括号插话、分号长句一直没人管。

判据不是我拍的, 是拿 LoL 官方 zh_CN 技能文案(860 个技能 / 10.6 万字, `C:/tmp/lol/corpus.json`,
抓法见 docs/plans/ref/20260930-LoL文案体例.md)对比我们的文案按每万字量出来的:
  分号「；」 LoL 0.19 / 我们 35.3(148 倍) · 括号段 LoL 9.5 / 我们 95(10 倍) · 破折号 LoL 0.85 / 我们 5.0
  LoL 零次: 都算 / 算一次 / 照常 / 对方 / 打到 / 每挨 / 归零 / 清空 / 攒到 / 攒够 / 炸开 / 打满 ……
★括号: 我第一版拍了「单个 ≤ 12 字」—— 自检当场红: 截图那句「（普攻、技能、真实伤害都算）」只有 11 字, 被放过了。
  回头量长度分布: LoL 中位 6 / p90 16 / 最长 28, 我们中位 5 / p90 18 —— **长度根本没差**。差在**数量**(密度 10 倍)
  和**内容**(口水话, 由禁用词表管)。⇒ 判据改成: 单个 ≤ 28 字(LoL 最长) + 全部文案括号密度 ≤ 15/万字(LoL 10.1)。
  数值展开式(含 = 或 ×)是我们 Shift 层的写法, 不计入。
★★密度只数【括号里有汉字】的段: 「（{N:...}）」这种纯数值显示不是插话。两边同一口径重量: LoL 9.4/万字, 我们改写前 ≈95, 第一轮改写后 30.7。
「普攻」→「普通攻击」是用户拍板(10-06「真的要说普攻这个吗」/ 10-08「怎么还有普攻写法？」), 不是 LoL 数据(LoL 两种都用)。

用法: python tools/copy_lol_style_lint.py   (进 run-tests 门禁, 通过打印 ALL OK)
"""
import io, json, os, re, sys

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIELD = re.compile(r'^(brief|desc|detail|effectBrief|effectDesc\d*|descMelee|skill_desc)$')
BRACE = re.compile(r'\{[^{}]*\}')
HTML = re.compile(r'</?[a-zA-Z][^>]*>')
BB = re.compile(r'\[/?[a-z_]+(?:=[^\]]*)?\]')
PAREN = re.compile(r'[（(]([^（）()]*)[)）]')
BANNED = ['；', '——', '—', '…', '都算', '也算', '算作', '算一次', '照常', '对方', '打到', '打中', '每挨', '挨打', '归零', '清空',
          '白打', '顺手', '反正', '其实', '攒到', '攒够', '炸开', '打满', '普攻', '不需要手动', '吧。', '呢。', '啦', '嘛']
PAREN_MAX = 28            # LoL 实测最长括号段
PAREN_DENSITY_MAX = 15.0  # 每万字【含汉字】括号段数上限(LoL 同口径实测 9.4)
CJK = re.compile(r'[\u4e00-\u9fff]')


def _strip(s):
    return BB.sub('', HTML.sub('', BRACE.sub('', s)))


def violations(text):
    out = []
    plain = _strip(text)
    for w in BANNED:
        if w in plain:
            out.append('禁用「%s」' % w)
    for m in PAREN.finditer(BRACE.sub('{}', text)):
        inner = m.group(1)
        if '=' in inner or '×' in inner:
            continue
        core = _strip(inner)
        if len(core) > PAREN_MAX:
            out.append('括号过长「%s」' % core)
    return out


def _walk(o, path, acc, file):
    if isinstance(o, dict):
        for k, v in o.items():
            if isinstance(v, str) and FIELD.match(k) and re.search(r'[\u4e00-\u9fff]', v):
                acc.append((file, path + '.' + k, v))
            elif isinstance(v, (dict, list)):
                _walk(v, path + '.' + str(k), acc, file)
    elif isinstance(o, list):
        for i, x in enumerate(o):
            label = x.get('id', i) if isinstance(x, dict) else i
            _walk(x, path + '[%s]' % label, acc, file)


def collect():
    acc = []
    for f in ['data/pets.json', 'data/phase2-equipment.json']:
        _walk(json.load(io.open(os.path.join(ROOT, f), encoding='utf-8')), '', acc, f)
    for f in ['scripts/gamedata/minion_codex.gd', 'scripts/gamedata/glossary.gd']:
        s = io.open(os.path.join(ROOT, f), encoding='utf-8').read()
        for m in re.finditer(r'"((?:[^"\\\n]|\\.)*[\u4e00-\u9fff](?:[^"\\\n]|\\.)*)"', s):
            ls = s.rfind('\n', 0, m.start()) + 1
            if s[ls:m.start()].lstrip().startswith('#') or len(m.group(1)) < 8:
                continue
            acc.append((f, 'L%d' % (s.count('\n', 0, m.start()) + 1), m.group(1)))
    return acc


def selftest():
    ## 已知阳性: 用户截图里那一句原文 + 分号 + 破折号; 已知阴性: 数值展开式与 LoL 式短限定语。
    pos = '对敌人造成的所有伤害（普攻、技能、真实伤害都算）按目标的稀有度提升；持续 3 秒——（' + '很长' * 15 + '）'
    neg = '造成（{C:X%}%×攻击力 = {N:ATK}）物理伤害，施加一层【气环】（最多 3 层）。'
    vp, vn = violations(pos), violations(neg)
    assert any('都算' in x for x in vp) and any('；' in x for x in vp) and any('括号' in x for x in vp), vp
    assert vn == [], vn


def main():
    selftest()
    acc = collect()
    bad = []
    n_par = 0
    n_chars = 0
    for f, p, t in acc:
        n_chars += len(_strip(t))
        n_par += sum(1 for m in PAREN.finditer(BRACE.sub('{}', t)) if '=' not in m.group(1) and '×' not in m.group(1)
                     and CJK.search(_strip(m.group(1))))
        for v in violations(t):
            bad.append('%s %s: %s' % (f, p, v))
    dens = n_par / max(1, n_chars) * 10000.0
    print('  [分母] 扫了 %d 段玩家文案(龟 / 装备 / 小将 / 名词解释) / %d 字' % (len(acc), n_chars))
    print('  括号密度(含汉字) %.1f / 万字(上限 %.0f, LoL 9.4)' % (dens, PAREN_DENSITY_MAX))
    if dens > PAREN_DENSITY_MAX:
        bad.append('全部文案: 括号密度 %.1f/万字 > %.0f(括号插话太多, 写进正句或删)' % (dens, PAREN_DENSITY_MAX))
    if len(acc) < 400:
        print('  [FAIL] 分母过小(<400): 扫描范围漂了, 空检查不是通过')
        return 1
    for b in bad[:40]:
        print('  [FAIL] ' + b)
    if bad:
        print('FAILED: %d 处(规则与 LoL 实测依据见本文件头)' % len(bad))
        return 1
    print('ALL OK — 文案体例(无分号/破折号/括号插话/口语词/「普攻」)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
