Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ToolkitName = "GameAnimationSample"
$script:ManagedPrefix = "AXCHEMY-GAME-ANIMATION-SAMPLE"

$script:GasHostOwnedIniKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($key in @(
    "GameDefaultMap",
    "EditorStartupMap",
    "ServerDefaultMap",
    "TransitionMap",
    "LocalMapOptions",
    "GlobalDefaultGameMode",
    "GlobalDefaultServerGameMode"
)) {
    [void]$script:GasHostOwnedIniKeys.Add($key)
}

function Write-GasMessage {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("Info", "Warn", "Error", "Success")][string]$Level = "Info"
    )

    $color = switch ($Level) {
        "Info" { "Cyan" }
        "Warn" { "Yellow" }
        "Error" { "Red" }
        "Success" { "Green" }
    }

    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Get-GasRepositoryRoot {
    param([string]$StartPath)

    $current = if ($StartPath) {
        (Resolve-Path -LiteralPath $StartPath).Path
    } else {
        (Resolve-Path -LiteralPath $PSScriptRoot).Path
    }

    while ($true) {
        $templatesPath = Join-Path $current "Templates"
        $scriptsPath = Join-Path $current "Scripts"
        if ((Test-Path -LiteralPath $templatesPath) -and (Test-Path -LiteralPath $scriptsPath)) {
            return $current
        }

        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            break
        }

        $current = $parent
    }

    return (Resolve-Path -LiteralPath $PSScriptRoot).Path
}

function Get-GasProjectRoot {
    param([string]$ProjectRoot)

    if (-not $ProjectRoot) {
        throw "ProjectRoot is required."
    }

    return (Resolve-Path -LiteralPath $ProjectRoot).Path
}

function Get-GasHostProjectContext {
    param([Parameter(Mandatory)][string]$HostProject)

    $resolvedHostProject = (Resolve-Path -LiteralPath $HostProject).Path
    if ($resolvedHostProject -match '\.uproject$') {
        return [pscustomobject]@{
            HostProjectPath = $resolvedHostProject
            HostProjectRoot = Split-Path -Parent $resolvedHostProject
            UProjectPath = $resolvedHostProject
        }
    }

    $uprojectFiles = @(Get-ChildItem -LiteralPath $resolvedHostProject -Filter *.uproject -File -Force -ErrorAction SilentlyContinue)
    if ($uprojectFiles.Count -eq 1) {
        return [pscustomobject]@{
            HostProjectPath = $resolvedHostProject
            HostProjectRoot = $resolvedHostProject
            UProjectPath = $uprojectFiles[0].FullName
        }
    }

    if ($uprojectFiles.Count -eq 0) {
        $recursiveUProjectFiles = @(Get-ChildItem -LiteralPath $resolvedHostProject -Recurse -Filter *.uproject -File -Force -ErrorAction SilentlyContinue)
        if ($recursiveUProjectFiles.Count -eq 1) {
            return [pscustomobject]@{
                HostProjectPath = $resolvedHostProject
                HostProjectRoot = Split-Path -Parent $recursiveUProjectFiles[0].FullName
                UProjectPath = $recursiveUProjectFiles[0].FullName
            }
        }

        if ($recursiveUProjectFiles.Count -gt 1) {
            $names = ($recursiveUProjectFiles | Select-Object -ExpandProperty FullName) -join ", "
            throw "Multiple .uproject files were found under '$resolvedHostProject': $names. Pass the exact .uproject path."
        }
    }

    if ($uprojectFiles.Count -gt 1) {
        $names = ($uprojectFiles | Select-Object -ExpandProperty Name) -join ", "
        throw "More than one .uproject file was found in '$resolvedHostProject': $names. Pass the exact .uproject path."
    }

    throw "No .uproject file was found in '$resolvedHostProject'. Pass the project .uproject path or a folder containing exactly one .uproject."
}

function New-GasDirectory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Read-GasJson {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        throw "Expected a file path but received a directory: '$Path'."
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
}

function Get-GasNormalizedText {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }

    return ($Text -replace "`r`n", "`n" -replace "`r", "`n")
}

function Get-GasPrettyJson {
    param([Parameter(Mandatory)]$Value)

    return (Get-GasNormalizedText -Text ($Value | ConvertTo-Json -Depth 100)).TrimEnd() + "`n"
}

function Get-GasHostIntegrationBlockDefinitions {
    return @(
        [pscustomobject]@{
            IniFile = "DefaultGame.ini"
            Id = "DefaultGame.AssetManager"
            Template = "DefaultGame.AssetManager.ini"
            Generated = $false
        }
        [pscustomobject]@{
            IniFile = "DefaultInput.ini"
            Id = "DefaultInput.InputSettings"
            Template = "DefaultInput.InputSettings.ini"
            Generated = $false
        }
        [pscustomobject]@{
            IniFile = "DefaultGameplayTags.ini"
            Id = "DefaultGameplayTags.Tags"
            Template = "DefaultGameplayTags.Tags.ini"
            Generated = $false
        }
        [pscustomobject]@{
            IniFile = "DefaultEngine.ini"
            Id = "DefaultEngine.Runtime"
            Template = "DefaultEngine.Runtime.ini"
            Generated = $false
        }
        [pscustomobject]@{
            IniFile = "DefaultEngine.ini"
            Id = "DefaultEngine.PackageRedirects"
            Template = "DefaultEngine.PackageRedirects.ini"
            Generated = $true
        }
        [pscustomobject]@{
            IniFile = "DefaultNetworkPrediction.ini"
            Id = "DefaultNetworkPrediction.Settings"
            Template = "DefaultNetworkPrediction.Settings.ini"
            Generated = $false
        }
    )
}

function Get-GasHostIntegrationRules {
    param([Parameter(Mandatory)][string]$BlockId)

    switch ($BlockId) {
        "DefaultGame.Staging" {
            return @{ "Staging" = @{ "AllowedConfigFiles" = "Array" } }
        }
        "DefaultGame.AssetManager" {
            return @{
                "/Script/Engine.AssetManagerSettings" = @{
                    "PrimaryAssetTypesToScan" = "Array"
                    "bOnlyCookProductionAssets" = "Scalar"
                    "bShouldManagerDetermineTypeAndName" = "Scalar"
                    "bShouldGuessTypeAndNameInEditor" = "Scalar"
                    "bShouldAcquireMissingChunksOnLoad" = "Scalar"
                    "bShouldWarnAboutInvalidAssets" = "Scalar"
                    "MetaDataTagsForAssetRegistry" = "Scalar"
                }
            }
        }
        "DefaultInput.InputSettings" {
            return @{
                "/Script/Engine.InputSettings" = @{
                    "AxisConfig" = "Array"
                    "AxisMappings" = "Array"
                    "bAltEnterTogglesFullscreen" = "Scalar"
                    "bF11TogglesFullscreen" = "Scalar"
                    "bUseMouseForTouch" = "Scalar"
                    "bEnableMouseSmoothing" = "Scalar"
                    "bEnableFOVScaling" = "Scalar"
                    "bCaptureMouseOnLaunch" = "Scalar"
                    "bEnableLegacyInputScales" = "Scalar"
                    "bEnableMotionControls" = "Scalar"
                    "bFilterInputByPlatformUser" = "Scalar"
                    "bShouldFlushPressedKeysOnViewportFocusLost" = "Scalar"
                    "bAlwaysShowTouchInterface" = "Scalar"
                    "bShowConsoleOnFourFingerTap" = "Scalar"
                    "bEnableGestureRecognizer" = "Scalar"
                    "bUseAutocorrect" = "Scalar"
                    "DefaultViewportMouseCaptureMode" = "Scalar"
                    "DefaultViewportMouseLockMode" = "Scalar"
                    "FOVScale" = "Scalar"
                    "DoubleClickTime" = "Scalar"
                    "DefaultPlayerInputClass" = "Scalar"
                    "DefaultInputComponentClass" = "Scalar"
                    "DefaultTouchInterface" = "Scalar"
                    "ConsoleKeys" = "Array"
                }
            }
        }
        "DefaultGameplayTags.Tags" {
            return @{
                "/Script/GameplayTags.GameplayTagsSettings" = @{
                    "ImportTagsFromConfig" = "Scalar"
                    "WarnOnInvalidTags" = "Scalar"
                    "ClearInvalidTags" = "Scalar"
                    "AllowEditorTagUnloading" = "Scalar"
                    "AllowGameTagUnloading" = "Scalar"
                    "FastReplication" = "Scalar"
                    "bDynamicReplication" = "Scalar"
                    "InvalidTagCharacters" = "Scalar"
                    "NumBitsForContainerSize" = "Scalar"
                    "NetIndexFirstBitSegment" = "Scalar"
                    "GameplayTagRedirects" = "Array"
                    "GameplayTagList" = "Array"
                }
            }
        }
        "DefaultEngine.Runtime" {
            return @{
                "ConsoleVariables" = @{
                    "fx.Niagara.ForceLastTickGroup" = "Scalar"
                    "p.EnableCharacterAccelerationReplication" = "Scalar"
                    "net.SubObjects.DefaultUseSubObjectReplicationList" = "Scalar"
                }
                "/Script/Engine.DataDrivenConsoleVariableSettings" = @{
                    "CVarsArray" = "Array"
                }
                "/Script/Engine.PhysicsSettings" = @{
                    "bTickPhysicsAsync" = "Scalar"
                }
                "/Script/Engine.CollisionProfile" = @{
                    "Profiles" = "Array"
                    "DefaultChannelResponses" = "Array"
                    "EditProfiles" = "Array"
                    "ProfileRedirects" = "Array"
                }
                "/Script/NavigationSystem.NavigationSystemV1" = @{
                    "bAllowClientSideNavigation" = "Scalar"
                }
                "/Script/PoseSearch.PoseSearchSettings" = @{
                    "AvailabilitiesBufferSize" = "Scalar"
                }
            }
        }
        "DefaultEngine.PackageRedirects" {
            return @{
                "CoreRedirects" = @{
                    "PackageRedirects" = "Array"
                }
            }
        }
        "DefaultNetworkPrediction.Settings" {
            return @{
                "/Script/NetworkPrediction.NetworkPredictionSettingsObject" = @{
                    "Settings" = "Scalar"
                }
            }
        }
        default {
            return $null
        }
    }
}

function Get-GasIniLineInfo {
    param([AllowEmptyString()][string]$Line)

    $trimmed = if ($null -eq $Line) { "" } else { $Line.Trim() }
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return [pscustomobject]@{
            Kind = "Blank"
            Section = $null
            Key = $null
            Value = $null
            Operator = ""
            IsArrayOperation = $false
        }
    }

    if ($trimmed.StartsWith(";") -or $trimmed.StartsWith("#")) {
        return [pscustomobject]@{
            Kind = "Comment"
            Section = $null
            Key = $null
            Value = $null
            Operator = ""
            IsArrayOperation = $false
        }
    }

    if ($trimmed -match '^\[(?<Section>.*)\]$') {
        return [pscustomobject]@{
            Kind = "Section"
            Section = $Matches.Section.Trim()
            Key = $null
            Value = $null
            Operator = ""
            IsArrayOperation = $false
        }
    }

    $equalsIndex = $trimmed.IndexOf("=")
    if ($equalsIndex -lt 1) {
        return [pscustomobject]@{
            Kind = "Other"
            Section = $null
            Key = $null
            Value = $null
            Operator = ""
            IsArrayOperation = $false
        }
    }

    $assignment = $trimmed
    $operator = ""
    if ($assignment.StartsWith("+") -or $assignment.StartsWith("-") -or $assignment.StartsWith("!") -or $assignment.StartsWith(".")) {
        $operator = $assignment.Substring(0, 1)
        $assignment = $assignment.Substring(1)
    }

    $key = $assignment.Substring(0, $assignment.IndexOf("=")).Trim()
    if ([string]::IsNullOrWhiteSpace($key)) {
        return [pscustomobject]@{
            Kind = "Other"
            Section = $null
            Key = $null
            Value = $null
            Operator = $operator
            IsArrayOperation = $false
        }
    }

    return [pscustomobject]@{
        Kind = "Assignment"
        Section = $null
        Key = $key
        Value = $assignment.Substring($assignment.IndexOf("=") + 1).Trim()
        Operator = $operator
        IsArrayOperation = $operator -in @("+", "-", "!", ".")
    }
}

function Test-GasHostOwnedIniSetting {
    param([Parameter(Mandatory)]$LineInfo)

    if ($LineInfo.Kind -ne "Assignment") {
        return $false
    }

    if ($script:GasHostOwnedIniKeys.Contains($LineInfo.Key)) {
        return $true
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$LineInfo.Section) -and
        [string]$LineInfo.Section -match '(?i)(^|/)EngineSettings\.GameMapsSettings$') {
        return $true
    }

    return $false
}

function Remove-GasHostOwnedSettingsFromManagedBlocks {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    $escapedPrefix = [regex]::Escape($script:ManagedPrefix)
    $managedPattern = "(?ms)(?<Begin>^[ \t]*; BEGIN $escapedPrefix::[^\r\n]*\n)(?<Body>.*?)(?<End>^[ \t]*; END $escapedPrefix::[^\r\n]*$)"
    return [regex]::Replace((Get-GasNormalizedText -Text $Text), $managedPattern, {
        param($match)

        $inGameMapsSection = $false
        $sanitizedBody = New-Object System.Collections.Generic.List[string]
        foreach ($line in $match.Groups["Body"].Value -split "`n") {
            $lineInfo = Get-GasIniLineInfo -Line $line
            if ($lineInfo.Kind -eq "Section") {
                $inGameMapsSection = [string]$lineInfo.Section -match '(?i)(^|/)EngineSettings\.GameMapsSettings$'
                if ($inGameMapsSection) {
                    continue
                }
            }

            if ($inGameMapsSection) {
                continue
            }

            if ($lineInfo.Kind -eq "Assignment") {
                $managedLineInfo = [pscustomobject]@{
                    Kind = $lineInfo.Kind
                    Section = $null
                    Key = $lineInfo.Key
                    Value = $lineInfo.Value
                    Operator = $lineInfo.Operator
                    IsArrayOperation = $lineInfo.IsArrayOperation
                }
                if (Test-GasHostOwnedIniSetting -LineInfo $managedLineInfo) {
                    continue
                }
            }

            [void]$sanitizedBody.Add($line)
        }

        return $match.Groups["Begin"].Value + ($sanitizedBody -join "`n") + $match.Groups["End"].Value
    })
}

function Get-GasIniSettingIdentity {
    param(
        [AllowEmptyString()][string]$Section,
        [Parameter(Mandatory)][string]$Key
    )

    $normalizedSection = if ($null -eq $Section) { "" } else { $Section.Trim().ToLowerInvariant() }
    return "$normalizedSection`0$($Key.Trim().ToLowerInvariant())"
}

function Get-GasIniArrayEntryIdentity {
    param(
        [AllowEmptyString()][string]$Section,
        [Parameter(Mandatory)]$LineInfo
    )

    $settingIdentity = Get-GasIniSettingIdentity -Section $Section -Key $LineInfo.Key
    return "$settingIdentity`0$($LineInfo.Operator)`0$($LineInfo.Value.Trim())"
}

function Get-GasHostIntegrationConfig {
    param(
        [Parameter(Mandatory)][string]$BlockId,
        [AllowEmptyString()][string]$Content
    )

    $rules = Get-GasHostIntegrationRules -BlockId $BlockId
    $normalizedContent = Get-GasNormalizedText -Text $Content
    if ($null -eq $rules) {
        return $normalizedContent
    }

    if ([string]::IsNullOrWhiteSpace($normalizedContent)) {
        return ""
    }

    $preamble = New-Object System.Collections.Generic.List[string]
    $sections = New-Object System.Collections.Generic.List[object]
    $currentSection = $null
    $currentLines = $null

    foreach ($line in $normalizedContent -split "`n") {
        $lineInfo = Get-GasIniLineInfo -Line $line
        if ($lineInfo.Kind -eq "Section") {
            if ($null -ne $currentSection) {
                [void]$sections.Add([pscustomobject]@{
                    Name = $currentSection
                    Header = $currentLines[0]
                    Lines = @($currentLines | Select-Object -Skip 1)
                })
            }

            $currentSection = $lineInfo.Section
            $currentLines = New-Object System.Collections.Generic.List[string]
            [void]$currentLines.Add($line)
            continue
        }

        if ($null -eq $currentSection) {
            if ($lineInfo.Kind -eq "Comment" -or $lineInfo.Kind -eq "Blank") {
                [void]$preamble.Add($line)
            }
        } else {
            [void]$currentLines.Add($line)
        }
    }

    if ($null -ne $currentSection) {
        [void]$sections.Add([pscustomobject]@{
            Name = $currentSection
            Header = $currentLines[0]
            Lines = @($currentLines | Select-Object -Skip 1)
        })
    }

    $filteredSections = New-Object System.Collections.Generic.List[object]
    $seenScalarKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seenArrayEntries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($section in $sections) {
        if (-not $rules.ContainsKey($section.Name)) {
            continue
        }

        $sectionRules = $rules[$section.Name]
        $acceptedLines = New-Object System.Collections.Generic.List[string]
        $acceptedAssignmentCount = 0
        foreach ($line in $section.Lines) {
            $lineInfo = Get-GasIniLineInfo -Line $line
            if ($lineInfo.Kind -eq "Assignment") {
                if (Test-GasHostOwnedIniSetting -LineInfo ([pscustomobject]@{
                        Kind = $lineInfo.Kind
                        Section = $section.Name
                        Key = $lineInfo.Key
                        Value = $lineInfo.Value
                        Operator = $lineInfo.Operator
                        IsArrayOperation = $lineInfo.IsArrayOperation
                    })) {
                    continue
                }

                if (-not $sectionRules.ContainsKey($lineInfo.Key)) {
                    continue
                }

                $ruleType = [string]$sectionRules[$lineInfo.Key]
                if ($ruleType -eq "Scalar" -and $lineInfo.IsArrayOperation) {
                    continue
                }
                # Only additive array entries may be imported from the sample.
                # Never replay '-' (remove) or '!' (clear) into an existing host.
                if ($ruleType -eq "Array" -and $lineInfo.Operator -ne "+") {
                    continue
                }

                $sectionLineInfo = [pscustomobject]@{
                    Kind = $lineInfo.Kind
                    Section = $section.Name
                    Key = $lineInfo.Key
                    Value = $lineInfo.Value
                    Operator = $lineInfo.Operator
                    IsArrayOperation = $lineInfo.IsArrayOperation
                }
                if ($lineInfo.IsArrayOperation) {
                    $arrayEntryIdentity = Get-GasIniArrayEntryIdentity -Section $section.Name -LineInfo $sectionLineInfo
                    if (-not $seenArrayEntries.Add($arrayEntryIdentity)) {
                        continue
                    }
                } elseif (-not $seenScalarKeys.Add((Get-GasIniSettingIdentity -Section $section.Name -Key $lineInfo.Key))) {
                    continue
                }

                [void]$acceptedLines.Add($line)
                $acceptedAssignmentCount++
                continue
            }

            if ($lineInfo.Kind -eq "Comment" -or $lineInfo.Kind -eq "Blank") {
                [void]$acceptedLines.Add($line)
            }
        }

        if ($acceptedAssignmentCount -gt 0) {
            [void]$filteredSections.Add([pscustomobject]@{
                Header = $section.Header
                Lines = @($acceptedLines)
            })
        }
    }

    if ($filteredSections.Count -eq 0) {
        return ""
    }

    $outputLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in $preamble) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            [void]$outputLines.Add($line)
        }
    }

    foreach ($section in $filteredSections) {
        while ($outputLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($outputLines[$outputLines.Count - 1])) {
            $outputLines.RemoveAt($outputLines.Count - 1)
        }

        if ($outputLines.Count -gt 0) {
            [void]$outputLines.Add("")
        }

        [void]$outputLines.Add($section.Header)
        foreach ($line in $section.Lines) {
            [void]$outputLines.Add($line)
        }
    }

    return ($outputLines -join "`n").Trim()
}

function Merge-GasSourceDataDrivenConsoleVariables {
    param(
        [Parameter(Mandatory)][string]$TemplateText,
        [Parameter(Mandatory)][string]$SourceDefaultEngineText
    )

    # The source sample is authoritative for DataDriven CVars: a fixed template
    # may be missing variables referenced by the sample's Blueprint debug UI.
    # Import only additive CVarsArray entries from the original DefaultEngine.ini.
    $targetSection = "/Script/Engine.DataDrivenConsoleVariableSettings"
    $sourceCVars = [System.Collections.Generic.List[string]]::new()
    $sourceByName = [System.Collections.Generic.Dictionary[string,string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $insideSourceSection = $false

    foreach ($line in ((Get-GasNormalizedText -Text $SourceDefaultEngineText) -split "`n")) {
        $info = Get-GasIniLineInfo -Line $line
        if ($info.Kind -eq "Section") {
            $insideSourceSection = $info.Section -eq $targetSection
            continue
        }

        if (-not $insideSourceSection -or $info.Kind -ne "Assignment" -or
            $info.Key -ne "CVarsArray") {
            continue
        }

        # Never import destructive array operations from the original project.
        if ($info.Operator -ne "+") {
            continue
        }

        $nameMatch = [regex]::Match($info.Value, '(?i)(?:^|[,(])\s*Name\s*=\s*"([^"]+)"')
        if (-not $nameMatch.Success) {
            throw "Source DefaultEngine.ini contains a CVarsArray entry without a quoted Name. Refusing to generate an incomplete runtime configuration: $line"
        }

        $name = $nameMatch.Groups[1].Value.Trim()
        if ($sourceByName.ContainsKey($name)) {
            if ($sourceByName[$name] -ne $info.Value) {
                throw "Source DefaultEngine.ini defines conflicting CVarsArray entries for '$name'."
            }
            continue
        }

        $sourceByName.Add($name, $info.Value)
        [void]$sourceCVars.Add($line.Trim())
    }

    $resultLines = [System.Collections.Generic.List[string]]::new()
    $insideTemplateSection = $false
    $foundTemplateSection = $false
    foreach ($line in ((Get-GasNormalizedText -Text $TemplateText) -split "`n")) {
        $info = Get-GasIniLineInfo -Line $line
        if ($info.Kind -eq "Section") {
            $insideTemplateSection = $info.Section -eq $targetSection
            [void]$resultLines.Add($line)
            if ($insideTemplateSection) {
                $foundTemplateSection = $true
                foreach ($entry in $sourceCVars) {
                    [void]$resultLines.Add($entry)
                }
            }
            continue
        }

        # Replace (rather than append to) the template's static CVar snapshot.
        if ($insideTemplateSection -and $info.Kind -eq "Assignment" -and
            $info.Key -eq "CVarsArray") {
            continue
        }
        [void]$resultLines.Add($line)
    }

    if (-not $foundTemplateSection -and $sourceCVars.Count -gt 0) {
        [void]$resultLines.Add("")
        [void]$resultLines.Add("[$targetSection]")
        foreach ($entry in $sourceCVars) {
            [void]$resultLines.Add($entry)
        }
    }

    # Keep the existing runtime allowlist as an independent safety boundary.
    return Get-GasHostIntegrationConfig -BlockId "DefaultEngine.Runtime" -Content ($resultLines -join "`n")
}

function Write-GasJson {
    param(
        [Parameter(Mandatory)]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    $json = Get-GasPrettyJson -Value $Value
    $existing = if (Test-Path -LiteralPath $Path) {
        Get-GasNormalizedText -Text (Get-Content -LiteralPath $Path -Raw)
    } else {
        $null
    }

    if ($existing -eq $json) {
        return
    }

    [System.IO.File]::WriteAllText($Path, ($json -replace "`n", [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
}

function Get-GasProjectMetadata {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $uprojectPath = Join-Path $ProjectRoot "GameAnimationSample.uproject"
    if (-not (Test-Path -LiteralPath $uprojectPath)) {
        throw "Unable to locate GameAnimationSample.uproject under '$ProjectRoot'."
    }

    $uproject = Read-GasJson -Path $uprojectPath
    $pluginDependencies = @($uproject.Plugins | Where-Object { $_.Enabled -eq $true } | ForEach-Object {
        $entry = [ordered]@{
            Name = $_.Name
            Enabled = $true
        }

        if ($_.PSObject.Properties.Name -contains "TargetAllowList" -and $_.TargetAllowList) {
            $entry.TargetAllowList = @($_.TargetAllowList)
        }

        [pscustomobject]$entry
    })

    return [pscustomobject]@{
        ProjectRoot = $ProjectRoot
        UProjectPath = $uprojectPath
        EngineAssociation = $uproject.EngineAssociation
        PluginDependencies = $pluginDependencies
        ContentRoots = Get-GasSourceContentRoots -ProjectRoot $ProjectRoot
        SourceProject = $uproject
    }
}

function Get-GasSourceContentRoots {
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $contentRoot = Join-Path $ProjectRoot "Content"
    if (-not (Test-Path -LiteralPath $contentRoot)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $contentRoot -Directory |
        Where-Object { $_.Name -notin @("Collections", "Developers") } |
        Sort-Object Name |
        ForEach-Object { $_.Name })
}

function New-GasPluginDescriptor {
    param(
        [Parameter(Mandatory)][string]$PluginName,
        [Parameter(Mandatory)][string]$VersionName,
        [Parameter(Mandatory)][int]$Version,
        [Parameter(Mandatory)][string]$EngineVersion,
        [Parameter(Mandatory)]$PluginDependencies
    )

    # Unreal plugin descriptors require three-part versions such as "5.8.0";
    # project EngineAssociation uses two parts such as "5.8".
    $descriptorEngineVersion = if ($EngineVersion -match '^5\.8(?:\.\d+)?$') {
        '5.8.0'
    } elseif ($EngineVersion -match '^\d+\.\d+$') {
        '{0}.0' -f $EngineVersion
    } else {
        $EngineVersion
    }

    return [ordered]@{
        FileVersion = 3
        Version = $Version
        VersionName = $VersionName
        FriendlyName = "Game Animation Sample"
        Description = "Community-friendly Unreal Engine plugin packaging of the Epic Game Animation Sample, prepared by Axchemy Studios for install and update workflows."
        Category = "Animation"
        CreatedBy = "Axchemy Studios - Marcio Vale CEO"
        CreatedByURL = "https://www.axchemy.com/"
        DocsURL = "https://github.com/marciocamello/game-animation-sample-toolkit"
        MarketplaceURL = ""
        SupportURL = "https://github.com/marciocamello/game-animation-sample-toolkit"
        EngineVersion = $descriptorEngineVersion
        CanContainContent = $true
        IsBetaVersion = $true
        IsExperimentalVersion = $false
        Installed = $false
        EnabledByDefault = $false
        RequiresBuildPlatform = $false
        Plugins = @($PluginDependencies)
    }
}

function Get-GasManagedBlock {
    param(
        [Parameter(Mandatory)][string]$BlockId,
        [Parameter(Mandatory)][string]$Content
    )

    $begin = "; BEGIN $script:ManagedPrefix::$BlockId"
    $end = "; END $script:ManagedPrefix::$BlockId"
    return @($begin, (Get-GasNormalizedText -Text $Content).Trim(), $end) -join "`n"
}

function Remove-GasExactManagedBlockOccurrences {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Block
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Block)) {
        return $Text
    }

    $escapedBlock = [regex]::Escape($Block)
    $pattern = "(?ms)(?:^|\n{2,})$escapedBlock(?:\n{2,}|$)"

    return [regex]::Replace($Text, $pattern, {
        param($match)
        if ($match.Value.StartsWith("`n`n")) {
            return "`n`n"
        }

        return ""
    })
}

function Remove-GasExactManagedLineOccurrences {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Block
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Block)) {
        return $Text
    }

    $blockLines = @(Get-GasNormalizedText -Text $Block).Split("`n")
    $managedLineSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($line in $blockLines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line.StartsWith("[") -or $line.StartsWith("; BEGIN") -or $line.StartsWith("; END")) {
            continue
        }

        [void]$managedLineSet.Add($line)
    }

    if ($managedLineSet.Count -eq 0) {
        return $Text
    }

    $normalizedText = Get-GasNormalizedText -Text $Text
    $outputLines = New-Object System.Collections.Generic.List[string]

    foreach ($line in $normalizedText -split "`n") {
        if ($managedLineSet.Contains($line)) {
            continue
        }

        [void]$outputLines.Add($line)
    }

    return ($outputLines -join "`n")
}



function Get-GasIniArraySemanticIdentity {
    param(
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)]$LineInfo
    )

    if ($Section -ieq 'Staging' -and $LineInfo.Key -ieq 'AllowedConfigFiles') {
        return (Get-GasIniSettingIdentity -Section $Section -Key $LineInfo.Key) + '|' + (Get-GasStagingPathIdentity $LineInfo.Value)
    }
    $identityField = switch ($LineInfo.Key) {
        "AxisMappings" { "AxisName"; break }
        "AxisConfig" { "AxisKeyName"; break }
        "GameplayTagList" { "Tag"; break }
        "GameplayTagRedirects" { "OldTagName"; break }
        "Profiles" { "Name"; break }
        "EditProfiles" { "Name"; break }
        "ProfileRedirects" { "OldName"; break }
        "DefaultChannelResponses" { "Channel"; break }
        "CVarsArray" { "Name"; break }
        "PackageRedirects" { "OldName"; break }
        default { return $null }
    }
    $match = [regex]::Match($LineInfo.Value, '(?i)(?:^|[,(])\s*' + [regex]::Escape($identityField) + '\s*=\s*"?([^",)]+)"?')
    if (-not $match.Success) {
        return $null
    }

    $id = $match.Groups[1].Value.Trim().ToLowerInvariant()
    if ($LineInfo.Key -eq "AxisMappings") {
        $keyMatch = [regex]::Match($LineInfo.Value, '(?i)(?:^|[,(])\s*Key\s*=\s*"?([^",)]+)"?')
        if (-not $keyMatch.Success) {
            return $null
        }
        $id += "|" + $keyMatch.Groups[1].Value.Trim().ToLowerInvariant()
    }

    return (Get-GasIniSettingIdentity -Section $Section -Key $LineInfo.Key) + "|" + $id
}

function Merge-GasHostAssetScanPaths {
    param(
        [AllowEmptyString()][string]$HostText,
        [AllowEmptyString()][string]$TemplateText
    )

    # AssetManager identifies PrimaryAssetTypesToScan entries by PrimaryAssetType.
    # A second Map entry can shadow the host's Map directories (UE-178303).
    # Extend an existing host entry rather than adding another entry of that type.
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ((Get-GasNormalizedText -Text $HostText) -split [char]10)) {
        [void]$lines.Add($line)
    }

    $wanted = @{}
    foreach ($line in ((Get-GasNormalizedText -Text $TemplateText) -split [char]10)) {
        $info = Get-GasIniLineInfo -Line $line
        if ($info.Kind -ne "Assignment" -or $info.Key -ne "PrimaryAssetTypesToScan" -or $info.Operator -ne "+") {
            continue
        }

        $type = [regex]::Match($info.Value, 'PrimaryAssetType="?([^",)]+)"?')
        if (-not $type.Success) {
            throw "Unsupported PrimaryAssetTypesToScan template entry: $line"
        }

        $paths = @([regex]::Matches($info.Value, '\(Path="([^"]+)"\)') | ForEach-Object { $_.Groups[1].Value })
        if ($paths.Count -eq 0) {
            throw "Missing paths in PrimaryAssetTypesToScan template: $line"
        }

        $typeName = $type.Groups[1].Value
        if (-not $wanted.ContainsKey($typeName)) {
            $wanted[$typeName] = [System.Collections.Generic.List[string]]::new()
        }
        foreach ($path in $paths) {
            if (-not $wanted[$typeName].Contains($path)) {
                [void]$wanted[$typeName].Add($path)
            }
        }
    }

    $mergedTypes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($typeName in @($wanted.Keys)) {
        $candidateIndices = [System.Collections.Generic.List[int]]::new()
        $section = ""
        $insideManaged = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match '^\s*; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::') {
                $insideManaged = $true
                continue
            }
            if ($line -match '^\s*; END AXCHEMY-GAME-ANIMATION-SAMPLE::') {
                $insideManaged = $false
                continue
            }
            $info = Get-GasIniLineInfo -Line $line
            if ($info.Kind -eq "Section") {
                $section = $info.Section
                continue
            }
            if ($insideManaged -or $section -ine "/Script/Engine.AssetManagerSettings" -or
                $info.Kind -ne "Assignment" -or $info.Key -ne "PrimaryAssetTypesToScan" -or
                $info.Operator -in @("-", "!")) {
                continue
            }

            $match = [regex]::Match($info.Value, 'PrimaryAssetType="?([^",)]+)"?')
            if ($match.Success -and $match.Groups[1].Value -ieq $typeName) {
                [void]$candidateIndices.Add($i)
            }
        }

        if ($candidateIndices.Count -gt 1) {
            throw "Host already has multiple PrimaryAssetTypesToScan entries for '$typeName'. Resolve this conflict before installing/updating."
        }
        if ($candidateIndices.Count -eq 0) {
            continue
        }

        $index = $candidateIndices[0]
        $line = $lines[$index]
        $directoryGroup = [regex]::Match($line, 'Directories=\((?<Entries>.*?)\)(?=,\s*(?:SpecificAssets|Rules)=|\)$)')
        if (-not $directoryGroup.Success) {
            throw "Cannot safely extend the host's '$typeName' scan directories; unsupported INI format: $line"
        }

        $entries = $directoryGroup.Groups["Entries"].Value
        foreach ($path in $wanted[$typeName]) {
            $present = @([regex]::Matches($entries, '\(Path="([^"]+)"\)') |
                Where-Object { $_.Groups[1].Value -ieq $path })
            if ($present.Count -eq 0) {
                $newEntry = '(Path="' + $path + '")'
                $entries = if ([string]::IsNullOrWhiteSpace($entries)) { $newEntry } else { $entries.TrimEnd() + "," + $newEntry }
            }
        }

        $replacement = "Directories=(" + $entries + ")"
        $lines[$index] = $line.Substring(0, $directoryGroup.Index) + $replacement +
            $line.Substring($directoryGroup.Index + $directoryGroup.Length)
        [void]$mergedTypes.Add($typeName)
    }

    return [pscustomobject]@{
        Text = $lines -join [string][char]10
        MergedTypes = $mergedTypes
    }
}


function Assert-GasManagedIniMarkers {
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Path
    )

    $activeId = $null
    foreach ($line in ((Get-GasNormalizedText -Text $Text) -split [char]10)) {
        $begin = [regex]::Match($line, '^\s*; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::(?<Id>[^\s]+)\s*$')
        if ($begin.Success) {
            if ($null -ne $activeId) {
                throw "Nested or unclosed Axchemy-managed INI block '$activeId' in '$Path'."
            }
            $activeId = $begin.Groups["Id"].Value
            continue
        }

        $end = [regex]::Match($line, '^\s*; END AXCHEMY-GAME-ANIMATION-SAMPLE::(?<Id>[^\s]+)\s*$')
        if ($end.Success) {
            if ($null -eq $activeId -or $activeId -cne $end.Groups["Id"].Value) {
                throw "Unmatched Axchemy-managed INI end marker in '$Path'."
            }
            $activeId = $null
        }
    }
    if ($null -ne $activeId) {
        throw "Malformed managed block '$activeId' in '$Path'."
    }
}

function Update-ManagedIniBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BlockId,
        [Parameter(Mandatory)][string]$Content,
        [switch]$PassThru,
        [AllowEmptyString()][string]$CurrentText
    )

    # Always filter at the reconciliation boundary as a defense-in-depth measure.
    # This also makes updates safe when the installed package was generated by an
    # older toolkit version whose InstallData contained the source project's full
    # DefaultEngine.ini.
    $Content = Get-GasHostIntegrationConfig -BlockId $BlockId -Content $Content

    $current = if ($PSBoundParameters.ContainsKey('CurrentText')) {
        $CurrentText
    } elseif (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path -Raw
    } else {
        ""
    }
    # Get-Content -Raw returns null for an existing empty INI. Normalize before
    # marker regexes so empty host configs behave like missing configs.
    $current = Get-GasNormalizedText -Text $current
    if (-not [string]::IsNullOrEmpty($current)) {
        $current = Get-GasNormalizedText -Text $current
        Assert-GasManagedIniMarkers -Text $current -Path $Path
    }

    $begin = [regex]::Escape("; BEGIN $script:ManagedPrefix::$BlockId")
    $end = [regex]::Escape("; END $script:ManagedPrefix::$BlockId")
    $managedPattern = "(?ms)^[ \t]*$begin[ \t]*\n.*?^[ \t]*$end[ \t]*(?:\n|$)"

    # Fail closed on malformed or unbalanced markers rather than writing to a
    # potentially corrupted host config file.
    $beginCount = [regex]::Matches($current, "(?m)^[ \t]*$begin[ \t]*$").Count
    $endCount = [regex]::Matches($current, "(?m)^[ \t]*$end[ \t]*$").Count
    $completeCount = [regex]::Matches($current, $managedPattern).Count
    if ($beginCount -ne $endCount -or $beginCount -ne $completeCount) {
        throw "Malformed managed block '$BlockId' in '$Path'. Refusing to alter the host INI."
    }

    $hostOutside = [regex]::Replace($current, $managedPattern, "")
    $hostOutside = Remove-GasHostOwnedSettingsFromManagedBlocks -Text $hostOutside

    $mergedTypes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($BlockId -eq "DefaultGame.AssetManager") {
        $assetMerge = Merge-GasHostAssetScanPaths -HostText $hostOutside -TemplateText $Content
        $hostOutside = $assetMerge.Text
        $mergedTypes = $assetMerge.MergedTypes
    }

    $hostLineSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $hostArrayEntrySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $hostAssignmentSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $hostSemanticEntries = @{}
    $hostCollisionNames = @{}
    $hostClearedArrays = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $hostSection = ""
    foreach ($line in @($hostOutside -split [char]10)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        [void]$hostLineSet.Add($line)
        $info = Get-GasIniLineInfo -Line $line
        if ($info.Kind -eq "Section") {
            $hostSection = $info.Section
        } elseif ($info.Kind -eq "Assignment") {
            [void]$hostAssignmentSet.Add((Get-GasIniSettingIdentity -Section $hostSection -Key $info.Key))
            if (-not $info.IsArrayOperation -and $hostSection -ieq 'Staging' -and $info.Key -ieq 'AllowedConfigFiles') {
                $hostSemanticEntries[(Get-GasIniArraySemanticIdentity -Section $hostSection -LineInfo $info)] = $info.Value
            }
            if ($info.IsArrayOperation) {
                if ($info.Operator -eq '!') { [void]$hostClearedArrays.Add((Get-GasIniSettingIdentity -Section $hostSection -Key $info.Key)) }
                [void]$hostArrayEntrySet.Add((Get-GasIniArrayEntryIdentity -Section $hostSection -LineInfo $info))
                if ($info.Operator -in @("+", ".")) {
                    if ($hostSection -ieq '/Script/Engine.CollisionProfile' -and $info.Key -ieq 'DefaultChannelResponses') {
                        $name = [regex]::Match($info.Value, '(?i)(?:^|[,(])\s*Name\s*=\s*"?([^",)]+)')
                        if ($name.Success) { $hostCollisionNames[$name.Groups[1].Value.Trim()] = $info.Value }
                    }
                    $semanticIdentity = Get-GasIniArraySemanticIdentity -Section $hostSection -LineInfo $info
                    if ($semanticIdentity -and -not $hostSemanticEntries.ContainsKey($semanticIdentity)) {
                        $hostSemanticEntries[$semanticIdentity] = $info.Value
                    }
                }
            }
        }
    }

    # Build each section as a unit. Never suppress its header just because the
    # host already has that section: orphaned assignments would land in the
    # wrong section when unrelated sections follow it.
    $newSections = [System.Collections.Generic.List[object]]::new()
    $currentHeader = $null
    $currentLines = [System.Collections.Generic.List[string]]::new()
    $seenScalars = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seenArrays = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $seenSemanticArrays = @{}
    foreach ($line in ((Get-GasNormalizedText -Text $Content) -split [char]10)) {
        $info = Get-GasIniLineInfo -Line $line
        if ($info.Kind -eq "Section") {
            if ($null -ne $currentHeader -and $currentLines.Count -gt 0) {
                [void]$newSections.Add([pscustomobject]@{ Header = $currentHeader; Lines = @($currentLines.ToArray()) })
            }
            $currentHeader = $line
            $currentLines = [System.Collections.Generic.List[string]]::new()
            $sampleSection = $info.Section
            continue
        }
        if ($info.Kind -ne "Assignment" -or $null -eq $currentHeader) {
            continue
        }

        if (Test-GasHostOwnedIniSetting -LineInfo ([pscustomobject]@{
            Kind = $info.Kind; Section = $sampleSection; Key = $info.Key
        })) {
            continue
        }

        if ($BlockId -eq "DefaultGame.AssetManager" -and $info.Key -eq "PrimaryAssetTypesToScan") {
            $typeMatch = [regex]::Match($info.Value, 'PrimaryAssetType="?([^",)]+)"?')
            if ($typeMatch.Success -and $mergedTypes.Contains($typeMatch.Groups[1].Value)) {
                continue
            }
        }

        $identity = Get-GasIniSettingIdentity -Section $sampleSection -Key $info.Key
        if ($info.IsArrayOperation) {
            if ($hostClearedArrays.Contains($identity)) { throw "Host explicitly clears array '$identity' in '$Path'. Resolve this conflict before integrating the sample." }
            if ($sampleSection -ieq '/Script/Engine.CollisionProfile' -and $info.Key -ieq 'DefaultChannelResponses') {
                $name = [regex]::Match($info.Value, '(?i)(?:^|[,(])\s*Name\s*=\s*"?([^",)]+)')
                if ($name.Success -and $hostCollisionNames.ContainsKey($name.Groups[1].Value.Trim()) -and
                    (Get-GasComparableIniValue $info.Value) -ine (Get-GasComparableIniValue $hostCollisionNames[$name.Groups[1].Value.Trim()])) {
                    throw "Host conflict for collision channel name '$($name.Groups[1].Value)' in '$Path'."
                }
            }
            $semanticIdentity = Get-GasIniArraySemanticIdentity -Section $sampleSection -LineInfo $info
            if ($semanticIdentity -and $seenSemanticArrays.ContainsKey($semanticIdentity)) {
                if ($info.Key -in @('DefaultChannelResponses','PackageRedirects','Profiles','EditProfiles','ProfileRedirects','GameplayTagRedirects','CVarsArray') -and
                    (Get-GasComparableIniValue $info.Value) -ine (Get-GasComparableIniValue $seenSemanticArrays[$semanticIdentity])) {
                    throw "Conflicting source array definitions for '$semanticIdentity'."
                }
                continue
            }
            if ($semanticIdentity) { $seenSemanticArrays[$semanticIdentity] = $info.Value }
            if ($semanticIdentity -and $hostSemanticEntries.ContainsKey($semanticIdentity)) {
                if ((Get-GasComparableIniValue $info.Value) -ine (Get-GasComparableIniValue $hostSemanticEntries[$semanticIdentity]) -and
                    $info.Key -in @("DefaultChannelResponses", "PackageRedirects", "Profiles", "EditProfiles", "ProfileRedirects", "GameplayTagRedirects")) {
                    throw "Host conflict for $($info.Key) ('$semanticIdentity') in '$Path'. Refusing to override an existing collision channel or redirect."
                }
                # Retain user-defined input bindings, profiles, tags, and CVars.
                continue
            }
            $entryIdentity = Get-GasIniArrayEntryIdentity -Section $sampleSection -LineInfo $info
            if ($hostArrayEntrySet.Contains($entryIdentity) -or
                -not $seenArrays.Add($entryIdentity) -or $hostLineSet.Contains($line)) {
                continue
            }
        } elseif ($hostAssignmentSet.Contains($identity) -or -not $seenScalars.Add($identity)) {
            continue
        }

        [void]$currentLines.Add($line)
    }
    if ($null -ne $currentHeader -and $currentLines.Count -gt 0) {
        [void]$newSections.Add([pscustomobject]@{ Header = $currentHeader; Lines = @($currentLines.ToArray()) })
    }

    $newBlockLines = [System.Collections.Generic.List[string]]::new()
    foreach ($section in $newSections) {
        if ($newBlockLines.Count -gt 0) {
            [void]$newBlockLines.Add("")
        }
        [void]$newBlockLines.Add($section.Header)
        foreach ($line in $section.Lines) {
            [void]$newBlockLines.Add($line)
        }
    }

    $updated = $hostOutside.TrimEnd([char]13, [char]10)
    if ($newBlockLines.Count -gt 0) {
        $block = Get-GasManagedBlock -BlockId $BlockId -Content ($newBlockLines -join [string][char]10)
        $updated = if ([string]::IsNullOrEmpty($updated)) { $block } else {
            $updated + ([string][char]10) + ([string][char]10) + $block
        }
    }
    if (-not [string]::IsNullOrEmpty($updated)) {
        $updated = $updated + [string][char]10
    }

    # Multiple blocks can target the same INI (DefaultEngine.Runtime and
    # DefaultEngine.PackageRedirects). Removing a block preserves the blank
    # lines preceding it, so re-appending the block would otherwise add one
    # more empty line on every update. Normalize spacing only immediately
    # before our own managed markers; never reformat host-owned sections.
    $managedSeparatorPattern = '(?m)\n{3,}(?=^[ \t]*; BEGIN ' +
        [regex]::Escape($script:ManagedPrefix) + '::)'
    $updated = [regex]::Replace($updated, $managedSeparatorPattern, "`n`n")

    if ($PassThru) { return $updated }
    if ($current -eq $updated) {
        return $false
    }

    [System.IO.File]::WriteAllText($Path, ($updated -replace "`n", [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    return $true
}

function Set-GasManagedBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BlockId,
        [Parameter(Mandatory)][string]$Content
    )

    $block = Get-GasManagedBlock -BlockId $BlockId -Content $Content
    $existing = if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path -Raw
    } else {
        ""
    }

    $begin = [regex]::Escape("; BEGIN $script:ManagedPrefix::$BlockId")
    $end = [regex]::Escape("; END $script:ManagedPrefix::$BlockId")
    $pattern = "(?ms)$begin.*?$end"

    if ([regex]::IsMatch($existing, $pattern)) {
        $updated = [regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block })
    } else {
        $separator = if ([string]::IsNullOrWhiteSpace($existing)) { "" } else { [Environment]::NewLine + [Environment]::NewLine }
        $updated = $existing.TrimEnd() + $separator + $block + [Environment]::NewLine
    }

    [System.IO.File]::WriteAllText($Path, $updated, [System.Text.UTF8Encoding]::new($false))
}

function Get-GasRenderedTemplate {
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][hashtable]$Tokens
    )

    $content = Get-Content -LiteralPath $TemplatePath -Raw
    foreach ($key in $Tokens.Keys) {
        $content = $content.Replace("{{${key}}}", [string]$Tokens[$key])
    }
    return $content
}

function Get-GasPluginPackageRoot {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$PluginName = $script:ToolkitName
    )

    if ($PluginName -cne 'GameAnimationSample') { throw 'Only PluginName GameAnimationSample is supported.' }
    $resolvedProjectRoot = Assert-GasSafePath -Path $ProjectRoot

    return Join-Path $resolvedProjectRoot "Development\Plugins\$PluginName"
}

function Get-GasInstallDataRoot {
    param([Parameter(Mandatory)][string]$PackageRoot)

    return Join-Path $PackageRoot "InstallData"
}

function Test-GasPluginPackageRoot {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [string]$PluginName = $script:ToolkitName
    )

    $resolvedPackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path
    if (-not (Test-Path -LiteralPath $resolvedPackageRoot -PathType Container)) {
        throw "PackageRoot '$PackageRoot' was not found or is not a directory."
    }

    if ((Split-Path -Leaf $resolvedPackageRoot) -ne $PluginName) {
        throw "PackageRoot basename must be '$PluginName'. Received '$resolvedPackageRoot'."
    }

    $upluginPath = Join-Path $resolvedPackageRoot "$PluginName.uplugin"
    if (-not (Test-Path -LiteralPath $upluginPath -PathType Leaf)) {
        throw "PackageRoot '$resolvedPackageRoot' must contain '$PluginName.uplugin'."
    }

    $manifestPath = Get-GasPackageManifestPath -PackageRoot $resolvedPackageRoot
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "PackageRoot '$resolvedPackageRoot' must contain '$PluginName.install.json'."
    }

    return $resolvedPackageRoot
}

function Assert-GasHostPluginLayout {
    param(
        [Parameter(Mandatory)][string]$HostPluginRoot,
        [string]$PluginName = $script:ToolkitName
    )

    if (-not (Test-Path -LiteralPath $HostPluginRoot -PathType Container)) {
        throw "Host plugin root '$HostPluginRoot' was not created."
    }

    foreach ($requiredPath in @(
        (Join-Path $HostPluginRoot "$PluginName.uplugin"),
        (Join-Path $HostPluginRoot "$PluginName.install.json"),
        (Join-Path $HostPluginRoot "InstallData"),
        (Join-Path $HostPluginRoot "Tools")
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Invalid installed plugin layout. Missing '$requiredPath'."
        }
    }

    $nestedUPlugin = Join-Path $HostPluginRoot "$PluginName\$PluginName.uplugin"
    if (Test-Path -LiteralPath $nestedUPlugin) {
        throw "Invalid installed plugin layout. Nested plugin detected at '$nestedUPlugin'."
    }
}

function New-GasUniqueBackupRoot {
    param(
        [Parameter(Mandatory)][string]$BackupsRoot,
        [Parameter(Mandatory)][string]$PluginName
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $basePath = Join-Path $BackupsRoot "$PluginName-$timestamp"
    if (-not (Test-Path -LiteralPath $basePath)) {
        return $basePath
    }

    for ($index = 1; $index -le 99; $index++) {
        $candidate = "$basePath-$index"
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    throw "Unable to create a unique backup path under '$BackupsRoot'."
}


function New-GasHostMutationSnapshot {
    param(
        [Parameter(Mandatory)][string]$HostProjectRoot,
        [Parameter(Mandatory)][string]$UProjectPath
    )

    $snapshotRoot = Join-Path $HostProjectRoot ("Saved\GameAnimationSampleToolkit\Transactions\" + [guid]::NewGuid().ToString("N"))
    New-GasDirectory -Path $snapshotRoot
    $snapshotConfigRoot = Join-Path $snapshotRoot "Config"
    New-GasDirectory -Path $snapshotConfigRoot

    Copy-Item -LiteralPath $UProjectPath -Destination (Join-Path $snapshotRoot "HostProject.uproject") -Force
    if ((Get-FileHash -LiteralPath $UProjectPath).Hash -ne (Get-FileHash -LiteralPath (Join-Path $snapshotRoot 'HostProject.uproject')).Hash) { throw "Host descriptor snapshot verification failed: '$snapshotRoot'." }
    foreach ($definition in @(Get-GasHostIntegrationBlockDefinitions)) {
        $sourcePath = Join-Path $HostProjectRoot ("Config\" + $definition.IniFile)
        $snapshotPath = Join-Path $snapshotConfigRoot $definition.IniFile
        if ((Test-Path -LiteralPath $sourcePath -PathType Leaf) -and
            -not (Test-Path -LiteralPath $snapshotPath)) {
            Copy-Item -LiteralPath $sourcePath -Destination $snapshotPath -Force
            if ((Get-FileHash -LiteralPath $sourcePath).Hash -ne (Get-FileHash -LiteralPath $snapshotPath).Hash) { throw "Host config snapshot verification failed: '$snapshotRoot'." }
        }
    }

    $inventory = @(Get-GasTreeInventory $snapshotRoot)
    Assert-GasInventory -Root $snapshotRoot -Inventory $inventory
    Write-GasJson -Value @{ Files = $inventory } -Path (Join-Path $snapshotRoot 'SnapshotInventory.json')

    return $snapshotRoot
}

function Restore-GasHostMutationSnapshot {
    param(
        [Parameter(Mandatory)][string]$SnapshotRoot,
        [Parameter(Mandatory)][string]$HostProjectRoot,
        [Parameter(Mandatory)][string]$UProjectPath
    )

    $inventoryPath = Join-Path $SnapshotRoot 'SnapshotInventory.json'
    if (Test-Path -LiteralPath $inventoryPath) { Assert-GasInventory -Root $SnapshotRoot -Inventory (Read-GasJson $inventoryPath).Files }
    Copy-Item -LiteralPath (Join-Path $SnapshotRoot "HostProject.uproject") -Destination $UProjectPath -Force
    $snapshotConfigRoot = Join-Path $SnapshotRoot "Config"
    foreach ($filename in @((Get-GasHostIntegrationBlockDefinitions | ForEach-Object { $_.IniFile }) | Select-Object -Unique)) {
        $hostFile = Join-Path $HostProjectRoot ("Config\" + $filename)
        $savedFile = Join-Path $snapshotConfigRoot $filename
        if (Test-Path -LiteralPath $savedFile -PathType Leaf) {
            Copy-Item -LiteralPath $savedFile -Destination $hostFile -Force
        } elseif (Test-Path -LiteralPath $hostFile -PathType Leaf) {
            Remove-Item -LiteralPath $hostFile -Force
        }
    }
}

function Copy-GasPluginPackageToHost {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$HostPluginRoot,
        [string]$PluginName = $script:ToolkitName
    )

    $resolvedPackageRoot = Test-GasPluginPackageRoot -PackageRoot $PackageRoot -PluginName $PluginName
    $null = Assert-GasSafePath $HostPluginRoot -Tree
    Assert-GasSeparatePaths $resolvedPackageRoot $HostPluginRoot
    $null = Assert-GasPackage $resolvedPackageRoot
    if (Test-Path -LiteralPath $HostPluginRoot) {
        throw "Host plugin root '$HostPluginRoot' already exists. Use update instead of install."
    }

    New-GasDirectory -Path $HostPluginRoot
    Copy-GasDirectoryContent -Source $resolvedPackageRoot -Destination $HostPluginRoot
    Assert-GasHostPluginLayout -HostPluginRoot $HostPluginRoot -PluginName $PluginName
}

function Replace-GasHostPluginPackage {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$HostPluginRoot,
        [Parameter(Mandatory)][string]$BackupsRoot,
        [string]$PluginName = $script:ToolkitName
    )

    $resolvedPackageRoot = Test-GasPluginPackageRoot -PackageRoot $PackageRoot -PluginName $PluginName
    $null = Assert-GasSafePath $HostPluginRoot -Tree
    $null = Assert-GasSafePath $BackupsRoot -Tree
    Assert-GasSeparatePaths $resolvedPackageRoot $HostPluginRoot
    Assert-GasSeparatePaths $HostPluginRoot $BackupsRoot
    $null = Assert-GasPackage $resolvedPackageRoot
    $installedIdentity = Read-GasJson (Join-Path $HostPluginRoot 'GameAnimationSample.host-install.json')
    if ($installedIdentity.PluginName -cne 'GameAnimationSample') { throw 'Unmanaged plugin replacement rejected.' }
    if (-not (Test-Path -LiteralPath $HostPluginRoot -PathType Container)) {
        throw "Plugin '$PluginName' is not installed at '$HostPluginRoot'."
    }

    New-GasDirectory -Path $BackupsRoot
    $backupRoot = New-GasUniqueBackupRoot -BackupsRoot $BackupsRoot -PluginName $PluginName
    Copy-Item -LiteralPath $HostPluginRoot -Destination $backupRoot -Recurse -Force

    # Restore internally if replacement fails before this function can return
    # its backup path to the caller. Otherwise the outer transaction would not
    # know where the previous plugin was saved.
    try {
        Remove-Item -LiteralPath $HostPluginRoot -Recurse -Force
        New-GasDirectory -Path $HostPluginRoot
        Copy-GasDirectoryContent -Source $resolvedPackageRoot -Destination $HostPluginRoot
        Assert-GasHostPluginLayout -HostPluginRoot $HostPluginRoot -PluginName $PluginName
    }
    catch {
        $originalFailure = $_
        try {
            if (Test-Path -LiteralPath $HostPluginRoot) {
                Remove-Item -LiteralPath $HostPluginRoot -Recurse -Force
            }
            Copy-Item -LiteralPath $backupRoot -Destination $HostPluginRoot -Recurse -Force
            Assert-GasHostPluginLayout -HostPluginRoot $HostPluginRoot -PluginName $PluginName
        }
        catch {
            throw "Package replacement failed. Recovery of the original plugin also failed. Backup is at '$backupRoot'. Replacement error: $originalFailure. Recovery error: $_"
        }
        throw $originalFailure
    }

    return $backupRoot
}

function Resolve-GasUnrealEditorCmd {
    param(
        [Parameter(Mandatory)][string]$EngineAssociation,
        [string]$PreferredPath
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($PreferredPath) { $candidates.Add($PreferredPath) }
    if ($env:UE_UNREALEDITOR_CMD) { $candidates.Add($env:UE_UNREALEDITOR_CMD) }

    # Resolve the installed editor from the source project's EngineAssociation.
    # The user's preferred path or environment override always takes priority.
    if ($EngineAssociation -match '^\d+\.\d+$' -and $env:ProgramFiles) {
        $standardEditorPath = "Epic Games\UE_{0}\Engine\Binaries\Win64\UnrealEditor-Cmd.exe" -f $EngineAssociation
        $candidates.Add((Join-Path $env:ProgramFiles $standardEditorPath))
    }

    $cmd = Get-Command "UnrealEditor-Cmd.exe" -ErrorAction SilentlyContinue
    if ($cmd) { $candidates.Add($cmd.Source) }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Copy-GasDirectoryContent {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [string[]]$ExcludeDirectories = @(),
        [string[]]$ExcludeFiles = @()
    )

    New-GasDirectory -Path $Destination

    $excludeDirectorySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $ExcludeDirectories) { [void]$excludeDirectorySet.Add($entry) }

    $excludeFileSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $ExcludeFiles) { [void]$excludeFileSet.Add($entry) }

    Get-ChildItem -LiteralPath (Resolve-Path -LiteralPath $Source).Path -Force | ForEach-Object {
        if ($_.PSIsContainer) {
            if ($excludeDirectorySet.Contains($_.Name)) {
                return
            }

            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Destination $_.Name) -Recurse -Force
            return
        }

        if ($excludeFileSet.Contains($_.Name)) {
            return
        }

        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Destination $_.Name) -Force
    }
}

function ConvertTo-GasAssetPackagePath {
    param(
        [Parameter(Mandatory)][string]$ContentRoot,
        [Parameter(Mandatory)][string]$FullName,
        [Parameter(Mandatory)][string]$MountPoint
    )

    $relative = [System.IO.Path]::GetRelativePath($ContentRoot, $FullName)
    $withoutExtension = [System.IO.Path]::ChangeExtension($relative, $null)
    $normalized = ($withoutExtension -replace "\\", "/").TrimStart("/")
    return "$MountPoint/$normalized"
}

function New-GasPackageRedirectContent {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$PluginMountPoint = "/GameAnimationSample"
    )

    $contentRoot = Join-Path $ProjectRoot "Content"
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine("[CoreRedirects]")

    $assetFiles = Get-ChildItem -LiteralPath $contentRoot -Recurse -File -Include *.uasset, *.umap |
        Where-Object {
            $_.FullName -notmatch "\\Collections\\" -and
            $_.FullName -notmatch "\\Developers\\"
        } |
        Sort-Object FullName

    foreach ($asset in $assetFiles) {
        $oldPath = ConvertTo-GasAssetPackagePath -ContentRoot $contentRoot -FullName $asset.FullName -MountPoint "/Game"
        $newPath = ConvertTo-GasAssetPackagePath -ContentRoot $contentRoot -FullName $asset.FullName -MountPoint $PluginMountPoint
        [void]$builder.AppendLine("+PackageRedirects=(OldName=`"$oldPath`",NewName=`"$newPath`")")
    }

    return $builder.ToString().TrimEnd()
}

function Get-GasBuildVersion {
    param([Parameter(Mandatory)][string]$EngineVersion)

    if ([string]::IsNullOrWhiteSpace($EngineVersion)) {
        throw "EngineVersion is required to generate the plugin build version."
    }

    $normalizedEngineVersion = $EngineVersion.Trim()

    return [pscustomobject]@{
        Version = [int](Get-Date -Format "yyyyMMdd")
        VersionName = "$normalizedEngineVersion.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        BuiltAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    }
}

function Get-GasPackageManifestPath {
    param([Parameter(Mandatory)][string]$PackageRoot)

    return Join-Path $PackageRoot "GameAnimationSample.install.json"
}

function New-GasInstallManifest {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$BuildMode,
        [Parameter(Mandatory)]$Metadata,
        [Parameter(Mandatory)]$BuildVersion
    )

    return [ordered]@{
        PluginName = $script:ToolkitName
        PluginMountPoint = "/GameAnimationSample"
        BuildMode = $BuildMode
        BuildVersion = $BuildVersion.VersionName
        BuildVersionNumber = $BuildVersion.Version
        BuiltAtUtc = $BuildVersion.BuiltAtUtc
        EngineAssociation = $Metadata.EngineAssociation
        SourceProject = Split-Path -Leaf $Metadata.UProjectPath
        PackageRoot = $PackageRoot
        RequiredEnginePlugins = @($Metadata.PluginDependencies)
        ManagedIniBlocks = @((Get-GasHostIntegrationBlockDefinitions | ForEach-Object { $_.Id })) + @('DefaultGame.Staging')
        Attribution = [ordered]@{
            Studio = "Axchemy Studios - Marcio Vale CEO"
            GitHub = "https://github.com/marciocamello"
            Website = "https://www.axchemy.com/"
        }
    }
}

function Update-GasUProjectPlugins {
    param(
        [Parameter(Mandatory)][string]$UProjectPath,
        [Parameter(Mandatory)][string]$PluginName,
        [Parameter(Mandatory)]$RequiredPlugins
    )

    Update-UProjectPluginEntries -UProjectPath $UProjectPath -PluginName $PluginName -RequiredPlugins $RequiredPlugins
}

function Get-NormalizedPluginNameMap {
    param([AllowEmptyCollection()][object[]]$Plugins = @())

    $map = [ordered]@{}
    foreach ($plugin in @($Plugins)) {
        if ($null -eq $plugin) {
            continue
        }

        $name = [string]$plugin.Name
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $normalized = $name.Trim().ToLowerInvariant()
        if (-not $map.Contains($normalized)) {
            $map[$normalized] = [ordered]@{
                Name = $name.Trim()
                Entries = New-Object System.Collections.Generic.List[object]
            }
        }

        [void]$map[$normalized].Entries.Add($plugin)
    }

    return $map
}

function ConvertTo-GasOrderedHashtable {
    param([Parameter(Mandatory)]$InputObject)

    $ordered = [ordered]@{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $ordered[$property.Name] = $property.Value
    }

    return $ordered
}

function Merge-GasOrderedHashtable {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Base,
        [Parameter(Mandatory)]$Overlay,
        [string[]]$ForceProperties = @()
    )

    $forced = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($propertyName in $ForceProperties) {
        [void]$forced.Add($propertyName)
    }

    foreach ($property in $Overlay.PSObject.Properties) {
        if ($Base.Contains($property.Name)) {
            if ($forced.Contains($property.Name)) {
                $Base[$property.Name] = $property.Value
                continue
            }

            if ($null -eq $Base[$property.Name] -and $null -ne $property.Value) {
                $Base[$property.Name] = $property.Value
            }

            continue
        }

        $Base[$property.Name] = $property.Value
    }

    return $Base
}

function Update-UProjectPluginEntries {
    param(
        [Parameter(Mandatory)][string]$UProjectPath,
        [Parameter(Mandatory)][string]$PluginName,
        [Parameter(Mandatory)]$RequiredPlugins,
        [switch]$PassThru
    )

    $uproject = Read-GasJson -Path $UProjectPath
    $currentPlugins = @()
    if ($uproject.PSObject.Properties.Name -contains "Plugins" -and $uproject.Plugins) {
        $currentPlugins = @($uproject.Plugins)
    }

    $normalizedMap = Get-NormalizedPluginNameMap -Plugins $currentPlugins
    $requiredSpecs = New-Object System.Collections.Generic.List[object]

    $requiredToolkitEntry = [ordered]@{
        Name = $PluginName
        Enabled = $true
    }
    [void]$requiredSpecs.Add([pscustomobject]$requiredToolkitEntry)

    foreach ($required in @($RequiredPlugins)) {
        if ($null -eq $required -or [string]::IsNullOrWhiteSpace([string]$required.Name)) {
            continue
        }

        $entry = [ordered]@{
            Name = ([string]$required.Name).Trim()
            Enabled = $true
        }

        if ($required.PSObject.Properties.Name -contains "TargetAllowList" -and $required.TargetAllowList) {
            $entry.TargetAllowList = @($required.TargetAllowList)
        }

        [void]$requiredSpecs.Add([pscustomobject]$entry)
    }

    $requiredLookup = @{}
    foreach ($spec in $requiredSpecs) {
        $requiredLookup[$spec.Name.Trim().ToLowerInvariant()] = $spec
    }

    $reconciled = New-Object System.Collections.Generic.List[object]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($group in $normalizedMap.GetEnumerator()) {
        $entries = @($group.Value.Entries.ToArray())
        if ($entries.Count -eq 0) {
            continue
        }

        # Normalize only entries owned by this integration. Preserve unrelated
        # entries verbatim, including optional Enabled and custom metadata.
        if (-not $requiredLookup.ContainsKey($group.Key)) {
            foreach ($entry in $entries) { [void]$reconciled.Add($entry) }
            [void]$seen.Add($group.Key)
            continue
        }

        $canonical = ConvertTo-GasOrderedHashtable -InputObject $entries[0]
        for ($index = 1; $index -lt $entries.Count; $index++) {
            $canonical = Merge-GasOrderedHashtable -Base $canonical -Overlay $entries[$index]
        }

        $normalizedName = $group.Key
        if ($requiredLookup.ContainsKey($normalizedName)) {
            $canonical = Merge-GasOrderedHashtable -Base $canonical -Overlay $requiredLookup[$normalizedName] -ForceProperties @("Enabled")
        }

        if (-not $canonical.Contains("Enabled")) {
            $canonical["Enabled"] = $true
        } elseif ($requiredLookup.ContainsKey($normalizedName)) {
            $canonical["Enabled"] = $true
        }

        [void]$reconciled.Add([pscustomobject]$canonical)
        [void]$seen.Add($normalizedName)
    }

    foreach ($spec in $requiredSpecs) {
        $normalizedName = $spec.Name.Trim().ToLowerInvariant()
        if ($seen.Contains($normalizedName)) {
            continue
        }

        $entry = ConvertTo-GasOrderedHashtable -InputObject $spec
        $entry["Enabled"] = $true
        [void]$reconciled.Add([pscustomobject]$entry)
        [void]$seen.Add($normalizedName)
    }

    if ($uproject.PSObject.Properties.Name -contains "Plugins") {
        $uproject.Plugins = @($reconciled.ToArray())
    } else {
        Add-Member -InputObject $uproject -MemberType NoteProperty -Name Plugins -Value @($reconciled.ToArray())
    }

    $updated = Get-GasPrettyJson -Value $uproject
    $current = if (Test-Path -LiteralPath $UProjectPath) {
        Get-GasNormalizedText -Text (Get-Content -LiteralPath $UProjectPath -Raw)
    } else {
        ""
    }

    if ($PassThru) { return $updated }
    if ($current -eq $updated) {
        return $false
    }

    [System.IO.File]::WriteAllText($UProjectPath, ($updated -replace "`n", [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    return $true
}

function Get-GasToolkitRootFromPackage {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [string]$PluginName = $script:ToolkitName
    )

    $resolved = (Resolve-Path -LiteralPath $BasePath).Path
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add($resolved)
    $candidates.Add((Join-Path $resolved "Development\Plugins\$PluginName"))
    $candidates.Add((Join-Path $resolved "Plugins\$PluginName"))

    if ((Split-Path -Leaf $resolved) -ieq "Tools") {
        $candidates.Add((Resolve-Path -LiteralPath (Join-Path $resolved "..")).Path)
    }

    foreach ($candidate in $candidates) {
        if (-not $candidate) {
            continue
        }

        $manifestPath = Join-Path $candidate "GameAnimationSample.install.json"
        $upluginPath = Join-Path $candidate "GameAnimationSample.uplugin"
        if ((Test-Path -LiteralPath $manifestPath) -or (Test-Path -LiteralPath $upluginPath)) {
            return $candidate
        }
    }

    return (Join-Path $resolved "Development\Plugins\$PluginName")
}

function Sync-GasRuntimeFilesToPackage {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$PackageRoot
    )

    $toolsRoot = Join-Path $PackageRoot "Tools"
    $installDataRoot = Join-Path $PackageRoot "InstallData"
    New-GasDirectory -Path $toolsRoot
    New-GasDirectory -Path $installDataRoot

    # Build must run from the cloned toolkit repository (it requires the source
    # Templates/ and Scripts/ layout). The installed plugin only ships tools
    # that can actually operate from its Tools/ directory.
    foreach ($file in @(
        "Install-GameAnimationSampleToProject.ps1",
        "Update-GameAnimationSampleInProject.ps1"
    )) {
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot $file) -Destination (Join-Path $toolsRoot $file) -Force
    }

    New-GasDirectory (Join-Path $toolsRoot 'Scripts')
    foreach ($name in @('GameAnimationSampleTools.psm1', 'GameAnimationSampleSafety.ps1')) {
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot "Scripts\$name") -Destination (Join-Path $toolsRoot "Scripts\$name") -Force
    }
    # InstallData is already rendered (including source-derived CVars and redirects)
    # by Build-GameAnimationSamplePlugin.ps1. Never overwrite it with raw templates.
}

. (Join-Path $PSScriptRoot 'GameAnimationSampleSafety.ps1')

Export-ModuleMember -Function *-Gas*, Update-ManagedIniBlock, Update-UProjectPluginEntries, Get-NormalizedPluginNameMap, Get-GasNormalizedText, Get-GasPrettyJson, ConvertTo-GasOrderedHashtable, Merge-GasOrderedHashtable
