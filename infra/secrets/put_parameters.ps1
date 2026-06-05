<#
  Pousse les secrets/config de l'app dans AWS SSM Parameter Store sous
  /marche-cm/prod/*. Idempotent (--overwrite).

  - Génère les secrets Django (SECRET_KEY, DATA_ENCRYPTION_KEY Fernet,
    REDIS_PASSWORD, DEVICE_FINGERPRINT_SECRET) s'ils n'existent pas déjà dans SSM.
  - Lit les secrets externes + config depuis values.local.env (NON committé).

  Usage (depuis le dossier du projet) :
    powershell -File infra\secrets\put_parameters.ps1
#>
param(
  [string]$AwsProfile = "central-market_credentials",
  [string]$Region     = "eu-north-1",
  [string]$Prefix     = "/marche-cm/prod"
)
# NB : PAS de ErrorActionPreference=Stop — les commandes natives (aws) écrivent
# sur stderr dans des cas normaux (ParameterNotFound), ce qui deviendrait fatal.
$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# aws via le python du venv (robuste face au shim batch)
$AwsPy     = "E:\tools\awsenv\Scripts\python.exe"
$AwsScript = "E:\tools\awsenv\Scripts\aws"
function Invoke-AwsSilent { param([string[]]$a) & $AwsPy $AwsScript @a *> $null; return $LASTEXITCODE }

function Set-SsmParam {
  param([string]$Name, [string]$Value, [ValidateSet("String","SecureString")][string]$Type)
  if ([string]::IsNullOrWhiteSpace($Value)) { Write-Host "  (vide, ignoré) $Name" -ForegroundColor DarkYellow; return }
  # Forme --value=... : tout ce qui suit le '=' est littéral, même un '-' initial
  # (sinon aws interprète une valeur commençant par '-' comme une option).
  $code = Invoke-AwsSilent @("ssm","put-parameter","--name","$Prefix/$Name","--value=$Value",
    "--type",$Type,"--overwrite","--region",$Region,"--profile",$AwsProfile)
  if ($code -eq 0) { Write-Host "  ok  $Prefix/$Name  ($Type)" -ForegroundColor Green }
  else { Write-Host "  ECHEC ($code) $Prefix/$Name" -ForegroundColor Red }
}

function Test-SsmParam {
  param([string]$Name)
  return ((Invoke-AwsSilent @("ssm","get-parameter","--name","$Prefix/$Name","--region",$Region,"--profile",$AwsProfile)) -eq 0)
}

function New-Secret { param([string]$PyExpr) return (& $AwsPy -c "import secrets,base64,os;print($PyExpr)").Trim() }

# Empêche l'AWS CLI de "suivre" une valeur commençant par http(s)://file:// (sinon
# il tente de télécharger l'URL au lieu de la stocker — ex. BACKEND_PUBLIC_URL).
Invoke-AwsSilent @("configure","set","cli_follow_urlparam","false","--profile",$AwsProfile) | Out-Null

# Vérif d'accès AWS avant de commencer
if ((Invoke-AwsSilent @("sts","get-caller-identity","--profile",$AwsProfile,"--region",$Region)) -ne 0) {
  Write-Host "Profil AWS '$AwsProfile' inaccessible. Lance d'abord: aws configure --profile $AwsProfile" -ForegroundColor Red
  exit 1
}

Write-Host "== Secrets Django (generes si absents) ==" -ForegroundColor Cyan
$django = @{
  "SECRET_KEY"                = 'secrets.token_urlsafe(64)'
  "DATA_ENCRYPTION_KEY"       = 'base64.urlsafe_b64encode(os.urandom(32)).decode()'
  "REDIS_PASSWORD"            = 'secrets.token_urlsafe(32)'
  "DEVICE_FINGERPRINT_SECRET" = 'secrets.token_urlsafe(48)'
}
foreach ($k in $django.Keys) {
  if (Test-SsmParam $k) { Write-Host "  (existe deja, conserve) $Prefix/$k" -ForegroundColor DarkGray }
  else { Set-SsmParam -Name $k -Value (New-Secret $django[$k]) -Type "SecureString" }
}

Write-Host "== Config non-secrete ==" -ForegroundColor Cyan
Set-SsmParam -Name "DB_HOST"                 -Value "marchecm-postgres.ch64seqcuph3.eu-north-1.rds.amazonaws.com" -Type "String"
Set-SsmParam -Name "DB_PORT"                 -Value "5432"           -Type "String"
Set-SsmParam -Name "DB_USER"                 -Value "marchecm_admin" -Type "String"
Set-SsmParam -Name "DB_SSLMODE"              -Value "require"        -Type "String"
Set-SsmParam -Name "AWS_STORAGE_BUCKET_NAME" -Value "market-cm"      -Type "String"
Set-SsmParam -Name "AWS_S3_REGION_NAME"      -Value "eu-north-1"     -Type "String"

Write-Host "== Secrets externes (values.local.env) ==" -ForegroundColor Cyan
$values = Join-Path $here "values.local.env"
if (-not (Test-Path $values)) {
  Write-Host "  values.local.env absent — copie values.local.env.example, renseigne-le, puis relance." -ForegroundColor Yellow
  Write-Host "  (Les secrets Django ci-dessus sont deja pousses.)" -ForegroundColor Yellow
  exit 0
}
$map = @{}
Get-Content $values | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $i = $_.IndexOf('='); $key = $_.Substring(0,$i).Trim(); $val = $_.Substring($i+1).Trim()
  if ($key) { $map[$key] = $val }
}
foreach ($k in @("DB_PASSWORD","NOTCHPAY_PUBLIC_KEY","NOTCHPAY_PRIVATE_KEY",
                 "NOTCHPAY_CHECKOUT_WEBHOOK_SECRET","NOTCHPAY_DISBURSE_WEBHOOK_SECRET",
                 "EMAIL_HOST_PASSWORD")) {
  Set-SsmParam -Name $k -Value $map[$k] -Type "SecureString"
}
foreach ($k in @("DB_NAME","EMAIL_HOST","EMAIL_HOST_USER","DEFAULT_FROM_EMAIL",
                 "ALLOWED_HOSTS","BACKEND_PUBLIC_URL")) {
  Set-SsmParam -Name $k -Value $map[$k] -Type "String"
}

Write-Host ""
Write-Host "Termine. Verifier : aws ssm get-parameters-by-path --path $Prefix --recursive --profile $AwsProfile --region $Region --query 'Parameters[].Name'" -ForegroundColor Magenta
