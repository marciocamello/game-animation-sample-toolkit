# Game Animation Sample Plugin Toolkit — v0.1.0 (PROPOSED)

**Unpublished draft:** No release or version tag has been created by this document.

## Summary

This source-only Windows/PowerShell toolkit builds a reusable Unreal Engine content plugin **locally** from the Epic Game Animation Sample that each user downloads through Fab. It installs or updates the package in a separate Unreal Engine project while preserving existing project configuration wherever the documented merge rules allow.

**Tested configuration:** Unreal Engine **5.8.4**, Windows 11, PowerShell 7 and Win64 Development. No other combination is certified.

## Features

- PowerShell scripts for package Build, Install, Update, Clean-Build and validation.
- Non-destructive RawCopy packaging with generated package redirects and local SHA-256 package inventory.
- Host-aware, allowlisted INI and `.uproject` integration that preserves map/game-mode settings and merges AssetManager scan directories additively.
- Host-derived `[Staging]` permission for `DefaultNetworkPrediction.ini` in UE 5.8.4.
- Install/Update `-DryRun` plans, ownership checks, safe-path validation, preflight conflict detection and deduplication.
- Transactional host snapshots, prior-plugin backups, rollback on script-level failures and retained journals for manual interrupted-operation recovery.
- Synthetic regression suites for toolkit functionality, release safety and staging logic.

## Validation evidence (maintainer-run, 2026-10-27)

- Original sample plugin package successfully rebuilt and updated in an isolated host copy.
- Editor/PIE sample interaction including Motion Matching, character switching and camera control.
- Win64 Development cooking/BuildCookRun and standalone packaged gameplay succeeded.
- Follow-up BuildCookRun after staging correction: **3,352 Windows packages cooked**, `DefaultNetworkPrediction.ini` staged without the previous warning, **ExitCode 0**.
- Original host Update passed; original map setting preserved; subsequent functional testing approved.
- Last reported script checks: **38/38 release-safety** and **18/18 staging** tests, plus toolkit validation suite PASS.

These are environment-specific acceptance results and **not** a clean-blank-project or cross-platform certification.

## Installation

Download the Epic sample through [Fab](https://www.fab.com/listings/880e319a-a59e-4ed2-b268-b32dac7fa016), clone this repository, and follow the [README Quick Start](../README.md#quick-start) using PowerShell 7. `-OutputRoot` is the **exact generated plugin directory** and must match the Install/Update `-PackageRoot`. Use `-DryRun` before writing to a host and close its Unreal Editor first.

## Limitations and cautions

- RawCopy plus generated redirects does not eliminate all original asset-path assumptions. Runtime compatibility depends on the host's assets, plugins and configuration.
- Dependency minimization and alternate engine/platform support have not been certified.
- The installer can roll back handled script errors, but not guarantee a fully atomic recovery from OS crashes/power loss; keep project backups.
- Backups and transaction snapshots are retained until reviewed and manually cleaned.
- Some performance observations in the original sample run (console-variable lookups, PSO hitches and audio format conversion) are **not** claimed to be fixed by this toolkit.
- Do not distribute Epic source/sample content as part of this release.

## Licensing and distribution

**MIT** applies only to the toolkit's own scripts and documentation. Epic sample assets and derivative content are separately licensed and **not included**. End users must obtain their own Game Animation Sample from Fab. See [THIRD_PARTY.md](../THIRD_PARTY.md) and [Fab license](https://www.fab.com/eula).

Before publication, pass the [public release checklist](PUBLIC_RELEASE_CHECKLIST.md), including a Git-history scan and privacy/security review.
