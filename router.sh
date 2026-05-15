#!/usr/bin/env bash
# Start the Zenoh router (rmw_zenohd) inside the running ROS2 container.
# Leave this terminal open — every other ros2 process expects this router.
# Requires a container already started via ./run.sh in another terminal.
set -euo pipefail

cd "$(dirname "$0")"

container="$(docker ps --filter ancestor=ros2_humble_zenoh:dev --format '{{.ID}}' | head -n1)"
if [ -z "${container}" ]; then
    echo "No running ros2_humble_zenoh:dev container found. Start one with ./run.sh first." >&2
    exit 1
fi

exec docker exec -it "${container}" /ros_entrypoint.sh ros2 run rmw_zenoh_cpp rmw_zenohd
