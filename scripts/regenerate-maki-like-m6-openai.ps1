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

$targetCodes = @("M1","M2","M3","M4","M5","M6","M7","M8")

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $imagesDir "_backup-openai-maki-$stamp"
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

function Build-PromptForMaki {
  param(
    [string]$Code,
    [string]$Name,
    [string]$Comp
  )

  $base = @(
    "Photorealistic premium japanese food photography.",
    "Exactly 4 maki pieces on a small elegant ceramic plate.",
    "All 4 maki lying on their side, same direction, same orientation.",
    "Camera angle 3/4 front, matching MAKI AVOCAT style composition.",
    "Consistent framing and visual style across all maki images.",
    "Nori outside, rice and filling visible on cut faces.",
    "No extra topping above the maki.",
    "No chopsticks, no sauce drips, no garnish, no hands.",
    "Smooth beige to sakura pink background, soft studio light.",
    "No text, no logo, no watermark."
  ) -join " "

  if ($Code -eq "M8") {
    return "$base Dish: MAKI CHEESE. Filling: only one clean cream-cheese cube in each maki center. No additional cheese outside."
  }

  $ing = if ([string]::IsNullOrWhiteSpace($Comp)) { "" } else { "Filling to reflect: $Comp." }
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

  $prompt = Build-PromptForMaki -Code $item.code -Name $item.name -Comp $item.comp

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
