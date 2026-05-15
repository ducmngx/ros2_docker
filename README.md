# ROS2 Humble + Zenoh Dev Container

Reproducible Docker dev environment for building a Zenoh-based fleet
management app on top of ROS2 Humble. Uses `rmw_zenoh_cpp` as the ROS2
middleware so the same nodes can later peer with a cloud-hosted Zenoh
router over arbitrary networks.

`rmw_zenoh` has no apt binary for Humble, so the Dockerfile builds it
from source from the [`humble` branch of ros2/rmw_zenoh][rmw-zenoh] into
`/opt/rmw_zenoh`. That overlay is sourced automatically in the shell.

[rmw-zenoh]: https://github.com/ros2/rmw_zenoh/tree/humble

## Layout

```
ros2_docker/
├── Dockerfile          # osrf/ros:humble-desktop + rmw_zenoh + dev tools
├── compose.yaml        # service definition (network=host, X11, /dev, volumes)
├── run.sh              # build (first time) + enter a fresh container
├── exec.sh             # attach a second shell to a running container
├── router.sh           # start the Zenoh router (rmw_zenohd) in the container
├── ros2_ws/            # your colcon workspace (host-editable, mounted in)
│   └── src/
└── zenoh_config/
    ├── session.json5       # Peer config for the router-host machine (localhost)
    ├── session.lan.json5   # Peer config for remote machines (dial router over LAN)
    └── router.json5        # Router (rmw_zenohd) config
```

For running across two machines on the same LAN, see
[MULTI_MACHINE.md](MULTI_MACHINE.md). For things that broke during
initial setup and the fixes, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Quickstart

1. **Start a shell in the container** (builds the image on first run):

   ```bash
   ./run.sh
   ```

   You should land in `dev@ros2-dev:~/ros2_ws$` with ROS2 already sourced and
   `RMW_IMPLEMENTATION=rmw_zenoh_cpp` set.

2. **Start the Zenoh router** in a second host terminal (required — every
   ros2 process expects it, and discovery is unreliable without it):

   ```bash
   ./router.sh
   ```

   Leave it running. Open more terminals with `./exec.sh` for everything
   else below. If you see `Unable to connect to a Zenoh router` warnings,
   the router isn't running.

3. **Smoke test** the middleware:

   ```bash
   # terminal A (./exec.sh)
   ros2 run demo_nodes_cpp talker

   # terminal B (./exec.sh)
   ros2 run demo_nodes_cpp listener
   ```

4. **Verify GUI**:

   ```bash
   rviz2
   ```

5. **Build your workspace** as you add packages under `ros2_ws/src/`:

   ```bash
   cd ~/ros2_ws
   colcon build --symlink-install
   source install/setup.bash
   ```

## Connecting to a cloud Zenoh router later

Edit `zenoh_config/session.json5`:

- Switch `mode` from `"peer"` to `"client"`.
- Add your router endpoint to `connect.endpoints`, e.g.
  `"tcp/router.example.com:7447"`.

Restart the container (`exit`, then `./run.sh`). Robots running the same
config from anywhere on the internet will join the same Zenoh fabric.

## Notes

- `network_mode: host` and `privileged: true` are enabled — fine for a dev
  box, not for production. USB devices appear at `/dev/...` because `/dev`
  is bind-mounted.
- The container user is created with your host UID/GID, so files written to
  `ros2_ws/` are owned by you on the host.
- `run.sh` uses `docker compose run --rm`, so each shell is a fresh
  container; all persistent state lives in the bind-mounted `ros2_ws/` and
  `zenoh_config/` directories.
- If `rviz2` fails with X11 errors, run `xhost +local:docker` on the host.
