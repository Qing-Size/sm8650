#!/usr/bin/env bash
set -euo pipefail

# This script deletes preinstalled software on a disposable GitHub VM only.
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "${RUNNER_OS:-}" != Linux ]]; then
  echo 'Refusing storage preparation outside a GitHub-hosted Linux runner.' >&2
  exit 1
fi

# No swap here on purpose: the swap file lives on the build disk, so it is
# created AFTER the source sync (see the workflow) to give repo the full disk.
min_free_gib="${YARP_MIN_FREE_GIB:-25}"

df -h / /mnt
free -h
sudo swapoff -a
sudo rm -f /mnt/swapfile /swapfile /yarp-swapfile
sudo docker image prune --all --force
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc \
  /usr/local/.ghcup /usr/local/swift /opt/hostedtoolcache \
  /usr/local/.rustup /usr/local/.cargo /usr/share/gradle /usr/share/kotlin \
  /usr/local/share/boost /opt/microsoft /usr/share/php /usr/local/lib/node_modules \
  /opt/az /usr/share/miniconda /usr/local/graalvm /usr/local/share/chromium
sudo apt-get clean
sudo rm -rf /var/cache/apt/archives/*.deb 2>/dev/null || true

sudo mkdir -p /build/yarp
sudo chown "$(id -u):$(id -g)" /build/yarp
df -h / /build/yarp
free -h

# Where did the disk go? Top-level report to help tune cleanup and trimming.
sudo du -xh --max-depth=1 / 2>/dev/null | sort -h | tail -n 12 || true

available_kib="$(df -Pk /build/yarp | awk 'NR == 2 {print $4}')"
if (( available_kib < min_free_gib * 1024 * 1024 )); then
  echo "::error::Only $((available_kib / 1024 / 1024)) GiB is free for sources and outputs; this build wants at least ${min_free_gib} GiB. Free more disk or run on a larger runner (override with YARP_MIN_FREE_GIB)."
  exit 1
fi
