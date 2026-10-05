<#
  简剧图标生成脚本（GDI+ / System.Drawing）

  输出：
    - windows\runner\resources\app_icon.ico   窗口标题栏 / 任务栏 / 桌面快捷方式图标（编译进 exe）
    - assets\icons\app_icon.ico               系统托盘图标（tray_manager 从 flutter_assets 读）
    - assets\icons\app_icon.png               应用内左上角品牌图标
    - android\...\mipmap-*\ic_launcher.png     安卓启动图标（各密度）

  用法：powershell -ExecutionPolicy Bypass -File tool\generate_icons.ps1
#>
param(
  [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# 与主题色板 0 号「苹果蓝 #0A84FF」同色系的渐变
$gradStart = [System.Drawing.Color]::FromArgb(255, 62, 168, 255)   # #3EA8FF
$gradEnd   = [System.Drawing.Color]::FromArgb(255, 0, 71, 214)     # #0047D6
$white     = [System.Drawing.Color]::White

# 圆角占边长比例（iOS 风格 squircle 近似）
$cornerRadiusRatio = 0.22
# 播放三角顶点（单位为边长比例，已按视觉重心右移）
$triA = @([double]0.350, [double]0.285)
$triB = @([double]0.350, [double]0.715)
$triC = @([double]0.720, [double]0.500)
$triStrokeRatio = 0.058   # 描边宽度：描边 + 填充共同把直角顶点磨圆

function New-RoundedRectPath {
  param([double]$x, [double]$y, [double]$w, [double]$h, [double]$r)
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $path.AddArc($x, $y, $d, $d, 180, 90)
  $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  return $path
}

function New-AppIconBitmap {
  param([int]$Size)
  $s = [double]$Size
  $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

  # 1) 圆角方块渐变底
  $rectPath = New-RoundedRectPath 0 0 $s $s ($s * $cornerRadiusRatio)
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.PointF(0, 0)),
    (New-Object System.Drawing.PointF($s, $s)),
    $gradStart, $gradEnd)
  $g.FillPath($brush, $rectPath)

  # 2) 白色播放三角（填充 + 粗圆头描边，顶点自然磨圆）
  $points = @(
    (New-Object System.Drawing.PointF([float]($triA[0] * $s), [float]($triA[1] * $s))),
    (New-Object System.Drawing.PointF([float]($triB[0] * $s), [float]($triB[1] * $s))),
    (New-Object System.Drawing.PointF([float]($triC[0] * $s), [float]($triC[1] * $s)))
  )
  $pen = New-Object System.Drawing.Pen($white, [float]($s * $triStrokeRatio))
  $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $g.FillPolygon((New-Object System.Drawing.SolidBrush($white)), $points)
  $g.DrawPolygon($pen, $points)

  $brush.Dispose()
  $pen.Dispose()
  $rectPath.Dispose()
  $g.Dispose()
  return $bmp
}

function Save-Png {
  param([System.Drawing.Bitmap]$Bmp, [string]$Path)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $Bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $Bmp.Dispose()
}

# 多尺寸 PNG-in-ICO（Vista+ 支持 256px PNG 条目）
function Build-Ico {
  param([string]$Path, [int[]]$Sizes)
  $blobs = New-Object System.Collections.Generic.List[byte[]]
  foreach ($sz in $Sizes) {
    $bmp = New-AppIconBitmap $sz
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $blobs.Add($ms.ToArray())
    $ms.Dispose()
  }

  $out = New-Object System.IO.MemoryStream
  $bw = New-Object System.IO.BinaryWriter($out)
  $bw.Write([uint16]0)                      # reserved
  $bw.Write([uint16]1)                      # type: icon
  $bw.Write([uint16]$Sizes.Count)
  $offset = 6 + (16 * $Sizes.Count)
  for ($i = 0; $i -lt $Sizes.Count; $i++) {
    $sz = $Sizes[$i]
    $dim = if ($sz -ge 256) { [byte]0 } else { [byte]$sz }
    $bw.Write($dim)                         # width
    $bw.Write($dim)                         # height
    $bw.Write([byte]0)                      # palette colors
    $bw.Write([byte]0)                      # reserved
    $bw.Write([uint16]1)                    # color planes
    $bw.Write([uint16]32)                   # bits per pixel
    $bw.Write([uint32]$blobs[$i].Length)
    $bw.Write([uint32]$offset)
    $offset += $blobs[$i].Length
  }
  foreach ($b in $blobs) { $bw.Write($b) }
  $bw.Flush()
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllBytes($Path, $out.ToArray())
  $bw.Dispose()
  $out.Dispose()
}

$icoSizes = @(16, 24, 32, 48, 64, 256)

# ===== Windows：窗口 / 任务栏 / 桌面图标 =====
Build-Ico -Path (Join-Path $RepoRoot 'windows\runner\resources\app_icon.ico') -Sizes $icoSizes

# ===== 托盘 + 应用内图标 =====
Build-Ico -Path (Join-Path $RepoRoot 'assets\icons\app_icon.ico') -Sizes $icoSizes
Save-Png -Bmp (New-AppIconBitmap 512) -Path (Join-Path $RepoRoot 'assets\icons\app_icon.png')

# ===== Android 启动图标 =====
$androidDensities = @{
  'mipmap-mdpi'    = 48
  'mipmap-hdpi'    = 72
  'mipmap-xhdpi'   = 96
  'mipmap-xxhdpi'  = 144
  'mipmap-xxxhdpi' = 192
}
foreach ($entry in $androidDensities.GetEnumerator()) {
  $p = Join-Path $RepoRoot ("android\app\src\main\res\" + $entry.Key + "\ic_launcher.png")
  Save-Png -Bmp (New-AppIconBitmap $entry.Value) -Path $p
}

Write-Host '图标已生成：'
Get-ChildItem -Recurse -File (Join-Path $RepoRoot 'assets\icons'), (Join-Path $RepoRoot 'windows\runner\resources\app_icon.ico') |
  ForEach-Object { '  {0}  ({1} bytes)' -f $_.FullName.Substring($RepoRoot.Length + 1), $_.Length }
