#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$HostProject,
    [Parameter(Mandatory)][string]$PackageRoot,
    [string]$FromManifest,
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Scripts\GameAnimationSampleTools.psm1') -Force
if ($FromManifest) {
    $root = Get-GasToolkitRootFromPackage $PackageRoot
    if ([IO.Path]::GetFullPath($FromManifest) -ne [IO.Path]::GetFullPath((Get-GasPackageManifestPath $root))) {
        throw 'FromManifest must reference the manifest inside PackageRoot; external overrides are unsafe.'
    }
}
Invoke-GasHostOperation -HostProject $HostProject -PackageRoot $PackageRoot -Operation Update -DryRun:$DryRun