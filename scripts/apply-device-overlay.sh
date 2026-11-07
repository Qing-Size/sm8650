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

git diff --check || true
git --no-pager diff || true
