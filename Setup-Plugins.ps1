param([string]$Python = 'python.exe', [switch]$WithMcp)
$ErrorActionPreference = 'Stop'
$animeSetup = Join-Path $PSScriptRoot 'scripts/mpv-anime-xray/Setup.ps1'
if (-not (Test-Path -LiteralPath $animeSetup)) { throw 'Unpack a uosc configuration release before running this script.' }
& $animeSetup -Python $Python -WithMcp:$WithMcp
if (-not $?) { throw 'Anime plugin setup did not finish.' }
Write-Host 'Configure script-opts/bluray.conf for your installed Blu-ray backends, then restart mpv.'
