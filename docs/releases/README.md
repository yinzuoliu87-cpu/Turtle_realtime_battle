# docs/releases —— 每一版的发版清单

一版一份 `<版本>.md`，由 `python tools/release.py checklist <版本>` 生成（模板是 `tools/release.py` 里的 `CHECKLIST`）。
按顺序做，每步回读对上了才打勾；打完勾随下一个提交进仓库，这一版每一步做没做、回读到什么就留在这里。
流程变了改模板，不在单份清单里改步骤顺序。

| 步骤 | 命令 |
|---|---|
| 版本号五处 + CHANGELOG 骨架 + 路线图一行（+ `RULES_VER`） | `python tools/release.py bump <版本> --rules same\|changed` |
| 打 tag（只推这一个，触发 TestFlight） | `python tools/release.py tag <版本>` |
| 提审 TestFlight 公开测试 | `python tools/asc.py submit <版本>` |
| 裁判机 / 陪练号 / 对手池 | `python tools/deploy.py <版本>` |
| 强制更新（苹果审过之后） | `python tools/prod_flags.py force-update <版本> --yes-prod` |
| 上一版撤出公开测试组 | `python tools/asc.py group-remove <上一版>` |

每条命令先跑 `--dry-run`（`prod_flags.py` 不带 `--yes-prod` 就只打计划）。
`tools/release_selftest.py` 在门禁里守 `release.py`（五处、行尾、`RULES_VER`、已存在的 tag 拒绝挪动）。
