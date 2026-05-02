# BTOX Android build script (PowerShell)

}
    "  {0,-12}  {1,10:N0} bytes" -f $_.Directory.Name,$_.Length
Get-ChildItem -Recurse -Filter 'libbtox_core.so' $jniLibs | ForEach-Object {
Write-Host "Olusturulan kutuphaneler:" -ForegroundColor Green
Write-Host ""

}
    Pop-Location
} finally {
    if ($LASTEXITCODE -ne 0) { throw "cargo ndk basarisiz." }
    & cargo @buildArgs
    Write-Host "cargo $($buildArgs -join ' ')" -ForegroundColor Cyan
try {
Push-Location $rustDir

if ($Profile -eq 'release') { $buildArgs += '--release' }
    'build')
    '-o', $jniLibs,
    '-t','arm64-v8a','-t','armeabi-v7a','-t','x86_64','-t','x86',
$buildArgs = @('ndk',

Write-Host "NDK: $env:ANDROID_NDK_HOME"
}
    exit 1
    Write-Host "ANDROID_NDK_HOME bulunamadi. Android Studio -> SDK Manager -> NDK kur." -ForegroundColor Red
if (-not $env:ANDROID_NDK_HOME) {
}
    }
        }
            if ($latest) { $env:ANDROID_NDK_HOME = $latest.FullName; break }
            $latest = Get-ChildItem $c -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if (Test-Path $c) {
    foreach ($c in $candidates) {
    )
        "$env:ANDROID_SDK_ROOT\ndk"
        "$env:ANDROID_HOME\ndk",
        "$env:LOCALAPPDATA\Android\Sdk\ndk",
    $candidates = @(
if (-not $env:ANDROID_NDK_HOME) {

$jniLibs   = Join-Path $root 'flutter\android\app\src\main\jniLibs'
$rustDir   = Join-Path $root 'rust'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ErrorActionPreference = 'Stop'

)
    [string]$Profile = 'release'
    [ValidateSet('debug','release')]
param(

#   ANDROID_NDK_HOME ayarlanmış olmalı (Android Studio: SDK Manager -> NDK 26+)
#   cargo install cargo-ndk
#   rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
# Önkoşullar:
#
# jniLibs altına .so dosyalarını yerleştirir.
# Rust çekirdeğini Android için cross-derler ve Flutter projesinin
