#!/usr/bin/env bash
# Run a command with memory caps when the runner's cgroup supports transient
# scopes, falling back to an uncapped run so harness quirks never block a build.
set -euo pipefail

if sudo systemd-run --scope --unit=yarp-probe \
    --property=MemoryHigh=11G --property=MemoryMax=13G \
    --property=MemorySwapMax=12G --property=CPUWeight=50 true >/dev/null 2>&1; then
  echo "run-capped: cgroup scope available; applying memory caps"
  exec sudo systemd-run --scope --unit=yarp-build \
    --property=MemoryHigh=11G --property=MemoryMax=13G \
    --property=MemorySwapMax=12G --property=CPUWeight=50 \
    runuser -u "$(id -un)" -- "$@"
else
  echo "::warning::run-capped: transient cgroup scope unavailable on this runner; building uncapped"
  exec "$@"
fi
