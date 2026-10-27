# Unreal Engine Forums post — DRAFT, NOT PUBLISHED

**Proposed category:** [Development → Pipeline & Plugins](https://forums.unrealengine.com/c/development-discussion/pipeline-plugins/147)

**Suggested title:** [Open Source] Game Animation Sample Plugin Toolkit — Reuse Epic's Sample in UE 5.8 Projects

> **Publication gate:** GitHub currently remains private. Publish this text only after the repository/history/license review and after the repository becomes publicly accessible. Include original demo screenshots/video only with permission to share the imagery; never attach original sample files or a generated plugin payload.

---

Hi Unreal Engine community,

I've been working on a way to reuse Epic's **Game Animation Sample** in existing UE projects without migrating the entire sample into every new project or losing control over the host project's configuration.

The result is the **Game Animation Sample Plugin Toolkit**: an open-source **PowerShell 7 workflow** that builds a reusable Unreal Engine content plugin **locally from your own Fab download**, then installs or updates it in another project.

### What it does

- Builds a local plugin package from the original Game Animation Sample project.
- Installs and updates the plugin with host-project preflight checks.
- Adds the necessary plugin dependencies and selectively integrates INI settings.
- Preserves your existing maps/game modes and merges relevant AssetManager scan directories.
- Supports `-DryRun` previews, integrity checks, timestamped plugin backups and rollback on handled failures.
- Avoids duplicate managed settings across updates.

The packaging implementation currently uses **RawCopy with generated redirects**. That means it is an integration tool—not a rewritten version of Epic's assets—and your particular project still needs Editor/runtime validation.

### Tested with UE 5.8.4

I tested the toolkit on **Windows / Unreal Engine 5.8.4** in an isolated copy of an existing host project, including Editor/PIE interactions, Motion Matching, character and camera switching, Win64 Development cooking and packaging, and standalone execution.

The final BuildCookRun completed successfully with **ExitCode 0**, and a separate staging correction eliminated an earlier warning for `DefaultNetworkPrediction.ini`. I also updated and functionally tested my original host project without changing its default map.

This is a tested workflow, but I can't guarantee compatibility with every host project or engine version.

### Getting started

1. Download [Epic's Game Animation Sample from Fab](https://www.fab.com/listings/880e319a-a59e-4ed2-b268-b32dac7fa016).
2. Clone the [Game Animation Sample Plugin Toolkit](https://github.com/marciocamello/game-animation-sample-toolkit).
3. Run the PowerShell build script against your local sample.
4. Preview and install the generated plugin in your own Unreal Engine project.
5. Open the sample map from the plugin content and test it in the Editor.

The GitHub repository contains **scripts, templates, tests and documentation only**. It **does not include Epic sample assets or a prebuilt content plugin**. Users obtain the sample separately through Fab.

**GitHub:** https://github.com/marciocamello/game-animation-sample-toolkit

**Original sample:** https://www.fab.com/listings/880e319a-a59e-4ed2-b268-b32dac7fa016

This is an independent community project from **Axchemy Studios**, not an official Epic Games plugin.

If you're reusing Motion Matching or character locomotion features from the sample in your own UE projects, I'd appreciate technical feedback, bug reports and compatibility results.

---

**Suggested tags:** `unreal-engine`, `plugins`, `motion-matching`, `animation`, `powershell`

**Optional media:** 30–60-second demonstration of plugin content under a host project, `DefaultLevel` PIE footage, and a before/after `DefaultGame.ini` staging snippet; avoid portraying a prebuilt Epic sample asset bundle as a downloadable release.
