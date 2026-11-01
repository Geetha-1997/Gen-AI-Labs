[CmdletBinding()]
param([string]$Region = "ap-south-1")
$ErrorActionPreference = "Stop"
function Invoke-Aws([string[]]$Arguments) {
  & aws @Arguments
  if ($LASTEXITCODE -ne 0) { throw "AWS CLI failed: aws $($Arguments -join ' ')" }
}
$account = (& aws sts get-caller-identity --query Account --output text).Trim()
if ($LASTEXITCODE -ne 0) { throw "AWS identity check failed." }
$bucket = "gen-ai-labs-tfstate-$account-$Region"
$exists = & aws s3api head-bucket --bucket $bucket 2>$null
if ($LASTEXITCODE -ne 0) {
  Invoke-Aws @("s3api","create-bucket","--bucket",$bucket,"--region",$Region,"--create-bucket-configuration","LocationConstraint=$Region")
}
Invoke-Aws @("s3api","put-public-access-block","--bucket",$bucket,"--public-access-block-configuration","BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true")
Invoke-Aws @("s3api","put-bucket-versioning","--bucket",$bucket,"--versioning-configuration","Status=Enabled")
$encryption = '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
Invoke-Aws @("s3api","put-bucket-encryption","--bucket",$bucket,"--server-side-encryption-configuration",$encryption)
$policy = @{
  Version = "2012-10-17"
  Statement = @(@{
    Sid = "DenyInsecureTransport"
    Effect = "Deny"
    Principal = "*"
    Action = "s3:*"
    Resource = @("arn:aws:s3:::$bucket", "arn:aws:s3:::$bucket/*")
    Condition = @{ Bool = @{ "aws:SecureTransport" = "false" } }
  })
} | ConvertTo-Json -Depth 10 -Compress
Invoke-Aws @("s3api","put-bucket-policy","--bucket",$bucket,"--policy",$policy)
$table = & aws dynamodb describe-table --region $Region --table-name gen-ai-labs-terraform-locks --query Table.TableStatus --output text 2>$null
if ($LASTEXITCODE -ne 0) {
  Invoke-Aws @("dynamodb","create-table","--region",$Region,"--table-name","gen-ai-labs-terraform-locks","--attribute-definitions","AttributeName=LockID,AttributeType=S","--key-schema","AttributeName=LockID,KeyType=HASH","--billing-mode","PAY_PER_REQUEST")
  Invoke-Aws @("dynamodb","wait","table-exists","--region",$Region,"--table-name","gen-ai-labs-terraform-locks")
}
Write-Host "Terraform state bucket: $bucket"
Write-Host "Copy infra/terraform/backend.tf.example to backend.tf, replace the bucket name, then run terraform init -migrate-state."
