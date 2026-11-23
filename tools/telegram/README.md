# Telegram 网页版操作脚本（PowerShell）

用户 Chrome 里 web.telegram.org/a/ 已登录；跟龟投主站 Tom 沟通时用（用户授权见 memory ref-telegram-web-tom）。
窗口一律放右屏；截图 / 点击都按每屏 DPI（common.ps1 设 SetProcessDpiAwarenessContext(-4)）。产物写 `.out/telegram/`。

| 脚本 | 用途 |
|---|---|
| open.ps1 | 开新窗口 → 挪到右屏最大化；句柄存 `.out/telegram/hwnd.txt` |
| shot.ps1 -Name x | 右屏半尺寸截图 → `.out/telegram/x.png` |
| click.ps1 x y | 按半尺寸截图上的坐标点击（×2） |
| paste.ps1 文件 | 文件内容（UTF-8）进剪贴板 → Ctrl+V；文字一律粘贴，不逐字敲 |
| keys.ps1 '{ENTER}' | SendKeys |
| scroll.ps1 | 滚轮（往下传无符号 4294967176） |
| win.ps1 [-Act close] | 挪窗 / 关窗（WM_CLOSE，Chrome 回后台不杀进程）；先用 hwnd.txt，打开对话后标题会变成对方名字 |
| crop.ps1 / watch_row.ps1 / watch_title.ps1 | 裁图 / 盯某一行或标题变化 |

发文件：回形针 → File → 文件框粘贴完整路径 → 回车 → 写说明 → 发送；等上传走完再关窗。
消息里的 `xxx.md` 会被识别成链接并挂预览，发送前点 × 去掉。
