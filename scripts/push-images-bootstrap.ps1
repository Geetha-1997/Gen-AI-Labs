[CmdletBinding()]
param([string]$Region = "ap-south-1")
$ErrorActionPreference = "Stop"
function Invoke-AwsText([string[]]$Arguments) {
  $result = & aws @Arguments
  if ($LASTEXITCODE -ne 0) { throw "AWS CLI failed: aws $($Arguments -join ' ')" }
  return ($result | Out-String).Trim()
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  $account = Invoke-AwsText @("sts","get-caller-identity","--query","Account","--output","text")
  $registry = "$account.dkr.ecr.$Region.amazonaws.com"
  $backend = "$registry/gen-ai-labs-api"
  $frontend = "$registry/gen-ai-labs-web"
  $tag = git rev-parse --short=12 HEAD 2>$null
  if (-not $tag) { $tag = Get-Date -Format "yyyyMMddHHmmss" }
  Invoke-AwsText @("ecr","get-login-password","--region",$Region) | docker login --username AWS --password-stdin $registry
  if ($LASTEXITCODE -ne 0) { throw "ECR login failed." }
  docker build -t "${backend}:$tag" -t "${backend}:current" .\backend
  if ($LASTEXITCODE -ne 0) { throw "Backend image build failed." }
  docker build --build-arg VITE_API_URL= --build-arg VITE_MODEL_NAME=Llama -t "${frontend}:$tag" -t "${frontend}:current" .\frontend
  if ($LASTEXITCODE -ne 0) { throw "Frontend image build failed." }
  foreach ($image in @("${backend}:$tag","${backend}:current","${frontend}:$tag","${frontend}:current")) {
    docker push $image
    if ($LASTEXITCODE -ne 0) { throw "Image push failed: $image" }
  }
  Write-Host "Bootstrap images pushed. Continue with the full Terraform plan/apply. Commit tag: $tag"
} finally { Pop-Location }
