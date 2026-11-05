# -*- coding: utf-8 -*-
"""sfx_audit.py — 音效 v2 产物与定选表一致(门禁审计器; 不需要仓库外的源文件)。等价于 build_sfx_v2.py --check:
文件齐 / 有声段响度在目标 ±1 dB 或峰值卡住 / 峰值与时长不超上限 / 声道 / 授权台账全覆盖 / scripts/gamedata/sfx_events.gd 与定选表一致 /
旧音效(ev/ 与 PoC 七条、方波合成两条)已删 / 描述表里没有像素 · 卡通一类字眼(2026-11-05 用户「你音效是死贴着像素吗，跟云顶学啥了」)。
用法: python tools/sfx_audit.py   → 末行 ALL OK"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "assetgen"))
import build_sfx_v2  # noqa: E402

sys.exit(build_sfx_v2.check())
