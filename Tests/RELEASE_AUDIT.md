# Release audit — 2026-10-26

## Subsequent acceptance status (maintainer follow-up, 2026-10-27)

This document preserves the **2026-10-26 script-only audit** below, including its original pending items and test scope. After that audit, the maintainer successfully built a full local Epic sample package, updated an isolated copy of an existing UE 5.8.4 host, verified Editor/PIE (including Motion Matching and character/camera behavior), completed Win64 Development BuildCookRun and a packaged standalone run, and updated/tested the original host. A later staging-specific BuildCookRun succeeded with 3,352 cooked Windows packages, the `DefaultNetworkPrediction.ini` file included, no recurrence of its earlier staging warning, and AutomationTool ExitCode 0. The original host's `GameDefaultMap` was preserved.

The staging-hardening branch also reported **38/38 release safety** and **18/18 staging tests** passing. See [CONFIG_STAGING_AUDIT.md](CONFIG_STAGING_AUDIT.md) for the follow-up details and boundaries.

**Current publication decision:** the previously untested UE 5.8.4/Win64 paths now have maintainer-run acceptance evidence. **Public visibility/release is still gated** on review of the current Git tree **and reachable Git history**, assets/licenses, sensitive data, release contents and documentation consistency (see [PUBLIC_RELEASE_CHECKLIST.md](../docs/PUBLIC_RELEASE_CHECKLIST.md)). The original audit's “PENDENTE” label should not be read as saying that the later UE verification never occurred. No universal/platform compatibility is claimed.

---

Base: `origin/main` at `10398bd`. Work branch: `fix/release-toolkit-security-and-install-hardening`.

## Readiness

**PENDENTE for unrestricted public release.** Local script and synthetic-package regression results are recorded below. This audit does not certify a full Epic payload, cooked builds or new UE Editor/PIE behavior. Previous user-reported UE 5.8.4 success is useful historical evidence, not a test of these changes.

## Findings and corrections

| Finding / cause | Correction |
| --- | --- |
| Install's catch could delete a preexisting plugin after the copy helper rejected it | Fail before any write; rollback removes only a plugin committed by the current transaction |
| Manifest plugin name and paths were trusted; source/host overlap and links were not consistently rejected | Fixed identity/mount, local canonical path checks, root/UNC/device/ADS/traversal and link/reparse rejection |
| Update accepted an installed folder without toolkit ownership evidence | Require host ownership metadata and compatible installed package identity |
| INI conflicts were discovered after replacing the plugin | Shared in-memory preflight and dry-run plan for all host file changes |
| Old output was deleted before a replacement build could succeed | Sibling staging, validation, directory commit and retained previous output |
| CVar fixes existed, but other INIs still relied on stale templates | Allowlisted source extraction for tags, input, runtime and NetworkPrediction; deliberate plugin AssetManager paths |
| Foley Ragdoll/Punch/Kick exist in the audited source but were omitted by the template | Extract actual source tags; no invented tags or asset/Blueprint edits |
| Source custom profiles, Mouse/Obstacle channels and other selected runtime settings were omitted | Explicit named collision allowlist, Ragdoll edit, Obstacle redirect, selected networking/PoseSearch settings |
| Root-level content could have redirects but was not copied | Copy root content files as well as selected content directories |
| Full source Config snapshot was distributed in active plugin Config | Move the inactive archive to Build/SourceConfig |
| Old backups retained only plugin payload after successful operations | Retain host snapshots, existence information via absent files, SHA-256 snapshot inventory and transaction journal |
| Interruptions had no explicit state or retry barrier | Preparing/Prepared/Committed/RolledBack journal; unfinished operations block retries |
| Updates could discard user additions or modified plugin payloads | Inventory ownership checks; preserve additional non-conflicting files and reject edited inventoried files |
| Global RawCopy redirects could capture a host asset at the same /Game path | Reject existing host .uasset/.umap collisions in preflight |
| Reconciliation changed metadata of unrelated plugin entries | Restrict normalization to integration-owned entries; preserve unrelated optional fields |
| Equivalent named INI arrays could duplicate with different casing/spacing/comments | Semantic identities, tag deduplication, source conflict checks and host CVar precedence |

## Local validation

Changed files: `Build-GameAnimationSamplePlugin.ps1`, `Clean-Build-GameAnimationSamplePlugin.ps1`, `Install-GameAnimationSampleToProject.ps1`, `Update-GameAnimationSampleInProject.ps1`, `Validate-GameAnimationSampleToolkit.ps1`, `Scripts/GameAnimationSampleTools.psm1`, new `Scripts/GameAnimationSampleSafety.ps1`, `README.md`, `TECHNICAL_README.md`, new `Tests/Test-ReleaseSafety.ps1`, `Tests/SourceConfigAudit.json` and this report. Licenses/notices and Epic assets are unchanged.

Run from the repository in PowerShell 7:

```powershell
pwsh -File .\Validate-GameAnimationSampleToolkit.ps1
pwsh -File .\Tests\Test-ReleaseSafety.ps1
git diff --check
```

The release suite uses the native `System.Management.Automation.Language.Parser` on every repository `.ps1` and `.psm1` before invoking toolkit code. Package validation parses the distributed tools as well.

Final local run: **8 PowerShell files, 0 ParserErrors; existing validation suite PASS; 37/37 release safety checks PASS; `git diff --check` PASS.** Tests were rerun after correcting the PowerShell null-string binding used by atomic `File.Replace`; these results apply to the final scripts.

Follow-up migration fix (2026-10-26): Refresh previously applied current installability checks to the old generated output, preventing a rebuild precisely because its new safety module was absent. Refresh now checks legacy Axchemy RawCopy identity separately; full current validation still applies to the newly generated package. Regression covers default-path Build/Clean DryRun with no writes, legacy `5.8` descriptors without inventory/safety module, foreign identity rejection, successful rebuild and byte-identical retention of the old package. **38/38 release safety checks PASS; existing validation suite PASS; native parser PASS; `git diff --check` PASS.** All rebuilds used disposable synthetic samples; only real-package manifest/descriptor metadata was inspected read-only.

The existing regression suite covers customized and Blank hosts, map/GameMode preservation, AssetManager directory merging, legacy managed-block reconciliation, collision conflicts, malformed markers/packages, repeated updates, host metadata and DDCVars/InstallData synchronization.

The additional **37 release safety checks** cover synthetic RawCopy builds, source immutability, complete package/inventory/notices, source Foley/DDCVar extraction, distributed-tool equality, clean install, repeat install rejection, byte-level update idempotence, Install/Update/Build dry-run filesystem invariance, partial copy/config/swap failures, full plugin/host rollback, backup verification, missing-INI restoration, exclusive descriptor locks, read-only config, legacy inventory migration, unmanaged plugin data, disabled dependencies, traversal/overlap/missing paths, junctions/hard links, manifest/descriptor corruption, interrupted transactions, redirect collisions, explicit array clears, simulated IO/access errors and safe RefreshOutput behavior.

All writing tests use GUID-named disposable directories under the system temporary directory. Synthetic `.uasset`/`.umap` payloads contain text and are never loaded in Unreal. IO/access failures are controlled script exceptions; tests do not fill disks, change OS settings or damage permissions. File locking and read-only flags apply only to fixture files. Tests hash file contents and enumerate directories, rather than trusting success messages.

`SourceConfigAudit.json` records a separate read-only inspection of all seven local sample config files. SHA-256 values were compared before and after extraction. Selected source assignment counts: AssetManager 8, Input 82, GameplayTags 53, Runtime 42, NetworkPrediction 1. The source descriptor was inspected read-only. No real host project was used for Install, Update, validation cloning, build, Editor or PIE.

## Acceptance matrix

| Area | Status | Evidence / boundary |
| --- | --- | --- |
| PowerShell syntax and distributed scripts | PASS | Native parser and package/tool equality checks |
| Clean install, legacy upgrade, Blank/customized hosts | PASS | Both local suites |
| Repeat update and INI idempotence | PASS | Host/plugin hashes and semantic config assertions |
| Maps/GameModes and unrelated settings | PASS | Existing regression snapshots and new metadata checks |
| AssetManager, tags, DDCVars and safe array merge | PASS | Both suites; source Foley inspection |
| Backups and script-exception rollback | PASS | Copy/swap/INI/IO/access injection; snapshot/backup inventory checks |
| Dangerous paths, links, foreign plugin, corrupt package | PASS | Preflight rejection and filesystem invariance |
| Build InstallData protection and package completeness | PASS | Synthetic build, generated hashes, sync regression and required files |
| Dry-run without filesystem writes | PASS | Full fixture file/directory comparison |
| UE 5.8 descriptor/config generation | PASS | EngineVersion fixed to 5.8.0; generation against inspected source INIs |
| Full-size Epic payload build and performance/storage budget | PENDENTE | Synthetic payload used; no original sample build or original asset writes |
| Editor, PIE, cooking, inherited/platform INI behavior | PENDENTE | Unreal deliberately not run in this audit |
| Minimal necessary engine dependency set | PENDENTE | Preserve enabled source dependencies; asset-level necessity not proven |
| Power-loss/process-kill recovery automation | PENDENTE | Journals/manual recovery and retry barrier implemented; no claim of atomic multi-file crash recovery |

## Residual limits

- The toolkit supports local Windows/PowerShell 7 paths and explicit UE 5.8 engine associations. UNC, junction-based workspaces and custom engine GUID associations are rejected.
- A named mutex serializes cooperating toolkit writers. It cannot prevent unrelated processes changing files or substituting links between validation and mutation. Use a trusted workspace with Unreal and other project writers closed.
- Space/read-only preflight and ordinary exception recovery cannot guarantee success under later disk exhaustion, filesystem/device faults, access revocation or sudden power loss. Snapshot/backup paths are retained for manual recovery if rollback fails.
- Old installed manifests without an inventory cannot identify edits to overlapping old payload files. Their full plugin backup is retained; review migration deliberately. Old source packages must be rebuilt to distribute the new safety module.
- SHA-256 inventories provide integrity checks, not publisher authentication. A package contains executable PowerShell; use a trusted source.
- Renderer/skinning and platform/device settings remain host-owned. They may affect sample behavior; the suites do not assert complete engine config inheritance or runtime asset compatibility.
- RawCopy retains original asset internals and uses global redirects. Existing direct host asset collisions are rejected, but indirect references, assets in other plugins and engine/platform overrides require Unreal-level validation.
- FindConsoleObject frequency, Skinned Asset, audio and original Blueprint warnings were not “fixed” by arbitrary config changes or asset edits.
- Backups, transaction config snapshots and previous build outputs are never silently expired. Users must budget storage and deliberately remove reviewed history.

No production host was modified or used as a test target during this original script-only audit. The original sample was inspected read-only; no assets, INIs, descriptor, maps or Blueprints were changed. No Unreal process, remote CI, GitHub Action, package publication, release/tag, PR or main merge was performed.
