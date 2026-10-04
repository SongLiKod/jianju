# 一键打包：flutter build apk --release 并输出 dist\简剧<版本>.apk
# 用法: powershell -ExecutionPolicy Bypass -File build_apk.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '.')

& 'C:\software\flutter\bin\flutter.bat' build apk --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$verLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\d+(?:\.\d+){1,2})' |
  Select-Object -First 1
if (-not $verLine) { Write-Error 'pubspec.yaml 未找到 version:'; exit 1 }
$ver = $verLine.Matches[0].Groups[1].Value

$src = 'build\app\outputs\flutter-apk\app-release.apk'
if (!(Test-Path $src)) { Write-Error "未找到 $src"; exit 1 }

$dist = 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$dst = Join-Path $dist "简剧$ver.apk"
Copy-Item $src $dst -Force
Write-Host "=> $dst"
