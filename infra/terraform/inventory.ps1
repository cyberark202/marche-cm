<#
  Inventaire READ-ONLY de l'infra AWS existante (compte central-market).
  N'effectue AUCUNE modification : uniquement des appels describe/list/get.
  Exporte le résultat en JSON dans infra/terraform/inventory/ pour codifier
  ensuite le Terraform et préparer les `terraform import`.

  Usage :
    pwsh -File infra/terraform/inventory.ps1 -Profile central-market_credentials [-Region eu-west-3]
#>
param(
  [string]$Profile = "central-market_credentials",
  [string]$Region  = ""
)

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out  = Join-Path $here "inventory"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$common = @("--profile", $Profile, "--output", "json")
if ($Region -ne "") { $common += @("--region", $Region) }

# Appel direct du python du venv : évite le shim aws.cmd (batch) qui, via cmd.exe,
# re-parse les métacaractères (|, &, <, >) présents dans les expressions --query.
$AwsPy     = "E:\tools\awsenv\Scripts\python.exe"
$AwsScript = "E:\tools\awsenv\Scripts\aws"
function Invoke-Aws { param([string[]]$a) & $AwsPy $AwsScript @a }

function Dump($name, [string[]]$awsArgs) {
  Write-Host "→ $name" -ForegroundColor Cyan
  $file = Join-Path $out "$name.json"
  $res = Invoke-Aws ($awsArgs + $common) 2>&1
  if ($LASTEXITCODE -eq 0) {
    $res | Out-File -FilePath $file -Encoding utf8
    Write-Host "   ok → $file" -ForegroundColor Green
  } else {
    Write-Host "   ERREUR : $res" -ForegroundColor Yellow
    "ERROR: $res" | Out-File -FilePath $file -Encoding utf8
  }
}

Write-Host "=== Identité appelante ===" -ForegroundColor Magenta
Invoke-Aws (@("sts","get-caller-identity") + $common)

Dump "ec2_instances"        @("ec2","describe-instances")
Dump "vpcs"                 @("ec2","describe-vpcs")
Dump "subnets"              @("ec2","describe-subnets")
Dump "route_tables"        @("ec2","describe-route-tables")
Dump "internet_gateways"   @("ec2","describe-internet-gateways")
Dump "nat_gateways"        @("ec2","describe-nat-gateways")
Dump "security_groups"     @("ec2","describe-security-groups")
Dump "elastic_ips"         @("ec2","describe-addresses")
Dump "key_pairs"           @("ec2","describe-key-pairs")
Dump "ebs_volumes"         @("ec2","describe-volumes")
Dump "rds_instances"       @("rds","describe-db-instances")
Dump "rds_subnet_groups"   @("rds","describe-db-subnet-groups")
Dump "rds_snapshots"       @("rds","describe-db-snapshots","--snapshot-type","manual")
Dump "s3_buckets"          @("s3api","list-buckets")
Dump "iam_users"           @("iam","list-users")
Dump "iam_roles"           @("iam","list-roles")
Dump "iam_policies_local"  @("iam","list-policies","--scope","Local")
Dump "iam_instance_profiles" @("iam","list-instance-profiles")
Dump "ecr_repos"           @("ecr","describe-repositories")
Dump "cloudwatch_alarms"   @("cloudwatch","describe-alarms")
Dump "log_groups"          @("logs","describe-log-groups")

Write-Host ""
Write-Host "Inventaire terminé. Fichiers dans : $out" -ForegroundColor Magenta
