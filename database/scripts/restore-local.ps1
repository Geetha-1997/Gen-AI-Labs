[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)][string]$BackupFile,
  [string]$Container = "gen-ai-labs-db-1",
  [string]$Database = "genailabs",
  [string]$User = "genai"
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) { throw "Backup file not found: $BackupFile" }
Write-Warning "This overwrites objects in the target local database. It is not an RDS restore procedure."
if ($PSCmdlet.ShouldProcess("$Container/$Database", "Restore PostgreSQL custom-format backup")) {
  $remote = "/tmp/restore-genailabs.dump"
  docker cp $BackupFile "${Container}:$remote"
  if ($LASTEXITCODE -ne 0) { throw "Could not copy backup into database container." }
  docker exec $Container pg_restore --clean --if-exists --no-owner -U $User -d $Database $remote
  if ($LASTEXITCODE -ne 0) { throw "pg_restore failed." }
  docker exec $Container rm -f $remote
  Write-Host "Local database restore completed."
}
