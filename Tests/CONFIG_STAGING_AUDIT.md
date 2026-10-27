# UE 5.8.4 config staging hardening — 2026-10-27

## Post-implementation UE validation — completed on 2026-10-27

**Follow-up to the original, script-only audit below.** The maintainer subsequently performed the previously pending checks on the installed UE 5.8.4 engine. This section records separately reported/manual evidence and does not retroactively change the scope or results of the original Codex audit.

1. Rebuilt the local Game Animation Sample plugin package with updated tooling and previewed/applied Update to an isolated copy of an existing host.
2. Verified the target host `Config/DefaultGame.ini` contained the `[Staging]` allowance for `<HostName>/Config/DefaultNetworkPrediction.ini`, with the host name derived from its actual `.uproject`.
3. Ran Win64 Development `RunUAT BuildCookRun` against `/GameAnimationSample/Levels/DefaultLevel`: build succeeded; cook reported **3,352 Windows packages cooked**, 10 skipped by platform; `DefaultNetworkPrediction.ini` was explicitly included in the stage manifest; the previous unclassified-config warning did **not** recur; package completed with **`BUILD SUCCESSFUL` and AutomationTool `ExitCode=0`**.
4. Independently updated the maintainer's original host. The operation reported `[Success] Update completed` with retained plugin backup and host transaction snapshot. The host's existing `GameDefaultMap` value was preserved, and the staging allowance was present. The maintainer later reported functional testing **approved**.

This completes the specific **UE 5.8.4/Win64 staging-warning acceptance check** left outstanding by the original script audit. It does not certify every host, a fresh blank-project template, other platforms, or all custom config hierarchy overrides. A successful packaged standalone launch/character/camera test was also reported from the prior release-hardening validation, not rerun specifically for this staging patch.

The **18/18 directed staging** and **38/38 release-safety** script results below remain the original script-test evidence. Later sections marked “pending” describe the status **at the time of the original audit**, before this follow-up.

---

Branch: `fix/network-prediction-config-staging`. Base: `c596872`.

## Context and root cause

The maintainer reports successful plugin packaging, transactional host update, map/Foley preservation, Unreal Editor/PIE, Win64 cooking, BuildCookRun Development Win64, standalone character/camera changes and normal shutdown on UE 5.8.4. This is accepted as reported functional validation; no new Unreal run was performed for this change.

AutomationTool stages unclassified runtime INIs by default but warns when no explicit allow/deny decision exists. The toolkit generated `DefaultNetworkPrediction.ini` without the corresponding host `[Staging]` allowance. ExitCode=0 is consistent with the warning path: the missing decision is not itself a packaging failure.

The installed UE source was inspected read-only, with `Engine/Build/Build.version` confirming **5.8.4, changelist 58902052**:

- `Engine/Source/Programs/AutomationTool/Scripts/CopyBuildToStagingDirectory.Automation.cs`: `StageConfigFiles` emits the warning; `ShouldStageConfigFile` checks explicit allows before denies, then classifies suffixes.
- `Engine/Source/Programs/AutomationTool/AutomationUtils/DeploymentContext.cs`: reads `AllowedConfigFiles` / `DisallowedConfigFiles` from `[Staging]` in the Game config hierarchy; known suffixes include Engine, Game, Input and GameplayTags, but not NetworkPrediction. Paths are staged under `ShortProjectName`.
- `Engine/Source/Programs/AutomationTool/AutomationUtils/ProjectUtils.cs` and `CommandUtils.cs`: short project name comes from the `.uproject` filename with all extensions removed, not the containing directory.
- `Engine/Config/BaseGame.ini`: documents explicit per-config staging allowance/denial syntax.

The plugin Config directory follows the separate direct UFS staging path in CopyBuildToStagingDirectory; the warning classification being corrected here applies to the managed host Config files. No extra broad plugin/config allowance is needed for this warning.

The public [UE 5.8 release notes](https://dev.epicgames.com/documentation/unreal-engine/unreal-engine-5-8-release-notes?lang=en-US) also document `AllowedConfigFiles` staging entries. The local installed source determines the exact behavior for 5.8.4.

## Implementation and host safety

`Invoke-GasHostOperation` adds a host-generated `DefaultGame.Staging` block to the existing in-memory `DefaultGame.ini` plan:

```ini
[Staging]
+AllowedConfigFiles=YourHost/Config/DefaultNetworkPrediction.ini
```

- Host name is resolved from the actual `.uproject` at preflight. Package templates/InstallData contain no fixed host name.
- Only NetworkPrediction receives a new allowance; the other toolkit-managed root INIs are already classified by UE 5.8.4.
- Existing sections, other plugin permissions, custom config, maps and tags remain intact. Matching paths deduplicate ignoring case, slash direction and outer quotes. Existing plain or dot-prefixed allowance assignments are recognized.
- DefaultGame's explicit disallow, allowance removal or array clear aborts before writes, including DryRun. Adding an allow despite a deny would override host policy because AutomationTool checks allows first.
- Normal Update fills missing staging integration on older hosts and reconciles its managed path after host rename. It does not rewrite unrelated host permissions.
- Existing DefaultGame snapshots, byte verification, atomic writes, plugin staging, transaction journals and rollback are reused. No new host config file is introduced.
- New package manifests and installed ownership metadata identify the host-only `DefaultGame.Staging` block; source-derived integration blocks remain unchanged.
- Empty existing INIs are normalized to an empty string before marker parsing. This fixes an existing null-input failure exposed by Blank-host staging tests.

Rebuild generated packages to distribute the updated tools; never hand-edit inventoried package scripts. Then preview Install/Update with DryRun. This change intentionally performs no real-host installation or Unreal packaging run.

## Tests and evidence

Run locally in PowerShell 7:

```powershell
pwsh -File .\Validate-GameAnimationSampleToolkit.ps1
pwsh -File .\Tests\Test-ReleaseSafety.ps1
pwsh -File .\Tests\Test-ConfigStaging.ps1
git diff --check
```

The targeted suite builds a disposable synthetic package and tests the distributed installer as well as repository Update. Coverage includes no Staging section, existing Staging/other plugin rules, preexisting allowance variants, initial Install, repeat Update with complete host/plugin hash comparison, Install/Update DryRun with full fixture directory/file comparison, legacy-host update, host rename, conflicting allow/deny/remove/clear policies, deny removal, and source-name derivation matching AutomationTool.

For rollback, the test observes the new permission on disk, throws a controlled exception after that INI write, then compares the complete host/plugin tree against its previous hashes (excluding retained Saved recovery artifacts). The restored DefaultGame hash is also compared against its snapshot. Idempotence checks compare the full host/plugin files between updates, with explicit checks for the user map/GameMode settings, user GameplayTag and Foley tag.

Every PowerShell file is checked with the native parser before toolkit execution. No Epic assets or real projects are required. All write fixtures use GUID-named system temporary directories; existing production and test hosts, as well as the original sample, are untouched by this script-only test suite.

Final local results: **9 PowerShell files, 0 ParserErrors; toolkit validation suite PASS; release safety 38/38 PASS; directed staging 18/18 PASS; `git diff --check` PASS.** Unreal verification of the new allowance remains pending separately, as requested.

## Secondary observations

| Observation reported by maintainer | Classification and next evidence |
| --- | --- |
| 14 FindConsoleObject performance warnings | Runtime consumer lookup frequency. The local `ConsoleManager.cpp` warning explicitly suggests caching. The toolkit only imports source CVar definitions; it does not call runtime console APIs. Trace callers before assigning ownership to a particular original Epic Blueprint, engine subsystem or plugin. Fourteen warnings are not fourteen total lookups. No arbitrary CVar change or warning suppression was introduced. |
| Over 100 startup PSO creation hitches | Graphics-pipeline/cache warm-up and coverage opportunity. Compare cold/warm runs and profile representative character/camera/material usage. PSO precaching/bundled caches belong to a separate host rendering optimization, not INI installation. See [Epic PSO cache documentation](https://dev.epicgames.com/documentation/unreal-engine/optimizing-rendering-with-pso-caches-in-unreal-engine). |
| 44.1 kHz to 48 kHz audio conversion | Consistent with source/stream vs mixer sample-rate mismatch; complete logs are needed to identify the precise stage and asset/stream. The [Epic Audio Mixer overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/audio-mixer-overview) describes sample-rate conversion. Inspect platform/cook/mixer policy separately. No assets were resampled and no global audio rate was forced. |

## Remaining checks and boundaries

- Final Unreal validation of this staging correction is intentionally separate: rebuild package, preview/update an authorized isolated host, then verify the NetworkPrediction warning is absent on a later packaging run. No BuildCookRun was started automatically.
- Policy conflict checks inspect host DefaultGame.ini. Platform/custom/engine hierarchy overrides and staging directory remaps are not simulated by the PowerShell tool; verify the final hierarchy during Unreal validation.
- Local script tests demonstrate the new configuration/transaction behavior; they do not reproduce the reported startup performance counts or identify their exact runtime callers.
- Existing RawCopy, legacy inventory, concurrent external-writer and interrupted-recovery limitations still apply as documented in TECHNICAL_README.
- No original Epic assets, OS/Unreal installation settings, remote CI, release/tag, PR or main merge were modified.

## Changed files

- `Scripts/GameAnimationSampleSafety.ps1`: host-name generation, staging-policy preflight and transaction-plan integration.
- `Scripts/GameAnimationSampleTools.psm1`: staging block allowlist, semantic path deduplication, empty-INI handling and manifest metadata.
- `Tests/Test-ConfigStaging.ps1`: directed synthetic regression suite.
- `README.md`, `TECHNICAL_README.md`: actual staging behavior, test command, reported functional validation and performance boundaries.
- This report records source evidence, coverage and remaining manual validation.
