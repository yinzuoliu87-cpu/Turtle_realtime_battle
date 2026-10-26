# -*- coding: utf-8 -*-
"""referee_watch 的判据自测（不联网）。进 run-tests 门禁 —— run_audit 调脚本不带参数, 而 referee_watch.py 不带参数是真去探活。"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import referee_watch  # noqa: E402

if __name__ == "__main__":
    sys.exit(referee_watch.selftest())
