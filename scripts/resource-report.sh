#!/usr/bin/env bash
# One resource snapshot per minute for the build log.
while true; do
  date -u
  free -h
  df -h / "${YARP_SOURCE_DIR:-/build/yarp}" 2>/dev/null || df -h /
  swapon --show
  ps -eo pid,comm,%mem,%cpu --sort=-%mem | head -n 8
  echo "---"
  sleep 60
done
