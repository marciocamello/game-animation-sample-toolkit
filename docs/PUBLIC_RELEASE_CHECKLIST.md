# Public release checklist (draft; no publication authorized)

**Status:** Documentation prepared on `main` on 2026-10-27. Repository visibility is **private**. Do **not** make the repository public, create a tag or GitHub Release, upload a generated plugin package, or publish community announcements until the applicable gates are approved.

## Proposed positioning

- Project name: **Game Animation Sample Plugin Toolkit**.
- Recommended initial version: **v0.1.0** (proposal, not yet a tag or release).
- Tested: **Unreal Engine 5.8.4 / Windows 11 / PowerShell 7 / Win64 Development**.
- Other UE versions and operating systems: **not verified**.
- Distribution: source-only automation, templates, docs, tests and attribution. Users download Epic's sample themselves.
- License: MIT for original toolkit scripts/documentation only; Epic source assets remain under their own license.
- Independent Axchemy Studios community tooling, not affiliated with or endorsed by Epic Games.

## Mandatory gates before switching to Public

- [ ] **Audit current tracked files and all reachable Git history**, not just `.gitignore`. Inspect all branches, tags, deleted historical blobs, package archives, large objects and committed media for Epic sample assets, generated plugins and other material that is not authorized for redistribution.
- [ ] **Check secrets and privacy** in the same history: tokens/keys/passwords, connection strings, personal/user-specific local paths, internal references and sensitive logs. Treat a found secret as compromised and rotate it before publication. Do not assume deleting a file in the latest commit removes it from history.
- [ ] Confirm any third-party code or dependencies committed to this repository are legally redistributable. Review `LICENSE`, `NOTICE`, `THIRD_PARTY.md` and [Fab Standard License](https://www.fab.com/eula) plus the specific [Game Animation Sample listing](https://www.fab.com/listings/880e319a-a59e-4ed2-b268-b32dac7fa016).
- [ ] Confirm the GitHub source archive and proposed Release downloads contain **no** Epic `.uasset`, `.umap`, `.ubulk`, cooked files, prebuilt plugin payloads, generated sample code/config archives, local backups or caches. No standalone Epic asset redistribution.
- [ ] Check all README/tutorial commands against the current release scripts, with one consistent `-OutputRoot` / `-PackageRoot` relationship. Inspect docs links and filenames after the last edit.
- [ ] Verify repository **About** description and topics. Current remote description still mentions **Unreal Engine 5.7**; update to UE 5.8 (tested 5.8.4) as part of the approved publication changes.
- [ ] Check repository visibility and GitHub permissions, default branch, issue tracker, security reporting and any GitHub Pages/Actions workflows that would expose content.
- [ ] Run locally: `pwsh -File .\Validate-GameAnimationSampleToolkit.ps1`, `pwsh -File .\Tests\Test-ReleaseSafety.ps1`, `pwsh -File .\Tests\Test-ConfigStaging.ps1`; inspect `git diff --check` and working tree. These checks do not substitute for the asset/secret/history audit.
- [ ] Verify the source-only release notes accurately distinguish maintainer acceptance logs from the local synthetic tests, and note RawCopy/redirect risks.
- [ ] Have the maintainer approve the final public repository tree and **history** before changing the GitHub visibility.

## Already reported as verified (not an instruction to retest)

On 2026-10-27, the maintainer validated the generated package, transactional Update, host map preservation, UE 5.8.4 Editor/PIE/Motion Matching, Win64 Development BuildCookRun and packaged standalone behavior. A second BuildCookRun after the NetworkPrediction staging fix included the managed INI without the prior staging warning and completed with ExitCode 0, 3,352 cooked Windows packages. The original host was subsequently updated and functionally tested. Existing script suite results: 38/38 release safety, 18/18 staging. Details: [release audit](../Tests/RELEASE_AUDIT.md), [staging audit](../Tests/CONFIG_STAGING_AUDIT.md).

The above does **not** prove successful installation on every clean blank project or every UE/platform combination. The originally investigated full duplication flow is not shipped; the current plugin builder uses **RawCopy and generated redirects**.

## Proposed announcement materials

- [Proposed release notes](RELEASE_NOTES_v0.1.0.md)
- [Unreal Engine Forums post draft](UNREAL_FORUM_POST_DRAFT.md)
- [Step-by-step Epic community tutorial](../Epic-Community-Tutorial.md)
- Recommended forum category: [Development — Pipeline & Plugins](https://forums.unrealengine.com/c/development-discussion/pipeline-plugins/147).
- Suggested media: a short recorded demo from a legally acquired local sample showing plugin content under a host project's Content Browser, character/camera interaction and a clean Update summary. Do not include packaged source assets in the post/release.

## Publication actions (only after approval)

1. Complete repository/history/security/license audit and resolve blockers.
2. Update repository About description/topics and verify the public README/docs view.
3. Make the repository public when approved, keeping only the toolkit source.
4. Create source-only `v0.1.0` tag/Release with audited notes; attach no generated sample-content archive.
5. Publish the reviewed Epic Forums post and tutorial with a reachable GitHub URL.

Do not claim that any publication action in this checklist has already occurred.
