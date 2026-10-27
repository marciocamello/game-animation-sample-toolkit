#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$PluginName = "GameAnimationSample",
    [string]$OutputRoot,
    [switch]$DryRun,
    [string]$UnrealEditorCmd,
    [switch]$SkipUnrealDuplication
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Scripts\GameAnimationSampleTools.psm1") -Force

function Get-DirectoryFileSummary {
    param([Parameter(Mandatory)][string]$Path)

    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue
    $count = @($files).Count
    $measure = @($files | Measure-Object -Property Length -Sum)
    $bytes = if ($measure.Count -gt 0 -and $measure[0].PSObject.Properties.Name -contains "Sum" -and $measure[0].Sum) {
        [double]$measure[0].Sum
    } else {
        0
    }

    return [pscustomobject]@{
        FileCount = $count
        SizeMB = [math]::Round(($bytes / 1MB), 2)
    }
}

$resolvedProjectRoot = Get-GasProjectRoot -ProjectRoot $ProjectRoot
$packageRoot = Get-GasPluginPackageRoot -ProjectRoot $resolvedProjectRoot -PluginName $PluginName
if ($OutputRoot) { $packageRoot = Assert-GasSafePath $OutputRoot -Tree }
$null = Assert-GasSafePath $packageRoot -Tree

Write-GasMessage -Message "Rebuild requested for '$PluginName'."
Write-GasMessage -Level Warn -Message "This rebuild replaces the generated plugin package directory. Source sample content and other project directories will not be deleted."
Write-GasMessage -Level Warn -Message $packageRoot

if (Test-Path -LiteralPath $packageRoot) {
    $summary = Get-DirectoryFileSummary -Path $packageRoot
    Write-GasMessage -Message "Current package summary: $($summary.FileCount) files, $($summary.SizeMB) MB"
} else {
    Write-GasMessage -Message "No previous package was found. A fresh build will be created."
}

Write-GasMessage -Level Warn -Message "Starting -RefreshOutput rebuild: files inside the generated package will be replaced."

$buildScript = Join-Path $PSScriptRoot "Build-GameAnimationSamplePlugin.ps1"
$buildParams = @{
    ProjectRoot = $resolvedProjectRoot
    PluginName = $PluginName
    RefreshOutput = $true
    DryRun = $DryRun
}
if ($OutputRoot) { $buildParams.OutputRoot = $OutputRoot }

if ($UnrealEditorCmd) {
    $buildParams.UnrealEditorCmd = $UnrealEditorCmd
}

if ($SkipUnrealDuplication) {
    $buildParams.SkipUnrealDuplication = $true
}

& $buildScript @buildParams

if (-not $?) {
    throw "Rebuild failed."
}

if ($DryRun) { return }
$finalSummary = Get-DirectoryFileSummary -Path $packageRoot
Write-GasMessage -Level Success -Message "Rebuild finished: $($finalSummary.FileCount) files, $($finalSummary.SizeMB) MB"
