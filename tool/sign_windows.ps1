# Signs the Windows release exe with the Certum code-signing cert.
# SimplySign Desktop must be connected first: that is what puts the cert in the user's cert store.
param([string]$Subject = 'Open Source Developer, Ridha Ferchichi')
$ErrorActionPreference = 'Stop'

$exe = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\mybudget.exe'
if (-not (Test-Path $exe)) { throw "Build first: flutter build windows --release --dart-define-from-file=env.json" }
$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" | Sort-Object FullName | Select-Object -Last 1
if (-not $signtool) { throw 'signtool.exe not found; install the Windows SDK.' }

& $signtool.FullName sign /n $Subject /fd sha256 /tr http://time.certum.pl /td sha256 /v $exe
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& $signtool.FullName verify /pa /v $exe
exit $LASTEXITCODE
