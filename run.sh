#!/usr/bin/env bash
# Build (if needed) and enter the ROS2 Humble + Zenoh dev container.
set -euo pipefail

cd "$(dirname "$0")"

# Allow local docker user to connect to the X server for GUI tools.
if command -v xhost >/dev/null 2>&1; then
    xhost +local:docker >/dev/null || true
fi

export USER_UID="$(id -u)"
export USER_GID="$(id -g)"

# Ensure the image is built locally (avoids docker trying to pull the
# locally-tagged image from a registry on first run).
docker compose build ros2

# Use `run --rm` so each interactive shell is a fresh container; the workspace
# is bind-mounted so nothing important lives inside the container itself.
exec docker compose run --rm --service-ports ros2 bash
