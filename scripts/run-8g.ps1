# run-8g.ps1 -- Sage-A1.5 on Strata, 8 GB VRAM tier.
#
# Forces a <CARD_MIB> card down to an 8192 MiB tier and runs Sage-A1.5 with the expert cache
# in VRAM and the rest of the experts computed by the CPU pool.
#
# EDIT THE PATHS BELOW FIRST.  Judge by the ENGINE LOG, never by this script's exit code.
#
# THE ONE SWITCH THAT MATTERS: $env:STRATA_PIN_ARENA_GIB.  Without it the expert bank is not
# pinned and prefill falls from ~1918 tok/s to ~939 (measured, same argv otherwise).
#
# NOT TO USE: --kv-resident (silently loses context), --pcie-frac (noise floor, 1.0 is worse),
# --expert-cache-per-layer (decoded 21% slower in-tree), --prompt-batch below 1024 (output changes).
#
# usage: .\run-8g.ps1 <fresh-log-tag>

param([Parameter(Mandatory=$true)][string]$Tag)

$ErrorActionPreference = 'Stop'

# ---- edit these ---------------------------------------------------------------------------
$Cuda      = 'C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.3'   # needs cublas64_13.dll
$Engine    = 'C:\strata\PolyStrata\build-p3\strata-poly.exe'
$Model     = 'C:\models\Sage-A1.5\Sage-A1.5-Q4_K_M.gguf'
$Tokens    = 'C:\models\Sage-A1.5\prompt_ids_2k.txt'
$Profile   = Join-Path $PSScriptRoot '..\profile\sage-profile-2k.bin'
$LogDir    = Join-Path $PSScriptRoot '..\logs'
$CardMib   = 32760          # your card's total VRAM in MiB
$TierMib   = 8192           # the tier you want; 8192 = the 8 GB tier
$MaxContext = 12288
$MaxNew    = 128
# ---- end edit ------------------------------------------------------------------------------

$Reserve = $CardMib - $TierMib
$env:PATH = "$Cuda\bin;$Cuda\bin\x64;$env:PATH"

foreach ($p in @($Engine, $Model, $Tokens)) {
    if (-not (Test-Path $p)) { Write-Error "MISSING: $p"; exit 2 }
}
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force $LogDir | Out-Null }
$Log = Join-Path $LogDir "sage-8g-$Tag.log"
if (Test-Path $Log) { Write-Error "LOG EXISTS ALREADY - that is the trap: $Log"; exit 9 }

# the pinned expert arena, in GiB; roughly the size of the expert bank
$env:STRATA_PIN_ARENA_GIB = '20'

$args = @(
    '--model', $Model,
    '--vram-reserve-mib', $Reserve,
    '--max-context', $MaxContext,
    '--window', '1', '--lookup', '0',
    '--expert-profile', $Profile,
    '--tokens-file', $Tokens,
    '--max-new', $MaxNew
)

Write-Host "log     = $Log"
Write-Host "reserve = $Reserve MiB  (card $CardMib - tier $TierMib)"
Write-Host "arena   = STRATA_PIN_ARENA_GIB=$env:STRATA_PIN_ARENA_GIB GiB"
Write-Host ''

& $Engine @args *> $Log
$rc = $LASTEXITCODE
Write-Host "ENGINE_EXIT=$rc"
Write-Host ''
Write-Host '--- what to read in the log ---------------------------------------------'
Write-Host '  "loaded in ... ; N of 10240 routed experts in VRAM (X GiB)"  the tier the engine chose'
Write-Host '  "prompt N tokens P tok/s, generated M tokens D tok/s"         the two speed numbers'
Write-Host '  "copy ledger: ... prefill staging K / G GB"                   K > 0 means the pin arena worked'
Write-Host '------------------------------------------------------------------------'
exit $rc
