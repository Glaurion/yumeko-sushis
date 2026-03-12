param(
  [string]$ProjectRoot = "C:\Users\Benjamin_DHINAUT\Documents\GitHub\yumeko-sushis",
  [int]$CanvasSize = 1024,
  [int]$InnerMargin = 120,
  [int]$JpegQuality = 94,
  [switch]$NoBackup
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$catalogPath = Join-Path $ProjectRoot "index.html"
$imagesDir = Join-Path $ProjectRoot "images"
$kitDir = Join-Path $imagesDir "ai-kit"

if (-not (Test-Path $catalogPath)) {
  throw "index.html introuvable: $catalogPath"
}
if (-not (Test-Path $imagesDir)) {
  throw "Dossier images introuvable: $imagesDir"
}
if (-not (Test-Path $kitDir)) {
  New-Item -ItemType Directory -Path $kitDir | Out-Null
}

$content = Get-Content -Raw -Path $catalogPath
$pattern = "(?m)^\s*([A-Z0-9]+):\{name:'([^']+)',\s*img:'([^']+)'"
$matches = [regex]::Matches($content, $pattern)

if ($matches.Count -eq 0) {
  throw "Aucun article trouve dans le catalogue."
}

$items = @()
foreach ($m in $matches) {
  $items += [PSCustomObject]@{
    code = $m.Groups[1].Value
    name = $m.Groups[2].Value
    img = $m.Groups[3].Value
  }
}

$items = $items | Sort-Object code -Unique

if (-not $NoBackup) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupDir = Join-Path $imagesDir "_backup-uniform-$stamp"
  New-Item -ItemType Directory -Path $backupDir | Out-Null

  foreach ($item in $items) {
    $src = Join-Path $imagesDir $item.img
    if (Test-Path $src) {
      Copy-Item -Path $src -Destination (Join-Path $backupDir $item.img) -Force
    }
  }
  Write-Host "Backup cree: $backupDir"
}

function New-Graphics([System.Drawing.Bitmap]$bmp) {
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  return $g
}

function Save-Jpeg(
  [System.Drawing.Bitmap]$bmp,
  [string]$outputPath,
  [int]$quality
) {
  $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq "image/jpeg" }

  $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
  $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
    [System.Drawing.Imaging.Encoder]::Quality,
    [long]$quality
  )
  $bmp.Save($outputPath, $codec, $encParams)
  $encParams.Dispose()
}

function Build-Prompt([string]$name) {
  return ("photo culinaire studio, produit japonais " +
    "'" + $name + "', " +
    "objet unique centre, style premium, " +
    "fond uniforme beige et rose sakura, " +
    "lumiere douce, contraste propre, " +
    "sans texte, sans logo, sans watermark, " +
    "format carre 1024x1024")
}

$topColor = [System.Drawing.Color]::FromArgb(255, 248, 241, 236)   # beige clair
$bottomColor = [System.Drawing.Color]::FromArgb(255, 246, 214, 228) # sakura doux
$vignetteColor = [System.Drawing.Color]::FromArgb(38, 99, 62, 77)
$shadowColor = [System.Drawing.Color]::FromArgb(58, 25, 18, 23)

$prompts = @()
$done = 0

foreach ($item in $items) {
  $srcPath = Join-Path $imagesDir $item.img
  if (-not (Test-Path $srcPath)) {
    Write-Warning "Image manquante ignoree: $($item.img)"
    continue
  }

  $image = [System.Drawing.Image]::FromFile($srcPath)
  $canvas = New-Object System.Drawing.Bitmap $CanvasSize, $CanvasSize
  $g = New-Graphics $canvas

  $bgRect = New-Object System.Drawing.Rectangle 0, 0, $CanvasSize, $CanvasSize
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $bgRect, $topColor, $bottomColor, 90
  )
  $g.FillRectangle($brush, $bgRect)
  $brush.Dispose()

  # subtle vignette to keep focus in the center
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddEllipse(-180, -140, $CanvasSize + 360, $CanvasSize + 280)
  $region = New-Object System.Drawing.Region($bgRect)
  $region.Exclude($path)
  $vBrush = New-Object System.Drawing.SolidBrush($vignetteColor)
  $g.FillRegion($vBrush, $region)
  $vBrush.Dispose()
  $region.Dispose()
  $path.Dispose()

  $maxW = $CanvasSize - (2 * $InnerMargin)
  $maxH = $CanvasSize - (2 * $InnerMargin)
  $ratio = [Math]::Min($maxW / $image.Width, $maxH / $image.Height)
  $drawW = [int][Math]::Round($image.Width * $ratio)
  $drawH = [int][Math]::Round($image.Height * $ratio)
  $drawX = [int][Math]::Round(($CanvasSize - $drawW) / 2)
  $drawY = [int][Math]::Round(($CanvasSize - $drawH) / 2)

  $shadowRect = New-Object System.Drawing.Rectangle ($drawX + 8), ($drawY + 14), $drawW, $drawH
  $sBrush = New-Object System.Drawing.SolidBrush($shadowColor)
  $g.FillRectangle($sBrush, $shadowRect)
  $sBrush.Dispose()

  $g.DrawImage($image, $drawX, $drawY, $drawW, $drawH)

  $tmpPath = "$srcPath.tmp.jpg"
  Save-Jpeg -bmp $canvas -outputPath $tmpPath -quality $JpegQuality

  $g.Dispose()
  $canvas.Dispose()
  $image.Dispose()

  Move-Item -Path $tmpPath -Destination $srcPath -Force

  $done += 1

  $prompts += [PSCustomObject]@{
    code = $item.code
    name = $item.name
    filename = $item.img
    prompt = (Build-Prompt $item.name)
    negative_prompt = "texte, logo, watermark, personne, mains, flou, deformee, cadre coupe"
  }
}

$promptsPath = Join-Path $kitDir "prompts-menu.json"
$prompts | ConvertTo-Json -Depth 5 | Set-Content -Path $promptsPath -Encoding UTF8

$summary = [PSCustomObject]@{
  generated_count = $done
  item_count_total = $items.Count
  prompts_file = $promptsPath
  image_folder = $imagesDir
}

$summary | ConvertTo-Json -Depth 3 | Write-Host
