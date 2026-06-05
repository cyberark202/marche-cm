<#
  Exécute un script shell sur l'EC2 via AWS SSM (AWS-RunShellScript) — sans SSH.
  Insensible aux bans SSH / IP dynamique. L'EC2 doit être "Online" dans SSM.

    powershell -File infra\deploy\ssm_run.ps1 -ScriptFile infra\deploy\_diag.sh
#>
param(
  [Parameter(Mandatory=$true)][string]$ScriptFile,
  [string]$AwsProfile = "central-market_credentials",
  [string]$Region     = "eu-north-1",
  [string]$InstanceId = "i-09e104c1cd49c757e",
  [int]$TimeoutSec    = 1800
)
$ErrorActionPreference = "Continue"
$py = "E:\tools\awsenv\Scripts\python.exe"; $sc = "E:\tools\awsenv\Scripts\aws"
function Aws { param([string[]]$a) & $py $sc @a }

# Lecture .NET : string propre sans NoteProperties ETS (PSPath, etc.)
$script = [System.IO.File]::ReadAllText($ScriptFile)
$payload = @{
  InstanceIds  = @($InstanceId)
  DocumentName = "AWS-RunShellScript"
  Parameters   = @{ commands = @($script); executionTimeout = @("$TimeoutSec") }
} | ConvertTo-Json -Depth 6
$json = Join-Path $env:TEMP "ssm_payload.json"
# Écriture UTF-8 SANS BOM (l'AWS CLI rejette le BOM dans --cli-input-json)
[System.IO.File]::WriteAllText($json, $payload, (New-Object System.Text.UTF8Encoding($false)))

$cmdId = (Aws @("ssm","send-command","--cli-input-json","file://$json","--region",$Region,"--profile",$AwsProfile,"--query","Command.CommandId","--output","text")).Trim()
if (-not $cmdId) { Write-Host "send-command a echoue" -ForegroundColor Red; exit 1 }
Write-Host "CommandId: $cmdId" -ForegroundColor Cyan

$status = "Pending"
do {
  Start-Sleep -Seconds 6
  $status = (Aws @("ssm","get-command-invocation","--command-id",$cmdId,"--instance-id",$InstanceId,"--region",$Region,"--profile",$AwsProfile,"--query","Status","--output","text")).Trim()
  Write-Host "  status=$status" -ForegroundColor DarkGray
} while ($status -in @("Pending","InProgress","Delayed"))

Write-Host "=== STDOUT ===" -ForegroundColor Green
Aws @("ssm","get-command-invocation","--command-id",$cmdId,"--instance-id",$InstanceId,"--region",$Region,"--profile",$AwsProfile,"--query","StandardOutputContent","--output","text")
$err = (Aws @("ssm","get-command-invocation","--command-id",$cmdId,"--instance-id",$InstanceId,"--region",$Region,"--profile",$AwsProfile,"--query","StandardErrorContent","--output","text"))
if ($err -and $err.Trim()) { Write-Host "=== STDERR ===" -ForegroundColor Yellow; $err }
Write-Host "FINAL STATUS: $status" -ForegroundColor Magenta
