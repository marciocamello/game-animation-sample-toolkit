# Turn the Game Animation Sample Into an Updateable Unreal Engine Plugin

**Unreal Engine 5.8 | Windows | PowerShell 7**

This tutorial explains how to keep Epic's **Game Animation Sample** as a local source project, package it as a reusable Unreal Engine content plugin, install it into another project, and update it later without replacing the host project's maps and settings.

The [Game Animation Sample Plugin Toolkit](https://github.com/marciocamello/game-animation-sample-toolkit) is a community project from **Axchemy Studios**. It provides the automation; **it does not distribute the Game Animation Sample or a prebuilt content plugin**.

## Why This Workflow Matters

The Game Animation Sample is useful for exploring Motion Matching, locomotion and character animation. However, bringing sample content into an existing Unreal project can involve more than copying assets: required plugins, project configuration, GameplayTags, inputs and asset references also need attention.

This toolkit provides a repeatable local workflow to:

- Keep your original Game Animation Sample project available as the source.
- Build a separate, reusable `GameAnimationSample` plugin package.
- Preview and install the plugin in a host project.
- Preserve existing host maps, game modes and unrelated settings.
- Rebuild and update later, with backups and transaction recovery.

The current package uses **RawCopy with generated asset redirects**. It does not rewrite all internal asset references, so you should still validate the plugin in your own project.

## Get The Sample First

Download the official sample from Fab before using the toolkit:

**[Epic Games — Game Animation Sample on Fab](https://www.fab.com/listings/880e319a-a59e-4ed2-b268-b32dac7fa016)**

1. Sign in with your Epic Games account.
2. Open the Fab listing and add the sample to your library.
3. Download or create the sample project through Fab or Epic Games Launcher.
4. Open the downloaded source project once in **Unreal Engine 5.8**.
5. Keep the source project on your computer. The build script reads its local content and configuration.

**Important:** The toolkit's GitHub repository contains no Epic sample `.uasset` or `.umap` files, generated plugin payloads, or cooked assets. Every user must obtain the sample separately.

## Repository Contents

The toolkit repository includes:

- `Build-GameAnimationSamplePlugin.ps1` — generates the local plugin package.
- `Install-GameAnimationSampleToProject.ps1` — installs the generated package into a host project.
- `Update-GameAnimationSampleInProject.ps1` — updates a toolkit-owned installation.
- `Validate-GameAnimationSampleToolkit.ps1` — runs local tests or verifies host integration using a temporary copy.
- PowerShell safety modules, managed `.ini` templates, release tests and technical documentation.

An optional Unreal Python duplication experiment is present in the repository, but **the active packaging workflow uses PowerShell RawCopy**, not that experiment.

## Build The Plugin Package

Clone the [toolkit repository](https://github.com/marciocamello/game-animation-sample-toolkit) and open **PowerShell 7** in the repository root.

Run the builder using the path to your local Epic sample project:

~~~powershell
pwsh -File .\Build-GameAnimationSamplePlugin.ps1 -ProjectRoot "C:\Unreal\GameAnimationSample"
~~~

With the default output setting, the generated plugin package is placed at:

`C:\Unreal\GameAnimationSample\Development\Plugins\GameAnimationSample`

This is a **generated directory**, not the original sample's `Content` folder.

You can alternatively keep the generated package entirely outside the source project by supplying `-OutputRoot "C:\UnrealPackages\GameAnimationSample"`. If you do, use **that exact directory** as `-PackageRoot` in the commands below.

The builder packages content and configuration, generates asset redirects and installation metadata, and prepares the local plugin for host integration. It does not intentionally modify the original sample assets.

## Install Into A Clean Project

Choose a separate **Unreal Engine 5.8** host project and close its Unreal Editor before installation.

First preview the proposed changes with `-DryRun`:

~~~powershell
pwsh -File .\Install-GameAnimationSampleToProject.ps1 -HostProject "C:\Unreal\MyGame\MyGame.uproject" -PackageRoot "C:\Unreal\GameAnimationSample\Development\Plugins\GameAnimationSample" -DryRun
~~~

If preflight passes, run the actual install:

~~~powershell
pwsh -File .\Install-GameAnimationSampleToProject.ps1 -HostProject "C:\Unreal\MyGame\MyGame.uproject" -PackageRoot "C:\Unreal\GameAnimationSample\Development\Plugins\GameAnimationSample"
~~~

The installer:

- Copies the generated plugin into `<HostProject>\Plugins\GameAnimationSample`.
- Enables the plugin and required source-defined dependencies in the host `.uproject`.
- Reconciles selected `.ini` settings, including GameplayTags, inputs, runtime settings and AssetManager scan paths.
- Preserves the host's original default map and game modes.
- Checks for incompatible host configuration before writing, and retains a recovery snapshot.

The install does **not** set the Game Animation Sample level as your game's startup map.

## Verify The Plugin In Unreal Engine

Open the host project in Unreal Engine 5.8 after installation.

1. Confirm `GameAnimationSample` is enabled in the Plugins window.
2. In the Content Browser, enable **Show Plugin Content** if needed.
3. Open `/GameAnimationSample/Levels/DefaultLevel` manually.
4. Run **Play In Editor (PIE)** and check animation, Motion Matching, movement, characters and cameras.
5. Review the Output Log for missing dependencies, asset paths or configuration conflicts.
6. If you plan to package the project, perform a Windows cook/package and test the resulting executable.

Different host projects may contain conflicting assets or configuration; the toolkit is designed to reject several unsafe cases rather than overwrite them silently.

## Update Later

When you change your local source sample or update the toolkit, rebuild the generated package with `-RefreshOutput`:

~~~powershell
pwsh -File .\Build-GameAnimationSamplePlugin.ps1 -ProjectRoot "C:\Unreal\GameAnimationSample" -RefreshOutput
~~~

With Unreal Editor closed, preview and apply the update:

~~~powershell
pwsh -File .\Update-GameAnimationSampleInProject.ps1 -HostProject "C:\Unreal\MyGame\MyGame.uproject" -PackageRoot "C:\Unreal\GameAnimationSample\Development\Plugins\GameAnimationSample" -DryRun
~~~

~~~powershell
pwsh -File .\Update-GameAnimationSampleInProject.ps1 -HostProject "C:\Unreal\MyGame\MyGame.uproject" -PackageRoot "C:\Unreal\GameAnimationSample\Development\Plugins\GameAnimationSample"
~~~

The updater verifies ownership and compatibility, keeps a timestamped backup of the previous plugin, and reconciles managed settings without intentionally duplicating them. Host recovery snapshots and transaction journals are retained under `<HostProject>\Saved\GameAnimationSampleToolkit`.

For Unreal Engine 5.8, the toolkit also generates the host-specific `[Staging]` permission for `DefaultNetworkPrediction.ini` as part of the managed configuration, without overwriting unrelated staging rules.

## Validation

The toolkit was tested by the maintainer on **Unreal Engine 5.8.4**, Windows, in an isolated copy of an existing host project. Validation covered plugin packaging, host updates, Editor/PIE, Motion Matching, character and camera interactions, Win64 Development cooking, BuildCookRun and standalone execution.

The final Windows BuildCookRun completed with **ExitCode 0**, including **3,352 cooked Windows packages**. A follow-up staging check confirmed that `DefaultNetworkPrediction.ini` was included without the earlier staging-classification warning. The maintainer also updated and functionally tested the original host project, preserving its existing default map.

These results apply to the tested setup and do not imply that all custom host projects are automatically compatible.

## Recommended Workflow

1. Obtain the Game Animation Sample from Fab.
2. Open the source project locally in Unreal Engine 5.8.
3. Build the plugin package using the toolkit.
4. Preview installation using `-DryRun`, then install.
5. Verify the plugin content and sample map in your host project.
6. Rebuild with `-RefreshOutput` and run Update when needed.

## Troubleshooting

**The generated package already exists.** Rebuild with `-RefreshOutput` rather than manually deleting a verified older output.

**The plugin is already installed.** Use the Update script for a toolkit-owned installation; Install intentionally does not overwrite an existing plugin.

**The installer reports a conflict.** Check the reported `.ini`, collision profile, redirect or plugin setting. The toolkit refuses some changes when they could override a host decision.

**Some assets do not load.** Check plugin dependencies, the generated manifest and redirects, and the Unreal Output Log. RawCopy keeps some original asset-path assumptions.

**An operation takes time without showing a progress bar.** Large package verification/copy operations may not show continuous progress. Look for the final success/error message. The `>>` shown by PowerShell for multiline input is a prompt, not part of the command.

For deeper diagnostics, see the repository's [technical integration guide](https://github.com/marciocamello/game-animation-sample-toolkit/blob/main/TECHNICAL_README.md).

## Resources

- [Official Game Animation Sample — Fab](https://www.fab.com/listings/880e319a-a59e-4ed2-b268-b32dac7fa016)
- [Game Animation Sample Plugin Toolkit — GitHub](https://github.com/marciocamello/game-animation-sample-toolkit)
- [Toolkit README and complete usage instructions](https://github.com/marciocamello/game-animation-sample-toolkit/blob/main/README.md)
- [Technical integration guide](https://github.com/marciocamello/game-animation-sample-toolkit/blob/main/TECHNICAL_README.md)

## Final Notes

The goal is to make it easier to **reuse and update Epic's Game Animation Sample within your own Unreal Engine 5.8 projects**, without replacing host-owned settings or redistributing Epic's sample files.

The toolkit's own scripts and documentation are released under the MIT License. Epic's source assets and derivative content remain subject to their applicable Epic/Fab licensing terms; they are not relicensed or distributed by this repository.

**Developed by Axchemy Studios as an independent community project. Not an official Epic Games plugin.**
