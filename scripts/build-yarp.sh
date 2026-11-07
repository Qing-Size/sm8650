#!/usr/bin/env bash
set -euo pipefail

builder_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="${YARP_SOURCE_DIR:-/build/yarp}"
dist_root="${YARP_DIST_DIR:-${builder_root}/dist}"
lock_file="${builder_root}/sources.json"
device_path="device/xiaomi/houji"
product_name="houji"
image_name="YARP-houji-8a58fc3-recovery.img"
mkdir -p "${source_root}" "${dist_root}"

case "${1:-}" in
  sync)
    cd "${source_root}"
    manifest_revision="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest"]["revision"])' "${lock_file}")"
    repo init -u https://github.com/TWRP-Test/platform_manifest_twrp_aosp.git \
      -b "${manifest_revision}" --depth=1 --no-clone-bundle --no-tags
    python3 "${builder_root}/scripts/source-lock.py" overlay "${lock_file}" "${source_root}"
    # Trim the tree to what a recovery build needs: the manifest's official
    # remove-minimal.xml plus scripts/yarp-trim-extra.xml, filtered against
    # the resolved manifest so unknown entries are skipped, never fatal.
    if [ "${YARP_APPLY_MINIMAL_TRIM:-1}" = "1" ]; then
      cp "${builder_root}/scripts/yarp-trim-keep.xml" "${source_root}/.repo/local_manifests/yarp-trim-keep.xml"
      python3 "${builder_root}/scripts/apply-trim.py" "${source_root}" "${builder_root}/scripts/yarp-trim-extra.xml"
    else
      echo '::warning::YARP_APPLY_MINIMAL_TRIM=0: syncing the full manifest; this will not fit on a 72 GiB runner.'
    fi
    repo sync -c -j "${SYNC_JOBS:-8}" --fail-fast --no-tags --no-clone-bundle \
      --optimized-fetch --retry-fetches=3
    python3 "${builder_root}/scripts/source-lock.py" verify "${lock_file}" "${source_root}"
    repo manifest -r -o "${dist_root}/source-manifest.xml"
    cp "${lock_file}" "${dist_root}/sources.json"
    git -C bootable/recovery diff --check || true
    # Decryption overlay + exact device-tree revision while git still works.
    bash "${builder_root}/scripts/apply-device-overlay.sh" "${source_root}/${device_path}"
    git -C "${source_root}/${device_path}" rev-parse HEAD > "${dist_root}/device-revision.txt" || true
    # The compile only needs checked-out files: drop repo's git object stores.
    rm -rf "${source_root}/.repo/projects" "${source_root}/.repo/project-objects"
    df -h "${source_root}"
    du -sh "${source_root}/.repo" 2>/dev/null || true
    available_kib="$(df -Pk "${source_root}" | awk 'NR == 2 {print $4}')"
    min_free_after_sync_gib="${YARP_MIN_FREE_AFTER_SYNC_GIB:-5}"
    if (( available_kib < min_free_after_sync_gib * 1024 * 1024 )); then
      echo "::error::Only $((available_kib / 1024 / 1024)) GiB remains after source sync and git-store pruning (want >= ${min_free_after_sync_gib} GiB); refusing to continue so diagnostic logs can still upload. Override with YARP_MIN_FREE_AFTER_SYNC_GIB."
      exit 1
    fi
    ;;
  build)
    cd "${source_root}"
    export ALLOW_MISSING_DEPENDENCIES=true
    if [ -n "${CCACHE_DIR:-}" ]; then
      export USE_CCACHE=1
      ccache -M 8G
    else
      export USE_CCACHE=0
    fi
    export MALLOC_ARENA_MAX=2
    export SOONG_GOMEMLIMIT=8GiB
    export GOMEMLIMIT=8GiB
    export GOGC=50
    export GOMAXPROCS=2
    export SOONG_UI_NINJA_ARGS="-j1 -k 100"
    export NINJA_HIGHMEM_NUM_JOBS=1
    set +u
    source build/envsetup.sh
    lunch twrp_houji
    mka -j"${BUILD_JOBS:-2}" installclean
    mka -j"${BUILD_JOBS:-2}" recoveryimage
    ;;
  package)
    product_root="${source_root}/out/target/product/${product_name}"
    python3 "${builder_root}/scripts/verify-image.py" "${product_root}" > "${dist_root}/verification.json"
    cp "${product_root}/recovery.img" "${dist_root}/${image_name}"
    cd "${dist_root}"
    sha256sum "${image_name}" > SHA256SUMS.txt
    cat verification.json
    ;;
  *)
    printf 'Usage: %s {sync|build|package}\n' "$0" >&2
    exit 2
    ;;
esac
