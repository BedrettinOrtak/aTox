# BTOX geliştirici komutları (PowerShell)
# Kullanım:  .\dev.ps1 <komut>
#   bridge       - flutter_rust_bridge ile Dart/Rust köprüsünü üret
#   rust         - Rust kütüphanesini host için derle (stub)
#   rust-real    - Rust kütüphanesini gerçek tox ile derle (host)
#   android      - Rust'u Android için cross-derle ve jniLibs altına koy
#   apk          - Flutter ile debug APK derle
#   run          - Flutter uygulamasını bağlı emülatör/cihazda çalıştır
#   clean        - Tüm build artefaktlarını sil

param([Parameter(Position=0)] [string]$cmd = 'help')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Step($name, $block) {
    Write-Host ""
    Write-Host "▶ $name" -ForegroundColor Cyan
    & $block
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) { throw "$name basarisiz." }
}

switch ($cmd) {
    'bridge' {
        Step 'flutter_rust_bridge codegen' {
            Push-Location $root
            try { flutter_rust_bridge_codegen generate }
            finally { Pop-Location }
        }
    }
    'rust' {
        Step 'cargo build (stub)' {
            Push-Location (Join-Path $root 'rust')
            try { cargo build } finally { Pop-Location }
        }
    }
    'rust-real' {
        Step 'cargo build --features real-tox' {
            Push-Location (Join-Path $root 'rust')
            try { cargo build --features real-tox } finally { Pop-Location }
        }
    }
    'android' {
        Step 'Android cross-build' {
            & (Join-Path $root 'build_android.ps1') -Profile release
        }
    }
    'apk' {
        Step 'flutter build apk --debug' {
            Push-Location (Join-Path $root 'flutter')
            try {
                if (-not (Test-Path 'android')) { flutter create --platforms=android . | Out-Host }
                flutter pub get
                flutter build apk --debug
            } finally { Pop-Location }
        }
    }
    'run' {
        Step 'flutter run' {
            Push-Location (Join-Path $root 'flutter')
            try {
                if (-not (Test-Path 'android')) { flutter create --platforms=android . | Out-Host }
                flutter pub get
                flutter run
            } finally { Pop-Location }
        }
    }
    'clean' {
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue `
            (Join-Path $root 'rust\target'), `
            (Join-Path $root 'flutter\build'), `
            (Join-Path $root 'flutter\.dart_tool'), `
            (Join-Path $root 'flutter\android\app\src\main\jniLibs')
        Write-Host 'Temizlendi.' -ForegroundColor Green
    }
    default {
        Write-Host "BTOX dev komutlari:"
        Write-Host "  bridge      flutter_rust_bridge ile koprü üret"
        Write-Host "  rust        Rust'u host için derle (stub)"
        Write-Host "  rust-real   Rust'u gerçek tox ile derle"
        Write-Host "  android     Rust'u Android için cross-derle"
        Write-Host "  apk         Debug APK derle"
        Write-Host "  run         Emülatörde çalıştır"
        Write-Host "  clean       Build artefaktlarini sil"
    }
}

