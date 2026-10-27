# Game Animation Sample Plugin

Technical integration guide for the Unreal Engine community.

Prepared by **Axchemy Studios - Marcio Vale CEO**

- Website: https://www.axchemy.com/
- GitHub: https://github.com/marciocamello
- Repository: https://github.com/marciocamello/game-animation-sample-toolkit

## 0. Quick Start

Before you run any script, get the Epic sample locally:

1. Sign in to your Epic Games account.
2. Open the Fab listing for the Game Animation Sample: https://www.fab.com/listings/880e319a-a59e-4ed2-b268-b32dac7fa016
3. Add the sample to your library or acquire it for free if the listing shows the free flow.
4. Download the sample with the Epic Games Launcher or via Fab in Unreal Engine.
5. Open the downloaded sample project once in Unreal Engine 5.8 so the engine registers the project and plugins.
6. Keep that local sample project on disk. The build script uses it as the source input.

The intended execution order is:

1. build the package from the local sample
2. install or update the host project
3. run validation only if you want a dry-run audit against a host snapshot

Important:

- This repository does not contain Epic sample content.
- The repository only contains the automation, docs, and config templates needed to package the sample locally.
- The downloaded sample should stay outside GitHub and remain on your machine as the build source.

## 1. Purpose

This repository converts the Epic **Game Animation Sample** project into a reusable project plugin workflow.

The goal is to:

- keep the original sample project untouched
- generate a reusable plugin package under `Development\Plugins\GameAnimationSample`
- support first-time installation in a host project
- support future package updates without overwriting the host project's own settings

This repository is intended for **Unreal Engine 5.8** projects.

## 2. Package Structure

After running the build step, the generated package contains (the build script itself stays in the cloned toolkit repository):

- `GameAnimationSample.uplugin`
- `Content\...`
- `Config\...`
- `Build\SourceConfig\...` (inactive source-config archive)
- `InstallData\...`
- `Tools\Install-GameAnimationSampleToProject.ps1`
- `Tools\Update-GameAnimationSampleInProject.ps1`
- `Tools\Scripts\GameAnimationSampleTools.psm1`
- `Tools\Scripts\GameAnimationSampleSafety.ps1`
- `GameAnimationSample.install.json`
- `README.md`
- `TECHNICAL_README.md`
- `LICENSE`
- `NOTICE`
- `THIRD_PARTY.md`

## 3. Build Workflow

### 3.1. Source Project

The source project is the local Epic Game Animation Sample project. The build process does **not** remove content from the source project.

### 3.2. Build Command

Run:

`pwsh -File .\Build-GameAnimationSamplePlugin.ps1 -ProjectRoot "<path-to-your-local-GameAnimationSample>" -OutputRoot "<separate-output-directory>\GameAnimationSample"`

This explicit `-OutputRoot` path **is the package directory**. Pass that exact path as `-PackageRoot` to Install, Update, and DryRun. Do not point `-PackageRoot` at the source sample or the toolkit repository. See the [README quick start](README.md#quick-start) for one consistent set of example paths.

### 3.3. Build Output

Use `-OutputRoot` outside the source project for complete separation. For backward compatibility, omitting it writes generated files to:

`<sample-project-root>\Development\Plugins\GameAnimationSample`

### 3.4. Current Build Mode

The build writes a manifest file named `GameAnimationSample.install.json`. The active public build is PowerShell RawCopy mode; the Unreal Python duplication experiment is not executed by this workflow.

The public toolkit currently builds in **RawCopy** mode. That keeps the workflow non-destructive and avoids trying to clean or rewrite sample content in place. The package relies on redirects as a compatibility layer.

Important:

- rerun the build with `-RefreshOutput` when the source sample changes; existing output must pass toolkit package validation
- do not build twice over an older package directory without that explicit refresh
- stale content in the generated output can cause duplicate asset IDs and path conflicts in Unreal Editor

The builder creates a unique sibling staging directory, validates all required files, parses distributed PowerShell tools and verifies the generated SHA-256 inventory before committing. Existing output is renamed to `.previous-<guid>` and retained. A failed build leaves the prior package intact. `-DryRun` also works through the Clean-Build wrapper and writes nothing. Only `PluginName=GameAnimationSample` is supported.

Refresh validates the old output's Axchemy manifest/descriptor identity independently of current installability. Recognized legacy RawCopy outputs may lack the new safety module/inventory or use the old `5.8` descriptor string; these can be previewed and rebuilt. Installed host plugins and foreign identities are rejected. The newly built package still must pass full current package validation before replacing the old output.

## 4. First-Time Installation in a Host Project

### 4.1. Preconditions

The target project should:

- be an Unreal Engine 5.8 project
- allow project plugins under `<HostProject>\Plugins`
- not already contain a `Plugins\GameAnimationSample` folder

### 4.2. Install Command

Run:

`pwsh -File .\Install-GameAnimationSampleToProject.ps1 -HostProject "<path-to-host.uproject>" -PackageRoot "<generated-package-directory>"`

Use `-DryRun` first; close Unreal Editor before the real Install. If you used the default build output instead of `-OutputRoot`, `<generated-package-directory>` is `<sample-project-root>\Development\Plugins\GameAnimationSample`.

### 4.3. What the Installer Does

The installer performs the following steps:

1. validates local paths, package/descriptor identity, required files, script syntax, inventory hashes and host engine association
2. computes all INI and `.uproject` changes in memory and rejects incompatible host decisions before writes
3. snapshots the host files, stages the incoming package on the host volume and verifies copied hashes
4. commits the plugin directory and applies the planned host file contents, verifying each write
5. writes stable ownership metadata to `GameAnimationSample.host-install.json` and marks the transaction committed

Pass `-DryRun` to Install or Update to perform steps 1–2 without creating directories, snapshots or temporary files. The returned object includes `Files` (proposed complete contents), `PackageFiles`, `ReplacedFiles`, `PreservedFiles`, `Dependencies`, `PluginDestination`, `HostSnapshotRoot`, `EstimatedAdditionalBytes` and `Backup` (Update only). The proposed timestamped backup path is selected again on a later real run. Dry-run reads package and host configuration and checks available space/read-only attributes; it cannot prove future write access, disk availability or concurrent external changes without attempting writes.

### 4.4. Managed Host Config Files

The installer adds managed blocks to:

- `Config\DefaultGame.ini`
- `Config\DefaultInput.ini`
- `Config\DefaultGameplayTags.ini`
- `Config\DefaultEngine.ini`
- `Config\DefaultNetworkPrediction.ini`

These blocks are clearly delimited with:

- `; BEGIN AXCHEMY-GAME-ANIMATION-SAMPLE::<BlockId>`
- `; END AXCHEMY-GAME-ANIMATION-SAMPLE::<BlockId>`

This makes the integration idempotent and easier to audit.

### 4.5. Host Configuration Contract

The source config snapshot is archived under `Build/SourceConfig`, outside the active plugin `Config` directory. Host integration comes from selective extraction of the source INIs using the explicit section/key allowlist in `Tools\Scripts\GameAnimationSampleTools.psm1`. Unknown sections and keys are excluded. Templates supply the deliberate plugin AssetManager scan paths; source AssetManager scalar settings are extracted, while its project scan paths are excluded. Selected `/Game/` references are remapped to `/GameAnimationSample/`.

Source `+CVarsArray` definitions replace the template CVar list. Names are deduplicated case-insensitively, conflicting source defaults abort, and destructive `-`/`!` mutations are discarded. Existing host CVars win by `Name`, including custom values and different casing/spacing. Generated InstallData is hashed before and after runtime-tools synchronization and is never replaced by templates. Rebuild packages to receive source configuration changes.

GameplayTags and redirects are extracted from the source `DefaultGameplayTags.ini`, rather than a frozen list. The local source audited on 2026-10-26 defines `Foley.Event.Ragdoll`, `Foley.Event.Punch` and `Foley.Event.Kick`; these were absent from the old template. They now reach InstallData and the host without inventing asset dependencies or changing Blueprints. A different source sample only contributes tags that it actually defines.

Input and NetworkPrediction use their allowlisted source sections. Runtime extraction includes named sample custom collision profiles (`WaterBodyCollision`, `ObstaclePreset`, `TraversalObjectPreset`, `CharacterCapsule`), `Traversable`/`Mouse`/`Obstacle` channels, the sample Ragdoll profile edit, the Obstacle profile redirect, navigation/physics settings, selected console variables and PoseSearch buffer tuning. Engine baseline collision profiles are not imported wholesale. Host scalar settings take precedence; incompatible named collision/redirect definitions fail preflight.

`DefaultDeviceProfiles.ini` (Android/iOS device tuning), `DefaultEditor.ini`, renderer/platform settings, project identity, packaging maps and unknown configuration are excluded from host integration. Existing renderer/skinning settings may still affect sample behavior; asset/editor validation is required before deciding whether any of these host-owned settings should be adjusted manually.

The `DefaultEngine.Runtime` host block contains only explicitly validated runtime, console-variable, collision, physics, navigation, and other plugin settings. It never imports the source `GameMapsSettings` section or these host-owned settings:

- `GameDefaultMap`
- `EditorStartupMap`
- `ServerDefaultMap`
- `TransitionMap`
- `LocalMapOptions`
- `GlobalDefaultGameMode`
- `GlobalDefaultServerGameMode`

Array operations are merged and deduplicated where possible. Existing host scalar settings are retained instead of being blindly overwritten. Install and update also remove these settings from legacy Axchemy-managed blocks while preserving the host values outside those blocks.

### 4.6. Asset Manager directory merging and array conflicts

Unreal treats `PrimaryAssetTypesToScan` as unique by `PrimaryAssetType` (see Epic issue UE-178303). For an existing host `Map` or `PrimaryAssetLabel` entry, the toolkit extends `Directories` in the existing host line with the `/GameAnimationSample` path. It does not append a competing entry of that type, remove the original `/Game` directories, or rewrite the host's other fields. This is the one intended additive edit to an unmanaged host line. Repeating install/update does not append the path twice. If the host already has multiple entries of the same type, an unsupported structure, or a conflicting collision channel or package redirect, the script fails rather than guessing.

The importer discards legacy `-` and `!` source-template array operations. User-owned input mappings and scalar settings take precedence. Every inserted managed block has the correct INI section header, including when the host already has that section elsewhere.

### 4.7. UE 5.8.4 config staging

Install/Update generate a separate `DefaultGame.Staging` block in the host's `Config/DefaultGame.ini`:

```ini
[Staging]
+AllowedConfigFiles=YourHost/Config/DefaultNetworkPrediction.ini
```

`YourHost` comes from the actual `.uproject` filename, not its folder or the original sample name. The name is resolved at host preflight, never embedded in package InstallData. It follows AutomationTool's `GetShortProjectName` behavior (all filename extensions removed). A renamed host updates its managed entry on the next Update.

Unreal 5.8.4 automatically recognizes the managed Engine, Game, Input and GameplayTags INI suffixes, but not NetworkPrediction. An unclassified config is still staged by default and emits a warning. The explicit allowance documents that this runtime config is intentional. No blanket allowance or denial is introduced. Existing `[Staging]` sections, other plugin permissions and unrelated settings remain in place. Matching paths deduplicate with case/slash/quote normalization, including plain and dot-prefixed assignments.

An explicit `DisallowedConfigFiles` match, removal of the required allowance or clear of the host allowance array fails preflight instead of silently overriding host intent (AutomationTool checks allows before denies). Policy checks inspect the host's DefaultGame.ini; engine/platform/custom hierarchy or directory remaps require final Unreal verification. Source-sample staging entries are not imported. The generated entry is part of the same in-memory DefaultGame plan and existing config snapshot/transaction, including DryRun and rollback. Newly built manifests and host ownership metadata list `DefaultGame.Staging`; no additional host files are written.

Rebuild the package to distribute updated runtime scripts, then run Update/DryRun using that same package directory. **The separate Unreal check has now been completed:** on 2026-10-27 the maintainer rebuilt and updated an isolated host, confirmed `DefaultGame.ini` contained the host-derived allowance, and successfully reran Win64 Development BuildCookRun. Its staging manifest included `DefaultNetworkPrediction.ini` with **no recurrence of the earlier unclassified-config warning**; the final AutomationTool ExitCode was 0. This observation applies to the tested UE 5.8.4 setup, not arbitrary platform configuration hierarchies. See `Tests/CONFIG_STAGING_AUDIT.md` for the historic investigation and follow-up result.

### 4.8. Install/update recovery

Before changes, the toolkit creates a snapshot of the host's `.uproject` and every existing managed INI under `Saved\GameAnimationSampleToolkit\Transactions\<unique-id>`. Missing INIs remain absent in the snapshot and are removed on rollback. When installation fails, it restores these files and removes only the plugin created by that transaction. Update moves the previous plugin to the timestamped backup and restores it on failure. The previous plugin is moved, rather than deleted or copied over. Staged package copies are verified by SHA-256 before the swap.

Snapshots are retained on success and failure, alongside a `Transaction.json` journal (`Preparing`, `Prepared`, `Committed`, `RolledBack`). Successful rollback deletes partial staging payloads. An unfinished journal blocks subsequent operations until recovery is reviewed. Plugin backups retain the legacy layout and timestamp/collision suffix naming; no automatic retention deletion occurs. Host recovery files are in the associated transaction snapshot, not mixed into the old plugin payload.

If rollback itself cannot complete, the error includes the snapshot location for manual recovery. This is best-effort script-level rollback; an OS crash or sudden power loss is not a fully atomic filesystem transaction. Keep the original project in version control and back up the project before the first installation.

For manual recovery, close Unreal and all project writers. Read the journal and preserve both directories first. Restore `HostProject.uproject` to the exact host descriptor and each snapshotted `Config` file to the host. For managed INIs absent in the snapshot, remove only files known to have been created by the interrupted transaction. For Update, restore the complete plugin backup to `Plugins/GameAnimationSample`; for Install, remove only the partial plugin identified in that journal. Recheck hashes/config and deliberately mark the reviewed journal `RolledBack` before retrying. Do not replay snapshot paths from untrusted sources. There is no automatic crash-recovery command.

Only local filesystem paths are supported. Roots, UNC/device paths, alternate streams, `..` traversal, symbolic links, junctions, hard links and other reparse points in inspected paths are rejected. Source/package and host must not overlap. Host resolution from a parent folder uses the actual `.uproject` parent as the write root. A named mutex serializes toolkit writers for the same host; it does not prevent third-party applications from changing files after preflight. Run with the editor closed in a trusted workspace. Package hashes detect accidental corruption; they do not authenticate an untrusted package or its executable tools.

### 4.9. What the Installer Does Not Do

The default installer does **not**:

- replace the host project's default map
- replace the host project's editor startup map
- overwrite the host project's config files wholesale
- remove the host project's own custom settings

## 5. Update Workflow

### 5.1. Rebuild the Package

When Epic ships a newer version of the sample:

1. update your local source `GameAnimationSample`
2. run the build step again
3. inspect the regenerated manifest at `<generated-package-directory>\GameAnimationSample.install.json` (the default directory is `<sample-project-root>\Development\Plugins\GameAnimationSample`)

### 5.2. Update the Host Project

Run:

`pwsh -File .\Update-GameAnimationSampleInProject.ps1 -HostProject "<path-to-host.uproject>" -PackageRoot "<generated-package-directory>"`

Run this first with `-DryRun`, then without it after checking the proposed changes. `<generated-package-directory>` is the same exact output path chosen for the build.

### 5.3. What the Update Script Does

The update flow:

1. requires installed toolkit ownership metadata and compatible package identity
2. validates the new package and plans every host configuration change before writing
3. stages and verifies the new payload, then moves the old plugin into a unique backup
4. commits the replacement and applies the planned INI/descriptor changes with rollback on failure
5. retains the host recovery snapshot and previous plugin backup

User changes to files tracked by a new package's inventory block Update. Unmanaged additional files are preserved if they do not collide with incoming package paths; collisions abort. Legacy installed packages without an inventory remain upgradeable, but edits to their overlapping payload files cannot be identified reliably. Review their complete backup before migration. Rebuild legacy *source packages* to include current safety tools before using this release. `-FromManifest` may reference only the manifest inside `PackageRoot`; external overrides are rejected.

This lets you move the host project forward without replacing unrelated project decisions.

### 5.4. Rebuild Discipline

The build output is not auto-cleared in the public toolkit.

Before rebuilding from a changed source sample or distributing updated installer tools, rerun the builder with `-RefreshOutput` (and the **same** `-OutputRoot` if used) so the previous generated package output is replaced explicitly while retaining its reviewed backup.

If you do not, stale assets from the previous build can remain in the generated package and surface later as duplicate asset IDs or mount path conflicts.

## 6. Required Unreal Engine Plugins

The package currently enables the following engine plugins in the host project:

- `AnimationLocomotionLibrary`
- `AnimationWarping`
- `Chooser`
- `CurveExpression`
- `DrawDebugLibrary`
- `GameplayInteractions`
- `HairStrands`
- `LiveLink`
- `LiveLinkControlRig`
- `Locomotor`
- `MetaHumanLiveLink`
- `ModelingToolsEditorMode` (Editor target)
- `MotionWarping`
- `Mover`
- `NetworkPrediction`
- `PoseSearch`
- `RigLogic`
- `SmartObjects`

The list above describes an earlier sample revision and is illustrative. Actual dependencies are the enabled entries in the current source descriptor, copied into both the package descriptor and manifest and checked for agreement. The locally audited source also enables ChaosMover, AnimationLayering, MoverExamples and MovieSceneAnimMixer and does not enable MetaHumanLiveLink. Dependency minimization beyond that source contract requires asset-level validation and remains unproven. Existing host metadata and target restrictions are preserved; an explicitly disabled required plugin aborts preflight. Engine plugin availability is ultimately resolved by Unreal, which this local test suite does not run.

## 7. Validation Checklist

After installation in a clean project, validate the following:

1. the plugin appears under `Plugins\GameAnimationSample`
2. the host `.uproject` has `GameAnimationSample` enabled
3. the required engine plugins were added
4. the managed blocks exist in the host `.ini` files
5. Unreal Editor opens without immediate config or plugin dependency errors
6. plugin content appears in the Content Browser
7. the sample map can be opened manually from plugin content
8. gameplay tags, input mappings, collision channel setup, and network prediction settings are present
9. `[Staging]` includes the host-derived allowance for `DefaultNetworkPrediction.ini`, with no classification warning in a subsequent Windows package build
10. package/standalone functionality and the host's original `GameDefaultMap` are checked independently

### 7.1. Maintainer's UE 5.8.4 acceptance evidence (2026-10-27)

The maintainer reported and supplied logs for a Windows UE 5.8.4 session using a **separate test copy of an existing host project**, not a newly created empty template. The local plugin package was rebuilt; transactional Update and host INI preservation passed. Editor/PIE loaded the sample map, Motion Matching/PoseSearch, and character/camera interaction. A Win64 Development BuildCookRun completed with 3,352 cooked Windows packages and AutomationTool ExitCode 0; the packaged standalone game ran and exited normally. A **second** BuildCookRun after the staging fix confirmed that the unclassified `DefaultNetworkPrediction.ini` warning was absent. The original host then received the updated package, preserved `GameDefaultMap=/Engine/Maps/Templates/OpenWorld`, and passed the maintainer's functional check.

This is evidence for the **tested host and platform only**. It is not an automated compatibility matrix, clean blank-host certification, full dependency minimization, proof against all asset path collisions, or test of non-Windows platforms. The synthetic safety/staging suites separately passed 38/38 and 18/18 checks; they do not run the Unreal Editor. See [staging audit and validation addendum](Tests/CONFIG_STAGING_AUDIT.md).

## 8. Toolkit Verification Script

The local verifier is optional. Use it when you want a dry-run audit before touching a real host project, or when you want to inspect install/update reconciliation in a temporary clone:

```powershell
pwsh -File .\Validate-GameAnimationSampleToolkit.ps1 -HostProject "<path-to-host-project>" -PackageRoot "<path-to-generated-package>"
```

This mode clones the host project into a temporary workspace, runs the same install/update reconciliation used by the toolkit, and verifies the resulting files without modifying the source project.

The install and update scripts themselves already perform idempotent reconciliation directly on the target host project. The no-argument validation mode executes a synthetic test fixture with repeated updates and rollback checks; it does not require the Epic sample, Unreal Editor, or PIE. They are the real workflow. The verifier is only for preflight checks and regression inspection.

If you want the built-in self-test mode instead, run:

```powershell
pwsh -File .\Validate-GameAnimationSampleToolkit.ps1
```

What the host-audit mode checks:

1. duplicate Axchemy-managed `.ini` blocks collapse to one canonical block
2. existing user `.ini` settings outside managed blocks are preserved
3. `.uproject` plugin entries are deduplicated by `Name`
4. required Game Animation Sample plugins are enabled; explicitly disabled dependencies fail preflight
5. repeated install/update runs remain idempotent

Also run `pwsh -File .\Tests\Test-ReleaseSafety.ps1`. It parses all repository PowerShell files, builds synthetic payloads, invokes distributed tools, verifies dry-run filesystem invariance and injects controlled copy/config/IO/access failures. It never uses a real host, Unreal Editor or PIE. See `Tests/RELEASE_AUDIT.md` and `Tests/SourceConfigAudit.json` for evidence and limitations. Full-size Epic payload packaging, cooking and UE runtime behavior are separate acceptance items.

## 9. Known Limitation

The ideal end state is a full content duplication into the plugin mount point:

`/GameAnimationSample/...`

However, the current Unreal Editor duplication pass still reports many failures for this sample. Because of that, the package currently ships in **RawCopy** mode plus generated package redirects.

This means:

- the workflow is implemented and testable
- install and update automation are implemented (validate in your environment before production use)
- config merging is working
- the remaining risk is runtime/editor compatibility for sample assets that still assume `/Game/...` paths

If deeper compatibility issues appear in another host, capture the exact asset references and logs before proposing a fallback. A controlled, collision-safe installation of selected content under `/Game` is a possible future design, **not** behavior currently implemented or promised by this toolkit.

## 10. Troubleshooting

### 10.1. Plugin already exists

If installation fails because the plugin already exists in the host project, use the update script instead of the install script.

### 10.2. Missing engine plugins

If Unreal still reports missing plugin dependencies, open the host `.uproject` and confirm the generated plugin list includes the required entries from the manifest.

### 10.3. Config conflicts

The integration is block-based. Inspect the host `.ini` files and review only the managed sections delimited by the Axchemy markers.

### 10.4. Asset load errors

Inspect:

- `Build\BuildReport.json`
- `GameAnimationSample.install.json`
- Unreal Editor output log

If the package is in `RawCopy` mode, asset path assumptions are the first thing to verify.

### 10.5. Runtime performance observations (UE 5.8.4)

The maintainer reported 14 FindConsoleObject performance-warning occurrences, over 100 startup PSO creation hitches and 44.1-to-48 kHz audio-conversion warnings after successful standalone validation. These counts are observations from that run, not measurements reproduced by the script suite. They do not establish a toolkit installation failure.

FindConsoleObject warnings describe repeated runtime lookups; the UE implementation recommends caching the console object. The PowerShell toolkit defines missing source CVars but does not execute runtime lookups. Identify the callers (original Blueprint/C++ consumers, engine or dependent plugins) using traces before attributing a specific warning to Epic assets. Changing defaults or disabling diagnostics does not address lookup frequency.

PSO hitches concern runtime graphics-pipeline creation and cache coverage. Profile representative character/camera/material paths and compare cold/warm starts; evaluate PSO precaching or bundled caches as a separate host optimization. The toolkit does not generate PSO caches or enforce renderer policies. See [Epic PSO caches](https://dev.epicgames.com/documentation/unreal-engine/optimizing-rendering-with-pso-caches-in-unreal-engine).

Audio conversion is consistent with source/stream and mixer sample-rate mismatch. Without the complete warning and asset/stream context, the exact conversion stage is unproven. Inspect audio format and platform mixer/cook settings separately; the toolkit does not resample original assets or force the host to a different mixer rate. See [Epic Audio Mixer overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/audio-mixer-overview).

These are scoped performance investigations, not reasons to modify original Epic assets or apply arbitrary global configuration changes in this release-hardening fix. Full evidence and remaining checks are in `Tests/CONFIG_STAGING_AUDIT.md`.

### 10.6. Long operations and PowerShell command entry

The package contains several gigabytes of source-derived content. Package hashing, preflight and Update can take time without a visible progress bar. Wait for the terminal's explicit `[Success]`/failure result; do not interpret a missing progress display alone as proof of a hang. If there is an actual failure, retain the full console output and the transaction journal instead of immediately rerunning the operation. The PowerShell `>>` secondary prompt is **not** part of commands copied from the console. The imported-module warning about unapproved PowerShell verbs is non-fatal and distinct from Install/Update failure.

## 11. Licensing and Attribution

Automation scripts and documentation in this repository are released under the MIT License.

Epic-owned sample content and derivative assets copied from the Unreal Engine Game Animation Sample are **not** relicensed under MIT and remain subject to Epic's applicable content license terms. In particular, Fab's Standard License restricts standalone redistribution of licensed assets: do not publish the generated plugin payload, sample source content, `.uasset`/`.umap` files, or converted asset bundles as a public toolkit release. Users must obtain the sample from Epic/Fab themselves. Verify the terms applicable to the individual sample acquisition. Reference: [Fab Standard License](https://www.fab.com/eula) and [original sample listing](https://www.fab.com/listings/880e319a-a59e-4ed2-b268-b32dac7fa016).

Keep the following files together when redistributing the repository:

- `LICENSE`
- `NOTICE`
- `THIRD_PARTY.md`

## 12. Recommended Community Usage

For community testing, the recommended sequence is:

1. build the package from the local sample project
2. install it into a clean Unreal Engine 5.8 project
3. open the project and validate plugin availability
4. manually open the sample map from plugin content
5. document any asset path or redirect issues before wider release

That provides an auditable, repeatable starting point. Before opening this repository to the public, consult the [public release checklist](docs/PUBLIC_RELEASE_CHECKLIST.md) and ensure no Epic payload or secret is reachable from the Git history. A draft announcement is maintained in [docs/UNREAL_FORUM_POST_DRAFT.md](docs/UNREAL_FORUM_POST_DRAFT.md).
