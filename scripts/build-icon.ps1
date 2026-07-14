param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\codex-monitor-hud.ico'),
    [string]$PreviewPath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-RoundedRectanglePath {
    param([Drawing.RectangleF]$Bounds, [double]$Radius)
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $diameter = [single]($Radius * 2)
    $path.AddArc($Bounds.Left, $Bounds.Top, $diameter, $diameter, 180, 90)
    $path.AddArc($Bounds.Right - $diameter, $Bounds.Top, $diameter, $diameter, 270, 90)
    $path.AddArc($Bounds.Right - $diameter, $Bounds.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Bounds.Left, $Bounds.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-HudIconPng {
    param([int]$Size)
    $bitmap = New-Object Drawing.Bitmap($Size, $Size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([Drawing.Color]::Transparent)

        $margin = [single][Math]::Max(1, $Size * 0.055)
        $bounds = New-Object Drawing.RectangleF($margin, $margin, [single]($Size - (2 * $margin)), [single]($Size - (2 * $margin)))
        $backgroundPath = New-RoundedRectanglePath $bounds ([Math]::Max(2, $Size * 0.23))
        $background = New-Object Drawing.Drawing2D.LinearGradientBrush($bounds, [Drawing.Color]::FromArgb(255,5,20,34), [Drawing.Color]::FromArgb(255,7,67,96), 42.0)
        $rim = New-Object Drawing.Pen([Drawing.Color]::FromArgb(135,36,211,255), [single][Math]::Max(0.8, $Size * 0.028))
        try {
            $graphics.FillPath($background, $backgroundPath)
            $graphics.DrawPath($rim, $backgroundPath)
        } finally { $rim.Dispose(); $background.Dispose(); $backgroundPath.Dispose() }

        $bracketPen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255,34,211,238), [single][Math]::Max(1.25, $Size * 0.072))
        $wavePen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255,244,252,255), [single][Math]::Max(1.3, $Size * 0.078))
        try {
            foreach ($pen in @($bracketPen,$wavePen)) {
                $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
                $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
                $pen.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
            }
            $left = [Drawing.PointF[]]@(
                (New-Object Drawing.PointF([single]($Size*0.32),[single]($Size*0.27))),
                (New-Object Drawing.PointF([single]($Size*0.21),[single]($Size*0.27))),
                (New-Object Drawing.PointF([single]($Size*0.21),[single]($Size*0.73))),
                (New-Object Drawing.PointF([single]($Size*0.32),[single]($Size*0.73)))
            )
            $right = [Drawing.PointF[]]@(
                (New-Object Drawing.PointF([single]($Size*0.68),[single]($Size*0.27))),
                (New-Object Drawing.PointF([single]($Size*0.79),[single]($Size*0.27))),
                (New-Object Drawing.PointF([single]($Size*0.79),[single]($Size*0.73))),
                (New-Object Drawing.PointF([single]($Size*0.68),[single]($Size*0.73)))
            )
            $wave = [Drawing.PointF[]]@(
                (New-Object Drawing.PointF([single]($Size*0.28),[single]($Size*0.53))),
                (New-Object Drawing.PointF([single]($Size*0.39),[single]($Size*0.53))),
                (New-Object Drawing.PointF([single]($Size*0.46),[single]($Size*0.36))),
                (New-Object Drawing.PointF([single]($Size*0.57),[single]($Size*0.67))),
                (New-Object Drawing.PointF([single]($Size*0.65),[single]($Size*0.48))),
                (New-Object Drawing.PointF([single]($Size*0.72),[single]($Size*0.48)))
            )
            $graphics.DrawLines($bracketPen, $left)
            $graphics.DrawLines($bracketPen, $right)
            $graphics.DrawLines($wavePen, $wave)

            $dotSize = [single][Math]::Max(2.0, $Size * 0.105)
            $dotBrush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255,125,255,205))
            try { $graphics.FillEllipse($dotBrush, [single]($Size*0.70), [single]($Size*0.20), $dotSize, $dotSize) } finally { $dotBrush.Dispose() }
        } finally { $wavePen.Dispose(); $bracketPen.Dispose() }

        $stream = New-Object IO.MemoryStream
        try {
            $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
            return $stream.ToArray()
        } finally { $stream.Dispose() }
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}

function Convert-PngToIconDib {
    param([byte[]]$PngBytes, [int]$Size)
    $input = New-Object IO.MemoryStream(,$PngBytes)
    $bitmap = [Drawing.Bitmap]::FromStream($input)
    $output = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($output)
    try {
        $xorBytes = $Size * $Size * 4
        $maskStride = [int]([Math]::Ceiling($Size / 32.0) * 4)
        $writer.Write([uint32]40)
        $writer.Write([int32]$Size)
        $writer.Write([int32]($Size * 2))
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]0)
        $writer.Write([uint32]$xorBytes)
        $writer.Write([int32]0)
        $writer.Write([int32]0)
        $writer.Write([uint32]0)
        $writer.Write([uint32]0)
        for ($y = $Size - 1; $y -ge 0; $y--) {
            for ($x = 0; $x -lt $Size; $x++) {
                $pixel = $bitmap.GetPixel($x,$y)
                $writer.Write([byte]$pixel.B)
                $writer.Write([byte]$pixel.G)
                $writer.Write([byte]$pixel.R)
                $writer.Write([byte]$pixel.A)
            }
        }
        $maskRow = New-Object byte[] $maskStride
        for ($y = 0; $y -lt $Size; $y++) { $writer.Write([byte[]]$maskRow) }
        $writer.Flush()
        return $output.ToArray()
    } finally { $writer.Dispose(); $output.Dispose(); $bitmap.Dispose(); $input.Dispose() }
}

$sizes = @(16,20,24,32,40,48,64,128,256)
$pngFrames = @()
$frames = @()
foreach ($size in $sizes) {
    $png = New-HudIconPng $size
    $pngFrames += ,$png
    $frames += ,(Convert-PngToIconDib $png $size)
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
$stream = New-Object IO.FileStream($OutputPath, [IO.FileMode]::Create)
$writer = New-Object IO.BinaryWriter($stream)
try {
    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$frames.Count)
    $offset = 6 + (16 * $frames.Count)
    for ($i = 0; $i -lt $frames.Count; $i++) {
        $sizeByte = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
        $writer.Write([byte]$sizeByte)
        $writer.Write([byte]$sizeByte)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$frames[$i].Length)
        $writer.Write([uint32]$offset)
        $offset += $frames[$i].Length
    }
    foreach ($frame in $frames) { $writer.Write([byte[]]$frame) }
} finally { $writer.Dispose(); $stream.Dispose() }

if (-not [string]::IsNullOrWhiteSpace($PreviewPath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PreviewPath) | Out-Null
    [IO.File]::WriteAllBytes($PreviewPath, [byte[]]$pngFrames[$pngFrames.Count - 1])
}

Write-Output "Icon: $OutputPath ($($frames.Count) sizes)"
