#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$HostProject,
    [ValidateSet('Minimal')][string]$Mode = 'Minimal',
    [Parameter(Mandatory)][string]$PackageRoot,
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Scripts\GameAnimationSampleTools.psm1') -Force
Invoke-GasHostOperation -HostProject $HostProject -PackageRoot $PackageRoot -Operation Install -DryRun:$DryRun