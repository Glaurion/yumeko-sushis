param(
  [string]$ApiKey = "",
  [ValidateSet("low","medium","high")]
  [string]$Quality = "medium"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  $ApiKey = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY")
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  throw "OPENAI_API_KEY manquante."
}

$projectRoot = "C:\Users\Benjamin_DHINAUT\Documents\GitHub\yumeko-sushis"
$catalogPath = Join-Path $projectRoot "index.html"
$imagesDir = Join-Path $projectRoot "images"

# Codes a regenerer (en excluant les visuels deja valides par l'utilisateur)
$targetCodes = @(
  "M1","M2","M3","M4","M8",
  "C2","C3","C5","C6","C8","C9",
  "P1",
  "R1"
)

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $imagesDir "_backup-openai-selected-$stamp"
New-Item -ItemType Directory -Path $backupDir | Out-Null

$content = Get-Content -Raw -Path $catalogPath
$pattern = "(?m)^\s*([A-Z0-9]+):\{name:'([^']+)',\s*img:'([^']+)',\s*pieces:(\d+),\s*comp:'([^']*)'"
$matches = [regex]::Matches($content, $pattern)

$byCode = @{}
foreach ($m in $matches) {
  $code = $m.Groups[1].Value
  $byCode[$code] = [PSCustomObject]@{
    code = $code
    name = $m.Groups[2].Value
    img = $m.Groups[3].Value
    pieces = [int]$m.Groups[4].Value
    comp = $m.Groups[5].Value
  }
}

function Save-AsJpeg {
  param(
    [byte[]]$Bytes,
    [string]$OutputPath
  )
  $tmp = [System.IO.Path]::ChangeExtension($OutputPath, ".tmpimg")
  [System.IO.File]::WriteAllBytes($tmp, $Bytes)

  $img = [System.Drawing.Image]::FromFile($tmp)
  $bmp = New-Object System.Drawing.Bitmap($img)
  $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq "image/jpeg" }
  $enc = New-Object System.Drawing.Imaging.EncoderParameters(1)
  $enc.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
    [System.Drawing.Imaging.Encoder]::Quality, 95L
  )
  $bmp.Save($OutputPath, $codec, $enc)

  $enc.Dispose()
  $bmp.Dispose()
  $img.Dispose()
  Remove-Item $tmp -Force
}

function Build-Prompt {
  param(
    [string]$Code,
    [string]$Name,
    [string]$Comp
  )

  $base = @(
    "Photorealistic premium japanese sushi food photography.",
    "Small elegant ceramic plate with exactly 4 sushi pieces.",
    "All 4 pieces lying down (couches), same direction and same orientation.",
    "3/4 front camera angle.",
    "Tight, clean composition.",
    "Visual style must match the already-approved images from this menu (same lighting and framing).",
    "Smooth beige to sakura pink background.",
    "Soft studio light and subtle natural shadow.",
    "No chopsticks, no garnish, no sauce drizzle, no hands.",
    "No text, no logo, no watermark."
  ) -join " "

  $ing = if ([string]::IsNullOrWhiteSpace($Comp)) { "" } else { "Ingredients to reflect: $Comp." }

  if ($Code -like "C*") {
    return "$base California uramaki style. Outer rice coated with black and white sesame seeds. No orange fish roe topping. Dish: $Name. $ing"
  }

  if ($Code -like "M*") {
    if ($Code -eq "M8") {
      return "$base Maki style with nori outside. Dish: MAKI CHEESE. Filling: clean cream-cheese center only, no cheese on top/outside."
    }
    return "$base Maki style with nori outside. Dish: $Name. $ing"
  }

  if ($Code -like "P*") {
    return "$base Spring maki style with translucent rice paper outside (no nori outside). Dish: $Name. $ing"
  }

  if ($Code -eq "R1") {
    return "$base Rolls style. Salmon clearly visible on top/outside, avocado and cream cheese in the center. Dish: $Name."
  }

  return "$base Dish: $Name. $ing"
}

$ok = 0
$failed = @()

foreach ($code in $targetCodes) {
  if (-not $byCode.ContainsKey($code)) {
    $failed += "${code}: introuvable"
    continue
  }

  $item = $byCode[$code]
  $outPath = Join-Path $imagesDir $item.img
  if (Test-Path $outPath) {
    Copy-Item $outPath (Join-Path $backupDir $item.img) -Force
  }

  $prompt = Build-Prompt -Code $item.code -Name $item.name -Comp $item.comp
  $attempt = 0
  $done = $false

  while (-not $done -and $attempt -lt 3) {
    $attempt++
    try {
      $body = @{
        model = "gpt-image-1"
        prompt = $prompt
        size = "1024x1024"
        quality = $Quality
      } | ConvertTo-Json -Depth 10

      $resp = Invoke-RestMethod -Method Post `
        -Uri "https://api.openai.com/v1/images/generations" `
        -Headers @{ Authorization = "Bearer $ApiKey" } `
        -ContentType "application/json" `
        -Body $body

      if (-not ($resp.data -and $resp.data[0] -and $resp.data[0].b64_json)) {
        throw "Reponse image invalide."
      }

      $bytes = [Convert]::FromBase64String($resp.data[0].b64_json)
      Save-AsJpeg -Bytes $bytes -OutputPath $outPath
      Write-Host "[OK] $($item.code) -> $($item.img)"
      $ok++
      $done = $true
    } catch {
      Write-Warning "[Retry $attempt/3] $($item.code): $($_.Exception.Message)"
      if ($attempt -ge 3) {
        $failed += "${code}: $($_.Exception.Message)"
      }
      Start-Sleep -Milliseconds 1200
    }
  }

  Start-Sleep -Milliseconds 850
}

Write-Host ("backup=" + $backupDir)
Write-Host ("ok=" + $ok)
Write-Host ("failed_count=" + $failed.Count)
if ($failed.Count -gt 0) {
  Write-Host "failed_items:"
  $failed | ForEach-Object { Write-Host (" - " + $_) }
}
