param(
    [string]$InputPath = (Join-Path $PSScriptRoot 'img.png'),
    [string]$OutputPath = (Join-Path $PSScriptRoot 'img.ico')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing

$InputPath = [System.IO.Path]::GetFullPath($InputPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if (-not [System.IO.File]::Exists($InputPath)) {
    throw "Input image not found: $InputPath`nPlace a transparent img.png beside this script and try again."
}

if ([System.IO.Path]::GetExtension($InputPath) -ine '.png') {
    throw 'The input image must be a PNG file.'
}

$outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
if (-not [System.IO.Directory]::Exists($outputDirectory)) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

$iconSizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$pngFrames = [System.Collections.Generic.List[byte[]]]::new()
$sourceImage = $null
$temporaryPath = Join-Path $outputDirectory ('.img-' + [System.Guid]::NewGuid().ToString('N') + '.tmp.ico')

try {
    $sourceImage = [System.Drawing.Image]::FromFile($InputPath)

    foreach ($size in $iconSizes) {
        $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $memory = [System.IO.MemoryStream]::new()

        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

            $scale = [Math]::Min($size / $sourceImage.Width, $size / $sourceImage.Height)
            $drawWidth = [Math]::Max(1, [int][Math]::Round($sourceImage.Width * $scale))
            $drawHeight = [Math]::Max(1, [int][Math]::Round($sourceImage.Height * $scale))
            $drawX = [int][Math]::Floor(($size - $drawWidth) / 2)
            $drawY = [int][Math]::Floor(($size - $drawHeight) / 2)
            $destination = [System.Drawing.Rectangle]::new($drawX, $drawY, $drawWidth, $drawHeight)

            $graphics.DrawImage($sourceImage, $destination, 0, 0, $sourceImage.Width, $sourceImage.Height, [System.Drawing.GraphicsUnit]::Pixel)
            $bitmap.Save($memory, [System.Drawing.Imaging.ImageFormat]::Png)
            $pngFrames.Add($memory.ToArray())
        }
        finally {
            $memory.Dispose()
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }

    $fileStream = [System.IO.File]::Open($temporaryPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $writer = [System.IO.BinaryWriter]::new($fileStream)

    try {
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$pngFrames.Count)

        $imageOffset = 6 + (16 * $pngFrames.Count)
        for ($index = 0; $index -lt $pngFrames.Count; $index++) {
            $size = $iconSizes[$index]
            $writer.Write([byte]$(if ($size -eq 256) { 0 } else { $size }))
            $writer.Write([byte]$(if ($size -eq 256) { 0 } else { $size }))
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$pngFrames[$index].Length)
            $writer.Write([UInt32]$imageOffset)
            $imageOffset += $pngFrames[$index].Length
        }

        foreach ($frame in $pngFrames) {
            $writer.Write($frame)
        }
    }
    finally {
        $writer.Dispose()
        $fileStream.Dispose()
    }

    if ([System.IO.File]::Exists($OutputPath)) {
        [System.IO.File]::Delete($OutputPath)
    }
    [System.IO.File]::Move($temporaryPath, $OutputPath)

    Write-Host "Conversion complete: $OutputPath" -ForegroundColor Green
    Write-Host "Icon sizes: $($iconSizes -join ', ') pixels"
}
finally {
    if ($null -ne $sourceImage) {
        $sourceImage.Dispose()
    }
    if ([System.IO.File]::Exists($temporaryPath)) {
        [System.IO.File]::Delete($temporaryPath)
    }
}
