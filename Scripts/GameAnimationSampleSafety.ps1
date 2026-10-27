Set-StrictMode -Version Latest

function Get-GasComparableIniValue {
    param([string]$Value)
    return [regex]::Replace($Value, '"(?:\\.|[^"\\])*"|\s+', [Text.RegularExpressions.MatchEvaluator]{
        param($match)
        if ($match.Value.StartsWith('"')) { return $match.Value }
        return ''
    })
}

function Write-GasAtomicText {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    $temporary = Join-Path (Split-Path -Parent $Path) ('.gas-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Assert-GasSafePath {
    param([Parameter(Mandatory)][string]$Path, [switch]$Tree)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[*?]' -or $Path -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe path: '$Path'."
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $root = [IO.Path]::GetPathRoot($full).TrimEnd([char[]]'\/')
    if ($full -eq $root -or $full.StartsWith('\\') -or $full.Substring($root.Length) -match ':') {
        throw "Drive roots, UNC/device paths and alternate streams are unsupported: '$Path'."
    }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.LinkType -eq 'HardLink') { throw "Link/reparse point rejected: '$cursor'." }
        }
        $cursor = Split-Path -Parent $cursor
    }
    if ($Tree -and (Test-Path -LiteralPath $full -PathType Container)) {
        # Enumerate one level at a time; never traverse a link before rejecting it.
        $pending = [Collections.Generic.Stack[string]]::new()
        $pending.Push($full)
        while ($pending.Count) {
            foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.LinkType -eq 'HardLink') { throw "Link/reparse point rejected: '$($item.FullName)'." }
                if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            }
        }
    }
    return $full
}

function Assert-GasSeparatePaths {
    param([string]$First, [string]$Second)
    $a = (Assert-GasSafePath $First) + [IO.Path]::DirectorySeparatorChar
    $b = (Assert-GasSafePath $Second) + [IO.Path]::DirectorySeparatorChar
    if ($a.StartsWith($b, [StringComparison]::OrdinalIgnoreCase) -or $b.StartsWith($a, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Overlapping paths rejected: '$First' and '$Second'."
    }
}

function Assert-GasRefreshOutput {
    param([Parameter(Mandatory)][string]$PackageRoot)
    $null = Assert-GasSafePath $PackageRoot -Tree
    # Refresh replaces a generated build, not an installation. Older generated
    # packages need not contain the current tools, inventory or descriptor patch.
    if (Test-Path -LiteralPath (Join-Path $PackageRoot 'GameAnimationSample.host-install.json')) {
        throw 'RefreshOutput cannot replace an installed host plugin.'
    }
    $manifest = Read-GasJson (Get-GasPackageManifestPath $PackageRoot)
    $descriptor = Read-GasJson (Join-Path $PackageRoot 'GameAnimationSample.uplugin')
    if ($manifest.PluginName -cne 'GameAnimationSample' -or $manifest.PluginMountPoint -cne '/GameAnimationSample' -or
        $manifest.BuildMode -cne 'RawCopy' -or $manifest.SourceProject -cne 'GameAnimationSample.uproject' -or
        $manifest.Attribution.Studio -cne 'Axchemy Studios - Marcio Vale CEO' -or
        [string]::IsNullOrWhiteSpace($manifest.BuildVersion) -or $manifest.BuildVersionNumber -lt 1 -or
        $descriptor.FileVersion -ne 3 -or $descriptor.CanContainContent -ne $true -or
        $descriptor.EngineVersion -notmatch '^5\.8(?:\.\d+)?$' -or
        $descriptor.CreatedBy -cne 'Axchemy Studios - Marcio Vale CEO') {
        throw 'RefreshOutput requires an identifiable Axchemy-generated UE 5.8 RawCopy package.'
    }
}

function Assert-GasPackage {
    param([Parameter(Mandatory)][string]$PackageRoot)
    $null = Assert-GasSafePath $PackageRoot -Tree
    Assert-GasHostPluginLayout -HostPluginRoot $PackageRoot
    $manifest = Read-GasJson (Get-GasPackageManifestPath $PackageRoot)
    if ($manifest.PluginName -cne 'GameAnimationSample' -or $manifest.PluginMountPoint -cne '/GameAnimationSample' -or
        [string]::IsNullOrWhiteSpace($manifest.BuildVersion) -or $manifest.BuildVersionNumber -lt 1) {
        throw 'Invalid toolkit manifest identity/version.'
    }
    $descriptor = Read-GasJson (Join-Path $PackageRoot 'GameAnimationSample.uplugin')
    if ($descriptor.FileVersion -ne 3 -or $descriptor.EngineVersion -cne '5.8.0' -or $descriptor.CanContainContent -ne $true) {
        throw 'Invalid .uplugin: expected content plugin with EngineVersion 5.8.0.'
    }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($dependency in @($manifest.RequiredEnginePlugins)) {
        if ($dependency.Name -notmatch '^[A-Za-z][A-Za-z0-9_]*$' -or -not $names.Add($dependency.Name) -or $dependency.Name -ieq 'GameAnimationSample') {
            throw 'Invalid or duplicate dependency in manifest.'
        }
    }
    if ($descriptor.PSObject.Properties.Name -contains 'Plugins') {
        $descriptorNames = @($descriptor.Plugins | ForEach-Object { [string]$_.Name } | Sort-Object)
        $manifestNames = @($manifest.RequiredEnginePlugins | ForEach-Object { [string]$_.Name } | Sort-Object)
        if (($descriptorNames -join '|') -ine ($manifestNames -join '|')) { throw 'Descriptor and manifest dependencies disagree.' }
    }
    foreach ($definition in Get-GasHostIntegrationBlockDefinitions) {
        $path = Join-Path $PackageRoot "InstallData\$($definition.Template)"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required InstallData: '$path'." }
        if (((Get-Content -LiteralPath $path -Raw) -replace '\{\{PLUGIN_MOUNT_POINT\}\}', '/GameAnimationSample') -match '\{\{') { throw "Unrendered InstallData: '$path'." }
    }
    foreach ($relative in @('Tools\Install-GameAnimationSampleToProject.ps1', 'Tools\Update-GameAnimationSampleInProject.ps1',
            'Tools\Scripts\GameAnimationSampleTools.psm1', 'Tools\Scripts\GameAnimationSampleSafety.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot $relative) -PathType Leaf)) { throw "Missing runtime tool '$relative'. Rebuild package." }
    }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'Tools') -Recurse -File | Where-Object Extension -in '.ps1', '.psm1') {
        $parseErrors = $null; $tokens = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "ParserError in distributed script '$($file.FullName)'." }
    }
    if ($manifest.PSObject.Properties.Name -contains 'Files') {
        foreach ($required in @('Content', 'LICENSE', 'NOTICE', 'THIRD_PARTY.md', 'README.md', 'TECHNICAL_README.md')) {
            if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot $required))) { throw "Incomplete package: missing '$required'." }
        }
        if (@(Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'Content') -Recurse -File | Where-Object Extension -in '.uasset', '.umap').Count -eq 0) { throw 'Package has no Unreal content payload.' }
        $inventoryNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $manifest.Files) {
            if ($entry.Path -notmatch '^[A-Za-z0-9_][^:]*$' -or [IO.Path]::IsPathRooted($entry.Path)) { throw 'Unsafe inventory path.' }
            $path = Assert-GasSafePath (Join-Path $PackageRoot $entry.Path)
            if (-not $inventoryNames.Add([IO.Path]::GetRelativePath($PackageRoot, $path))) { throw 'Duplicate package inventory path.' }
            if (-not $path.StartsWith($PackageRoot.TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Inventory path traversal.' }
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.SHA256) { throw "Package hash mismatch: '$($entry.Path)'." }
        }
        foreach ($file in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Force) {
            $relative = [IO.Path]::GetRelativePath($PackageRoot, $file.FullName)
            if ($relative -notin @('GameAnimationSample.install.json', 'GameAnimationSample.host-install.json') -and -not $inventoryNames.Contains($relative)) { throw "Unlisted package file: '$relative'." }
        }
    }
    return $manifest
}

function Get-GasTreeInventory {
    param([Parameter(Mandatory)][string]$Root)
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{ Path = [IO.Path]::GetRelativePath($Root, $_.FullName); SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
}

function Assert-GasInventory {
    param([string]$Root, [object[]]$Inventory)
    foreach ($entry in $Inventory) {
        if ((Get-FileHash -LiteralPath (Join-Path $Root $entry.Path) -Algorithm SHA256).Hash -ne $entry.SHA256) { throw "Copy verification failed: '$($entry.Path)'." }
    }
}

function Get-GasSourceIntegrationConfig {
    param([string]$ProjectRoot, [Parameter(Mandatory)]$Definition, [string]$Fallback)
    $sourcePath = Join-Path $ProjectRoot "Config\$($Definition.IniFile)"
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Missing source config '$sourcePath'." }
    $source = Get-GasNormalizedText (Get-Content -LiteralPath $sourcePath -Raw)
    if ($Definition.Id -eq 'DefaultGame.AssetManager') {
        # Host scan paths are a deliberate plugin-mount contract, not sample project paths.
        $scalars = Get-GasHostIntegrationConfig -BlockId $Definition.Id -Content $source
        $scalars = ($scalars -split "`n" | Where-Object { $_ -notmatch '^\+PrimaryAssetTypesToScan=' }) -join "`n"
        $arrays = ($Fallback -split "`n" | Where-Object { $_ -match '^\+PrimaryAssetTypesToScan=' }) -join "`n"
        return "$scalars`n$arrays"
    }
    if ($Definition.Id -eq 'DefaultEngine.Runtime') {
        # Exclude engine baseline profiles; import only the sample's named custom profiles.
        $source = ($source -split "`n" | Where-Object {
            if ($_ -match '^\+Profiles=') { return $_ -match 'Name="(?:WaterBodyCollision|ObstaclePreset|TraversalObjectPreset|CharacterCapsule)"' }
            if ($_ -match '^\+EditProfiles=') { return $_ -match 'Name="Ragdoll"' }
            if ($_ -match '^\+ProfileRedirects=') { return $_ -match 'OldName="Obstacle"' }
            if ($_ -match '^\+DefaultChannelResponses=') { return $_ -match 'Name="(?:Traversable|Mouse|Obstacle)"' }
            return $true
        }) -join "`n"
    }
    # This allowlist excludes renderer/platform/project identity/maps/editor defaults.
    $selected = Get-GasHostIntegrationConfig -BlockId $Definition.Id -Content $source
    if ($Definition.Id -eq 'DefaultEngine.Runtime') {
        $selected = Merge-GasSourceDataDrivenConsoleVariables -TemplateText $selected -SourceDefaultEngineText $source
    }
    return $selected.Replace('/Game/', '/GameAnimationSample/')
}

function Get-GasStagingPathIdentity {
    param([string]$Value)
    return $Value.Trim().Trim('"').Replace('\', '/').ToLowerInvariant()
}

function Get-GasHostStagingConfig {
    param([Parameter(Mandatory)][string]$UProjectPath, [AllowEmptyString()][string]$DefaultGameText)
    # AutomationTool ProjectUtils.GetShortProjectName strips every extension.
    $projectName = ([IO.Path]::GetFileName($UProjectPath) -split '\.', 2)[0]
    if ($projectName -notmatch '^[A-Za-z0-9_][A-Za-z0-9_ -]*$') { throw 'Unsupported host name for config staging.' }
    $requiredPath = "$projectName/Config/DefaultNetworkPrediction.ini"
    $requiredIdentity = Get-GasStagingPathIdentity $requiredPath
    $text = Get-GasNormalizedText $DefaultGameText
    Assert-GasManagedIniMarkers -Text $text -Path 'DefaultGame.ini'
    # Decisions outside our own block belong to the host and take precedence.
    $text = [regex]::Replace($text, '(?ms)^[ \t]*; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultGame\.Staging[ \t]*\n.*?^[ \t]*; END AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultGame\.Staging[ \t]*(?:\n|$)', '')
    $disallowed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $section = ''
    foreach ($line in $text -split "`n") {
        $info = Get-GasIniLineInfo $line
        if ($info.Kind -eq 'Section') { $section = $info.Section; continue }
        if ($section -ine 'Staging' -or $info.Kind -ne 'Assignment') { continue }
        $identity = Get-GasStagingPathIdentity $info.Value
        if ($info.Key -ieq 'AllowedConfigFiles' -and ($info.Operator -eq '!' -or ($info.Operator -eq '-' -and $identity -eq $requiredIdentity))) {
            throw "Host staging conflict: AllowedConfigFiles explicitly clears/removes '$requiredPath'."
        }
        if ($info.Key -ine 'DisallowedConfigFiles') { continue }
        switch ($info.Operator) {
            '!' { $disallowed.Clear() }
            '-' { [void]$disallowed.Remove($identity) }
            '' { $disallowed.Clear(); [void]$disallowed.Add($identity) }
            default { [void]$disallowed.Add($identity) }
        }
    }
    if ($disallowed.Contains($requiredIdentity)) { throw "Host staging conflict: DisallowedConfigFiles denies required '$requiredPath'." }
    return "[Staging]`n+AllowedConfigFiles=$requiredPath"
}

function Invoke-GasHostOperation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$HostProject, [Parameter(Mandatory)][string]$PackageRoot,
        [ValidateSet('Install','Update')][string]$Operation, [switch]$DryRun,
        [Parameter(DontShow)][scriptblock]$FaultInjector)

    $null = Assert-GasSafePath $HostProject
    $context = Get-GasHostProjectContext $HostProject
    $hostRoot = Assert-GasSafePath $context.HostProjectRoot
    $mutexKey = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($hostRoot.ToLowerInvariant())))
    $mutex = [Threading.Mutex]::new($false, "Local\GasToolkit-$mutexKey")
    $acquired = $false
    try {
    try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { throw 'Another toolkit operation is running for this host.' }
    $source = Assert-GasSafePath (Get-GasToolkitRootFromPackage $PackageRoot) -Tree
    Assert-GasSeparatePaths $source $hostRoot
    $manifest = Assert-GasPackage $source
    $target = Join-Path $hostRoot 'Plugins\GameAnimationSample'
    $configExisted = Test-Path -LiteralPath (Join-Path $hostRoot 'Config')
    $pluginsExisted = Test-Path -LiteralPath (Join-Path $hostRoot 'Plugins')
    $preserveFiles = @()
    foreach ($path in @($context.UProjectPath, (Join-Path $hostRoot 'Config'), (Join-Path $hostRoot 'Saved\GameAnimationSampleToolkit'), (Join-Path $hostRoot 'Plugins'))) {
        $null = Assert-GasSafePath $path -Tree
    }
    $transactions = Join-Path $hostRoot 'Saved\GameAnimationSampleToolkit\Transactions'
    if (Test-Path -LiteralPath $transactions) {
        foreach ($directory in Get-ChildItem -LiteralPath $transactions -Directory) {
            $journal = Join-Path $directory.FullName 'Transaction.json'
            if (Test-Path -LiteralPath $journal) {
                $state = Read-GasJson $journal
                if ($state.Phase -notin @('Committed','RolledBack')) { throw "Unfinished transaction. Review recovery snapshot '$($directory.FullName)' before retrying." }
            }
        }
    }
    $hostDescriptor = Read-GasJson $context.UProjectPath
    if ($hostDescriptor.EngineAssociation -notmatch '^5\.8(?:\.\d+)?$') { throw 'Only explicit UE 5.8 host EngineAssociation is supported; custom engine GUIDs require separate validation.' }
    if ($Operation -eq 'Install' -and (Test-Path -LiteralPath $target)) { throw 'Plugin already exists. Install will never replace it; use Update for a managed installation.' }
    if ($Operation -eq 'Update') {
        $installed = Read-GasJson (Join-Path $target 'GameAnimationSample.host-install.json')
        if ($installed.PluginName -cne 'GameAnimationSample') { throw 'Installed plugin is not toolkit-managed.' }
        $oldManifest = Read-GasJson (Join-Path $target 'GameAnimationSample.install.json')
        if ($oldManifest.PluginName -cne 'GameAnimationSample' -or $oldManifest.PluginMountPoint -cne '/GameAnimationSample') { throw 'Incompatible installed package identity.' }
        $owned = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($oldManifest.PSObject.Properties.Name -contains 'Files') {
            foreach ($file in $oldManifest.Files) {
                $oldPath = Assert-GasSafePath (Join-Path $target $file.Path)
                if (-not $oldPath.StartsWith($target + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe installed inventory path.' }
                [void]$owned.Add([IO.Path]::GetRelativePath($target, $oldPath))
                if (-not (Test-Path -LiteralPath $oldPath) -or (Get-FileHash -LiteralPath $oldPath -Algorithm SHA256).Hash -ne $file.SHA256) { throw "Installed managed file was modified or removed: '$oldPath'. Preserve your work before updating." }
            }
        }
        $preserveFiles = @(Get-ChildItem -LiteralPath $target -Recurse -File -Force | Where-Object {
            $relative = [IO.Path]::GetRelativePath($target, $_.FullName)
            if ($relative -in @('GameAnimationSample.install.json', 'GameAnimationSample.host-install.json') -or $owned.Contains($relative)) { return $false }
            if (Test-Path -LiteralPath (Join-Path $source $relative)) {
                if ($oldManifest.PSObject.Properties.Name -contains 'Files') { throw "Unmanaged installed file conflicts with incoming package: '$relative'." }
                return $false # Legacy packages lack per-file ownership; keep the complete old plugin backup.
            }
            return $true
        })
    }
    # Reject disabled dependencies rather than silently changing a host decision.
    if ($hostDescriptor.PSObject.Properties.Name -contains 'Plugins') {
        foreach ($entry in $hostDescriptor.Plugins) {
            if ($entry.Name -in @($manifest.RequiredEnginePlugins | ForEach-Object Name) -and
                $entry.PSObject.Properties.Name -contains 'Enabled' -and $entry.Enabled -eq $false) { throw "Host explicitly disables required dependency '$($entry.Name)'." }
        }
    }
    $planned = [ordered]@{}
    $planned[$context.UProjectPath] = Update-UProjectPluginEntries -UProjectPath $context.UProjectPath -PluginName 'GameAnimationSample' -RequiredPlugins $manifest.RequiredEnginePlugins -PassThru
    foreach ($definition in Get-GasHostIntegrationBlockDefinitions) {
        $path = Join-Path $hostRoot "Config\$($definition.IniFile)"
        $content = Get-GasRenderedTemplate -TemplatePath (Join-Path $source "InstallData\$($definition.Template)") -Tokens @{ PLUGIN_MOUNT_POINT = '/GameAnimationSample' }
        if ($definition.Id -eq 'DefaultEngine.PackageRedirects') {
            foreach ($match in [regex]::Matches($content, '(?i)OldName\s*=\s*"/Game/([^"\r\n]+)"')) {
                $asset = Assert-GasSafePath (Join-Path $hostRoot ('Content\' + $match.Groups[1].Value))
                if (-not $asset.StartsWith((Join-Path $hostRoot 'Content') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe redirect source path.' }
                if ((Test-Path -LiteralPath "$asset.uasset") -or (Test-Path -LiteralPath "$asset.umap")) { throw "Package redirect would shadow existing host asset '$asset'." }
            }
        }
        $args = @{ Path = $path; BlockId = $definition.Id; Content = $content; PassThru = $true }
        if ($planned.Contains($path)) { $args.CurrentText = $planned[$path] }
        $planned[$path] = Update-ManagedIniBlock @args
    }
    # Host-only generation: no host project name is baked into InstallData.
    $gameIniPath = Join-Path $hostRoot 'Config\DefaultGame.ini'
    $stagingContent = Get-GasHostStagingConfig -UProjectPath $context.UProjectPath -DefaultGameText $planned[$gameIniPath]
    $planned[$gameIniPath] = Update-ManagedIniBlock -Path $gameIniPath -BlockId 'DefaultGame.Staging' -Content $stagingContent -CurrentText $planned[$gameIniPath] -PassThru
    $backups = Join-Path $hostRoot 'Saved\GameAnimationSampleToolkit\Backups'
    $backup = New-GasUniqueBackupRoot -BackupsRoot $backups -PluginName 'GameAnimationSample'
    $sourceFiles = @(Get-ChildItem -LiteralPath $source -Recurse -File -Force)
    $requiredBytes = [long](($sourceFiles | Measure-Object Length -Sum).Sum) + 1MB
    foreach ($file in $preserveFiles) { $requiredBytes += $file.Length }
    foreach ($path in $planned.Keys) {
        $requiredBytes += [Text.Encoding]::UTF8.GetByteCount($planned[$path])
        if (Test-Path -LiteralPath $path) { $requiredBytes += (Get-Item -LiteralPath $path).Length }
    }
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($hostRoot))
    if ($drive.AvailableFreeSpace -lt $requiredBytes) { throw "Insufficient free space for staging ($requiredBytes bytes required)." }
    foreach ($path in $planned.Keys) {
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReadOnly)) { throw "Read-only host file: '$path'." }
    }
    Write-GasMessage "Preflight passed: $Operation '$target'. Host snapshots: '$transactions'. Plugin backup (Update only): '$backup'."
    foreach ($path in $planned.Keys) { Write-GasMessage "Reconcile: '$path'" }
    if ($DryRun) {
        return [pscustomobject]@{
            Operation = $Operation; PluginDestination = $target
            Backup = $(if ($Operation -eq 'Update') { $backup } else { $null })
            HostSnapshotRoot = $transactions
            Files = $planned; Dependencies = $manifest.RequiredEnginePlugins
            PackageFiles = @($sourceFiles | ForEach-Object { [IO.Path]::GetRelativePath($source, $_.FullName) })
            ReplacedFiles = @(if ($Operation -eq 'Update') { Get-ChildItem -LiteralPath $target -Recurse -File -Force | ForEach-Object { [IO.Path]::GetRelativePath($target, $_.FullName) } })
            PreservedFiles = @($preserveFiles | ForEach-Object { [IO.Path]::GetRelativePath($target, $_.FullName) })
            EstimatedAdditionalBytes = $requiredBytes; DryRun = $true
        }
    }
    # Check for an open project descriptor before snapshot/staging.
    $guard = [IO.File]::Open($context.UProjectPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    $guard.Dispose()
    $snapshot = New-GasHostMutationSnapshot -HostProjectRoot $hostRoot -UProjectPath $context.UProjectPath
    $staged = Join-Path $snapshot 'Package'
    $oldMoved = $false; $newMoved = $false; $hostChanged = $false
    try {
        Write-GasJson -Value @{ Operation = $Operation; HostProject = $context.UProjectPath; Backup = $backup; Target = $target; Phase = 'Preparing' } -Path (Join-Path $snapshot 'Transaction.json')
        $inventory = Get-GasTreeInventory $source
        if ($FaultInjector) {
            foreach ($file in $sourceFiles) {
                $destination = Join-Path $staged ([IO.Path]::GetRelativePath($source, $file.FullName))
                New-GasDirectory (Split-Path -Parent $destination)
                Copy-Item -LiteralPath $file.FullName -Destination $destination
                & $FaultInjector 'DuringPackageCopy'
            }
        } else { Copy-Item -LiteralPath $source -Destination $staged -Recurse -Force }
        Assert-GasInventory -Root $staged -Inventory $inventory
        $null = Assert-GasPackage $staged
        foreach ($file in $preserveFiles) {
            $destination = Join-Path $staged ([IO.Path]::GetRelativePath($target, $file.FullName))
            New-GasDirectory (Split-Path -Parent $destination)
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
            if ((Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) { throw 'Unmanaged file copy verification failed.' }
        }
        if ($FaultInjector) { & $FaultInjector 'AfterStaging' }
        New-GasDirectory (Split-Path -Parent $target)
        New-GasDirectory $backups
        Write-GasJson -Value @{ Operation = $Operation; HostProject = $context.UProjectPath; Backup = $backup; Target = $target; Phase = 'Prepared' } -Path (Join-Path $snapshot 'Transaction.json')
        if ($Operation -eq 'Update') {
            [IO.Directory]::Move($target, $backup)
            $oldMoved = $true
        }
        [IO.Directory]::Move($staged, $target)
        $newMoved = $true
        if ($FaultInjector) { & $FaultInjector 'AfterPluginSwap' }
        $hostChanged = $true
        foreach ($path in $planned.Keys) {
            New-GasDirectory (Split-Path -Parent $path)
            $text = $planned[$path] -replace "`n", [Environment]::NewLine
            if (-not (Test-Path -LiteralPath $path) -or [IO.File]::ReadAllText($path) -cne $text) {
                Write-GasAtomicText -Path $path -Text $text
            }
            if ($FaultInjector) { & $FaultInjector 'DuringHostWrite' }
            if ($FaultInjector -and $path.EndsWith('.ini')) { & $FaultInjector 'DuringIniWrite' }
            if ([IO.File]::ReadAllText($path) -cne $text) { throw "Post-write verification failed: '$path'." }
        }
        Write-GasJson -Value @{ PluginName = 'GameAnimationSample'; BuildVersion = $manifest.BuildVersion; BuildVersionNumber = $manifest.BuildVersionNumber; PackageSource = $source; ManagedIniBlocks = @(@($manifest.ManagedIniBlocks) + 'DefaultGame.Staging' | Select-Object -Unique); RequiredEnginePlugins = $manifest.RequiredEnginePlugins } -Path (Join-Path $target 'GameAnimationSample.host-install.json')
        Assert-GasHostPluginLayout $target
        Write-GasJson -Value @{ Operation = $Operation; HostProject = $context.UProjectPath; Backup = $backup; Target = $target; Phase = 'Committed' } -Path (Join-Path $snapshot 'Transaction.json')
    } catch {
        $failure = $_
        try {
            if ($hostChanged) { Restore-GasHostMutationSnapshot -SnapshotRoot $snapshot -HostProjectRoot $hostRoot -UProjectPath $context.UProjectPath }
            if ($newMoved) { $null = Assert-GasSafePath $target -Tree; Remove-Item -LiteralPath $target -Recurse -Force }
            if ($oldMoved) { [IO.Directory]::Move($backup, $target) }
            foreach ($directory in @(@{ Name = 'Config'; Existed = $configExisted }, @{ Name = 'Plugins'; Existed = $pluginsExisted })) {
                $path = Join-Path $hostRoot $directory.Name
                if (-not $directory.Existed -and (Test-Path -LiteralPath $path) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) { Remove-Item -LiteralPath $path }
            }
            if (Test-Path -LiteralPath $staged) {
                $null = Assert-GasSafePath $staged -Tree
                Remove-Item -LiteralPath $staged -Recurse -Force
            }
            Write-GasJson -Value @{ Operation = $Operation; HostProject = $context.UProjectPath; Backup = $backup; Target = $target; Phase = 'RolledBack' } -Path (Join-Path $snapshot 'Transaction.json')
        } catch { throw "Rollback incomplete. Preserve snapshot '$snapshot' and backup '$backup'. Original: $failure. Recovery: $_" }
        throw "Operation rolled back. Snapshot retained at '$snapshot'. Error: $failure"
    }
    Write-GasMessage -Level Success "$Operation completed. Host recovery snapshot: '$snapshot'. Previous plugin backup (Update): '$backup'."
    } finally {
        if ($acquired) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
