# -*- coding: utf-8 -*-
"""sfx_audit.py — 音效产物与定选表一致(门禁审计器; 不需要仓库外的源文件)。等价于 build_sfx.py --check:
文件齐 / 响度(L100)在目标 ±1 或峰值卡住 / 峰值与时长不超上限 / 授权台账全覆盖 / scripts/gamedata/sfx_events.gd 与定选表一致。
用法: python tools/sfx_audit.py   → 末行 ALL OK"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "assetgen"))
import build_sfx  # noqa: E402

sys.exit(build_sfx.check())
