[CmdletBinding()]
param(
    [string]$RepositoryRoot = $PSScriptRoot,
    [string]$HostProject,
    [string]$PackageRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $RepositoryRoot "Scripts\GameAnimationSampleTools.psm1") -Force

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-RegexCount {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern
    )

    return ([regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count
}

function Get-GasHostMapSnapshot {
    param([Parameter(Mandatory)][string]$Text)

    $protectedKeys = @(
        "GameDefaultMap",
        "EditorStartupMap",
        "ServerDefaultMap",
        "TransitionMap",
        "LocalMapOptions",
        "GlobalDefaultGameMode",
        "GlobalDefaultServerGameMode"
    )
    $values = [ordered]@{}
    $counts = @{}
    $sectionCount = 0
    $inGameMapsSection = $false

    foreach ($line in (Get-GasNormalizedText -Text $Text) -split "`n") {
        $lineInfo = Get-GasIniLineInfo -Line $line
        if ($lineInfo.Kind -eq "Section") {
            $inGameMapsSection = [string]$lineInfo.Section -ieq "/Script/EngineSettings.GameMapsSettings"
            if ($inGameMapsSection) {
                $sectionCount++
            }
            continue
        }

        if (-not $inGameMapsSection -or $lineInfo.Kind -ne "Assignment" -or $lineInfo.IsArrayOperation) {
            continue
        }

        if ($protectedKeys -notcontains $lineInfo.Key) {
            continue
        }

        if (-not $values.Contains($lineInfo.Key)) {
            $values[$lineInfo.Key] = $lineInfo.Value
            $counts[$lineInfo.Key] = 0
        }

        $counts[$lineInfo.Key]++
    }

    return [pscustomobject]@{
        Values = $values
        Counts = $counts
        SectionCount = $sectionCount
    }
}

function Assert-GasHostMaps {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)]$ExpectedMaps,
        [Parameter(Mandatory)][string]$Phase
    )

    $actualMaps = Get-GasHostMapSnapshot -Text $Text
    Assert-True ($actualMaps.SectionCount -eq $ExpectedMaps.SectionCount) "[$Phase] Host GameMapsSettings section count changed."

    foreach ($entry in $ExpectedMaps.Values.GetEnumerator()) {
        Assert-True ($actualMaps.Values.Contains($entry.Key)) "[$Phase] Host map setting '$($entry.Key)' disappeared."
        Assert-True ([string]$actualMaps.Values[$entry.Key] -eq [string]$entry.Value) "[$Phase] Host '$($entry.Key)' changed to '$($actualMaps.Values[$entry.Key])'."
        Assert-True ($actualMaps.Counts[$entry.Key] -eq $ExpectedMaps.Counts[$entry.Key]) "[$Phase] Host '$($entry.Key)' was duplicated."
    }

    foreach ($entry in $actualMaps.Values.GetEnumerator()) {
        Assert-True ($ExpectedMaps.Values.Contains($entry.Key)) "[$Phase] Toolkit added host-owned map setting '$($entry.Key)'."
    }
}

function New-ValidationPackageRoot {
    param([Parameter(Mandatory)][string]$Root)

    New-GasDirectory -Path $Root
    $installDataRoot = Join-Path $Root "InstallData"
    New-GasDirectory -Path $installDataRoot
    New-GasDirectory -Path (Join-Path $Root "Tools")

    foreach ($entry in @(Get-GasHostIntegrationBlockDefinitions | Where-Object { -not $_.Generated })) {
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot "Templates\$($entry.Template)") -Destination (Join-Path $installDataRoot $entry.Template) -Force
    }

    # Reproduce the UE 5.8 source config, including two CharacterPhysics
    # CVars omitted by the former static toolkit template.
    $sourceEngineFixture = @"
[/Script/Engine.DataDrivenConsoleVariableSettings]
+CVarsArray=(Type=CVarInt,Name="DDCVar.CharacterPhysics.DrawDebug",ToolTip="",DefaultValueFloat=0.000000,DefaultValueInt=0,DefaultValueBool=False)
+CVarsArray=(Type=CVarInt,Name="DDCVar.CharacterPhysics.DefaultProfile",ToolTip="",DefaultValueFloat=0.000000,DefaultValueInt=1,DefaultValueBool=False)
+CVarsArray=(Type=CVarInt,Name="DDCvar.MMDatabaseLOD",ToolTip="",DefaultValueFloat=0.000000,DefaultValueInt=3,DefaultValueBool=False)
+CVarsArray=(Type=CVarInt,Name="DDCVar.CharacterPhysics.DrawDebug",ToolTip="",DefaultValueFloat=0.000000,DefaultValueInt=0,DefaultValueBool=False)
-CVarsArray=(Type=CVarInt,Name="DDCVar.SourceOnlyRemoval",DefaultValueInt=1)

[/Script/EngineSettings.GameMapsSettings]
GameDefaultMap=/Game/SourceOnlyDefault
"@
    $runtimeTemplatePath = Join-Path $installDataRoot "DefaultEngine.Runtime.ini"
    $runtimeTemplate = Get-Content -LiteralPath $runtimeTemplatePath -Raw
    # Simulate a stale template with obsolete and outdated CVar defaults.
    $runtimeTemplate = $runtimeTemplate.Replace('[/Script/Engine.DataDrivenConsoleVariableSettings]',
        '[/Script/Engine.DataDrivenConsoleVariableSettings]' + [string][char]10 +
        '+CVarsArray=(Type=CVarInt,Name="DDCvar.Traversal.DrawDebugLevel",DefaultValueInt=99)' + [string][char]10 +
        '+CVarsArray=(Type=CVarInt,Name="DDCvar.MMDatabaseLOD",DefaultValueInt=99)')
    $generatedRuntime = Merge-GasSourceDataDrivenConsoleVariables -TemplateText $runtimeTemplate -SourceDefaultEngineText $sourceEngineFixture
    Assert-True ($generatedRuntime.Contains('Name="DDCVar.CharacterPhysics.DefaultProfile"')) "Source CharacterPhysics.DefaultProfile CVar was not generated."
    Assert-True ($generatedRuntime.Contains('Name="DDCVar.CharacterPhysics.DrawDebug"')) "Source CharacterPhysics.DrawDebug CVar was not generated."
    Assert-True (([regex]::Matches($generatedRuntime, 'Name="DDCVar.CharacterPhysics.DrawDebug"')).Count -eq 1) "Generated runtime config duplicated a source CVar."
    Assert-True ($generatedRuntime -match 'Name="DDCvar\.MMDatabaseLOD"[^\r\n]*DefaultValueInt=3') "Source CVar value did not replace the stale template value."
    Assert-True (-not $generatedRuntime.Contains('DDCvar.Traversal.DrawDebugLevel')) "Static-only CVars leaked into generated source runtime config."
    Assert-True (-not $generatedRuntime.Contains('DDCVar.SourceOnlyRemoval')) "Destructive source CVar operation was imported."
    Assert-True (-not $generatedRuntime.Contains('SourceOnlyDefault')) "Source map setting was imported with CVars."
    [System.IO.File]::WriteAllText($runtimeTemplatePath, $generatedRuntime, [System.Text.UTF8Encoding]::new($false))

    # The conflicting value must occur in the same DataDriven section.
    $conflictingSource = $sourceEngineFixture.Replace('[/Script/EngineSettings.GameMapsSettings]',
        '+CVarsArray=(Type=CVarInt,Name="DDCVar.CharacterPhysics.DrawDebug",DefaultValueInt=99)' + [string][char]10 + '[/Script/EngineSettings.GameMapsSettings]')
    $rejectedConflictingCVar = $false
    try {
        $null = Merge-GasSourceDataDrivenConsoleVariables -TemplateText $runtimeTemplate -SourceDefaultEngineText $conflictingSource
    } catch {
        $rejectedConflictingCVar = [string]$_ -match 'conflicting CVarsArray'
    }
    Assert-True $rejectedConflictingCVar "Conflicting source CVars were silently accepted."

    # A historical package may contain destructive array operations.
    # The import boundary must filter them even when they are in InstallData.
    $assetTemplatePath = Join-Path $installDataRoot "DefaultGame.AssetManager.ini"
    $assetTemplate = Get-Content -LiteralPath $assetTemplatePath -Raw
    $assetTemplate = $assetTemplate.Replace("[/Script/Engine.AssetManagerSettings]", "[/Script/Engine.AssetManagerSettings]" + [string][char]10 +
        '-PrimaryAssetTypesToScan=(PrimaryAssetType="Map",Directories=((Path="/Game/SourceOnlyRemoval")))')
    [System.IO.File]::WriteAllText($assetTemplatePath, $assetTemplate, [System.Text.UTF8Encoding]::new($false))
    $inputTemplatePath = Join-Path $installDataRoot "DefaultInput.InputSettings.ini"
    $inputTemplate = Get-Content -LiteralPath $inputTemplatePath -Raw
    $inputTemplate = $inputTemplate.Replace("[/Script/Engine.InputSettings]", "[/Script/Engine.InputSettings]" + [string][char]10 +
        '-AxisConfig=(AxisKeyName="MouseX",AxisProperties=(Sensitivity=0.01))')
    [System.IO.File]::WriteAllText($inputTemplatePath, $inputTemplate, [System.Text.UTF8Encoding]::new($false))

    # Simulate an old/generated package whose DefaultEngine integration was
    # accidentally built from the source project's full DefaultEngine.ini.
    $runtimeTemplatePath = Join-Path $installDataRoot "DefaultEngine.Runtime.ini"
    $runtimeTemplate = Get-GasNormalizedText -Text (Get-Content -LiteralPath $runtimeTemplatePath -Raw)
    $runtimeTemplate = "UnsafePreamble=True`n" + $runtimeTemplate
    $runtimeTemplate += @"

[/Script/EngineSettings.GameMapsSettings]
GameDefaultMap=/Game/Levels/SampleDefault.SampleDefault
EditorStartupMap=/Game/Levels/SampleEditor.SampleEditor
ServerDefaultMap=/Game/Levels/SampleServer.SampleServer
GlobalDefaultGameMode=/Script/GameAnimationSample.SampleGameMode

[GameAnimationSample.SourceProjectIdentity]
SourceOnlySetting=True
"@
    [System.IO.File]::WriteAllText($runtimeTemplatePath, $runtimeTemplate, [System.Text.UTF8Encoding]::new($false))

    @"
[CoreRedirects]
+PackageRedirects=(OldName="/Game/Legacy/Example",NewName="/GameAnimationSample/Example")
"@ | Set-Content -LiteralPath (Join-Path $installDataRoot "DefaultEngine.PackageRedirects.ini") -NoNewline

    $manifest = [ordered]@{
        PluginName = "GameAnimationSample"
        PluginMountPoint = "/GameAnimationSample"
        BuildVersion = "20260430"
        BuildVersionNumber = 20260430
        RequiredEnginePlugins = @(
            [pscustomobject]@{ Name = "AnimationLocomotionLibrary"; Enabled = $true }
            [pscustomobject]@{ Name = "AnimationWarping"; Enabled = $true }
            [pscustomobject]@{ Name = "Chooser"; Enabled = $true }
            [pscustomobject]@{ Name = "CurveExpression"; Enabled = $true }
            [pscustomobject]@{ Name = "DrawDebugLibrary"; Enabled = $true }
            [pscustomobject]@{ Name = "GameplayInteractions"; Enabled = $true }
            [pscustomobject]@{ Name = "HairStrands"; Enabled = $true }
            [pscustomobject]@{ Name = "LiveLink"; Enabled = $true }
            [pscustomobject]@{ Name = "LiveLinkControlRig"; Enabled = $true }
            [pscustomobject]@{ Name = "Locomotor"; Enabled = $true }
            [pscustomobject]@{ Name = "MetaHumanLiveLink"; Enabled = $true }
            [pscustomobject]@{ Name = "ModelingToolsEditorMode"; Enabled = $true }
            [pscustomobject]@{ Name = "MotionWarping"; Enabled = $true }
            [pscustomobject]@{ Name = "Mover"; Enabled = $true }
            [pscustomobject]@{ Name = "NetworkPrediction"; Enabled = $true }
            [pscustomobject]@{ Name = "PoseSearch"; Enabled = $true }
            [pscustomobject]@{ Name = "RigLogic"; Enabled = $true }
            [pscustomobject]@{ Name = "SmartObjects"; Enabled = $true }
        )
        ManagedIniBlocks = @(
            "DefaultGame.AssetManager",
            "DefaultInput.InputSettings",
            "DefaultGameplayTags.Tags",
            "DefaultEngine.Runtime",
            "DefaultEngine.PackageRedirects",
            "DefaultNetworkPrediction.Settings"
        )
    }

    $manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $Root "GameAnimationSample.install.json") -NoNewline
    $testDescriptor = New-GasPluginDescriptor -PluginName "GameAnimationSample" -VersionName "5.8.test" -Version 1 -EngineVersion "5.8" -PluginDependencies @("PoseSearch")
    Assert-True ($testDescriptor.EngineVersion -eq "5.8.0") "Generated .uplugin EngineVersion must be three-part (5.8.0)."

    @{
        FileVersion = 3
        Version = 20260430
        VersionName = "5.8.20260430-000000"
        FriendlyName = "Game Animation Sample"
        EngineVersion = "5.8.0"
        CanContainContent = $true
    } | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $Root "GameAnimationSample.uplugin") -NoNewline

    # Regression: runtime-tools sync must not replace generated InstallData
    # with the original static Templates (the bug that dropped CharacterPhysics CVars).
    $runtimeBeforeSync = Get-Content -LiteralPath $runtimeTemplatePath -Raw
    $redirectPath = Join-Path $installDataRoot "DefaultEngine.PackageRedirects.ini"
    $redirectsBeforeSync = Get-Content -LiteralPath $redirectPath -Raw
    Sync-GasRuntimeFilesToPackage -RepositoryRoot $RepositoryRoot -PackageRoot $Root
    $runtimeAfterSync = Get-Content -LiteralPath $runtimeTemplatePath -Raw
    $redirectsAfterSync = Get-Content -LiteralPath $redirectPath -Raw
    Assert-True ($runtimeAfterSync -ceq $runtimeBeforeSync) "Tools sync overwrote generated runtime InstallData CVars with a static template."
    Assert-True ($redirectsAfterSync -ceq $redirectsBeforeSync) "Tools sync overwrote generated package redirects."
    Assert-True ($runtimeAfterSync.Contains('Name="DDCVar.CharacterPhysics.DrawDebug"')) "Tools sync removed source CharacterPhysics.DrawDebug CVar."
    Assert-True ($runtimeAfterSync.Contains('Name="DDCVar.CharacterPhysics.DefaultProfile"')) "Tools sync removed source CharacterPhysics.DefaultProfile CVar."
}

function New-ValidationHostProject {
    param([Parameter(Mandatory)][string]$Root)

    New-GasDirectory -Path $Root
    New-GasDirectory -Path (Join-Path $Root "Config")

    @"
{
  "FileVersion": 3,
  "EngineAssociation": "5.8",
  "Category": "",
  "Description": "",
  "Plugins": [
    { "Name": "UnrelatedPlugin", "Enabled": true, "MarketplaceURL": "https://example.invalid" },
    { "Name": "GameAnimationSample", "Enabled": false, "UserNote": "keep me" },
    { "Name": "gameanimationsample", "Enabled": false, "LegacyNote": "duplicate entry from old script" },
    { "Name": "AnimationWarping", "Enabled": true, "UserOwnedField": "preserve me" }
  ]
}
"@ | Set-Content -LiteralPath (Join-Path $Root "ValidationHost.uproject") -NoNewline

    @"
[ProjectSettings]
ExistingUserSetting=True

; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultGame.AssetManager
[/Script/Engine.AssetManagerSettings]
-PrimaryAssetTypesToScan=(PrimaryAssetType="Map",AssetBaseClass=/Script/Engine.World,bHasBlueprintClasses=False,bIsEditorOnly=True,Directories=((Path="/Game/Old")),SpecificAssets=,Rules=(Priority=-1,ChunkId=-1,bApplyRecursively=True,CookRule=Unknown))
; END AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultGame.AssetManager

; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultGame.AssetManager
[/Script/Engine.AssetManagerSettings]
-PrimaryAssetTypesToScan=(PrimaryAssetType="Map",AssetBaseClass=/Script/Engine.World,bHasBlueprintClasses=False,bIsEditorOnly=True,Directories=((Path="/Game/Duplicate")),SpecificAssets=,Rules=(Priority=-1,ChunkId=-1,bApplyRecursively=True,CookRule=Unknown))
; END AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultGame.AssetManager

[/Script/Engine.AssetManagerSettings]
-PrimaryAssetTypesToScan=(PrimaryAssetType="Map",AssetBaseClass=/Script/Engine.World,bHasBlueprintClasses=False,bIsEditorOnly=True,Directories=((Path="/Game/LegacyRaw")),SpecificAssets=,Rules=(Priority=-1,ChunkId=-1,bApplyRecursively=True,CookRule=Unknown))
+PrimaryAssetTypesToScan=(PrimaryAssetType="Map",AssetBaseClass=/Script/Engine.World,bHasBlueprintClasses=False,bIsEditorOnly=True,Directories=((Path="/Game/ValidationGame/Maps")),SpecificAssets=,Rules=(Priority=-1,ChunkId=-1,bApplyRecursively=True,CookRule=Unknown))
+PrimaryAssetTypesToScan=(PrimaryAssetType="PrimaryAssetLabel",AssetBaseClass=/Script/Engine.PrimaryAssetLabel,bHasBlueprintClasses=False,bIsEditorOnly=True,Directories=((Path="/Game/ValidationGame")),SpecificAssets=,Rules=(Priority=-1,ChunkId=-1,bApplyRecursively=True,CookRule=Unknown))

[/Script/ValidationGame.UserSettings]
AlwaysPreserve=True
"@ | Set-Content -LiteralPath (Join-Path $Root "Config\DefaultGame.ini") -NoNewline

    @"
[UserSettings]
ExistingUserSetting=True

[/Script/EngineSettings.GameMapsSettings]
GameDefaultMap=/Game/ValidationGame/Maps/L_Main
EditorStartupMap=/Game/ValidationGame/Maps/L_Editor
ServerDefaultMap=/Game/ValidationGame/Maps/L_Server
TransitionMap=/Game/ValidationGame/Maps/L_Transition
LocalMapOptions=?game=/Game/ValidationGame/Maps/L_Main
GlobalDefaultGameMode=/Script/ValidationGame.ValidationGameGameMode
GlobalDefaultServerGameMode=/Script/ValidationGame.ValidationGameGameMode

[/Script/Engine.DataDrivenConsoleVariableSettings]
+CVarsArray=(Type=CVarInt,Name="DDCVar.CharacterPhysics.DrawDebug",ToolTip="",DefaultValueFloat=0.000000,DefaultValueInt=7,DefaultValueBool=False)
"@ | Set-Content -LiteralPath (Join-Path $Root "Config\DefaultEngine.ini") -NoNewline

    @"
[UserSettings]
ExistingUserSetting=True

[/Script/Engine.InputSettings]
+AxisMappings=(AxisName="HostAction",Scale=1.000000,Key=F)
+AxisConfig=(AxisKeyName="MouseX",AxisProperties=(DeadZone=0.000000,Sensitivity=0.900000,Exponent=1.000000,bInvert=False))

[/Script/ValidationGame.InputConfig]
HostInputSetting=Original
"@ | Set-Content -LiteralPath (Join-Path $Root "Config\DefaultInput.ini") -NoNewline

    @"
[UserSettings]
ExistingUserSetting=True
"@ | Set-Content -LiteralPath (Join-Path $Root "Config\DefaultGameplayTags.ini") -NoNewline

    @"
[UserSettings]
ExistingUserSetting=True
"@ | Set-Content -LiteralPath (Join-Path $Root "Config\DefaultNetworkPrediction.ini") -NoNewline
}

function Copy-GasHostProjectSnapshot {
    param(
        [Parameter(Mandatory)][string]$SourceProjectRoot,
        [Parameter(Mandatory)][string]$DestinationProjectRoot
    )

    New-GasDirectory -Path $DestinationProjectRoot

    $null = Assert-GasSafePath $SourceProjectRoot -Tree
    Assert-GasSeparatePaths $SourceProjectRoot $DestinationProjectRoot
    $uprojectFiles = @(Get-ChildItem -LiteralPath $SourceProjectRoot -Filter *.uproject -File -Force -ErrorAction SilentlyContinue)
    if ($uprojectFiles.Count -ne 1) {
        throw "Expected exactly one .uproject file in '$SourceProjectRoot' when creating a validation snapshot."
    }

    Copy-Item -LiteralPath $uprojectFiles[0].FullName -Destination $DestinationProjectRoot -Force
    foreach ($folder in @("Config", "Plugins")) {
        $sourceFolder = Join-Path $SourceProjectRoot $folder
        if (Test-Path -LiteralPath $sourceFolder) {
            Copy-Item -LiteralPath $sourceFolder -Destination $DestinationProjectRoot -Recurse -Force
        }
    }
}

function Invoke-GasValidation {
    param(
        [Parameter(Mandatory)][string]$SourceHostProject,
        [Parameter(Mandatory)][string]$ResolvedPackageRoot
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gas-toolkit-validation-" + [guid]::NewGuid().ToString("N"))
    New-GasDirectory -Path $tempRoot

    try {
        $hostCloneRoot = Join-Path $tempRoot "HostProject"
        Copy-GasHostProjectSnapshot -SourceProjectRoot $SourceHostProject -DestinationProjectRoot $hostCloneRoot

        $hostContext = Get-GasHostProjectContext -HostProject $hostCloneRoot
        $manifest = Read-GasJson -Path (Get-GasPackageManifestPath -PackageRoot $ResolvedPackageRoot)

        $defaultEnginePath = Join-Path $hostContext.HostProjectRoot "Config\DefaultEngine.ini"
        $initialDefaultEngine = Get-GasNormalizedText -Text (Get-Content -LiteralPath $defaultEnginePath -Raw)
        $expectedHostMaps = Get-GasHostMapSnapshot -Text $initialDefaultEngine
        Assert-GasHostMaps -Text $initialDefaultEngine -ExpectedMaps $expectedHostMaps -Phase "initial host"

        Write-GasMessage -Message "Host project input: $($hostContext.HostProjectPath)"
        Write-GasMessage -Message "Resolved host root: $($hostContext.HostProjectRoot)"
        Write-GasMessage -Message "Resolved host .uproject: $($hostContext.UProjectPath)"
        Write-GasMessage -Message "Package root: $ResolvedPackageRoot"

        $initialHost = Read-GasJson -Path $hostContext.UProjectPath
        $initialPluginMap = Get-NormalizedPluginNameMap -Plugins @($initialHost.Plugins)
        $managedNames = @($manifest.PluginName) + @($manifest.RequiredEnginePlugins | ForEach-Object { [string]$_.Name })
        $alreadyManaged = @(
            $managedNames | Where-Object {
                $normalized = ([string]$_).Trim().ToLowerInvariant()
                $initialPluginMap.Contains($normalized)
            }
        )
        if ($alreadyManaged.Count -gt 0) {
            Write-GasMessage -Level Warn -Message "Snapshot already contains managed plugin entries: $($alreadyManaged -join ', '). They will be reconciled by Name and not duplicated."
        }

        $pluginRoot = Join-Path $hostContext.HostProjectRoot "Plugins\$($manifest.PluginName)"
        if (Test-Path -LiteralPath $pluginRoot) {
            $null = & (Join-Path $RepositoryRoot "Update-GameAnimationSampleInProject.ps1") -HostProject $hostContext.HostProjectRoot -PackageRoot $ResolvedPackageRoot
        } else {
            $null = & (Join-Path $RepositoryRoot "Install-GameAnimationSampleToProject.ps1") -HostProject $hostContext.HostProjectRoot -PackageRoot $ResolvedPackageRoot
        }

        # The host's pre-existing primary asset types must each remain a single
        # entry while receiving the new plugin search directory.
        $assetPath = Join-Path $hostContext.HostProjectRoot "Config\DefaultGame.ini"
        $afterInstallAssetManager = Get-GasNormalizedText -Text (Get-Content -LiteralPath $assetPath -Raw)
        foreach ($type in @("Map", "PrimaryAssetLabel")) {
            $typeEntries = @([regex]::Matches($afterInstallAssetManager, '(?m)^\+PrimaryAssetTypesToScan=\(PrimaryAssetType="' + $type + '"'))
            Assert-True ($typeEntries.Count -eq 1) "Install duplicated the host '$type' asset scanner."
        }
        foreach ($pathFragment in @('/Game/ValidationGame/Maps', '/Game/ValidationGame', '/GameAnimationSample/Levels', '/GameAnimationSample')) {
            Assert-True ($afterInstallAssetManager.Contains('Path="' + $pathFragment + '"')) "Install lost asset search directory '$pathFragment'."
        }
        Assert-True (([regex]::Matches($afterInstallAssetManager, 'Path="/GameAnimationSample/Levels"')).Count -eq 1) "Plugin map path was duplicated during install."
        Assert-True ($afterInstallAssetManager.Contains("AlwaysPreserve=True")) "Unrelated AssetManager INI content was lost."
        Assert-True (-not $afterInstallAssetManager.Contains("/Game/SourceOnlyRemoval")) "Old source template removed a host AssetManager path."
        Assert-True ($afterInstallAssetManager.Contains('-PrimaryAssetTypesToScan=(PrimaryAssetType="Map"')) "Install removed a user-owned array operation."

        $inputPath = Join-Path $hostContext.HostProjectRoot "Config\DefaultInput.ini"
        $afterInstallInput = Get-GasNormalizedText -Text (Get-Content -LiteralPath $inputPath -Raw)
        Assert-True ($afterInstallInput.Contains('Sensitivity=0.900000')) "Host-specific input tuning was changed."
        Assert-True ($afterInstallInput.Contains('HostInputSetting=Original')) "Unrelated host input section was changed."
        Assert-True ($afterInstallInput -notmatch '(?m)^-AxisConfig=') "Toolkit emitted destructive input-array entries."
        Assert-True ($afterInstallInput -notmatch "Sensitivity=0.01") "Old source template changed host axis configuration."

        $afterInstallDefaultEngine = Get-GasNormalizedText -Text (Get-Content -LiteralPath $defaultEnginePath -Raw)
        Assert-GasHostMaps -Text $afterInstallDefaultEngine -ExpectedMaps $expectedHostMaps -Phase "after install"
        $drawDebugLines = @([regex]::Matches($afterInstallDefaultEngine, '(?im)^\+CVarsArray=\([^\r\n]*Name="DDCVar\.CharacterPhysics\.DrawDebug"[^\r\n]*$'))
        Assert-True ($drawDebugLines.Count -eq 1) "Host-owned CharacterPhysics.DrawDebug CVar was duplicated or removed."
        Assert-True ($drawDebugLines[0].Value -match 'DefaultValueInt=7') "Host-owned CVar default was overwritten by the sample."
        $defaultProfileLines = @([regex]::Matches($afterInstallDefaultEngine, '(?im)^\+CVarsArray=\([^\r\n]*Name="DDCVar\.CharacterPhysics\.DefaultProfile"[^\r\n]*$'))
        Assert-True ($defaultProfileLines.Count -eq 1) "CharacterPhysics.DefaultProfile CVar was not added from the source."
        Assert-True ($defaultProfileLines[0].Value -match 'DefaultValueInt=1') "Imported CharacterPhysics.DefaultProfile default is incorrect."
        Assert-True ($afterInstallDefaultEngine -notmatch "UnsafePreamble|SampleDefault|SampleEditor|SampleServer|SampleGameMode|SourceOnlySetting") "Install copied source project map/identity settings into the host."

        # Simulate a prior toolkit version that put sample map selection inside
        # the Axchemy-managed runtime block. The next update must remove it.
        $runtimeBegin = "; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultEngine.Runtime"
        $legacyManagedMaps = @"
[/Script/EngineSettings.GameMapsSettings]
GameDefaultMap=/Game/Levels/LegacyManagedSample.LegacyManagedSample
EditorStartupMap=/Game/Levels/LegacyManagedSample.LegacyManagedSample
GlobalDefaultGameMode=/Script/GameAnimationSample.LegacySampleGameMode
"@
        $legacyRuntimeText = $afterInstallDefaultEngine.Replace($runtimeBegin, "$runtimeBegin`n$($legacyManagedMaps.Trim())")
        [System.IO.File]::WriteAllText($defaultEnginePath, $legacyRuntimeText, [System.Text.UTF8Encoding]::new($false))
        Assert-True ($legacyRuntimeText -match "LegacyManagedSample") "Failed to prepare the legacy managed map migration fixture."

        $null = & (Join-Path $RepositoryRoot "Update-GameAnimationSampleInProject.ps1") -HostProject $hostContext.HostProjectRoot -PackageRoot $ResolvedPackageRoot
        $afterFirstUpdateDefaultEngine = Get-GasNormalizedText -Text (Get-Content -LiteralPath $defaultEnginePath -Raw)
        Assert-GasHostMaps -Text $afterFirstUpdateDefaultEngine -ExpectedMaps $expectedHostMaps -Phase "after first update"
        Assert-True ($afterFirstUpdateDefaultEngine -notmatch "SampleDefault|SampleEditor|SampleServer|SampleGameMode|LegacyManagedSample|LegacySampleGameMode|SourceOnlySetting") "Sample map or source identity settings survived managed-block migration."

        $firstUpdateDefaultEngine = $afterFirstUpdateDefaultEngine
        $null = & (Join-Path $RepositoryRoot "Update-GameAnimationSampleInProject.ps1") -HostProject $hostContext.HostProjectRoot -PackageRoot $ResolvedPackageRoot
        $afterSecondUpdateDefaultEngine = Get-GasNormalizedText -Text (Get-Content -LiteralPath $defaultEnginePath -Raw)
        Assert-GasHostMaps -Text $afterSecondUpdateDefaultEngine -ExpectedMaps $expectedHostMaps -Phase "after second update"
        Assert-True ($afterSecondUpdateDefaultEngine -eq $firstUpdateDefaultEngine) "DefaultEngine.ini changed between repeated updates."

        $finalAssetManager = Get-GasNormalizedText -Text (Get-Content -LiteralPath $assetPath -Raw)
        $finalInput = Get-GasNormalizedText -Text (Get-Content -LiteralPath $inputPath -Raw)
        Assert-True ($finalAssetManager -eq $afterInstallAssetManager) "DefaultGame.ini changed between updates (map path or entries duplicated)."
        Assert-True ($finalInput -eq $afterInstallInput) "DefaultInput.ini changed between updates."
        foreach ($fragment in @('/Game/ValidationGame/Maps', '/Game/ValidationGame', '/GameAnimationSample/Levels')) {
            Assert-True ($finalAssetManager.Contains('Path="' + $fragment + '"')) "Update removed or changed an original host asset path."
        }
        $defaultGameManaged = [regex]::Match($finalAssetManager, "(?ms)^; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultGame\.AssetManager\n(?<Block>.*?)^; END AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultGame\.AssetManager$")
        if ($defaultGameManaged.Success) {
            Assert-True ($defaultGameManaged.Groups["Block"].Value.Contains("[/Script/Engine.AssetManagerSettings]")) "Generated AssetManager block is missing its INI section header."
        }
        $inputManaged = [regex]::Match($finalInput, "(?ms)^; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultInput\.InputSettings\n(?<Block>.*?)^; END AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultInput\.InputSettings$")
        Assert-True ($inputManaged.Success -and $inputManaged.Groups["Block"].Value.Contains("[/Script/Engine.InputSettings]")) "Generated input block is missing its INI section header."

        $runtimeBlockMatch = [regex]::Match($afterSecondUpdateDefaultEngine, "(?ms)^; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultEngine\.Runtime\n(?<Block>.*?)^; END AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultEngine\.Runtime$")
        if ($runtimeBlockMatch.Success) {
            Assert-True ($runtimeBlockMatch.Groups["Block"].Value -notmatch "GameMapsSettings|GameDefaultMap|EditorStartupMap|ServerDefaultMap|TransitionMap|LocalMapOptions|GlobalDefaultGameMode|GlobalDefaultServerGameMode") "Managed runtime block still contains host-owned map/game-mode settings."
        }

        Assert-True ($afterSecondUpdateDefaultEngine -match "fx\.Niagara\.ForceLastTickGroup=1") "Required console variable integration was not installed."
        Assert-True ($afterSecondUpdateDefaultEngine -match "p\.EnableCharacterAccelerationReplication=1") "Required runtime console variable integration was not installed."
        Assert-True ($afterSecondUpdateDefaultEngine -match "bTickPhysicsAsync=False") "Required physics integration was not installed."
        Assert-True ($afterSecondUpdateDefaultEngine -match "DefaultChannelResponses=.*Traversable") "Required collision channel integration was not installed."
        Assert-True ($afterSecondUpdateDefaultEngine -match "bAllowClientSideNavigation=False") "Required navigation integration was not installed."

        $networkPredictionText = Get-GasNormalizedText -Text (Get-Content -LiteralPath (Join-Path $hostContext.HostProjectRoot "Config\DefaultNetworkPrediction.ini") -Raw)
        Assert-True ($networkPredictionText -match "\[/Script/NetworkPrediction\.NetworkPredictionSettingsObject\]") "Required NetworkPrediction section was not installed."
        Assert-True ($networkPredictionText -match "Settings=\(PreferredTickingPolicy=Independent") "Required NetworkPrediction settings were not installed."

        $expectedBackupRoot = Join-Path $hostContext.HostProjectRoot "Saved\GameAnimationSampleToolkit\Backups"
        $legacyBackupRoot = Join-Path $hostContext.HostProjectRoot "Plugins\_Backups"
        Assert-True (Test-Path -LiteralPath $expectedBackupRoot) "Expected update backups under '$expectedBackupRoot'."
        Assert-True (-not (Test-Path -LiteralPath $legacyBackupRoot)) "Expected no update backups under '$legacyBackupRoot'."

        $backupDirectories = @(Get-ChildItem -LiteralPath $expectedBackupRoot -Directory -Filter "$($manifest.PluginName)-*" -ErrorAction SilentlyContinue)
        Assert-True ($backupDirectories.Count -ge 2) "Expected at least two update backups under '$expectedBackupRoot'."
        foreach ($backupDirectory in $backupDirectories) {
            Assert-True ($backupDirectory.Name -match "^$([regex]::Escape($manifest.PluginName))-\d{8}-\d{6}(?:-\d+)?$") "Expected timestamped backup name, got '$($backupDirectory.Name)'."
            Assert-GasHostPluginLayout -HostPluginRoot $backupDirectory.FullName -PluginName $manifest.PluginName
        }

        Assert-GasHostPluginLayout -HostPluginRoot (Join-Path $hostContext.HostProjectRoot "Plugins\$($manifest.PluginName)") -PluginName $manifest.PluginName

        $managedPrefix = "AXCHEMY-GAME-ANIMATION-SAMPLE"
        $blockMap = [ordered]@{
            "DefaultGame.ini" = "DefaultGame.AssetManager"
            "DefaultInput.ini" = "DefaultInput.InputSettings"
            "DefaultGameplayTags.ini" = "DefaultGameplayTags.Tags"
            "DefaultEngine.ini" = @("DefaultEngine.Runtime", "DefaultEngine.PackageRedirects")
            "DefaultNetworkPrediction.ini" = "DefaultNetworkPrediction.Settings"
        }

        foreach ($file in $blockMap.Keys) {
            $text = Get-Content -LiteralPath (Join-Path $hostContext.HostProjectRoot "Config\$file") -Raw
            $hadSyntheticUserSetting = $text -match "ExistingUserSetting=True"
            foreach ($blockId in @($blockMap[$file])) {
                $marker = "; BEGIN $managedPrefix::$blockId"
                $count = Get-RegexCount -Text $text -Pattern ([regex]::Escape($marker))
                if ($count -gt 0) {
                    Assert-True ($count -eq 1) "Expected one managed block for '$blockId' in '$file'."
                }
            }
            if ($hadSyntheticUserSetting) {
                Assert-True ($text -match "ExistingUserSetting=True") "Expected user settings to remain in '$file'."
            }
        }

        $finalHost = Read-GasJson -Path $hostContext.UProjectPath
        foreach ($name in $managedNames) {
            $matches = @($finalHost.Plugins | Where-Object { [string]$_.Name -ieq $name })
            Assert-True ($matches.Count -eq 1) "Expected exactly one plugin entry for '$name'."
            Assert-True ($matches[0].Enabled -eq $true) "Expected plugin '$name' to be enabled."
        }

        Assert-True ((@($finalHost.Plugins | Where-Object { [string]$_.Name -ceq "gameanimationsample" })).Count -eq 0) "Expected duplicate casing entry to be collapsed."
        if ((@($initialHost.Plugins | Where-Object { [string]$_.Name -eq "UnrelatedPlugin" })).Count -gt 0) {
            Assert-True ((@($finalHost.Plugins | Where-Object { [string]$_.Name -eq "UnrelatedPlugin" })).Count -eq 1) "Expected unrelated plugin entry to remain untouched."
        }
        if ($initialPluginMap.Contains("gameanimationsample") -and ($initialPluginMap["gameanimationsample"].Entries[0].PSObject.Properties.Name -contains "UserNote")) {
            Assert-True ((@($finalHost.Plugins | Where-Object { [string]$_.Name -ieq "GameAnimationSample" -and $_.PSObject.Properties.Name -contains "UserNote" -and [string]$_.UserNote -eq "keep me" })).Count -eq 1) "Expected host-owned plugin metadata to survive reconciliation."
        }
        if ($initialPluginMap.Contains("animationwarping") -and ($initialPluginMap["animationwarping"].Entries[0].PSObject.Properties.Name -contains "UserOwnedField")) {
            Assert-True ((@($finalHost.Plugins | Where-Object { [string]$_.Name -ieq "AnimationWarping" -and $_.PSObject.Properties.Name -contains "UserOwnedField" -and [string]$_.UserOwnedField -eq "preserve me" })).Count -eq 1) "Expected user-owned fields on required plugin entries to be preserved."
        }

        # Inject an invalid managed marker in the clone. The update must fail
        # and restore every file modified earlier in the same transaction.
        $beforeFailure = @{}
        foreach ($name in @("DefaultGame.ini", "DefaultInput.ini", "DefaultEngine.ini", "DefaultGameplayTags.ini", "DefaultNetworkPrediction.ini")) {
            $file = Join-Path $hostContext.HostProjectRoot ("Config\" + $name)
            $beforeFailure[$name] = Get-GasNormalizedText -Text (Get-Content -LiteralPath $file -Raw)
        }
        $beforeFailureUProject = Get-GasNormalizedText -Text (Get-Content -LiteralPath $hostContext.UProjectPath -Raw)
        $beforeFailurePlugin = Get-GasNormalizedText -Text (Get-Content -LiteralPath (Join-Path $pluginRoot "GameAnimationSample.host-install.json") -Raw)
        Add-Content -LiteralPath $inputPath -Value "; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::DefaultInput.InputSettings"
        $malformedInput = Get-GasNormalizedText -Text (Get-Content -LiteralPath $inputPath -Raw)
        $failedAsExpected = $false
        try {
            $null = & (Join-Path $RepositoryRoot "Update-GameAnimationSampleInProject.ps1") -HostProject $hostContext.HostProjectRoot -PackageRoot $ResolvedPackageRoot
        }
        catch {
            $failedAsExpected = [string]$_ -match "Malformed managed block"
        }
        Assert-True $failedAsExpected "Malformed INI marker did not fail closed."
        foreach ($name in $beforeFailure.Keys) {
            $file = Join-Path $hostContext.HostProjectRoot ("Config\" + $name)
            $currentContent = Get-GasNormalizedText -Text (Get-Content -LiteralPath $file -Raw)
            $expectedContent = if ($name -eq "DefaultInput.ini") { $malformedInput } else { $beforeFailure[$name] }
            Assert-True ($currentContent -eq $expectedContent) "Update failure modified host file '$name' despite rollback."
        }
        Assert-True ((Get-GasNormalizedText -Text (Get-Content -LiteralPath $hostContext.UProjectPath -Raw)) -eq $beforeFailureUProject) "Update failure changed .uproject despite rollback."
        Assert-True ((Get-GasNormalizedText -Text (Get-Content -LiteralPath (Join-Path $pluginRoot "GameAnimationSample.host-install.json") -Raw)) -eq $beforeFailurePlugin) "Update failure changed installed plugin despite rollback."

        # A brand-new Blank project can have no Plugins member in its .uproject.
        # Test this separately from the duplicate-entry legacy fixture.
        $blankHost = Join-Path $tempRoot "BlankHost"
        New-GasDirectory -Path $blankHost
        $blankUProject = Join-Path $blankHost "BlankHost.uproject"
        [System.IO.File]::WriteAllText($blankUProject, '{"FileVersion":3,"EngineAssociation":"5.8","Description":"Preserve me"}', [System.Text.UTF8Encoding]::new($false))
        $null = & (Join-Path $RepositoryRoot "Install-GameAnimationSampleToProject.ps1") -HostProject $blankUProject -PackageRoot $ResolvedPackageRoot
        $blankAfterInstall = Read-GasJson -Path $blankUProject
        Assert-True ($blankAfterInstall.Plugins.Count -gt 0) "Install failed to add a Plugins array to a blank .uproject."
        Assert-True ($blankAfterInstall.Description -eq "Preserve me") "Install changed unrelated fields on a blank .uproject."
        $blankRuntimeIni = Get-GasNormalizedText -Text (Get-Content -LiteralPath (Join-Path $blankHost "Config\DefaultEngine.ini") -Raw)
        foreach ($cvarName in @("DDCVar.CharacterPhysics.DrawDebug", "DDCVar.CharacterPhysics.DefaultProfile")) {
            $cvarPattern = 'Name="' + [regex]::Escape($cvarName) + '"'
            Assert-True (([regex]::Matches($blankRuntimeIni, $cvarPattern)).Count -eq 1) "Blank host did not receive exactly one '$cvarName'."
        }

        $null = & (Join-Path $RepositoryRoot "Update-GameAnimationSampleInProject.ps1") -HostProject $blankUProject -PackageRoot $ResolvedPackageRoot
        $blankRuntimeAfterUpdate = Get-GasNormalizedText -Text (Get-Content -LiteralPath (Join-Path $blankHost "Config\DefaultEngine.ini") -Raw)
        $blankAfterUpdate = Get-GasNormalizedText -Text (Get-Content -LiteralPath $blankUProject -Raw)
        $null = & (Join-Path $RepositoryRoot "Update-GameAnimationSampleInProject.ps1") -HostProject $blankUProject -PackageRoot $ResolvedPackageRoot
        Assert-True ((Get-GasNormalizedText -Text (Get-Content -LiteralPath $blankUProject -Raw)) -eq $blankAfterUpdate) "Blank host .uproject duplicated entries across updates."
        Assert-True ((Get-GasNormalizedText -Text (Get-Content -LiteralPath (Join-Path $blankHost "Config\DefaultEngine.ini") -Raw)) -eq $blankRuntimeAfterUpdate) "Blank host DefaultEngine.ini changed between repeated updates."

        # A host collision channel must never be silently replaced. Exercise the
        # actual updater (including replacement and rollback), not a helper stub.
        $blankEngine = Join-Path $blankHost "Config\DefaultEngine.ini"
        Add-Content -LiteralPath $blankEngine -Value @"

[/Script/Engine.CollisionProfile]
+DefaultChannelResponses=(Channel=ECC_GameTraceChannel1,DefaultResponse=ECR_Block,bTraceType=True,bStaticObject=False,Name="HostReservedChannel")
"@
        $originalBlankEngine = Get-GasNormalizedText -Text (Get-Content -LiteralPath $blankEngine -Raw)
        $blankInstalledManifest = Join-Path $blankHost "Plugins\GameAnimationSample\GameAnimationSample.host-install.json"
        $originalInstalledManifest = Get-GasNormalizedText -Text (Get-Content -LiteralPath $blankInstalledManifest -Raw)
        $collisionDetected = $false
        try {
            $null = & (Join-Path $RepositoryRoot "Update-GameAnimationSampleInProject.ps1") -HostProject $blankUProject -PackageRoot $ResolvedPackageRoot
        }
        catch {
            $collisionDetected = [string]$_ -match "Host conflict"
        }
        Assert-True $collisionDetected "Update overwrote a user-owned collision channel instead of failing."
        Assert-True ((Get-GasNormalizedText -Text (Get-Content -LiteralPath $blankEngine -Raw)) -eq $originalBlankEngine) "Conflict rollback changed the host's collision settings."
        Assert-True ((Get-GasNormalizedText -Text (Get-Content -LiteralPath $blankInstalledManifest -Raw)) -eq $originalInstalledManifest) "Conflict rollback failed to restore the previous plugin manifest."

        # Simulate a broken replacement package that passes manifest discovery
        # but lacks Tools/. This fails *inside* package replacement before a
        # backup path can be returned; the old installed plugin must recover.
        $malformedSourceParent = Join-Path $tempRoot "MalformedSource"
        New-GasDirectory -Path $malformedSourceParent
        $malformedPackage = Join-Path $malformedSourceParent "GameAnimationSample"
        Copy-Item -LiteralPath $ResolvedPackageRoot -Destination $malformedPackage -Recurse -Force
        Remove-Item -LiteralPath (Join-Path $malformedPackage "Tools") -Recurse -Force
        $oldPluginDescriptor = Get-GasNormalizedText -Text (Get-Content -LiteralPath (Join-Path $blankHost "Plugins\GameAnimationSample\GameAnimationSample.uplugin") -Raw)
        $badPackageRejected = $false
        try {
            $null = & (Join-Path $RepositoryRoot "Update-GameAnimationSampleInProject.ps1") -HostProject $blankUProject -PackageRoot $malformedPackage
        }
        catch {
            $badPackageRejected = [string]$_ -match "Invalid installed plugin layout"
        }
        Assert-True $badPackageRejected "Updater accepted a malformed replacement package."
        Assert-GasHostPluginLayout -HostPluginRoot (Join-Path $blankHost "Plugins\GameAnimationSample") -PluginName "GameAnimationSample"
        Assert-True ((Get-GasNormalizedText -Text (Get-Content -LiteralPath (Join-Path $blankHost "Plugins\GameAnimationSample\GameAnimationSample.uplugin") -Raw)) -eq $oldPluginDescriptor) "Broken package replacement did not restore original plugin files."
        Assert-True ((Get-GasNormalizedText -Text (Get-Content -LiteralPath $blankInstalledManifest -Raw)) -eq $originalInstalledManifest) "Broken package replacement did not restore installed manifest."

        Write-Host "Validation succeeded. Clone root: $hostCloneRoot"
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

if ($PSBoundParameters.ContainsKey("HostProject") -and $PSBoundParameters.ContainsKey("PackageRoot")) {
    $resolvedPackageRoot = Get-GasToolkitRootFromPackage -BasePath $PackageRoot
    Invoke-GasValidation -SourceHostProject $HostProject -ResolvedPackageRoot $resolvedPackageRoot
    return
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gas-toolkit-validation-" + [guid]::NewGuid().ToString("N"))
New-GasDirectory -Path $tempRoot
try {
    $packageRootRoot = Join-Path $tempRoot "GameAnimationSample"
    $hostRoot = Join-Path $tempRoot "HostProject"
    New-ValidationPackageRoot -Root $packageRootRoot
    New-ValidationHostProject -Root $hostRoot
    Invoke-GasValidation -SourceHostProject $hostRoot -ResolvedPackageRoot $packageRootRoot
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
