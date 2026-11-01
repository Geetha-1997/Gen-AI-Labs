param(
  [string]$Container = "gen-ai-labs-db-1",
  [string]$Database = "genailabs",
  [string]$User = "genai"
)
$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path $PSScriptRoot "..\backups"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outFile = Join-Path $outDir "genailabs-$stamp.dump"
docker exec $Container pg_dump -U $User -d $Database -Fc -f /tmp/genailabs.dump
if ($LASTEXITCODE -ne 0) { throw "pg_dump failed." }
docker cp "${Container}:/tmp/genailabs.dump" $outFile
if ($LASTEXITCODE -ne 0) { throw "Could not copy database backup." }
docker exec $Container rm -f /tmp/genailabs.dump
if ($LASTEXITCODE -ne 0) { throw "Could not remove temporary backup from container." }
Write-Host "Backup created: $outFile"
Write-Warning "Keep backups encrypted and outside Git; this file may contain personal data."
