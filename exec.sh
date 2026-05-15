#!/usr/bin/env bash
# Attach a second shell to the already-running ROS2 container.
# Requires a container started via run.sh in another terminal.
set -euo pipefail

cd "$(dirname "$0")"

container="$(docker ps --filter ancestor=ros2_humble_zenoh:dev --format '{{.ID}}' | head -n1)"
if [ -z "${container}" ]; then
    echo "No running ros2_humble_zenoh:dev container found. Start one with ./run.sh first." >&2
    exit 1
fi

exec docker exec -it "${container}" bash
