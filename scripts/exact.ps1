param(
    [Parameter(Mandatory=$true)][string]$Prompt,
    [int]$MaxContext = 16384,
    [int]$MaxNew = 256
)
$ErrorActionPreference = "Continue"
if (-not (Test-Path -LiteralPath $Prompt)) { Write-Error "prompt not found: $Prompt"; exit 2 }
$env:PATH = "E:\cuda-13.3\bin\x64;" + $env:PATH
$exe = "E:\视频\_flashnext\experiments\20261015-nemotron-on-strata\PolyStrata\build-p3\strata-poly.exe"
$model = "E:\models\Sage-A1.5\gguf-q4\Sage-A1.5-Q4_K_M.gguf"
& $exe --model $model --tokens-file $Prompt --max-context $MaxContext --max-new $MaxNew --window 4 --lookup 0 2>&1
$code = $LASTEXITCODE
if ($code -ne 0) { Write-Error "strata-poly exit $code"; exit $code }
