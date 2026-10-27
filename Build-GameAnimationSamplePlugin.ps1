#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$PluginName = "GameAnimationSample",
    [string]$OutputRoot,
    [switch]$DryRun,
    [string]$UnrealEditorCmd,
    [Alias("Clean")]
    [switch]$RefreshOutput,
    [switch]$SkipUnrealDuplication
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "Scripts\GameAnimationSampleTools.psm1") -Force

$repositoryRoot = Get-GasRepositoryRoot -StartPath $PSScriptRoot
$resolvedProjectRoot = Get-GasProjectRoot -ProjectRoot $ProjectRoot
$metadata = Get-GasProjectMetadata -ProjectRoot $resolvedProjectRoot
$packageRoot = Get-GasPluginPackageRoot -ProjectRoot $resolvedProjectRoot -PluginName $PluginName
if ($OutputRoot) {
    $packageRoot = Assert-GasSafePath $OutputRoot -Tree
    Assert-GasSeparatePaths $packageRoot $resolvedProjectRoot
}
$null = Assert-GasSafePath $packageRoot -Tree
$null = Assert-GasSafePath (Join-Path $resolvedProjectRoot 'Content') -Tree
$null = Assert-GasSafePath (Join-Path $resolvedProjectRoot 'Config') -Tree
if ($metadata.EngineAssociation -notmatch '^5\.8(?:\.\d+)?$') { throw 'Build requires a UE 5.8 sample.' }
if ((Test-Path -LiteralPath $packageRoot) -and -not $RefreshOutput) { throw "Output exists. Use -RefreshOutput after reviewing '$packageRoot'." }
if (Test-Path -LiteralPath $packageRoot) { Assert-GasRefreshOutput $packageRoot }
if ($DryRun) { Write-GasMessage "DryRun: RawCopy '$resolvedProjectRoot' -> '$packageRoot'; existing managed output requires -RefreshOutput. No files written."; return }
$finalPackageRoot = $packageRoot
$packageRoot = "$finalPackageRoot.staging-$([guid]::NewGuid().ToString('N'))"
$previousOutput = $null
try {
$installDataRoot = Get-GasInstallDataRoot -PackageRoot $packageRoot
$contentRoot = Join-Path $packageRoot "Content"
$configRoot = Join-Path $packageRoot "Config"
$buildRoot = Join-Path $packageRoot "Build"
$version = Get-GasBuildVersion -EngineVersion $metadata.EngineAssociation

foreach ($path in @($packageRoot, $installDataRoot, $contentRoot, $configRoot, $buildRoot)) {
    New-GasDirectory -Path $path
}

$descriptor = New-GasPluginDescriptor -PluginName $PluginName -VersionName $version.VersionName -Version $version.Version -EngineVersion $metadata.EngineAssociation -PluginDependencies $metadata.PluginDependencies
Write-GasJson -Value $descriptor -Path (Join-Path $packageRoot "$PluginName.uplugin")

[System.IO.File]::WriteAllText((Join-Path $configRoot "FilterPlugin.ini"), @"
[FilterPlugin]
/Binaries/...
/Intermediate/...
/Saved/...
/DerivedDataCache/...
/Collections/...
/Developers/...
"@, [System.Text.UTF8Encoding]::new($false))

# Keep the source Config snapshot in the generated package for archival/plugin
# purposes. It is intentionally not used as the host-project integration contract.
Copy-GasDirectoryContent -Source (Join-Path $resolvedProjectRoot "Config") -Destination (Join-Path $buildRoot 'SourceConfig') -ExcludeFiles @("DefaultEditor.ini")

foreach ($rootName in $metadata.ContentRoots) {
    $sourceDir = Join-Path $resolvedProjectRoot "Content\$rootName"
    $destinationDir = Join-Path $contentRoot $rootName
    Copy-Item -LiteralPath $sourceDir -Destination $destinationDir -Recurse -Force
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $resolvedProjectRoot 'Content') -File) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $contentRoot $file.Name)
}

$tokenMap = @{ PLUGIN_MOUNT_POINT = "/GameAnimationSample" }
$blockDefinitions = @(Get-GasHostIntegrationBlockDefinitions)
foreach ($entry in ($blockDefinitions | Where-Object { -not $_.Generated })) {
    $content = Get-GasRenderedTemplate -TemplatePath (Join-Path $repositoryRoot "Templates\$($entry.Template)") -Tokens $tokenMap
    if ($entry.Id -eq "DefaultEngine.Runtime") {
        $sourceDefaultEnginePath = Join-Path $resolvedProjectRoot "Config\DefaultEngine.ini"
        $sourceDefaultEngineText = Get-Content -LiteralPath $sourceDefaultEnginePath -Raw
        $content = Merge-GasSourceDataDrivenConsoleVariables -TemplateText $content -SourceDefaultEngineText $sourceDefaultEngineText
    }
    $content = Get-GasSourceIntegrationConfig -ProjectRoot $resolvedProjectRoot -Definition $entry -Fallback $content
    $content = Get-GasHostIntegrationConfig -BlockId $entry.Id -Content $content
    [System.IO.File]::WriteAllText((Join-Path $installDataRoot $entry.Template), $content, [System.Text.UTF8Encoding]::new($false))
}

$redirectContent = New-GasPackageRedirectContent -ProjectRoot $resolvedProjectRoot -PluginMountPoint "/GameAnimationSample"
$redirectContent = Get-GasHostIntegrationConfig -BlockId "DefaultEngine.PackageRedirects" -Content $redirectContent
[System.IO.File]::WriteAllText((Join-Path $installDataRoot "DefaultEngine.PackageRedirects.ini"), $redirectContent, [System.Text.UTF8Encoding]::new($false))

$buildMode = "RawCopy"
if ($UnrealEditorCmd -or -not $SkipUnrealDuplication) {
    Write-GasMessage -Level Warn -Message "Unreal duplication is disabled in the public toolkit. The package is generated in non-destructive RawCopy mode."
}

[System.IO.File]::WriteAllText((Join-Path $packageRoot "README.md"), @"
# Game Animation Sample Plugin Package

Prepared by **Axchemy Studios - Marcio Vale CEO**.

- Website: https://www.axchemy.com/
- GitHub: https://github.com/marciocamello

This package turns the Epic `GameAnimationSample` project into an installable Unreal Engine plugin workflow for community use.

See `TECHNICAL_README.md` for the full step-by-step setup and integration guide.

## Requirements

- Unreal Engine 5.8
- Access to the original Epic Game Animation Sample content
- A host project where project plugins and config merges are allowed

## Build

`pwsh -File .\Build-GameAnimationSamplePlugin.ps1 -ProjectRoot "<path-to-your-local-GameAnimationSample>"` (from the **cloned toolkit repository root**, not from inside this generated plugin)

## Install

`pwsh -File .\Tools\Install-GameAnimationSampleToProject.ps1 -HostProject "<path-to-host.uproject>" -PackageRoot "<path-to-your-local-GameAnimationSample>\Development\Plugins\GameAnimationSample"`

## Update

`pwsh -File .\Tools\Update-GameAnimationSampleInProject.ps1 -HostProject "<path-to-host.uproject>" -PackageRoot "<path-to-your-local-GameAnimationSample>\Development\Plugins\GameAnimationSample"`

## Notes

- Host INI settings and existing map paths are preserved. Existing AssetManager Map/PrimaryAssetLabel directory arrays are extended once, without adding a second entry of the same type.
- Install/update snapshot the host .uproject and managed INI files and restore them if a step fails.
- The default mode does not replace your host project's default map.
- Asset package redirects are generated as a compatibility layer for legacy `/Game/...` references.
"@, [System.Text.UTF8Encoding]::new($false))

# Keep the technical guide identical to the English source-of-truth document.
# Commands in that guide run from the toolkit repository root, not the generated package.
Copy-Item -LiteralPath (Join-Path $repositoryRoot "TECHNICAL_README.md") -Destination (Join-Path $packageRoot "TECHNICAL_README.md") -Force

# Ship the same notices as the public toolkit repository (no duplicate legal text).
foreach ($name in @("LICENSE", "NOTICE", "THIRD_PARTY.md")) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot $name) -Destination (Join-Path $packageRoot $name) -Force
}

# Rendered InstallData is authoritative; shipping tools must not overwrite it.
$installDataHashes = @{}
foreach ($file in (Get-ChildItem -LiteralPath $installDataRoot -File)) {
    $installDataHashes[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
}

Sync-GasRuntimeFilesToPackage -RepositoryRoot $repositoryRoot -PackageRoot $packageRoot

foreach ($fileName in $installDataHashes.Keys) {
    $filePath = Join-Path $installDataRoot $fileName
    if (-not (Test-Path -LiteralPath $filePath) -or
        (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash -ne $installDataHashes[$fileName]) {
        throw "Build failed: runtime tools sync changed generated InstallData file '$fileName'."
    }
}
$manifest = New-GasInstallManifest -PackageRoot $packageRoot -BuildMode $buildMode -Metadata $metadata -BuildVersion $version
$manifest.PackageRoot = $finalPackageRoot
$manifest.Files = @(Get-GasTreeInventory $packageRoot)
Write-GasJson -Value $manifest -Path (Get-GasPackageManifestPath -PackageRoot $packageRoot)
$null = Assert-GasPackage $packageRoot
if (Test-Path -LiteralPath $finalPackageRoot) {
    $previousOutput = "$finalPackageRoot.previous-$([guid]::NewGuid().ToString('N'))"
    [IO.Directory]::Move($finalPackageRoot, $previousOutput)
}
try { [IO.Directory]::Move($packageRoot, $finalPackageRoot) }
catch {
    if ($previousOutput) { [IO.Directory]::Move($previousOutput, $finalPackageRoot) }
    throw
}
if ($previousOutput) { Write-GasMessage "Previous output retained at '$previousOutput'." }

Write-GasMessage -Level Success -Message "Plugin package generated at '$finalPackageRoot' using build mode '$buildMode'."
} finally {
    if (Test-Path -LiteralPath $packageRoot) {
        $null = Assert-GasSafePath $packageRoot -Tree
        Remove-Item -LiteralPath $packageRoot -Recurse -Force
    }
}
