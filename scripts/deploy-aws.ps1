[CmdletBinding()]
param(
  [string]$Region = "ap-south-1",
  [string]$Project = "gen-ai-labs",
  [string]$BackendRepository = "gen-ai-labs-api",
  [string]$FrontendRepository = "gen-ai-labs-web"
)
$ErrorActionPreference = "Stop"
function Invoke-AwsText([string[]]$Arguments) {
  $result = & aws @Arguments
  if ($LASTEXITCODE -ne 0) { throw "AWS CLI failed: aws $($Arguments -join ' ')" }
  return ($result | Out-String).Trim()
}
function Wait-Ssm([string]$CommandId, [string]$InstanceId) {
  for ($i = 0; $i -lt 60; $i++) {
    try {
      $raw = Invoke-AwsText @("ssm","get-command-invocation","--region",$Region,"--command-id",$CommandId,"--instance-id",$InstanceId,"--output","json")
      $inv = $raw | ConvertFrom-Json
    } catch {
      Start-Sleep -Seconds 5
      continue
    }
    if ($inv.Status -in @("Success","Cancelled","TimedOut","Failed","Cancelling")) {
      if ($inv.Status -ne "Success") { throw "SSM command $CommandId failed on $InstanceId: $($inv.StandardErrorContent)" }
      return
    }
    Start-Sleep -Seconds 5
  }
  throw "Timed out waiting for SSM command $CommandId on $InstanceId"
}
function Get-TaggedInstances([string]$Role) {
  $query = "Reservations[].Instances[?State.Name=='running'].InstanceId[]"
  $ids = Invoke-AwsText @("ec2","describe-instances","--region",$Region,"--filters","Name=tag:Project,Values=$Project","Name=tag:Role,Values=$Role","Name=instance-state-name,Values=running","--query",$query,"--output","text")
  return @($ids -split '\s+' | Where-Object { $_ -match '^i-' })
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  $identity = Invoke-AwsText @("sts","get-caller-identity","--query","Account","--output","text")
  $registry = "$identity.dkr.ecr.$Region.amazonaws.com"
  $backendUri = "$registry/$BackendRepository"
  $frontendUri = "$registry/$FrontendRepository"
  $tag = (git rev-parse --short=12 HEAD 2>$null)
  if (-not $tag) { $tag = Get-Date -Format "yyyyMMddHHmmss" }

  Invoke-AwsText @("ecr","get-login-password","--region",$Region) | docker login --username AWS --password-stdin $registry
  if ($LASTEXITCODE -ne 0) { throw "Docker ECR login failed." }
  docker build -t "${backendUri}:$tag" -t "${backendUri}:current" .\backend
  if ($LASTEXITCODE -ne 0) { throw "Backend image build failed." }
  docker build --build-arg VITE_API_URL= --build-arg VITE_MODEL_NAME=Llama -t "${frontendUri}:$tag" -t "${frontendUri}:current" .\frontend
  if ($LASTEXITCODE -ne 0) { throw "Frontend image build failed." }
  docker push "${backendUri}:$tag"; if ($LASTEXITCODE -ne 0) { throw "Backend push failed." }
  docker push "${backendUri}:current"; if ($LASTEXITCODE -ne 0) { throw "Backend current-tag push failed." }
  docker push "${frontendUri}:$tag"; if ($LASTEXITCODE -ne 0) { throw "Frontend push failed." }
  docker push "${frontendUri}:current"; if ($LASTEXITCODE -ne 0) { throw "Frontend current-tag push failed." }

  $appInstances = Get-TaggedInstances "app"
  if ($appInstances.Count -lt 2) { throw "Expected two running app instances. Check Terraform and SSM registration." }
  $script:CurrentRole = "app"
  $login = "aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $registry"
  $migration = "$login; docker pull ${backendUri}:current; docker run --rm --env-file /opt/genai/backend.env ${backendUri}:current alembic upgrade head"
  $params = @{ commands = @($migration) } | ConvertTo-Json -Compress
  $commandId = Invoke-AwsText @("ssm","send-command","--region",$Region,"--document-name","AWS-RunShellScript","--instance-ids",$appInstances[0],"--parameters",$params,"--timeout-seconds","600","--query","Command.CommandId","--output","text")
  Wait-Ssm -CommandId $commandId -InstanceId $appInstances[0]

  $appUpdate = @($login, "docker pull ${backendUri}:current", "docker rm -f genai-api || true", "docker run -d --name genai-api --restart unless-stopped --log-driver=awslogs --log-opt awslogs-region=$Region --log-opt awslogs-group=/gen-ai-labs/production --log-opt awslogs-stream=api-`$(hostname) --env-file /opt/genai/backend.env -p 8000:8000 ${backendUri}:current")
  foreach ($instance in $appInstances) {
    $params = @{ commands = $appUpdate } | ConvertTo-Json -Compress
    $commandId = Invoke-AwsText @("ssm","send-command","--region",$Region,"--document-name","AWS-RunShellScript","--instance-ids",$instance,"--parameters",$params,"--timeout-seconds","600","--query","Command.CommandId","--output","text")
    Wait-Ssm -CommandId $commandId -InstanceId $instance
  }

  $webInstances = Get-TaggedInstances "web"
  if ($webInstances.Count -lt 2) { throw "Expected two running web instances. Check Terraform and SSM registration." }
  $webUpdate = @($login, "docker pull ${frontendUri}:current", "docker rm -f genai-web || true", "docker run -d --name genai-web --restart unless-stopped --log-driver=awslogs --log-opt awslogs-region=$Region --log-opt awslogs-group=/gen-ai-labs/production --log-opt awslogs-stream=web-`$(hostname) -p 8080:8080 -v /opt/genai/default.conf:/etc/nginx/conf.d/default.conf:ro ${frontendUri}:current")
  foreach ($instance in $webInstances) {
    $params = @{ commands = $webUpdate } | ConvertTo-Json -Compress
    $commandId = Invoke-AwsText @("ssm","send-command","--region",$Region,"--document-name","AWS-RunShellScript","--instance-ids",$instance,"--parameters",$params,"--timeout-seconds","600","--query","Command.CommandId","--output","text")
    Wait-Ssm -CommandId $commandId -InstanceId $instance
  }

  Write-Host "Deployment commands succeeded. Image tag: $tag"
  Write-Host "Check ALB target health and test the application URL before considering deployment complete."
} finally { Pop-Location }
