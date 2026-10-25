[CmdletBinding()]
param(
    [ValidateSet('arm64-v8a')]
    [string] $Abi = 'arm64-v8a',
    [string] $NdkBuild,
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$coreRoot = Join-Path $repositoryRoot 'core\bsnes'
$patch = Join-Path $repositoryRoot 'patches\0001-emuorbit-android-libretro.patch'
$expectedCommit = '7d5aa1e656b9171524d01b1b22917197d8121cb4'

if (-not (Test-Path -LiteralPath (Join-Path $coreRoot '.git'))) {
    throw 'O submódulo core/bsnes não foi inicializado. Execute git submodule update --init --recursive.'
}

$actualCommit = (& git -C $coreRoot rev-parse HEAD).Trim()
if ($actualCommit -ne $expectedCommit) {
    throw "O core não está no commit esperado: $expectedCommit. Encontrado: $actualCommit."
}

if ([string]::IsNullOrWhiteSpace($NdkBuild)) {
    $ndkRoot = if ($env:ANDROID_NDK_HOME) {
        $env:ANDROID_NDK_HOME
    } elseif ($env:ANDROID_NDK_ROOT) {
        $env:ANDROID_NDK_ROOT
    } else {
        $sdkRoot = if ($env:ANDROID_SDK_ROOT) {
            $env:ANDROID_SDK_ROOT
        } elseif ($env:ANDROID_HOME) {
            $env:ANDROID_HOME
        } else {
            Join-Path $env:LOCALAPPDATA 'Android\Sdk'
        }
        Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'ndk') -Directory |
            Sort-Object Name -Descending |
            Select-Object -First 1 |
            ForEach-Object FullName
    }
    if ([string]::IsNullOrWhiteSpace($ndkRoot)) {
        throw 'Android NDK não encontrado. Informe -NdkBuild com o caminho de ndk-build.cmd.'
    }
    $NdkBuild = Join-Path $ndkRoot 'ndk-build.cmd'
}

if (-not (Test-Path -LiteralPath $NdkBuild)) {
    throw "ndk-build.cmd não encontrado: $NdkBuild"
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot "artifacts\android\$Abi"
}

$worktree = Join-Path ([System.IO.Path]::GetTempPath()) "sns-glp-bsnes-$PID"
try {
    & git -C $coreRoot worktree add --detach $worktree $expectedCommit
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível criar o worktree temporário do core.'
    }

    & git -C $worktree apply --check --ignore-space-change $patch
    if ($LASTEXITCODE -ne 0) {
        throw 'O patch Android não corresponde ao commit fixado do core.'
    }
    & git -C $worktree apply --ignore-space-change $patch
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível aplicar o patch Android do core.'
    }

    $derived = Get-Content -LiteralPath (Join-Path $repositoryRoot 'patches/derived-source-hashes.json') -Raw | ConvertFrom-Json
    foreach ($entry in $derived.files) {
        $text = [IO.File]::ReadAllText((Join-Path $worktree $entry.path)).Replace("`r`n", "`n")
        $bytes = [Text.Encoding]::UTF8.GetBytes($text)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        if ($actual -cne $entry.derived_lf_sha256) { throw "Derived source mismatch: $($entry.path)" }
    }

    $targetRoot = Join-Path $worktree 'bsnes\target-libretro'
    $objectRoot = Join-Path $worktree '.ndk-obj'
    $libraryRoot = Join-Path $worktree '.ndk-libs'
    & $NdkBuild `
        "NDK_PROJECT_PATH=$targetRoot" `
        "APP_BUILD_SCRIPT=$(Join-Path $targetRoot 'jni\Android.mk')" `
        "NDK_OUT=$objectRoot" `
        "NDK_LIBS_OUT=$libraryRoot" `
        "APP_ABI=$Abi" `
        'APP_PLATFORM=android-26' `
        'NDK_DEBUG=0' `
        'APP_CFLAGS=-fno-lto' `
        'APP_CPPFLAGS=-fno-lto' `
        'APP_LDFLAGS=-fno-lto' `
        '-j4'
    if ($LASTEXITCODE -ne 0) {
        throw 'A compilação Android do core falhou.'
    }

    $library = Join-Path $libraryRoot "$Abi\libretro.so"
    if (-not (Test-Path -LiteralPath $library)) {
        throw "O core compilado não foi encontrado: $library"
    }
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    Copy-Item -LiteralPath $library -Destination (Join-Path $OutputDirectory 'libretro.so') -Force
    Get-FileHash -Algorithm SHA256 (Join-Path $OutputDirectory 'libretro.so')
} finally {
    if (Test-Path -LiteralPath $worktree) {
        & git -C $coreRoot worktree remove --force $worktree
    }
}
