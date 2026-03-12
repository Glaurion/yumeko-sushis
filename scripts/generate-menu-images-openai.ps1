param(
  [string]$ProjectRoot = "C:\Users\Benjamin_DHINAUT\Documents\GitHub\yumeko-sushis",
  [string]$ApiKey = "",
  [string]$Model = "gpt-image-1",
  [ValidateSet("1024x1024","1536x1024","1024x1536")]
  [string]$Size = "1024x1024",
  [ValidateSet("low","medium","high")]
  [string]$Quality = "high",
  [int]$DelayMs = 1100,
  [int]$MaxRetries = 3,
  [switch]$NoBackup,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  $ApiKey = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY")
}
if (-not $DryRun -and [string]::IsNullOrWhiteSpace($ApiKey)) {
  throw "OPENAI_API_KEY manquante. Passe -ApiKey ou exporte OPENAI_API_KEY."
}

$catalogPath = Join-Path $ProjectRoot "index.html"
$imagesDir = Join-Path $ProjectRoot "images"
$kitDir = Join-Path $imagesDir "ai-kit"

if (-not (Test-Path $catalogPath)) { throw "index.html introuvable: $catalogPath" }
if (-not (Test-Path $imagesDir)) { throw "Dossier images introuvable: $imagesDir" }
if (-not (Test-Path $kitDir)) { New-Item -ItemType Directory -Path $kitDir | Out-Null }

$content = Get-Content -Raw -Path $catalogPath
$pattern = "(?m)^\s*([A-Z0-9]+):\{name:'([^']+)',\s*img:'([^']+)'"
$matches = [regex]::Matches($content, $pattern)
if ($matches.Count -eq 0) { throw "Aucun article detecte dans le catalogue." }

$items = @()
foreach ($m in $matches) {
  $items += [PSCustomObject]@{
    code = $m.Groups[1].Value
    name = $m.Groups[2].Value
    img = $m.Groups[3].Value
  }
}
$items = $items | Sort-Object code -Unique

if (-not $NoBackup -and -not $DryRun) {
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupDir = Join-Path $imagesDir "_backup-openai-$stamp"
  New-Item -ItemType Directory -Path $backupDir | Out-Null
  foreach ($item in $items) {
    $src = Join-Path $imagesDir $item.img
    if (Test-Path $src) {
      Copy-Item -Path $src -Destination (Join-Path $backupDir $item.img) -Force
    }
  }
  Write-Host "Backup cree: $backupDir"
}

function New-Prompt([string]$code, [string]$name) {
  $baseStyle = @(
    "Photorealistic premium food photography."
    "Single main item only, centered in frame."
    "Square composition."
    "Clean sakura japan mood."
    "Soft warm studio light."
    "Background: smooth beige to sakura pink gradient, no texture banding."
    "Natural shadows."
    "No people, no hands, no cutlery unless needed."
    "No text, no logo, no watermark, no packaging labels, no brand marks."
    "No blur, no collage, no duplicated object."
  ) -join " "

  $typeHint = switch -Regex ($code) {
    "^B"   { "Cold drink product shot in minimalist japanese style." ; break }
    "^CO"  { "Japanese condiment in small ceramic bowl or clean product serving style." ; break }
    "^SO"  { "Soup served in elegant japanese bowl." ; break }
    "^G"   { "Gyoza plating, clearly visible pieces." ; break }
    "^BR"  { "Yakitori skewer style item, appetizing close-up." ; break }
    "^N"   { "Nigiri sushi style item." ; break }
    "^S"   { "Sashimi style plating." ; break }
    default { "Japanese sushi menu item studio shot." }
  }

  return "$baseStyle $typeHint Dish to depict: $name."
}

function Invoke-OpenAIImage(
  [string]$ApiKeyValue,
  [string]$Prompt,
  [string]$ModelValue,
  [string]$SizeValue,
  [string]$QualityValue
) {
  $headers = @{
    "Authorization" = "Bearer $ApiKeyValue"
  }

  $body = @{
    model = $ModelValue
    prompt = $Prompt
    size = $SizeValue
    quality = $QualityValue
    response_format = "b64_json"
  } | ConvertTo-Json -Depth 10

  $response = Invoke-RestMethod -Method Post `
    -Uri "https://api.openai.com/v1/images/generations" `
    -Headers $headers `
    -ContentType "application/json" `
    -Body $body

  if ($response.data -and $response.data[0] -and $response.data[0].b64_json) {
    return [Convert]::FromBase64String($response.data[0].b64_json)
  }

  if ($response.output -and $response.output[0].content[0].b64_json) {
    return [Convert]::FromBase64String($response.output[0].content[0].b64_json)
  }

  if ($response.data -and $response.data[0] -and $response.data[0].url) {
    $tmp = Invoke-WebRequest -Uri $response.data[0].url
    return $tmp.Content
  }

  throw "Reponse image inattendue."
}

$promptDump = @()
$ok = 0
$failed = @()

foreach ($item in $items) {
  $prompt = New-Prompt -code $item.code -name $item.name
  $outPath = Join-Path $imagesDir $item.img

  $promptDump += [PSCustomObject]@{
    code = $item.code
    name = $item.name
    filename = $item.img
    prompt = $prompt
  }

  if ($DryRun) {
    Write-Host "[DRY] $($item.code) -> $($item.img)"
    continue
  }

  $attempt = 0
  $saved = $false
  while (-not $saved -and $attempt -lt $MaxRetries) {
    $attempt++
    try {
      $bytes = Invoke-OpenAIImage `
        -ApiKeyValue $ApiKey `
        -Prompt $prompt `
        -ModelValue $Model `
        -SizeValue $Size `
        -QualityValue $Quality

      [System.IO.File]::WriteAllBytes($outPath, $bytes)
      Write-Host "[OK] $($item.code) $($item.name) -> $($item.img)"
      $ok++
      $saved = $true
    } catch {
      $msg = $_.Exception.Message
      Write-Warning "[Retry $attempt/$MaxRetries] $($item.code): $msg"
      if ($attempt -ge $MaxRetries) {
        $failed += "$($item.code): $msg"
      } else {
        Start-Sleep -Milliseconds 1500
      }
    }
  }

  Start-Sleep -Milliseconds $DelayMs
}

$promptsPath = Join-Path $kitDir "prompts-menu-openai.json"
$promptDump | ConvertTo-Json -Depth 6 | Set-Content -Path $promptsPath -Encoding UTF8

$result = [PSCustomObject]@{
  done = $ok
  total = $items.Count
  failed = $failed.Count
  prompts_file = $promptsPath
}

$result | ConvertTo-Json -Depth 6 | Write-Host

if ($failed.Count -gt 0) {
  Write-Host "Echecs:"
  $failed | ForEach-Object { Write-Host " - $_" }
}
