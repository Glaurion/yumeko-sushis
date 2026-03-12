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

$imagesDir = "C:\Users\Benjamin_DHINAUT\Documents\GitHub\yumeko-sushis\images"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $imagesDir "_backup-openai-fixes-$stamp"
New-Item -ItemType Directory -Path $backupDir | Out-Null

$baseStyle = "Photorealistic premium food photography. Single main dish centered, square 1:1, smooth beige to sakura pink background, soft studio light, natural shadow, no text, no logo, no watermark, no packaging."

$items = @(
  @{
    code = "M8"
    file = "m8.jpg"
    prompt = "$baseStyle Japanese sushi MAKI CHEESE: one maki piece with white rice and nori outside, ONLY one cube of cream cheese (saint moret style) in the center, no cheese topping outside, no extra garnish."
  },
  @{
    code = "C1"
    file = "c1.jpg"
    prompt = "$baseStyle California saumon: uramaki style with black and white sesame seeds on outer rice, salmon inside, no orange fish roe topping."
  },
  @{
    code = "C2"
    file = "c2.jpg"
    prompt = "$baseStyle California saumon avocat: uramaki with black and white sesame seeds outside, salmon and avocado inside, no orange topping."
  },
  @{
    code = "C3"
    file = "c3.jpg"
    prompt = "$baseStyle California saumon cheese: uramaki with black and white sesame seeds outside, salmon and cream cheese inside, no orange topping."
  },
  @{
    code = "C4"
    file = "c4.jpg"
    prompt = "$baseStyle California concombre: uramaki with black and white sesame seeds outside, cucumber inside, no orange topping."
  },
  @{
    code = "C5"
    file = "c5.jpg"
    prompt = "$baseStyle California concombre cheese: uramaki with black and white sesame seeds outside, cucumber and cream cheese inside, no orange topping."
  },
  @{
    code = "C6"
    file = "c6.jpg"
    prompt = "$baseStyle California avocat: uramaki with black and white sesame seeds outside, avocado inside, no orange topping."
  },
  @{
    code = "C7"
    file = "c7.jpg"
    prompt = "$baseStyle California avocat cheese: uramaki with black and white sesame seeds outside, avocado and cream cheese inside, no orange topping."
  },
  @{
    code = "C8"
    file = "c8.jpg"
    prompt = "$baseStyle California cheese: uramaki with black and white sesame seeds outside, cream cheese inside, no orange topping."
  },
  @{
    code = "C9"
    file = "c9.jpg"
    prompt = "$baseStyle California saumon cheese oignons frits: uramaki with black and white sesame seeds outside, salmon and cream cheese inside, small crispy fried onion bits inside only, no orange topping."
  },
  @{
    code = "R2"
    file = "r2.jpg"
    prompt = "$baseStyle ROLL AVOCAT SAUMON CHEESE: sushi roll where avocado slices are clearly on top/outside of the roll, salmon and cream cheese inside, premium japanese presentation."
  },
  @{
    code = "BR1"
    file = "br1.jpg"
    prompt = "$baseStyle YAKITORI BOEUF FROMAGE: skewers made of emmental cubes wrapped with thin beef carpaccio slices, glazed yakitori sauce, grilled look, no vegetables."
  }
)

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

$ok = 0
$failed = @()

foreach ($item in $items) {
  $path = Join-Path $imagesDir $item.file
  if (Test-Path $path) {
    Copy-Item $path (Join-Path $backupDir $item.file) -Force
  }

  $done = $false
  $attempt = 0
  while (-not $done -and $attempt -lt 3) {
    $attempt++
    try {
      $body = @{
        model = "gpt-image-1"
        prompt = $item.prompt
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
      Save-AsJpeg -Bytes $bytes -OutputPath $path
      Write-Host "[OK] $($item.code) -> $($item.file)"
      $ok++
      $done = $true
    } catch {
      Write-Warning "[Retry $attempt/3] $($item.code): $($_.Exception.Message)"
      if ($attempt -ge 3) { $failed += $item.code }
      Start-Sleep -Milliseconds 1200
    }
  }

  Start-Sleep -Milliseconds 900
}

Write-Host ("backup=" + $backupDir)
Write-Host ("ok=" + $ok)
Write-Host ("failed=" + ($failed -join ","))
