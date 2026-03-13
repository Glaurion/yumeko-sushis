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
  "C9" # CALIFORNIA SAUMON CHEESE OIGNONS FRITS
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
$backupDir = Join-Path $imagesDir "_backup-openai-c9-$stamp"
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
    "Consistent style with the rest of the menu: same framing, same soft lighting, same 3/4 front camera angle.",
    "Small elegant ceramic plate.",
    "Exactly 4 california pieces in the image.",
    "All 4 pieces aligned, same orientation, 3/4 front angle.",
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
    "C9" {
      return "$base Dish: CALIFORNIA SAUMON CHEESE OIGNONS FRITS. Uramaki with salmon and cream cheese filling. The OUTER COATING must be crispy fried onions only. No black sesame and no white sesame anywhere."
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
