# Game Animation Sample Plugin Toolkit

PowerShell toolkit for locally converting the Epic **Game Animation Sample** project into an installable, updateable Unreal Engine content plugin. This repository contains the **installer and update scripts**, not the sample assets or a prebuilt plugin.

Prepared by **Axchemy Studios - Marcio Vale CEO**

- Website: https://www.axchemy.com/
- GitHub: https://github.com/marciocamello
- Repository: https://github.com/marciocamello/game-animation-sample-toolkit

## What this repository contains

- PowerShell automation to build, install, validate, and update the plugin package
- An optional Unreal Python duplication experiment (not used by the active RawCopy build)
- managed `.ini` templates for host project integration
- technical documentation and redistribution notices

## What this repository does not contain

This repository is intentionally **source-light** and **GitHub-safe**.

It does **not** include:

- Epic sample assets
- generated plugin content payloads
- `.uasset` or `.umap` files
- caches, cooked data, or Unreal build artifacts

The expectation is that contributors already have local access to the Epic Game Animation Sample project and use that local copy as the input for the build step.

## How to get the sample

1. Sign in with your Epic Games account.
2. Open the Fab listing for the Game Animation Sample: https://www.fab.com/listings/880e319a-a59e-4ed2-b268-b32dac7fa016
3. Add the sample to your library or acquire it for free if the listing shows the free flow.
4. Install and open the Epic Games Launcher if you prefer to download from the launcher.
5. In the launcher, open `Fab`, locate the sample in `My Library`, and download it to disk.
6. Open the downloaded sample project in Unreal Engine 5.8 once to let the engine register plugins and project metadata.
7. Keep that local sample project on disk. This repository uses it as the source input for the build script.

## Repository layout

- `Build-GameAnimationSamplePlugin.ps1`
- `Install-GameAnimationSampleToProject.ps1`
- `Update-GameAnimationSampleInProject.ps1`
- `Validate-GameAnimationSampleToolkit.ps1`
- `Clean-Build-GameAnimationSamplePlugin.ps1`
- `Scripts/`
- `Templates/`
- `README.md`
- `TECHNICAL_README.md`
- `LICENSE`
- `NOTICE`
- `THIRD_PARTY.md`

## Quick start

**Tested environment:** Windows 11, PowerShell 7, Unreal Engine **5.8.4**, and the Epic Game Animation Sample obtained separately from [Fab](https://www.fab.com/listings/880e319a-a59e-4ed2-b268-b32dac7fa016). Other UE/platform combinations have not been verified. Work in a trusted local workspace and close Unreal Editor before installing or updating.

1. Clone this toolkit repository and open PowerShell 7 in its root.
2. Download the Game Animation Sample from Fab and open its original `.uproject` once in UE 5.8.
3. Choose a **separate output directory** for the generated plugin and set the paths below (replace the examples with your paths):

~~~powershell
$sample = "C:\Unreal\GameAnimationSample"
$hostProject = "C:\Unreal\MyGame\MyGame.uproject"
$package = "C:\UnrealPackages\GameAnimationSample"

pwsh -File .\Build-GameAnimationSamplePlugin.ps1 -ProjectRoot $sample -OutputRoot $package
~~~

4. Preview installation without writing anything, then install only after the plan passes:

~~~powershell
pwsh -File .\Install-GameAnimationSampleToProject.ps1 -HostProject $hostProject -PackageRoot $package -DryRun
pwsh -File .\Install-GameAnimationSampleToProject.ps1 -HostProject $hostProject -PackageRoot $package
~~~

5. Open the host project and verify the plugin content and `/GameAnimationSample/Levels/DefaultLevel` in the Editor/PIE. Installing the plugin does **not** change the host's default startup map.

When the source sample or toolkit changes, rebuild the **same separate output directory** with `-RefreshOutput`, preview the Update, then apply it:

~~~powershell
pwsh -File .\Build-GameAnimationSamplePlugin.ps1 -ProjectRoot $sample -OutputRoot $package -RefreshOutput
pwsh -File .\Update-GameAnimationSampleInProject.ps1 -HostProject $hostProject -PackageRoot $package -DryRun
pwsh -File .\Update-GameAnimationSampleInProject.ps1 -HostProject $hostProject -PackageRoot $package
~~~

**Alternative output:** Omitting `-OutputRoot` generates `<sample-project>\Development\Plugins\GameAnimationSample`. If you choose that layout, use that exact directory as `-PackageRoot` for Install and Update. Never point `-PackageRoot` at the toolkit repository itself.

**Optional host verification:** `pwsh -File .\Validate-GameAnimationSampleToolkit.ps1 -HostProject "<host-project-directory>" -PackageRoot "<generated-package>"` exercises reconciliation in a temporary host clone. For a no-write preview without cloning, use Install/Update `-DryRun`. The validation script without arguments runs its synthetic self-tests.

**Operational notes:** Install refuses to replace a preexisting plugin; use Update for toolkit-owned installations. A multi-GB package operation may take time and may not display a progress bar. Do not assume it is frozen solely because no progress bar appears; inspect the final `[Success]` result. Do not copy PowerShell's `>>` continuation prompt into commands. Backups and transaction snapshots are retained for recovery and can consume significant disk space.

## Host-project safety contract

- Install and update preserve the host project's existing game/editor/server maps, game modes, and user-defined INI scalar values.
- For an existing AssetManager `Map` or `PrimaryAssetLabel` entry, the toolkit adds the plugin scan directory to that existing entry. It does **not** delete the host scan directories or append a competing duplicate type. This is deliberately an additive change to the host's own asset scan entry.
- Existing matching host input mappings, profiles, redirects, tags and named CVars are not duplicated. Conflicting channels, collision profiles and redirects abort during preflight. Explicitly disabled dependencies and cleared host arrays also require deliberate resolution.
- Source-sample `-` and `!` array mutations are filtered out; they are never replayed into the host. Managed INI entries include their explicit section headers.
- Before install/update, the toolkit validates package identity, paths, dependencies and every INI merge in memory. It stages and hashes the incoming plugin before replacing anything. On failure it restores the .uproject, managed INIs and previous plugin. Recovery snapshots and transaction journals remain under `Saved/GameAnimationSampleToolkit/Transactions` on success and failure.
- Updates keep timestamped copies of the previous plugin under `Saved/GameAnimationSampleToolkit/Backups`. Host data outside the toolkit-managed files is not replaced.
- If the host has incompatible collision-channel or redirect entries, **the operation fails**. Resolve such conflicts deliberately; automatic overriding is unsafe.
- Install never replaces an existing plugin. Update requires toolkit ownership metadata. New packages include a SHA-256 inventory; edited managed plugin files block updates, and additional non-conflicting user files are preserved. Older installed packages without inventories can be upgraded, but overlapping edits in their old payload cannot be detected; review their complete backup.
- Local paths only: drive roots, UNC/device paths, parent traversal, links and reparse points are rejected. A named mutex serializes toolkit operations per host. Close Unreal Editor and other writers before installation; these tools cannot lock an entire project against external applications.
- RawCopy redirects that would shadow an existing host `.uasset` or `.umap` fail preflight.
- Install/Update add a host-derived `[Staging]` permission for `DefaultNetworkPrediction.ini` in `DefaultGame.ini`. Existing staging entries are preserved; explicit conflicting host deny/remove/clear policies abort preflight.

Preview an operation without writing any files or directories:

```powershell
pwsh -File .\Install-GameAnimationSampleToProject.ps1 -HostProject "<host.uproject>" -PackageRoot "<package>" -DryRun
pwsh -File .\Update-GameAnimationSampleInProject.ps1 -HostProject "<host.uproject>" -PackageRoot "<package>" -DryRun
```

PowerShell callers receive a plan object containing `Files` (paths and proposed complete contents), `PackageFiles`, `ReplacedFiles`, `PreservedFiles`, dependencies, destination, host snapshot root, estimated additional bytes and the proposed Update backup path. Dry-run checks cannot guarantee future free space or write permissions; it performs no write probe.

**Validation status (2026-10-27):** The maintainer completed real UE **5.8.4** checks in an isolated copy of an existing host project: plugin packaging, transactional update, Editor/PIE, Motion Matching/character/camera interaction, Windows cooking, Win64 Development BuildCookRun (**3,352 cooked packages; ExitCode=0**), and packaged standalone execution. After the NetworkPrediction staging change, a repeat BuildCookRun finished successfully, included `DefaultNetworkPrediction.ini`, and no longer emitted the prior unclassified-config warning. The original host project was subsequently updated and functionally tested by the maintainer; its `GameDefaultMap` remained unchanged. These are maintainer-run results on specific projects, **not** a universal compatibility guarantee, a clean blank-project certification, or a claim of testing other UE versions/platforms.

## Automated non-Editor tests

Run the local suites; none needs Unreal Editor or Epic assets:

```powershell
pwsh -File .\Validate-GameAnimationSampleToolkit.ps1
pwsh -File .\Tests\Test-ReleaseSafety.ps1
pwsh -File .\Tests\Test-ConfigStaging.ps1
```

The release safety suite parses PowerShell scripts, builds a synthetic RawCopy package and checks preflight, idempotence, backups, injected IO/access failures, rollback, and DryRun filesystem invariance. The last reported local run passed **38/38 release safety** and **18/18 staging** tests (9 PowerShell files parsed without errors). The real-engine follow-up is recorded as an addendum to `Tests/CONFIG_STAGING_AUDIT.md`; historic limitations in `Tests/RELEASE_AUDIT.md` are retained with their original scope. These tests are local; this repository does not claim automated CI coverage.

## Documentation and release preparation

- [`TECHNICAL_README.md`](TECHNICAL_README.md): implementation, host INI integration, recovery and limitations.
- [`Epic-Community-Tutorial.md`](Epic-Community-Tutorial.md): step-by-step community guide.
- [`Tests/CONFIG_STAGING_AUDIT.md`](Tests/CONFIG_STAGING_AUDIT.md): staging regression tests and subsequent Unreal verification.
- [`docs/PUBLIC_RELEASE_CHECKLIST.md`](docs/PUBLIC_RELEASE_CHECKLIST.md): remaining gates before switching repository visibility to public.
- [`docs/RELEASE_NOTES_v0.1.0.md`](docs/RELEASE_NOTES_v0.1.0.md): proposed, not-yet-published release notes.
- [`docs/UNREAL_FORUM_POST_DRAFT.md`](docs/UNREAL_FORUM_POST_DRAFT.md): forum announcement draft; not published.

## Licensing

Automation scripts and documentation are released under the MIT License.

Epic-owned sample content and derivative assets remain subject to Epic's applicable content license terms and are **not** relicensed by this repository. The public GitHub repository and any source-only toolkit release must exclude Epic source assets and converted plugin payloads. See [Fab Standard License](https://www.fab.com/eula) and [`THIRD_PARTY.md`](THIRD_PARTY.md); verify the license applicable to your specific acquisition.
