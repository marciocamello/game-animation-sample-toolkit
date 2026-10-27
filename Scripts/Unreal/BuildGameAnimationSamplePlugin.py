import json
import os

import unreal


def log(message):
    unreal.log("[GameAnimationSampleBuild] {}".format(message))


def fail(message):
    unreal.log_error("[GameAnimationSampleBuild] {}".format(message))
    raise RuntimeError(message)


def load_args():
    args_path = os.environ.get("GAS_BUILD_ARGS")
    if not args_path or not os.path.exists(args_path):
        fail("Missing GAS_BUILD_ARGS environment variable.")

    with open(args_path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def ensure_directory(path):
    if not unreal.EditorAssetLibrary.does_directory_exist(path):
        unreal.EditorAssetLibrary.make_directory(path)


def duplicate_root(source_root, destination_root):
    ensure_directory(destination_root)
    assets = unreal.EditorAssetLibrary.list_assets(source_root, recursive=True, include_folder=False)
    failed = []

    for asset_path in assets:
        if asset_path.endswith("_BuiltData"):
            continue

        relative_path = asset_path[len(source_root):].lstrip("/")
        destination_path = "{}/{}".format(destination_root.rstrip("/"), relative_path)
        destination_dir = os.path.dirname(destination_path).replace("\\", "/")
        ensure_directory(destination_dir)

        if unreal.EditorAssetLibrary.does_asset_exist(destination_path):
            unreal.EditorAssetLibrary.delete_asset(destination_path)

        result = unreal.EditorAssetLibrary.duplicate_asset(asset_path, destination_path)

        if not result:
            failed.append({"source": asset_path, "destination": destination_path})

    return failed


def main():
    args = load_args()
    failed = []

    for root_name in args["source_roots"]:
        source_root = "/Game/{}".format(root_name)
        destination_root = "{}/{}".format(args["plugin_mount_point"], root_name)
        log("Duplicating {} -> {}".format(source_root, destination_root))
        failed.extend(duplicate_root(source_root, destination_root))

    unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)
    with open(args["report_path"], "w", encoding="utf-8") as handle:
        json.dump({"failed_assets": failed}, handle, indent=2)

    if failed:
        fail("Asset duplication finished with {} failures.".format(len(failed)))

    log("Asset duplication completed successfully.")


if __name__ == "__main__":
    main()
