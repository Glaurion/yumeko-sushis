param(
  [string]$ApiKey = "",
  [ValidateSet("low","medium","high")]
  [string]$Quality = "high",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not $DryRun) {
  if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $ApiKey = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY")
  }
  if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "OPENAI_API_KEY missing. Set -ApiKey or environment variable OPENAI_API_KEY."
  }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$catalogPath = Join-Path $projectRoot "index.html"
$imagesDir = Join-Path $projectRoot "images"

$targetCategories = @(
  "MAKI",
  "CALIFORNIA",
  "MAKI PRINTEMPS",
  "ROLLS",
  "NIGIRI",
  "GYOZA",
  "BROCHETTE"
)

$content = Get-Content -Raw -Path $catalogPath

$categoryPattern = "'([^']+)':\[(.*?)\]"
$categoryMatches = [regex]::Matches($content, $categoryPattern)
$codes = New-Object System.Collections.Generic.List[string]
foreach ($m in $categoryMatches) {
  $categoryName = $m.Groups[1].Value
  if ($targetCategories -notcontains $categoryName) { continue }

  $rawCodes = $m.Groups[2].Value
  $codeMatches = [regex]::Matches($rawCodes, "'([A-Z0-9]+)'")
  foreach ($cm in $codeMatches) {
    $code = $cm.Groups[1].Value
    if (-not $codes.Contains($code)) {
      $codes.Add($code)
    }
  }
}

$itemPattern = "(?m)^\s*([A-Z0-9]+):\{name:'([^']+)',\s*img:'([^']+)'.*?comp:'([^']*)'"
$itemMatches = [regex]::Matches($content, $itemPattern)
$byCode = @{}
foreach ($m in $itemMatches) {
  $code = $m.Groups[1].Value
  $byCode[$code] = [PSCustomObject]@{
    code = $code
    name = $m.Groups[2].Value
    img = $m.Groups[3].Value
    comp = $m.Groups[4].Value
  }
}

$backupDir = ""
if (-not $DryRun) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupDir = Join-Path $imagesDir "_backup-openai-single-item-$stamp"
  New-Item -ItemType Directory -Path $backupDir | Out-Null
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

function Base-Prompt {
  return @(
    "Photorealistic premium Japanese food menu photography.",
    "Match the exact visual style already used on the Yumeko menu photos.",
    "Soft beige to sakura pink gradient background.",
    "Small elegant ceramic plate centered in frame.",
    "Soft studio light with natural shadow.",
    "Clean minimalist composition.",
    "Exactly one single food element on the plate.",
    "No additional pieces, no side dishes, no garnish, no chopsticks.",
    "No text, no logo, no watermark, no packaging, no hands."
  ) -join " "
}

function Build-Prompt {
  param(
    [string]$Code,
    [string]$Name,
    [string]$Comp
  )

  $base = Base-Prompt
  $ingredients = if ([string]::IsNullOrWhiteSpace($Comp)) { "" } else { "Ingredients: $Comp." }

  if ($Code -like "M*") {
    return "$base Single maki piece, nori outside and rice ring visible in cross-section. $ingredients Dish: $Name. One piece only."
  }

  if ($Code -like "C*") {
    return "$base Single california uramaki piece with rice outside coated with black and white sesame seeds. $ingredients Dish: $Name. One piece only."
  }

  if ($Code -like "P*") {
    return "$base Single spring maki piece wrapped with translucent rice paper and fresh leaf-style outer wrap. $ingredients Dish: $Name. One piece only."
  }

  if ($Code -like "R*") {
    return "$base Single roll piece with topping and center filling matching the dish. $ingredients Dish: $Name. One piece only."
  }

  if ($Code -like "N*") {
    return "$base Single nigiri piece. $ingredients Dish: $Name. One piece only."
  }

  if ($Code -like "G*") {
    return "$base Single gyoza dumpling. $ingredients Dish: $Name. One piece only."
  }

  if ($Code -like "BR*") {
    return "$base Single yakitori skewer (one skewer = one element). $ingredients Dish: $Name."
  }

  return "$base $ingredients Dish: $Name. One piece only."
}

$ok = 0
$failed = @()

foreach ($code in $codes) {
  if (-not $byCode.ContainsKey($code)) {
    Write-Warning "$code missing from catalog lines."
    $failed += "${code}: missing from catalog lines"
    continue
  }

  $item = $byCode[$code]
  $outPath = Join-Path $imagesDir $item.img
  $prompt = Build-Prompt -Code $item.code -Name $item.name -Comp $item.comp

  if ($DryRun) {
    Write-Host "[DRY] $($item.code) -> $($item.img)"
    Write-Host $prompt
    continue
  }

  if (Test-Path $outPath) {
    Copy-Item $outPath (Join-Path $backupDir $item.img) -Force
  }

  $done = $false
  $attempt = 0
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
        throw "Invalid image response."
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

if ($DryRun) {
  Write-Host ("codes_count=" + $codes.Count)
  exit 0
}

Write-Host ("backup=" + $backupDir)
Write-Host ("ok=" + $ok)
Write-Host ("failed_count=" + $failed.Count)
if ($failed.Count -gt 0) {
  Write-Host "failed_items:"
  $failed | ForEach-Object { Write-Host (" - " + $_) }
}
