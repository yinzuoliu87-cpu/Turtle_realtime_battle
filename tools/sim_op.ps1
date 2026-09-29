param(
  [Parameter(Mandatory=$true)][string]$Cmd,
  [int]$X = 0, [int]$Y = 0, [int]$W = 0, [int]$H = 0,
  [int]$Slot = 0,
  [int]$WinX = -99999, [int]$WinY = -99999,
  [int]$TargetPid = 0,
  [string]$Out = "C:	mp\sim_op.png"
)
# tools/sim_op.ps1 -- 操控模拟槽位的窗口: 截图 / 点击 / 置顶
#
# ★这份文件必须存成【UTF-8 带 BOM】。Windows PowerShell 5.1 读 .ps1 默认按 ANSI,
#   没 BOM 的中文注释会乱码, 乱码会把 param 块撑断 —— 报错长得像「赋值表达式无效」,
#   完全看不出是编码问题。(memory: fb-ps51-setcontent-mojibake)
#
# ★为什么不用 SendKeys / PostMessage:
#   Godot 走原生输入, PostMessage 的合成消息它多半不吃; SendKeys 本仓也有过教训。
#   ⇒ 老实走「置顶窗口 → 移光标 → 真按下抬起」。一次只操作一个窗口, 顺序来。
# ★必须 SetProcessDPIAware: 不然坐标与截图都会按缩放错位。
# ★参数名不叫 $Pid —— 那是 PowerShell 的自动变量, 不许当参数名。
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Op {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  // ★★SetProcessDPIAware() 只是【系统级】DPI 感知。两块屏 DPI 不同时, Windows 会把
  //   第二块屏上的窗口坐标与尺寸**虚拟化** ⇒ GetWindowRect 报的不是真物理像素,
  //   截图截到的是窗口左上角一块(放大且截断), 点击坐标同样偏。
  //   (2026-09-29 实测: 主屏 6 个正常, 副屏 p07~p10 全部截歪。)
  //   ⇒ 必须 **PER_MONITOR_AWARE_V2** (context = -4)。
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  public static void BestDpi() {
    try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch {}
    SetProcessDPIAware();
  }
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  // ★★Windows 的【前台锁】: SetForegroundWindow 在快速切换时会被系统静默拒绝,
  //   于是点击落在【上一个还占着焦点的窗口】上 —— 十个窗口界面一样, 点错了看不出来。
  //   (2026-09-29 实测: 一刀切点十个窗口, 只有当时已获焦的那个真的响应。)
  //   ⇒ 借前台线程的输入队列(AttachThreadInput) + **点完验证焦点真的换过去了**。
  public static bool Focus(IntPtr h) {
    for (int i = 0; i < 12; i++) {
      if (GetForegroundWindow() == h) return true;
      IntPtr fg = GetForegroundWindow();
      uint me = GetCurrentThreadId();
      uint other = fg == IntPtr.Zero ? me : GetWindowThreadProcessId2(fg);
      if (other != me) AttachThreadInput(me, other, true);
      ShowWindow(h, 9); BringWindowToTop(h); SetForegroundWindow(h);
      if (other != me) AttachThreadInput(me, other, false);
      System.Threading.Thread.Sleep(60);
    }
    return GetForegroundWindow() == h;
  }
  public static uint GetWindowThreadProcessId2(IntPtr h) { uint p; return GetWindowThreadProcessId(h, out p); }
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool AdjustWindowRect(ref RECT r, uint style, bool menu);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  // 客户区在屏幕上的真实矩形(物理像素)。★两块屏 DPI 不同时, 这是唯一可信的来源 ——
  //   别拿"我算出来的槽位几何"当真值, 那在 150% 的屏上会差 1.5 倍。
  public static int[] ClientRect(IntPtr h) {
    RECT c; GetClientRect(h, out c);
    POINT o; o.X = 0; o.Y = 0; ClientToScreen(h, ref o);
    return new int[] { o.X, o.Y, c.R - c.L, c.B - c.T };
  }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static System.Collections.Generic.HashSet<uint> OkPids = new System.Collections.Generic.HashSet<uint>();
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public const uint DOWN = 0x0002;
  public const uint UP = 0x0004;

  // 按【窗口左上角位置】找窗口 —— 不按 PID。
  // ★为什么: Godot 起来之后换了进程, Start-Process 记下的 PID 已经不拥有窗口了
  //   (2026-09-29 实测: 记的 42608 已不存在, 窗口在 47464 手里)。
  //   而十个窗口标题完全一样 ⇒ 只有位置能区分它们, 位置本来就是槽位身份。
  public static IntPtr FindAt(int x, int y, int tol) {
    IntPtr best = IntPtr.Zero; int bestd = int.MaxValue;
    EnumWindows(delegate(IntPtr h, IntPtr p) {
      if (!IsWindowVisible(h)) return true;
      var sb = new System.Text.StringBuilder(256);
      GetWindowTextW(h, sb, 256);
      if (sb.Length == 0) return true;
      // ★★只认游戏进程的窗口。2026-09-29 实测踩到: p01 的期望原点是 (0,0),
      //   而**桌面窗口(Program Manager)的原点也是 (0,0), 距离 0 永远赢**
      //   ⇒ p01 的每一次点击都被送给了桌面, 那个窗口七次点击纹丝不动。
      //   其余槽位原点是 (640,0)/(1280,360)… 没有系统窗口在那儿, 所以只有 p01 中招。
      uint wp; GetWindowThreadProcessId(h, out wp);
      if (OkPids.Count > 0 && !OkPids.Contains(wp)) return true;
      int[] cr = ClientRect(h);
      int d = Math.Abs(cr[0] - x) + Math.Abs(cr[1] - y);
      if (d < bestd) { bestd = d; best = h; }
      return true;
    }, IntPtr.Zero);
    return bestd <= tol ? best : IntPtr.Zero;
  }
}
"@
[Op]::BestDpi()
# 把所有 Godot 进程的 pid 灌进白名单 —— FindAt 只在它们里面找
Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue | ForEach-Object { [Op]::OkPids.Add([uint32]$_.Id) | Out-Null }

function Get-Win([int]$p) {
  # ① 先按【窗口左上角】找(可靠) ② 找不到再退回 PID(兼容旧调用)
  # ★用 -99999 当"没给"的哨兵, 不用 0 —— p01 的窗口原点就是 (0,0),
  #   拿 0 当"没给"会让第一个槽位永远走不到这条路(刚踩过)。
  # ★叠放之后十个窗口同一个位置, 按位置认不出来了 ⇒ **一律按 pid**。
  #   pids.txt 记的是真 pid(Godot 起来之后换进程那个坑已修)。
  #   位置匹配只留作 pid 缺失时的兜底。
  if ($p -le 0 -and $WinX -ne -99999 -and $WinY -ne -99999) {
    $h = [Op]::FindAt($WinX, $WinY, 80)
    if ($h -ne [IntPtr]::Zero) { return $h }
  }
  if ($p -le 0) { return [IntPtr]::Zero }
  $pr = Get-Process -Id $p -ErrorAction SilentlyContinue
  if ($null -eq $pr) { return [IntPtr]::Zero }
  return $pr.MainWindowHandle
}

if ($Cmd -eq "shot") {
  $b = New-Object System.Drawing.Bitmap $W,$H
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.CopyFromScreen($X,$Y,0,0,(New-Object System.Drawing.Size $W,$H))
  $b.Save($Out)
  Write-Output "shot -> $Out  ($X,$Y ${W}x${H})"
}
elseif ($Cmd -eq "click") {
  $h = Get-Win $TargetPid
  if ($h -ne [IntPtr]::Zero) {
    if (-not [Op]::Focus($h)) { Write-Output "click: 抢不到焦点, 放弃(没有瞎点)"; exit 2 }
    Start-Sleep -Milliseconds 80
  } else { Write-Output "click: 找不到窗口"; exit 1 }
  [Op]::SetCursorPos($X,$Y) | Out-Null
  Start-Sleep -Milliseconds 90
  [Op]::mouse_event([Op]::DOWN,0,0,0,[IntPtr]::Zero)
  Start-Sleep -Milliseconds 55
  [Op]::mouse_event([Op]::UP,0,0,0,[IntPtr]::Zero)
  Write-Output "click -> ($X,$Y) pid=$TargetPid"
}
elseif ($Cmd -eq "rect") {
  $h = Get-Win $TargetPid
  if ($h -eq [IntPtr]::Zero) { Write-Output "0 0 0 0"; exit 1 }
  $c = [Op]::ClientRect($h)
  Write-Output ("{0} {1} {2} {3}" -f $c[0], $c[1], $c[2], $c[3])
}
elseif ($Cmd -eq "move") {
  # 把窗口挪到指定【客户区】左上角。★Godot 窗口标题栏在客户区上方 31px,
  #   所以外框要放到 y-31, 否则第二行的标题栏会压住第一行底部 31 像素
  #   (2026-09-29 实测: 商店的「买下」钮正好落在那 31px 里, 点不到)。
  $h = Get-Win $TargetPid
  if ($h -eq [IntPtr]::Zero) { Write-Output "move: 找不到窗口"; exit 1 }
  [Op]::SetWindowPos($h, [IntPtr]::Zero, $X - 8, $Y - 31, 0, 0, 0x0005) | Out-Null
  Write-Output "move -> client($X,$Y)"
}
elseif ($Cmd -eq "focus") {
  $h = Get-Win $TargetPid
  if ($h -eq [IntPtr]::Zero) { Write-Output "没有窗口 pid=$TargetPid"; exit 1 }
  $okf = [Op]::Focus($h)
  Write-Output ("focus -> pid=$TargetPid  成功=" + $okf)
}
else { Write-Output "用法: -Cmd shot|click|focus"; exit 1 }
