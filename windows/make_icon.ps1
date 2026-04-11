# PNG → ICO 변환 스크립트 (CI/CD 또는 로컬 빌드 전 실행)
$srcPng = Resolve-Path "$PSScriptRoot\..\assets\icon.png"
$dstIco = "$PSScriptRoot\icon.ico"

Add-Type -AssemblyName System.Drawing

$bmp    = [System.Drawing.Bitmap]::FromFile($srcPng)
$handle = $bmp.GetHicon()
$icon   = [System.Drawing.Icon]::FromHandle($handle)
$stream = [System.IO.File]::Open($dstIco, [System.IO.FileMode]::Create)
$icon.Save($stream)
$stream.Close()
$bmp.Dispose()

Write-Host "icon.ico 생성 완료: $dstIco"
