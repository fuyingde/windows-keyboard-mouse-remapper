param(
    [string]$IconOnly = ""
)

$ErrorActionPreference = 'Stop'

function New-RoundedRectPath {
    param([float]$X, [float]$Y, [float]$Width, [float]$Height, [float]$Radius)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [Math]::Min($Radius * 2, [Math]::Min($Width, $Height))
    if ($d -lt 1) { $d = 1 }
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X + $Width - $d, $Y, $d, $d, 270, 90)
    $path.AddArc($X + $Width - $d, $Y + $Height - $d, $d, $d, 0, 90)
    $path.AddArc($X, $Y + $Height - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-KeyboardBitmap {
    param([int]$Size)
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $s = $Size / 24.0
    $bg = New-RoundedRectPath 0 0 $Size $Size ([Math]::Max(2, $Size * 0.22))
    $blue = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 23, 105, 232))
    $g.FillPath($blue, $bg)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, [Math]::Max(1.2, 1.8 * $s))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $kb = New-RoundedRectPath ([float](3 * $s)) ([float](6 * $s)) ([float](18 * $s)) ([float](12 * $s)) ([float](2.2 * $s))
    $g.DrawPath($pen, $kb)
    foreach ($pt in @(@(6, 9), @(10, 9), @(14, 9), @(18, 9), @(6, 12), @(10, 12), @(14, 12), @(18, 12))) {
        $g.DrawLine($pen, [float]($pt[0] * $s), [float]($pt[1] * $s), [float](($pt[0] + 1) * $s), [float]($pt[1] * $s))
    }
    $g.DrawLine($pen, [float](7 * $s), [float](15 * $s), [float](17 * $s), [float](15 * $s))
    $pen.Dispose(); $blue.Dispose(); $bg.Dispose(); $kb.Dispose(); $g.Dispose()
    return $bmp
}

function Save-KeyboardIcon {
    param([string]$Path)
    Add-Type -AssemblyName System.Drawing
    $sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
    $pngs = New-Object System.Collections.Generic.List[byte[]]
    foreach ($size in $sizes) {
        $bmp = New-KeyboardBitmap $size
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngs.Add($ms.ToArray()) | Out-Null
        $ms.Dispose()
        $bmp.Dispose()
    }

    $count = $sizes.Count
    $headerSize = 6 + (16 * $count)
    $header = New-Object byte[] $headerSize
    $header[2] = 1
    $header[4] = [byte]$count
    $offset = $headerSize
    for ($i = 0; $i -lt $count; $i++) {
        $entry = 6 + (16 * $i)
        $size = $sizes[$i]
        $wh = if ($size -ge 256) { 0 } else { $size }
        $len = $pngs[$i].Length
        $header[$entry] = $wh
        $header[$entry + 1] = $wh
        $header[$entry + 4] = 1
        $header[$entry + 6] = 32
        [BitConverter]::GetBytes([uint32]$len).CopyTo($header, $entry + 8)
        [BitConverter]::GetBytes([uint32]$offset).CopyTo($header, $entry + 12)
        $offset += $len
    }

    $stream = New-Object System.IO.MemoryStream
    $stream.Write($header, 0, $header.Length)
    foreach ($png in $pngs) {
        $stream.Write($png, 0, $png.Length)
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    [IO.File]::WriteAllBytes($Path, $stream.ToArray())
    $stream.Dispose()
}

if ($IconOnly) {
    Save-KeyboardIcon $IconOnly
    return
}

$sourceDir = $PSScriptRoot

$mainScripts = @(Get-ChildItem -LiteralPath $sourceDir -File -Filter '*.ahk')
if ($mainScripts.Count -ne 1) {
    throw "Expected exactly one main AHK file in $sourceDir, found $($mainScripts.Count)."
}
$mainScript = $mainScripts[0]

$installDir = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\AutoHotkey').InstallDir
$compiler = Join-Path $installDir 'Compiler\Ahk2Exe.exe'
$baseExe = Join-Path $installDir 'v2\AutoHotkey64.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    throw "Ahk2Exe was not found: $compiler"
}
if (-not (Test-Path -LiteralPath $baseExe)) {
    throw "AutoHotkey v2 64-bit base was not found: $baseExe"
}

$sourceText = Get-Content -LiteralPath $mainScript.FullName -Raw -Encoding UTF8
$versionMatch = [regex]::Match($sourceText, 'Ahk2Exe-SetVersion\s+(\d+)\.(\d+)')
if (-not $versionMatch.Success) {
    throw 'Version directive was not found in the main AHK file.'
}
$displayVersion = $versionMatch.Groups[1].Value + '.' + $versionMatch.Groups[2].Value

$releaseDirPath = Join-Path $sourceDir 'exe'
if (-not (Test-Path -LiteralPath $releaseDirPath)) {
    New-Item -ItemType Directory -Path $releaseDirPath | Out-Null
}
$releaseDir = Get-Item -LiteralPath $releaseDirPath
$outputName = $mainScript.BaseName + 'v' + $displayVersion + '.exe'

$temporaryOutput = Join-Path $releaseDir.FullName ([IO.Path]::GetFileNameWithoutExtension($outputName) + '.build.tmp.exe')
$finalOutput = Join-Path $releaseDir.FullName $outputName
if (Test-Path -LiteralPath $temporaryOutput) {
    Remove-Item -LiteralPath $temporaryOutput -Force
}

$iconFile = Join-Path $env:TEMP ('KeyMouseMapper-' + [guid]::NewGuid().ToString('N') + '.ico')
try {
    Save-KeyboardIcon $iconFile
    $compile = Start-Process -FilePath $compiler -ArgumentList @(
        '/in', $mainScript.FullName,
        '/out', $temporaryOutput,
        '/base', $baseExe,
        '/icon', $iconFile
    ) -PassThru -Wait -WindowStyle Hidden
    if ($null -ne $compile.ExitCode -and $compile.ExitCode -ne 0) {
        throw "Ahk2Exe failed with exit code $($compile.ExitCode)."
    }
    for ($attempt = 0; $attempt -lt 40 -and -not (Test-Path -LiteralPath $temporaryOutput); $attempt++) {
        Start-Sleep -Milliseconds 250
    }
    if (-not (Test-Path -LiteralPath $temporaryOutput)) {
        throw "Compiler reported success but the output file was not created."
    }
} finally {
    if (Test-Path -LiteralPath $iconFile) {
        Remove-Item -LiteralPath $iconFile -Force
    }
}

Copy-Item -LiteralPath $temporaryOutput -Destination $finalOutput -Force
Remove-Item -LiteralPath $temporaryOutput -Force

$result = Get-Item -LiteralPath $finalOutput
$hash = (Get-FileHash -LiteralPath $finalOutput -Algorithm SHA256).Hash
Write-Host "Build complete: $($result.FullName)"
Write-Host "Size: $($result.Length) bytes"
Write-Host "SHA256: $hash"
