# Settings-only backup retention — 2026-11-07

Branch: `fix/settings-only-backup-retention`. Base: `8d0eb3f`.

## Cause and correction

Update previously moved the complete installed plugin into timestamped Backups and retained it indefinitely. Refresh builds likewise retained complete `.previous-*` outputs. These included assets and could accumulate gigabytes per operation. The project root itself was not backed up, but retaining the full plugin payload was unnecessary for permanent configuration recovery.

Permanent backups now contain only:

- Host managed INIs, `.uproject` and snapshot metadata (Update).
- Plugin INIs from Config/InstallData, `.uplugin` and install/ownership JSON metadata.
- `SettingsBackup.json` recording `BackupKind=SettingsOnly` and hashes of retained files.

No Content/assets, Tools/scripts, binaries or caches are retained in completed-operation backups. Asset names/hashes can still occur inside the install manifest; these are metadata, not copied assets.

The original plugin temporarily moves to `Transactions/<id>/PreviousPlugin` for full rollback before commit. After commit it is deleted. If deletion fails, the current plugin remains valid, an explicit error identifies the temporary payload, and the next host operation is blocked until recovery/cleanup is reviewed. Code never attempts rollback after deletion has started. Failed uncommitted updates restore the old plugin and host settings; partial incoming payloads are removed.

Refresh builds retain a small `.settings-backup-<guid>` and delete their temporary `.previous-*` after commit. The exported legacy replacement helper follows the same settings-only policy and cleans its transient payload.

Host transaction snapshots retain only configuration/journal files after success or successful rollback. Permanent settings backups cannot restore old assets after success; use the source package/version control or an independent asset backup when an asset-version restore is required.

## Regression evidence

- Native parser runs before execution of test code.
- Updated existing validation checks verify settings backup kind/inventory and reject non-settings payload extensions.
- Release suite checks settings hashes, preserved legacy descriptor metadata, temporary cleanup after ordinary and legacy RefreshOutput, existing pre-commit rollback injections, and idempotence/DryRun behavior.
- A dedicated fixture adds a 4 MB synthetic asset, installs and updates three times, then verifies all retained history files are INI/JSON/uproject/uplugin, total history is below 1 MB, no Package/PreviousPlugin/Content directories remain, and the active 4 MB asset still exists.
- A controlled failure before post-commit cleanup verifies the active plugin remains valid and retries fail without writing while temporary cleanup is pending.
- A direct call to the older exported replacement helper verifies it also retains settings only.

Tests use only GUID-named temporary synthetic fixtures. No real project, original Epic asset, historical backup, Unreal process, BuildCookRun, engine/OS configuration or remote CI is changed.

Final local results: toolkit validation suite PASS; **41/41 release safety PASS; 18/18 config staging PASS; 9 PowerShell files, 0 ParserErrors; git diff --check PASS**.

## Deployment and historical backups

Rebuild generated packages to distribute the corrected runtime tools, then use the new installer/updater. Old Tools copies in existing packages keep their old behavior until replaced through a rebuild.

Previously created backups and `.previous-*` outputs are intentionally not swept automatically: they can contain the only copy of older or user-edited assets. This change prevents new routine retention of asset payloads. Any cleanup of historical directories in real projects requires a separate explicit scope/review; this task does not modify protected real projects.

The earlier RELEASE_AUDIT and CONFIG_STAGING_AUDIT files describe historical behavior; this report and current README/TECHNICAL_README supersede their statements about retention of complete plugin backups.
