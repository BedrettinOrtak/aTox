<#
.SYNOPSIS
    GitHub Actions 'build-apk' workflow'unun en son basarili calismasindan tox4j
    artifact'ini indirip yerel Maven deposuna (~/.m2) acar. Boylece Windows'ta
    Android Studio / emulator icin yerel build yapabilirsin.

.PRARQ
    - GitHub CLI: https://cli.github.com/  ->  `winget install --id GitHub.cli`
    - Bir kere giris: `gh auth login`

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\fetch-tox4j-windows.ps1
#>

$ErrorActionPreference = 'Stop'

# 0) gh CLI var mi?
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "GitHub CLI (gh) bulunamadi." -ForegroundColor Red
    Write-Host "Kur: winget install --id GitHub.cli  ya da  https://cli.github.com/"
    exit 1
}

# 1) Giris kontrolu
& gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "gh giris yapmamissin. Calistir: gh auth login" -ForegroundColor Yellow
    exit 1
}

# 2) Repo: cwd'deki git remote'tan al
$repo = (& git -C $PSScriptRoot/.. remote get-url origin) `
        -replace '\.git$','' `
        -replace '^git@github\.com:','' `
        -replace '^https?://github\.com/',''
Write-Host "Repo: $repo"

# 3) En son basarili build-apk runini bul
Write-Host "En son basarili 'build-apk' run araniyor..."
$runId = & gh run list --repo $repo --workflow build-apk.yaml --status success --limit 1 --json databaseId --jq '.[0].databaseId'
if (-not $runId) {
    Write-Host "Basarili 'build-apk' runi bulunamadi. Once Actions sekmesinden tetikleyip bitmesini bekle." -ForegroundColor Red
    exit 1
}
Write-Host "Run id: $runId"

# 4) Indir
$tmp = Join-Path $env:TEMP "atox-tox4j-$runId"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Path $tmp | Out-Null

Write-Host "tox4j artifact indiriliyor..."
& gh run download $runId --repo $repo --name tox4j --dir $tmp
if ($LASTEXITCODE -ne 0) { Write-Host "Indirme basarisiz." -ForegroundColor Red; exit 1 }

# 5) Hedef: ~/.m2/repository/org/toktok
$m2 = Join-Path $env:USERPROFILE ".m2\repository"
New-Item -ItemType Directory -Force -Path $m2 | Out-Null

# Artifact icerigi ya .m2/repository/... ya da repository/... seklinde olabilir.
$src = $null
foreach ($cand in @(
    (Join-Path $tmp "repository"),
    (Join-Path $tmp ".m2\repository"),
    $tmp
)) {
    if (Test-Path (Join-Path $cand "org\toktok")) { $src = $cand; break }
}
if (-not $src) {
    Write-Host "Indirilen artifact icinde org/toktok klasoru bulunamadi:" -ForegroundColor Red
    Get-ChildItem -Recurse $tmp | Select-Object -First 30 FullName
    exit 1
}

Write-Host "Kopyalaniyor: $src\org\toktok  ->  $m2\org\toktok"
Copy-Item -Recurse -Force (Join-Path $src "org\toktok") (Join-Path $m2 "org")

Write-Host ""
Write-Host "TAMAM. Yerel Maven deposunda tox4j hazir." -ForegroundColor Green
Write-Host "Simdi Android Studio'da Sync Project + Run yapabilirsin."

