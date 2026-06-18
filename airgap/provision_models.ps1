# Open Notebook airgap — auto-register Ollama models + set default assignments.
# Idempotent: waits for the API, registers the chat + embedding models if missing,
# and fills any unset default model slots. Safe to run on every boot.
# Server-side call to 127.0.0.1:5055 (no CORS involved).
param(
  [string]$ApiBase   = "http://127.0.0.1:5055",
  [string]$ChatModel = "gemma4:12b",
  [string]$EmbedModel = "nomic-embed-text",
  [int]$TimeoutSec   = 150
)
$ErrorActionPreference = 'Stop'
$H = @{ 'Content-Type' = 'application/json' }

# 1) wait for API health (migrations finish on first boot)
$ok = $false
for ($i = 0; $i -lt $TimeoutSec; $i++) {
  try {
    $health = Invoke-RestMethod -Uri "$ApiBase/health" -TimeoutSec 3
    if ($health.status -eq 'healthy') { $ok = $true; break }
  } catch {}
  Start-Sleep -Seconds 1
}
if (-not $ok) {
  Write-Output "[provision] API not healthy within $TimeoutSec s - skipping (register models manually in the Models page)."
  exit 0
}

# 2) ensure the two models exist
try { $models = @(Invoke-RestMethod -Uri "$ApiBase/api/models" -Headers $H -TimeoutSec 10) } catch { $models = @() }

function Ensure-Model([string]$name, [string]$type) {
  $hit = $models | Where-Object { $_.name -eq $name -and $_.type -eq $type } | Select-Object -First 1
  if ($hit) { Write-Host "[provision] model already present: $name ($type)"; return $hit.id }
  $body = @{ name = $name; provider = 'ollama'; type = $type } | ConvertTo-Json -Compress
  $r = Invoke-RestMethod -Uri "$ApiBase/api/models" -Method Post -Headers $H -Body $body -TimeoutSec 20
  Write-Host "[provision] registered: $name ($type) -> $($r.id)"
  return $r.id
}

$chatId  = Ensure-Model $ChatModel  'language'
$embedId = Ensure-Model $EmbedModel 'embedding'

# 3) fill unset default slots (keep any the operator already set)
$d = Invoke-RestMethod -Uri "$ApiBase/api/models/defaults" -Headers $H -TimeoutSec 10
if (-not $d.default_chat_model)           { $d.default_chat_model = $chatId }
if (-not $d.default_transformation_model) { $d.default_transformation_model = $chatId }
if (-not $d.default_tools_model)          { $d.default_tools_model = $chatId }
if (-not $d.large_context_model)          { $d.large_context_model = $chatId }
if (-not $d.default_embedding_model)      { $d.default_embedding_model = $embedId }
$body = $d | ConvertTo-Json -Compress
Invoke-RestMethod -Uri "$ApiBase/api/models/defaults" -Method Put -Headers $H -Body $body -TimeoutSec 10 | Out-Null

Write-Output "[provision] done. defaults: chat/transform/tools/large=$ChatModel, embedding=$EmbedModel"
Write-Output "[provision] NOTE: Ollama must have these models pulled (ollama pull $ChatModel ; ollama pull $EmbedModel)."
