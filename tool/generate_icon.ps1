# 生成简剧 APP 图标（红圆 + 白色播放三角）到 android mipmap 各密度
# 用法: powershell -File tool\generate_icon.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$res = Join-Path $PSScriptRoot '..\android\app\src\main\res'
$densities = @{
  'mipmap-mdpi'    = 48
  'mipmap-hdpi'    = 72
  'mipmap-xhdpi'   = 96
  'mipmap-xxhdpi'  = 144
  'mipmap-xxxhdpi' = 192
}

function New-IconBitmap([int]$size) {
  $bmp = [System.Drawing.Bitmap]::new($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)

  $s = $size
  # 红色渐变圆
  $rect = [System.Drawing.Rectangle]::new(0, 0, $s, $s)
  $c1 = [System.Drawing.Color]::FromArgb(255, 255, 75, 55)
  $c2 = [System.Drawing.Color]::FromArgb(255, 205, 0, 20)
  $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(0, 0),
    [System.Drawing.Point]::new($s, $s),
    $c1, $c2)
  $g.FillEllipse($brush, $rect)

  # 白色播放三角（略偏右做视觉居中）
  $cx = $s * 0.53
  $cy = $s * 0.5
  $h = $s * 0.42          # 三角高
  $hw = $h * 0.86         # 三角宽
  $p1 = [System.Drawing.PointF]::new([float]($cx - $hw * 0.42), [float]($cy - $h / 2))
  $p2 = [System.Drawing.PointF]::new([float]($cx - $hw * 0.42), [float]($cy + $h / 2))
  $p3 = [System.Drawing.PointF]::new([float]($cx + $hw * 0.58), [float]$cy)
  $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
  [System.Drawing.PointF[]]$pts = @($p1, $p2, $p3)
  $g.FillPolygon($white, $pts)

  $white.Dispose(); $brush.Dispose(); $g.Dispose()
  return $bmp
}

foreach ($kv in $densities.GetEnumerator()) {
  $dir = Join-Path $res $kv.Key
  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $bmp = New-IconBitmap $kv.Value
  $out = Join-Path $dir 'ic_launcher.png'
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host "OK $out ($($kv.Value)x$($kv.Value))"
}
Write-Host 'done.'
