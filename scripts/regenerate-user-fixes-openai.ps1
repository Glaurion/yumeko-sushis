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

$targetCodes = @(
  "M4", # MAKI CONCOMBRE
  "M8", # MAKI CHEESE
  "M2", # MAKI SAUMON AVOCAT
  "M3", # MAKI SAUMON CHEESE
  "C6", # CALIFORNIA AVOCAT
  "P3", # MAKI PRINTEMPS CONCOMBRE CHEESE
  "P1", # MAKI PRINTEMPS SAUMON AVOCAT
  "R1"  # ROLLS SAUMON AVOCAT CHEESE
)

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

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $imagesDir "_backup-openai-user-fixes-$stamp"
New-Item -ItemType Directory -Path $backupDir | Out-Null

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

function Prompt-Base {
  return @(
    "Photorealistic premium Japanese sushi menu photography.",
    "Visual style must match MAKI AVOCAT reference style (M6): same plate size, same framing, same light, same 3/4 front camera angle.",
    "Small elegant ceramic plate.",
    "Exactly 4 pieces.",
    "All 4 pieces lying down (not standing), same orientation and aligned cleanly.",
    "Clean minimalist composition with soft shadow.",
    "Smooth beige to sakura pink background.",
    "No chopsticks, no sauce drips, no garnish unless explicitly requested.",
    "No text, no logo, no watermark."
  ) -join " "
}

function Build-Prompt {
  param(
    [string]$Code,
    [string]$Name
  )

  $base = Prompt-Base

  switch ($Code) {
    "M4" {
      return "$base Dish: MAKI CONCOMBRE. Nori outside, white rice and cucumber filling only. Exactly 4 pieces, lying down, not standing."
    }
    "M8" {
      return "$base Dish: MAKI CHEESE. Nori outside, white rice with only cream-cheese center. Keep exact 3/4 angle like MAKI AVOCAT."
    }
    "M2" {
      return "$base Dish: MAKI SAUMON AVOCAT. Nori outside, filling salmon and avocado. Keep exact 3/4 angle like MAKI AVOCAT."
    }
    "M3" {
      return "$base Dish: MAKI SAUMON CHEESE. Nori outside, filling salmon and cream cheese. Keep exact 3/4 angle like MAKI AVOCAT."
    }
    "C6" {
      return "$base Dish: CALIFORNIA AVOCAT. Uramaki with black and white sesame seeds outside. Filling should be avocado only, no dark garnish inside."
    }
    "P3" {
      return "$base Dish: MAKI PRINTEMPS CONCOMBRE CHEESE. Structure must be: rice core wrapped first with rice paper, then an outer lettuce leaf, filling cucumber and cream cheese. Exactly 4 pieces."
    }
    "P1" {
      return "$base Dish: MAKI PRINTEMPS SAUMON AVOCAT. Structure must be: rice core wrapped first with rice paper, then an outer lettuce leaf, filling salmon and avocado. Exactly 4 pieces."
    }
    "R1" {
      return "$base Dish: ROLLS SAUMON AVOCAT CHEESE. 4 rolls pieces aligned with same orientation. Salmon clearly visible as topping/outside, avocado and cream cheese in the center."
    }
    default {
      return "$base Dish: $Name."
    }
  }
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

  $prompt = Build-Prompt -Code $item.code -Name $item.name
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

  Start-Sleep -Milliseconds 900
}

Write-Host ("backup=" + $backupDir)
Write-Host ("ok=" + $ok)
Write-Host ("failed_count=" + $failed.Count)
if ($failed.Count -gt 0) {
  Write-Host "failed_items:"
  $failed | ForEach-Object { Write-Host (" - " + $_) }
}
