#requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$results = [Collections.Generic.List[object]]::new()
function Check([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action, [string]$Pattern = '.') {
    try { & $Action | Out-Null } catch {
        if ([string]$_ -notmatch $Pattern) { throw "Unexpected rejection: $_ (expected $Pattern)" }
        return
    }
    throw 'Expected rejection, but operation succeeded.'
}
function Case([string]$Name, [scriptblock]$Action) {
    try { & $Action | Out-Null; $results.Add([pscustomobject]@{ Test = $Name; Result = 'PASS'; Detail = '' }) }
    catch { $results.Add([pscustomobject]@{ Test = $Name; Result = 'FAIL'; Detail = [string]$_ }) }
}
function Tree([string]$Root, [switch]$HostFilesOnly) {
    return (@(Get-ChildItem -LiteralPath $Root -Recurse -Force | Where-Object {
        -not $HostFilesOnly -or $_.FullName -notlike "$Root\Saved*"
    } | Sort-Object FullName | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($Root, $_.FullName)
        if ($_.PSIsContainer) { "D:$relative" } else { "F:$relative=$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
    }) -join "`n")
}
function New-Host([string]$Name) {
    $root = Join-Path $temp $Name
    New-GasDirectory (Join-Path $root 'Config')
    New-GasDirectory (Join-Path $root 'Plugins')
    Write-GasJson @{ FileVersion = 3; EngineAssociation = '5.8'; Description = 'keep host metadata' } (Join-Path $root 'Host.uproject')
    return $root
}
function Update-Fixture([string]$HostRoot, [scriptblock]$Inject) {
    Invoke-GasHostOperation -HostProject $HostRoot -PackageRoot $package -Operation Update -FaultInjector $Inject
}
function New-FaultInjector([string]$Point) {
    return { param($phase) if ($phase -eq $Point) { throw "INJECTED $phase" } }.GetNewClosure()
}

# Syntax validation precedes every execution of toolkit code.
Case 'Native parser: every repository PowerShell file' {
    foreach ($file in Get-ChildItem -LiteralPath $repository -Recurse -File | Where-Object Extension -in '.ps1', '.psm1') {
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        Check ($errors.Count -eq 0) "ParserError in $($file.FullName): $errors"
    }
}
if ($results[0].Result -ne 'PASS') { throw $results[0].Detail }
Import-Module (Join-Path $repository 'Scripts\GameAnimationSampleTools.psm1') -Force -DisableNameChecking
$temp = Join-Path ([IO.Path]::GetTempPath()) ('gas-release-safety-' + [guid]::NewGuid().ToString('N'))
New-GasDirectory $temp
try {
    $sample = Join-Path $temp 'Synthetic Sample'
    New-GasDirectory (Join-Path $sample 'Config')
    New-GasDirectory (Join-Path $sample 'Content\Levels')
    [IO.File]::WriteAllText((Join-Path $sample 'Content\Levels\Fixture.umap'), 'Synthetic payload, not an Unreal asset.')
    [IO.File]::WriteAllText((Join-Path $sample 'Content\RootFixture.uasset'), 'Synthetic root payload.')
    Write-GasJson @{ FileVersion = 3; EngineAssociation = '5.8'; Plugins = @(@{ Name = 'PoseSearch'; Enabled = $true }) } (Join-Path $sample 'GameAnimationSample.uproject')
    foreach ($entry in Get-GasHostIntegrationBlockDefinitions | Where-Object { -not $_.Generated }) {
        $content = Get-GasRenderedTemplate -TemplatePath (Join-Path $repository "Templates\$($entry.Template)") -Tokens @{ PLUGIN_MOUNT_POINT = '/Game' }
        [IO.File]::WriteAllText((Join-Path $sample "Config\$($entry.IniFile)"), $content)
    }
    Add-Content -LiteralPath (Join-Path $sample 'Config\DefaultGameplayTags.ini') -Value @'
+GameplayTagList=(Tag="Foley.Event.Ragdoll",DevComment="source")
+GameplayTagList=(Tag="Foley.Event.Punch",DevComment="source")
+GameplayTagList=(Tag="Foley.Event.Kick",DevComment="source")
+GameplayTagList=(Tag="Foley.Event.SourceOnly",DevComment="source")
'@
    Add-Content -LiteralPath (Join-Path $sample 'Config\DefaultEngine.ini') -Value @'
[/Script/Engine.DataDrivenConsoleVariableSettings]
+CVarsArray=(Type=CVarInt,Name="DDCVar.CharacterPhysics.DrawDebug",DefaultValueInt=0)
+CVarsArray=(Type=CVarInt,Name="ddcvar.characterphysics.drawdebug",DefaultValueInt=0)
+CVarsArray=(Type=CVarInt,Name="DDCVar.CharacterPhysics.DefaultProfile",DefaultValueInt=1)
-CVarsArray=(Type=CVarInt,Name="DDCVar.UnsafeRemoval",DefaultValueInt=0)
!CVarsArray=ClearArray
[/Script/EngineSettings.GameMapsSettings]
GameDefaultMap=/Game/Forbidden
GlobalDefaultGameMode=/Game/ForbiddenMode
[/Unknown]
UnknownSetting=True
'@
    $sampleBefore = Tree $sample
    $package = Join-Path $temp 'Distribution with spaces\GameAnimationSample'
    Case 'RawCopy build outside source, complete package and inventory' {
        & (Join-Path $repository 'Build-GameAnimationSamplePlugin.ps1') -ProjectRoot $sample -OutputRoot $package -SkipUnrealDuplication
        $null = Assert-GasPackage $package
        Check ((Tree $sample) -ceq $sampleBefore) 'Build modified source sample.'
        Check (Test-Path -LiteralPath (Join-Path $package 'Content\RootFixture.uasset')) 'Root content was omitted.'
        foreach ($name in 'LICENSE','NOTICE','THIRD_PARTY.md','TECHNICAL_README.md') { Check (Test-Path -LiteralPath (Join-Path $package $name)) "Missing $name" }
    }
    if (-not (Test-Path -LiteralPath $package)) { throw 'Build fixture failed; remaining tests cannot execute.' }
    Case 'Source tag extraction includes Foley omissions and new tags' {
        $tags = Get-Content -LiteralPath (Join-Path $package 'InstallData\DefaultGameplayTags.Tags.ini') -Raw
        foreach ($tag in 'Ragdoll','Punch','Kick','SourceOnly') { Check ($tags.Contains("Foley.Event.$tag")) "Missing source Foley tag: $tag" }
    }
    Case 'Source DDCVars case-insensitive deduplication, no destructive operators/maps' {
        $runtime = Get-Content -LiteralPath (Join-Path $package 'InstallData\DefaultEngine.Runtime.ini') -Raw
        Check (([regex]::Matches($runtime, '(?i)Name="DDCVar.CharacterPhysics.DrawDebug"')).Count -eq 1) 'Duplicate source CVar.'
        Check ($runtime.Contains('DDCVar.CharacterPhysics.DefaultProfile')) 'Missing DefaultProfile.'
        Check ($runtime -notmatch 'UnsafeRemoval|ClearArray|Forbidden|UnknownSetting') 'Unsafe source config imported.'
    }
    Case 'Distributed tools identical to repository runtime tools' {
        foreach ($relative in 'Install-GameAnimationSampleToProject.ps1','Update-GameAnimationSampleInProject.ps1','Scripts\GameAnimationSampleTools.psm1','Scripts\GameAnimationSampleSafety.ps1') {
            Check ((Get-FileHash -LiteralPath (Join-Path $repository $relative)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $package "Tools\$relative")).Hash) "Tool differs: $relative"
        }
        Check (-not (Test-Path -LiteralPath (Join-Path $package 'Tools\Scripts\Unreal'))) 'Development experiment shipped.'
    }
    $hostRoot = New-Host 'Host with spaces'
    Case 'Install DryRun: full filesystem unchanged and proposed contents available' {
        $before = Tree $temp
        $plan = & (Join-Path $repository 'Install-GameAnimationSampleToProject.ps1') -HostProject $hostRoot -PackageRoot $package -DryRun
        Check $plan.DryRun 'No dry-run plan.'
        Check ($plan.Files.Count -eq 6) 'Incomplete config plan.'
        Check ($plan.PackageFiles.Count -gt 10 -and $null -eq $plan.Backup -and $plan.EstimatedAdditionalBytes -gt 0) 'Incomplete package/storage plan.'
        Check ((Tree $temp) -ceq $before) 'DryRun wrote files/directories.'
    }
    Case 'Clean install using distributed Tools' {
        & (Join-Path $package 'Tools\Install-GameAnimationSampleToProject.ps1') -HostProject $hostRoot -PackageRoot $package
        Assert-GasHostPluginLayout (Join-Path $hostRoot 'Plugins\GameAnimationSample')
    }
    Case 'Repeated Install preserves existing plugin byte-for-byte' {
        $before = Tree $temp
        Reject { & (Join-Path $repository 'Install-GameAnimationSampleToProject.ps1') -HostProject $hostRoot -PackageRoot $package } 'already exists'
        Check ((Tree $temp) -ceq $before) 'Install rejection modified host.'
    }
    Case 'Repeated Update idempotent including host install metadata' {
        Update-Fixture $hostRoot
        $before = Tree $hostRoot -HostFilesOnly
        Update-Fixture $hostRoot
        Check ((Tree $hostRoot -HostFilesOnly) -ceq $before) 'Repeated update changed host/plugin files.'
    }
    Case 'Update DryRun: no filesystem writes' {
        $before = Tree $temp
        & (Join-Path $repository 'Update-GameAnimationSampleInProject.ps1') -HostProject $hostRoot -PackageRoot $package -DryRun
        Check ((Tree $temp) -ceq $before) 'Update DryRun wrote files.'
    }
    foreach ($point in 'DuringPackageCopy','AfterStaging','AfterPluginSwap','DuringIniWrite') {
        $failurePoint = $point
        Case "Injected $point failure restores host and plugin hashes" {
            $before = Tree $hostRoot -HostFilesOnly
            $inject = New-FaultInjector $failurePoint
            Reject { Update-Fixture $hostRoot $inject } 'INJECTED'
            Check ((Tree $hostRoot -HostFilesOnly) -ceq $before) "Incomplete rollback: $failurePoint"
        }
    }
    Case 'Plugin backup integrity and host recovery metadata' {
        $backup = @(Get-ChildItem -LiteralPath (Join-Path $hostRoot 'Saved\GameAnimationSampleToolkit\Backups') -Directory)[0]
        $old = Read-GasJson (Join-Path $backup.FullName 'GameAnimationSample.install.json')
        Assert-GasInventory $backup.FullName $old.Files
        $snapshots = @(Get-ChildItem -LiteralPath (Join-Path $hostRoot 'Saved\GameAnimationSampleToolkit\Transactions') -Directory)
        Check ($snapshots.Count -ge 3) 'Recovery snapshots not retained.'
        foreach ($snapshot in $snapshots) { Check (Test-Path -LiteralPath (Join-Path $snapshot.FullName 'HostProject.uproject')) 'Host descriptor missing from snapshot.' }
    }
    Case 'Clean install failure removes partial plugin and restores missing INIs' {
        $fresh = New-Host 'FailedInstall'
        Remove-Item -LiteralPath (Join-Path $fresh 'Config')
        Remove-Item -LiteralPath (Join-Path $fresh 'Plugins')
        $before = Tree $fresh -HostFilesOnly
        $inject = New-FaultInjector 'DuringIniWrite'
        Reject { Invoke-GasHostOperation -HostProject $fresh -PackageRoot $package -Operation Install -FaultInjector $inject } 'INJECTED'
        Check ((Tree $fresh -HostFilesOnly) -ceq $before) 'Failed install left host mutations.'
    }
    Case 'Host descriptor locked: preflight fails with no writes' {
        $before = Tree $hostRoot
        $stream = [IO.File]::Open((Join-Path $hostRoot 'Host.uproject'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        try { Reject { Update-Fixture $hostRoot } }
        finally { $stream.Dispose() }
        Check ((Tree $hostRoot) -ceq $before) 'Locked file rejection wrote files.'
    }
    Case 'Read-only host INI: preflight fails with no writes' {
        $ini = Join-Path $hostRoot 'Config\DefaultEngine.ini'
        $originalAttributes = [IO.File]::GetAttributes($ini)
        try {
            [IO.File]::SetAttributes($ini, $originalAttributes -bor [IO.FileAttributes]::ReadOnly)
            $before = Tree $hostRoot
            Reject { Update-Fixture $hostRoot } 'Read-only'
            Check ((Tree $hostRoot) -ceq $before) 'Read-only rejection wrote files.'
        } finally { [IO.File]::SetAttributes($ini, $originalAttributes) }
    }
    Case 'Legacy installed manifest without inventory upgrades with complete backup' {
        $legacy = New-Host 'LegacyHost'
        Invoke-GasHostOperation -HostProject $legacy -PackageRoot $package -Operation Install
        $oldPath = Join-Path $legacy 'Plugins\GameAnimationSample\GameAnimationSample.install.json'
        $old = Read-GasJson $oldPath
        $old.PSObject.Properties.Remove('Files')
        $old.BuildVersion = '5.8.previous'
        Write-GasJson $old $oldPath
        Update-Fixture $legacy
        $updated = Read-GasJson $oldPath
        Check ($updated.PSObject.Properties.Name -contains 'Files') 'Legacy package not upgraded.'
        $backup = @(Get-ChildItem -LiteralPath (Join-Path $legacy 'Saved\GameAnimationSampleToolkit\Backups') -Directory)[0]
        Check ((Read-GasJson (Join-Path $backup.FullName 'GameAnimationSample.install.json')).BuildVersion -eq '5.8.previous') 'Legacy backup lost.'
    }
    Case 'Array identities tolerate whitespace/casing and deduplicate tags semantically' {
        $path = Join-Path $temp 'Semantic.ini'
        $content = "[/Script/GameplayTags.GameplayTagsSettings]`n+GameplayTagList=(Tag=`"Foley.Event.Kick`",DevComment=`"one`")`n+GameplayTagList=(Tag=`"foley.event.kick`",DevComment=`"two`")"
        $planned = Update-ManagedIniBlock -Path $path -BlockId 'DefaultGameplayTags.Tags' -Content $content -CurrentText '' -PassThru
        Check (([regex]::Matches($planned, '(?i)Tag="Foley.Event.Kick"')).Count -eq 1) 'Semantic tag duplicate retained.'
        $current = "[/Script/Engine.DataDrivenConsoleVariableSettings]`n+CVarsArray = ( Name = `"ddcvar.characterphysics.drawdebug`", Type=CVarInt,DefaultValueInt=7 )"
        $template = "[/Script/Engine.DataDrivenConsoleVariableSettings]`n+CVarsArray=(Name=`"DDCVar.CharacterPhysics.DrawDebug`",Type=CVarInt,DefaultValueInt=0)"
        $planned = Update-ManagedIniBlock -Path $path -BlockId 'DefaultEngine.Runtime' -Content $template -CurrentText $current -PassThru
        Check (([regex]::Matches($planned, '(?i)ddcvar.characterphysics.drawdebug')).Count -eq 1 -and $planned.Contains('DefaultValueInt=7')) 'Customized CVar overwritten/duplicated.'
        $unrelatedHost = New-Host 'UnrelatedMetadata'
        $path = Join-Path $unrelatedHost 'Host.uproject'
        Write-GasJson @{ EngineAssociation = '5.8'; Plugins = @(@{ Name = 'Unrelated'; UserSetting = 42 }) } $path
        $plannedJson = Update-UProjectPluginEntries -UProjectPath $path -PluginName GameAnimationSample -RequiredPlugins @() -PassThru | ConvertFrom-Json
        $unrelated = @($plannedJson.Plugins | Where-Object Name -eq 'Unrelated')[0]
        Check ($unrelated.PSObject.Properties.Name -notcontains 'Enabled' -and $unrelated.UserSetting -eq 42) 'Unrelated plugin metadata changed.'
    }
    Case 'Unmanaged plugin files survive Update' {
        $custom = Join-Path $hostRoot 'Plugins\GameAnimationSample\UserNotes.txt'
        [IO.File]::WriteAllText($custom, 'keep user data')
        Update-Fixture $hostRoot
        Check ([IO.File]::ReadAllText($custom) -ceq 'keep user data') 'Unmanaged file lost.'
    }
    Case 'User edits to inventoried plugin files reject Update without writes' {
        $asset = Join-Path $hostRoot 'Plugins\GameAnimationSample\Content\RootFixture.uasset'
        $original = [IO.File]::ReadAllBytes($asset)
        try {
            [IO.File]::WriteAllText($asset, 'user edited asset')
            $before = Tree $temp
            Reject { Update-Fixture $hostRoot } 'modified or removed'
            Check ((Tree $temp) -ceq $before) 'Preflight rejection wrote files.'
        } finally { [IO.File]::WriteAllBytes($asset, $original) }
    }
    Case 'Unmanaged preexisting plugin refuses Update and Install' {
        $unmanaged = New-Host 'UnmanagedHost'
        New-GasDirectory (Join-Path $unmanaged 'Plugins\GameAnimationSample')
        [IO.File]::WriteAllText((Join-Path $unmanaged 'Plugins\GameAnimationSample\Important.txt'), 'user work')
        $before = Tree $unmanaged
        Reject { Update-Fixture $unmanaged }
        Reject { Invoke-GasHostOperation -HostProject $unmanaged -PackageRoot $package -Operation Install }
        Check ((Tree $unmanaged) -ceq $before) 'Unmanaged plugin changed.'
    }
    Case 'Disabled dependency preflight preserves explicit host decision' {
        $disabled = New-Host 'DisabledDependency'
        Write-GasJson @{ EngineAssociation = '5.8'; Plugins = @(@{ Name = 'PoseSearch'; Enabled = $false }) } (Join-Path $disabled 'Host.uproject')
        $before = Tree $disabled
        Reject { Invoke-GasHostOperation -HostProject $disabled -PackageRoot $package -Operation Install } 'explicitly disables'
        Check ((Tree $disabled) -ceq $before) 'Disabled dependency changed.'
    }
    Case 'Dangerous, missing and overlapping paths fail before writes' {
        $before = Tree $temp
        Reject { Assert-GasSafePath ([IO.Path]::GetPathRoot($temp)) } 'roots'
        Reject { Assert-GasSafePath (Join-Path $temp '..\outside') } 'Unsafe'
        Reject { Invoke-GasHostOperation -HostProject (Join-Path $temp 'Missing') -PackageRoot $package -Operation Install }
        Reject { Invoke-GasHostOperation -HostProject $hostRoot -PackageRoot $hostRoot -Operation Update } 'Overlapping'
        Reject { & (Join-Path $repository 'Build-GameAnimationSamplePlugin.ps1') -ProjectRoot $sample -PluginName '..\Unsafe' -RefreshOutput }
        Check ((Tree $temp) -ceq $before) 'Dangerous path preflight wrote files.'
    }
    Case 'Config junction rejected before any traversal/write' {
        $linkedHost = New-Host 'LinkedHost'
        $config = Join-Path $linkedHost 'Config'
        Remove-Item -LiteralPath $config
        New-Item -ItemType Junction -Path $config -Target (Join-Path $sample 'Config') | Out-Null
        try { Reject { Invoke-GasHostOperation -HostProject $linkedHost -PackageRoot $package -Operation Install } 'reparse|Link' }
        finally { [IO.Directory]::Delete($config) }
        Check ((Tree $sample) -ceq $sampleBefore) 'Linked source modified.'
    }
    Case 'Host hard-linked INI rejected without changing link target' {
        $linked = New-Host 'HardLinkedHost'
        $external = Join-Path $temp 'SharedConfig.txt'
        [IO.File]::WriteAllText($external, '[UserConfig]')
        New-Item -ItemType HardLink -Path (Join-Path $linked 'Config\DefaultEngine.ini') -Target $external | Out-Null
        Reject { Invoke-GasHostOperation -HostProject $linked -PackageRoot $package -Operation Install } 'Link|reparse'
        Check ([IO.File]::ReadAllText($external) -ceq '[UserConfig]') 'Hard-link target modified.'
    }
    Case 'Unfinished transaction blocks retry before any host mutation' {
        $pending = New-Host 'PendingTransaction'
        $journal = Join-Path $pending 'Saved\GameAnimationSampleToolkit\Transactions\interrupted\Transaction.json'
        New-GasDirectory (Split-Path -Parent $journal)
        Write-GasJson @{ Phase = 'Prepared' } $journal
        $before = Tree $pending
        Reject { Invoke-GasHostOperation -HostProject $pending -PackageRoot $package -Operation Install } 'Unfinished transaction'
        Check ((Tree $pending) -ceq $before) 'Retry changed interrupted host.'
    }
    Case 'RawCopy redirect cannot shadow a preexisting host asset' {
        $collisionHost = New-Host 'RedirectCollision'
        New-GasDirectory (Join-Path $collisionHost 'Content\Levels')
        [IO.File]::WriteAllText((Join-Path $collisionHost 'Content\Levels\Fixture.umap'), 'user map')
        $before = Tree $collisionHost
        Reject { Invoke-GasHostOperation -HostProject $collisionHost -PackageRoot $package -Operation Install } 'shadow existing host asset'
        Check ((Tree $collisionHost) -ceq $before) 'Host map changed by redirect preflight.'
    }
    Case 'Explicit host array clear is a preflight conflict' {
        $cleared = New-Host 'ClearedTags'
        [IO.File]::WriteAllText((Join-Path $cleared 'Config\DefaultGameplayTags.ini'), "[/Script/GameplayTags.GameplayTagsSettings]`n!GameplayTagList=ClearArray")
        $before = Tree $cleared
        Reject { Invoke-GasHostOperation -HostProject $cleared -PackageRoot $package -Operation Install } 'explicitly clears'
        Check ((Tree $cleared) -ceq $before) 'Host clear was changed.'
    }
    Case 'Collision channel name in a different slot is a preflight conflict' {
        $channelHost = New-Host 'CollisionNameConflict'
        [IO.File]::WriteAllText((Join-Path $channelHost 'Config\DefaultEngine.ini'), "[/Script/Engine.CollisionProfile]`n+DefaultChannelResponses=(Channel=ECC_GameTraceChannel8,DefaultResponse=ECR_Ignore,bTraceType=True,bStaticObject=False,Name=`"Traversable`")")
        $before = Tree $channelHost
        Reject { Invoke-GasHostOperation -HostProject $channelHost -PackageRoot $package -Operation Install } 'Host conflict'
        Check ((Tree $channelHost) -ceq $before) 'Collision conflict wrote files.'
    }
    Case 'Controlled IO/access exceptions roll back without OS fault injection' {
        $before = Tree $hostRoot -HostFilesOnly
        $ioFailure = { param($phase) if ($phase -eq 'DuringIniWrite') { throw [IO.IOException]::new('SIMULATED insufficient space') } }
        Reject { Update-Fixture $hostRoot $ioFailure } 'SIMULATED insufficient space'
        Check ((Tree $hostRoot -HostFilesOnly) -ceq $before) 'IO failure damaged host.'
        $accessFailure = { param($phase) if ($phase -eq 'AfterPluginSwap') { throw [UnauthorizedAccessException]::new('SIMULATED access denied') } }
        Reject { Update-Fixture $hostRoot $accessFailure } 'SIMULATED access denied'
        Check ((Tree $hostRoot -HostFilesOnly) -ceq $before) 'Access failure damaged host.'
    }
    Case 'Invalid manifest identity/path traversal rejected without host writes' {
        $manifestPath = Join-Path $package 'GameAnimationSample.install.json'
        $original = [IO.File]::ReadAllBytes($manifestPath)
        try {
            $manifest = Read-GasJson $manifestPath
            $manifest.PluginName = '..\Outside'
            Write-GasJson $manifest $manifestPath
            $before = Tree $hostRoot
            Reject { Update-Fixture $hostRoot } 'identity'
            Check ((Tree $hostRoot) -ceq $before) 'Invalid manifest wrote host.'
            [IO.File]::WriteAllBytes($manifestPath, $original)
            $manifest = Read-GasJson $manifestPath
            $manifest.Files[0].Path = '..\Outside'
            Write-GasJson $manifest $manifestPath
            Reject { Update-Fixture $hostRoot } 'Unsafe'
        } finally { [IO.File]::WriteAllBytes($manifestPath, $original) }
    }
    Case 'Invalid uplugin and corrupt package inventory rejected' {
        $descriptorPath = Join-Path $package 'GameAnimationSample.uplugin'
        $original = [IO.File]::ReadAllBytes($descriptorPath)
        try {
            [IO.File]::WriteAllText($descriptorPath, '{broken JSON')
            Reject { Update-Fixture $hostRoot }
            [IO.File]::WriteAllBytes($descriptorPath, $original)
            Add-Content -LiteralPath $descriptorPath -Value ' '
            Reject { Update-Fixture $hostRoot } 'hash mismatch'
        } finally { [IO.File]::WriteAllBytes($descriptorPath, $original) }
    }
    Case 'RefreshOutput refuses arbitrary directory and preserves old output on source failure' {
        $arbitrary = Join-Path $temp 'Arbitrary'
        New-GasDirectory $arbitrary
        [IO.File]::WriteAllText((Join-Path $arbitrary 'keep.txt'), 'keep')
        Reject { & (Join-Path $repository 'Build-GameAnimationSamplePlugin.ps1') -ProjectRoot $sample -OutputRoot $arbitrary -RefreshOutput }
        Check ([IO.File]::ReadAllText((Join-Path $arbitrary 'keep.txt')) -ceq 'keep') 'Refresh deleted arbitrary data.'
        $sourceEngine = Join-Path $sample 'Config\DefaultEngine.ini'
        $bytes = [IO.File]::ReadAllBytes($sourceEngine)
        $before = Tree $package
        try {
            Add-Content -LiteralPath $sourceEngine -Value "`n[/Script/Engine.DataDrivenConsoleVariableSettings]`n+CVarsArray=(Type=CVarInt,Name=`"DDCVar.CharacterPhysics.DrawDebug`",DefaultValueInt=99)"
            Reject { & (Join-Path $repository 'Build-GameAnimationSamplePlugin.ps1') -ProjectRoot $sample -OutputRoot $package -RefreshOutput } 'conflicting CVarsArray'
            Check ((Tree $package) -ceq $before) 'Failed build modified valid output.'
        } finally { [IO.File]::WriteAllBytes($sourceEngine, $bytes) }
    }
    Case 'Build and Clean wrapper DryRun leave all fixture files/directories unchanged' {
        $before = Tree $temp
        & (Join-Path $repository 'Clean-Build-GameAnimationSamplePlugin.ps1') -ProjectRoot $sample -OutputRoot $package -DryRun
        Check ((Tree $temp) -ceq $before) 'Build DryRun wrote files.'
    }
    Case 'RefreshOutput commits validated package and retains previous output' {
        & (Join-Path $repository 'Build-GameAnimationSamplePlugin.ps1') -ProjectRoot $sample -OutputRoot $package -RefreshOutput -SkipUnrealDuplication
        Check (@(Get-ChildItem -LiteralPath (Split-Path -Parent $package) -Directory -Filter 'GameAnimationSample.previous-*').Count -eq 1) 'Previous output not retained.'
        $null = Assert-GasPackage $package
        Check ((Tree $sample) -ceq $sampleBefore) 'Source modified during refresh.'
    }
    Case 'Legacy generated output supports default-path DryRun and safe rebuild' {
        $legacySample = Join-Path $temp 'Legacy Sample'
        Copy-Item -LiteralPath $sample -Destination $legacySample -Recurse
        $legacyOutput = Join-Path $legacySample 'Development\Plugins\GameAnimationSample'
        New-GasDirectory (Split-Path -Parent $legacyOutput)
        Copy-Item -LiteralPath $package -Destination $legacyOutput -Recurse
        Remove-Item -LiteralPath (Join-Path $legacyOutput 'Tools\Scripts\GameAnimationSampleSafety.ps1')
        $legacyManifestPath = Join-Path $legacyOutput 'GameAnimationSample.install.json'
        $manifest = Read-GasJson $legacyManifestPath
        $manifest.PSObject.Properties.Remove('Files')
        Write-GasJson $manifest $legacyManifestPath
        $descriptorPath = Join-Path $legacyOutput 'GameAnimationSample.uplugin'
        $descriptor = Read-GasJson $descriptorPath
        $descriptor.EngineVersion = '5.8'
        Write-GasJson $descriptor $descriptorPath
        Reject { Assert-GasPackage $legacyOutput } 'Invalid .uplugin'
        $before = Tree $temp
        & (Join-Path $repository 'Build-GameAnimationSamplePlugin.ps1') -ProjectRoot $legacySample -RefreshOutput -DryRun
        & (Join-Path $repository 'Clean-Build-GameAnimationSamplePlugin.ps1') -ProjectRoot $legacySample -DryRun
        Check ((Tree $temp) -ceq $before) 'Legacy refresh DryRun wrote files.'
        $manifest.PluginMountPoint = '/Foreign'
        Write-GasJson $manifest $legacyManifestPath
        $invalidBefore = Tree $temp
        Reject { & (Join-Path $repository 'Build-GameAnimationSamplePlugin.ps1') -ProjectRoot $legacySample -RefreshOutput -DryRun } 'identifiable'
        Check ((Tree $temp) -ceq $invalidBefore) 'Foreign identity rejection wrote files.'
        $manifest.PluginMountPoint = '/GameAnimationSample'
        Write-GasJson $manifest $legacyManifestPath
        $legacyBefore = Tree $legacyOutput
        & (Join-Path $repository 'Build-GameAnimationSamplePlugin.ps1') -ProjectRoot $legacySample -RefreshOutput -SkipUnrealDuplication
        $null = Assert-GasPackage $legacyOutput
        $previous = @(Get-ChildItem -LiteralPath (Split-Path -Parent $legacyOutput) -Directory -Filter 'GameAnimationSample.previous-*')
        Check ($previous.Count -eq 1 -and (Tree $previous[0].FullName) -ceq $legacyBefore) 'Original legacy package was not retained intact.'
        Check ((Tree $sample) -ceq $sampleBefore) 'Original fixture sample changed.'
    }
} finally {
    # The only recursive cleanup target is the verified, GUID-named fixture root.
    $resolved = [IO.Path]::GetFullPath($temp)
    Check ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^gas-release-safety-[a-f0-9]{32}$') 'Unsafe fixture cleanup.'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$results | Format-Table -AutoSize -Wrap
$failures = @($results | Where-Object Result -eq 'FAIL')
Write-Host "$($results.Count - $failures.Count)/$($results.Count) release safety checks passed."
if ($failures.Count) { throw "$($failures.Count) release safety checks failed." }
