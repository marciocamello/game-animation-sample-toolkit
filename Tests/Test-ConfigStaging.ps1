#requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$results = [Collections.Generic.List[object]]::new()
function Check([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action, [string]$Pattern) {
    try { & $Action | Out-Null } catch { Check ([string]$_ -match $Pattern) "Unexpected failure: $_"; return }
    throw 'Expected preflight rejection.'
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
function New-Host([string]$Folder, [string]$GameText = '', [string]$ProjectName = 'Aurora') {
    $root = Join-Path $temp $Folder
    New-GasDirectory (Join-Path $root 'Config')
    Write-GasJson @{ FileVersion = 3; EngineAssociation = '5.8'; Description = 'Keep metadata' } (Join-Path $root "$ProjectName.uproject")
    [IO.File]::WriteAllText((Join-Path $root 'Config\DefaultGame.ini'), $GameText)
    [IO.File]::WriteAllText((Join-Path $root 'Config\DefaultEngine.ini'), "[/Script/EngineSettings.GameMapsSettings]`nGameDefaultMap=/Game/UserMap`nEditorStartupMap=/Game/UserEditor`nGlobalDefaultGameMode=/Game/UserMode`n[UserEngine]`nKeep=42`n")
    [IO.File]::WriteAllText((Join-Path $root 'Config\DefaultGameplayTags.ini'), "[/Script/GameplayTags.GameplayTagsSettings]`n+GameplayTagList=(Tag=`"User.CustomTag`",DevComment=`"Keep`")`n")
    return $root
}
function Install([string]$Root, [switch]$DryRun) {
    & (Join-Path $package 'Tools\Install-GameAnimationSampleToProject.ps1') -HostProject $Root -PackageRoot $package -DryRun:$DryRun
}
function Update([string]$Root, [switch]$DryRun) {
    & (Join-Path $repository 'Update-GameAnimationSampleInProject.ps1') -HostProject $Root -PackageRoot $package -DryRun:$DryRun
}
function Game([string]$Root) { return Get-GasNormalizedText ([IO.File]::ReadAllText((Join-Path $Root 'Config\DefaultGame.ini'))) }
function New-StagingFailure([string]$Path, [hashtable]$Observation) {
    return { param($phase)
        if ($phase -eq 'DuringIniWrite') {
            $Observation.Written = ([IO.File]::ReadAllText($Path)).Contains('+AllowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini')
            throw 'INJECTED staging failure'
        }
    }.GetNewClosure()
}
function PermissionCount([string]$Text, [string]$ProjectName = 'Aurora') {
    $count = 0; $section = ''
    foreach ($line in $Text -split "`n") {
        $info = Get-GasIniLineInfo $line
        if ($info.Kind -eq 'Section') { $section = $info.Section }
        elseif ($section -ieq 'Staging' -and $info.Kind -eq 'Assignment' -and $info.Key -ieq 'AllowedConfigFiles' -and $info.Operator -in @('','+','.')) {
            if ((Get-GasStagingPathIdentity $info.Value) -eq ("$ProjectName/Config/DefaultNetworkPrediction.ini".ToLowerInvariant())) { $count++ }
        }
    }
    return $count
}

Case 'Native parser validates all PowerShell files before execution' {
    foreach ($file in Get-ChildItem -LiteralPath $repository -Recurse -File | Where-Object Extension -in '.ps1', '.psm1') {
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        Check ($errors.Count -eq 0) "ParserError: $($file.FullName) $errors"
    }
}
if ($results[0].Result -eq 'FAIL') { throw $results[0].Detail }
Import-Module (Join-Path $repository 'Scripts\GameAnimationSampleTools.psm1') -Force -DisableNameChecking
$temp = Join-Path ([IO.Path]::GetTempPath()) ('gas-config-staging-' + [guid]::NewGuid().ToString('N'))
New-GasDirectory $temp
try {
    $sample = Join-Path $temp 'SyntheticSource'
    New-GasDirectory (Join-Path $sample 'Config')
    New-GasDirectory (Join-Path $sample 'Content\Levels')
    [IO.File]::WriteAllText((Join-Path $sample 'Content\Levels\Fixture.umap'), 'Synthetic test payload; never loaded in Unreal.')
    Write-GasJson @{ EngineAssociation = '5.8'; Plugins = @(@{ Name = 'PoseSearch'; Enabled = $true }) } (Join-Path $sample 'GameAnimationSample.uproject')
    foreach ($definition in Get-GasHostIntegrationBlockDefinitions | Where-Object { -not $_.Generated }) {
        $text = Get-GasRenderedTemplate -TemplatePath (Join-Path $repository "Templates\$($definition.Template)") -Tokens @{ PLUGIN_MOUNT_POINT = '/Game' }
        [IO.File]::WriteAllText((Join-Path $sample "Config\$($definition.IniFile)"), $text)
    }
    Add-Content -LiteralPath (Join-Path $sample 'Config\DefaultGameplayTags.ini') -Value '+GameplayTagList=(Tag="Foley.Event.Kick",DevComment="fixture")'
    $package = Join-Path $temp 'Package\GameAnimationSample'
    & (Join-Path $repository 'Build-GameAnimationSamplePlugin.ps1') -ProjectRoot $sample -OutputRoot $package -SkipUnrealDuplication
    Case 'No Staging section: distributed installer adds exact host-derived permission' {
        $root = New-Host 'DifferentFolderName' "[UserGame]`nKeep=Original`n"
        Install $root
        Check ((PermissionCount (Game $root)) -eq 1) 'Missing or duplicated permission.'
        Check ((Game $root).Contains('+AllowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini')) 'Wrong staged path/project name.'
        Check ((Game $root).StartsWith("[UserGame]`nKeep=Original")) 'User config changed.'
        $ownership = Read-GasJson (Join-Path $root 'Plugins\GameAnimationSample\GameAnimationSample.host-install.json')
        Check ($ownership.ManagedIniBlocks -contains 'DefaultGame.Staging') 'Host block ownership missing.'
    }
    Case 'Existing Staging and other plugin permissions remain byte-equivalent' {
        $original = "[Staging]`n+AllowedConfigFiles=Aurora/Plugins/Other/Config/Other.ini`n+DisallowedConfigFiles=Aurora/Config/Private.ini`n+AllowedDirectories=Aurora/Content/Other`n[User]`nKeep=True`n"
        $root = New-Host 'OtherPluginHost' $original
        Install $root
        Check ((Game $root).StartsWith($original)) 'Existing staging/config entries changed.'
        Check ((PermissionCount (Game $root)) -eq 1) 'Missing permission.'
    }
    foreach ($existing in @('+AllowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini', '+AllowedConfigFiles="aUrOrA\Config\DefaultNetworkPrediction.ini"', 'AllowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini', '.AllowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini')) {
        Case "Existing permission deduplicates: $existing" {
            $root = New-Host ([guid]::NewGuid().ToString('N')) "[Staging]`n$existing`n"
            Install $root
            Update $root
            Check ((PermissionCount (Game $root)) -eq 1) 'Semantic duplicate was added.'
            Check ((Game $root).Contains($existing)) 'Existing permission was rewritten.'
        }
    }
    Case 'Repeated Update is byte-idempotent; maps, Foley tags and custom tags survive' {
        $root = New-Host 'Idempotent' "[Custom]`nKeep=Value`n"
        $maps = [IO.File]::ReadAllText((Join-Path $root 'Config\DefaultEngine.ini'))
        Install $root
        Update $root
        $before = Tree $root -HostFilesOnly
        Update $root
        Check ((Tree $root -HostFilesOnly) -ceq $before) 'Repeated update changed host/plugin files.'
        Check ((PermissionCount (Game $root)) -eq 1) 'Duplicate staging permission.'
        $engineText = Get-GasNormalizedText ([IO.File]::ReadAllText((Join-Path $root 'Config\DefaultEngine.ini')))
        Check ($engineText.StartsWith((Get-GasNormalizedText $maps).TrimEnd())) 'Maps/custom engine settings changed.'
        $tags = [IO.File]::ReadAllText((Join-Path $root 'Config\DefaultGameplayTags.ini'))
        Check ($tags.Contains('User.CustomTag') -and $tags.Contains('Foley.Event.Kick')) 'Host or Foley tag disappeared.'
    }
    Case 'Install DryRun includes staging plan with zero filesystem writes' {
        $root = New-Host 'InstallPreview'
        $before = Tree $temp
        $plan = Install $root -DryRun
        Check ($plan.Files[(Join-Path $root 'Config\DefaultGame.ini')].Contains('+AllowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini')) 'DryRun omits staging.'
        Check ((Tree $temp) -ceq $before) 'Install DryRun wrote files/directories.'
    }
    $legacy = New-Host 'OlderInstalledHost'
    Install $legacy
    $gamePath = Join-Path $legacy 'Config\DefaultGame.ini'
    $oldGame = [regex]::Replace((Game $legacy), '(?ms)^; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultGame\.Staging\n.*?^; END AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultGame\.Staging(?:\n|$)', '')
    [IO.File]::WriteAllText($gamePath, $oldGame)
    Case 'Older installed host: Update DryRun plans missing permission without writes' {
        $before = Tree $temp
        $plan = Update $legacy -DryRun
        Check ((PermissionCount $plan.Files[$gamePath]) -eq 1) 'Upgrade preview omits permission.'
        Check ((Tree $temp) -ceq $before) 'Update DryRun wrote files/directories.'
    }
    Case 'Failure after writing staging restores DefaultGame, all host files and old plugin' {
        $before = Tree $legacy -HostFilesOnly
        $observation = @{ Written = $false }
        $inject = New-StagingFailure -Path $gamePath -Observation $observation
        Reject { Invoke-GasHostOperation -HostProject $legacy -PackageRoot $package -Operation Update -FaultInjector $inject } 'INJECTED staging failure'
        Check $observation.Written 'Failure was not injected after staging config write.'
        Check ((Tree $legacy -HostFilesOnly) -ceq $before) 'Rollback changed host/plugin bytes.'
        $snapshot = @(Get-ChildItem -LiteralPath (Join-Path $legacy 'Saved\GameAnimationSampleToolkit\Transactions') -Directory | Where-Object { (Read-GasJson (Join-Path $_.FullName 'Transaction.json')).Phase -eq 'RolledBack' })[0]
        Check ((Get-FileHash -LiteralPath (Join-Path $snapshot.FullName 'Config\DefaultGame.ini')).Hash -eq (Get-FileHash -LiteralPath $gamePath).Hash) 'Config backup differs from restored file.'
    }
    Case 'Older installed host upgrades; host rename updates only its managed staged path' {
        Update $legacy
        Check ((PermissionCount (Game $legacy)) -eq 1) 'Upgrade failed to add permission.'
        Move-Item -LiteralPath (Join-Path $legacy 'Aurora.uproject') -Destination (Join-Path $legacy 'RenamedGame.uproject')
        Update $legacy
        Check ((PermissionCount (Game $legacy) 'RenamedGame') -eq 1) 'Renamed host path not generated.'
        Check ((Game $legacy) -notmatch 'Aurora/Config/DefaultNetworkPrediction.ini') 'Stale managed host name survived.'
    }
    foreach ($policy in @('+DisallowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini', ('+AllowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini' + "`n" + '+DisallowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini'), '!AllowedConfigFiles=ClearArray', '-AllowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini')) {
        Case "Host policy conflict rejects without writes: $policy" {
            $root = New-Host ([guid]::NewGuid().ToString('N')) "[Staging]`n$policy`n"
            $before = Tree $temp
            Reject { Install $root -DryRun } 'staging conflict'
            Reject { Install $root } 'staging conflict'
            Check ((Tree $temp) -ceq $before) 'Conflict rejection wrote files.'
        }
    }
    Case 'Removed disallow entries do not produce false conflicts' {
        $config = Get-GasHostStagingConfig -UProjectPath 'Aurora.uproject' -DefaultGameText "[Staging]`n+DisallowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini`n-DisallowedConfigFiles=Aurora/Config/DefaultNetworkPrediction.ini"
        Check ((PermissionCount $config) -eq 1) 'Effective host deny removal ignored.'
    }
    Case 'Only NetworkPrediction needs explicit staging among managed UE 5.8.4 configs' {
        $config = Get-GasHostStagingConfig -UProjectPath 'Galaxy.Client.uproject' -DefaultGameText ''
        Check ($config -ceq "[Staging]`n+AllowedConfigFiles=Galaxy/Config/DefaultNetworkPrediction.ini") 'ProjectUtils short-name behavior differs or scope broadened.'
        Check ($config -notmatch 'DefaultEngine.ini|DefaultInput.ini|DefaultGame.ini|DefaultGameplayTags.ini') 'Built-in categories unnecessarily allowlisted.'
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($temp)
    Check ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^gas-config-staging-[a-f0-9]{32}$') 'Unsafe fixture cleanup.'
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
$results | Format-Table -AutoSize -Wrap
$failures = @($results | Where-Object Result -eq 'FAIL')
$failures | ForEach-Object { Write-Host "$($_.Test): $($_.Detail)" }
Write-Host "$($results.Count - $failures.Count)/$($results.Count) config staging checks passed."
if ($failures.Count) { throw "$($failures.Count) config staging checks failed." }
