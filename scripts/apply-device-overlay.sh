#!/usr/bin/env bash
# Idempotent YARP data-decryption overlay for the pinned houji device tree.
#
# Xiaomi 14 (houji) encrypts userdata with FBE v2 + metadata encryption and
# KeyMint 3.0 backed by the StrongBox embedded secure element. The KeyMint
# StrongBox flow needs the OMAPI (android.se.omapi.ISecureElementService)
# service, which the stock system provides via SecureElementApplication.apk.
# TWRP-Test's twrp-16.0 platform ships a native OMAPI implementation that is
# switched on with TW_INCLUDE_OMAPI; this overlay enables it on the device
# tree and brands the build as YARP.
set -euo pipefail

device_path="${1:?usage: apply-device-overlay.sh <device-tree-path>}"
cd "${device_path}"

board="BoardConfig.mk"
test -f "${board}" || { echo "::error::BoardConfig.mk not found in ${device_path}"; exit 1; }

if grep -q '^TW_INCLUDE_OMAPI' "${board}"; then
  echo "Overlay: TW_INCLUDE_OMAPI already present in ${board}"
else
  cat >> "${board}" <<'EOF'

# YARP: enable the native OMAPI (Open Mobile API) service so the KeyMint 3.0
# StrongBox flow can reach the embedded secure element during FBE unlock.
TW_INCLUDE_OMAPI := true
EOF
  echo "Overlay: enabled TW_INCLUDE_OMAPI in ${board}"
fi

if grep -q '^TW_DEVICE_VERSION := Xiaomi_14-A14-YARP' "${board}"; then
  echo "Overlay: TW_DEVICE_VERSION already branded"
else
  printf '\nTW_DEVICE_VERSION := Xiaomi_14-A14-YARP\n' >> "${board}"
  echo "Overlay: branded TW_DEVICE_VERSION as Xiaomi_14-A14-YARP"
fi

# The device tree predates android16 (twrp-12.1 era). Assigning any variable
# registered via KATI_obsolete_var in build/make/core/config.mk is fatal, so
# neutralize every such assignment in the tree's makefiles.
obsolete_vars="BOARD_BUILD_SYSTEM_ROOT_IMAGE FS_GET_STATS BUILD_BROKEN_USES_SOONG_PYTHON2_MODULES BOARD_VNDK_RUNTIME_DISABLE TARGET_NO_VENDOR_BOOT BOARD_PLAT_PUBLIC_SEPOLICY_DIR BOARD_PLAT_PRIVATE_SEPOLICY_DIR PRODUCT_CHECK_ELF_FILES PRODUCT_SUPPORTS_VERITY PRODUCT_SUPPORTS_VERITY_FEC PRODUCT_SUPPORTS_BOOT_SIGNER PRODUCT_VERITY_SIGNING_KEY BOARD_HAL_STATIC_LIBRARIES LOCAL_HAL_STATIC_LIBRARIES PRODUCT_STATIC_BOOT_CONTROL_HAL TARGET_PREFER_32_BIT TARGET_PREFER_32_BIT_APPS TARGET_PREFER_32_BIT_EXECUTABLES TARGET_ANDROID_FILESYSTEM_CONFIG_H TARGET_ROOT_OUT_SBIN TARGET_ROOT_OUT_SBIN_UNSTRIPPED BUILD_BROKEN_PHONY_TARGETS BUILD_BROKEN_DUP_COPY_HEADERS BUILD_BROKEN_ENG_DEBUG_TAGS BUILD_BROKEN_ANDROIDMK_EXPORTS COVERAGE_PATHS COVERAGE_EXCLUDE_PATHS USE_CLANG_PLATFORM_BUILD PRODUCT_COMPATIBILITY_MATRIX_LEVEL_OVERRIDE BOARD_PREBUILT_PVMFWIMAGE BUILDING_PVMFW_IMAGE PRODUCT_IOT MD5SUM BUILD_DROIDDOC BUILD_APIDIFF LOCAL_TEST_CONFIG_OPTIONS PRODUCT_TREBLE_LINKER_NAMESPACES_OVERRIDE PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE PRODUCT_FULL_TREBLE_OVERRIDE"
for mk in BoardConfig.mk device.mk twrp_houji.mk Android.mk prebuilt/Android.mk; do
  [ -f "${mk}" ] || continue
  for var in ${obsolete_vars}; do
    if grep -q "^${var}[[:space:]]*[:+?]*=" "${mk}"; then
      sed -i "/^${var}[[:space:]]*[:+?]*=/ s|^|# removed by YARP overlay (obsolete in android16): |" "${mk}"
      echo "Overlay: neutralized obsolete var ${var} in ${mk}"
    fi
  done
done

# VNDK is gone in android16 entirely.
if grep -q '^PRODUCT_TARGET_VNDK_VERSION' device.mk 2>/dev/null; then
  sed -i 's/^PRODUCT_TARGET_VNDK_VERSION.*/# removed by YARP overlay: VNDK was removed in android16/' device.mk
  echo "Overlay: removed PRODUCT_TARGET_VNDK_VERSION (VNDK is gone in android16)"
fi
if grep -q '^PRODUCT_SHIPPING_API_LEVEL := 3[0-5]$' device.mk 2>/dev/null; then
  sed -i 's/^PRODUCT_SHIPPING_API_LEVEL := 3[0-5]$/PRODUCT_SHIPPING_API_LEVEL := 36/' device.mk
  echo "Overlay: bumped PRODUCT_SHIPPING_API_LEVEL to 36 for android16"
fi

git diff --check || true
git --no-pager diff || true
