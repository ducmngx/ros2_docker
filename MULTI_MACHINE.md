# Two-Machine ROS2 + Zenoh over LAN

This guide adds a second machine (e.g. a robot) to the dev setup so it
can publish/subscribe ROS2 topics with the first machine via Zenoh.

## Architecture

```
  ┌────────────────────────────┐         ┌──────────────────────────────┐
  │ Machine A — dev box        │         │ Machine B — robot             │
  │  (Docker, host networking) │         │  (Docker, host networking)    │
  │                            │         │                               │
  │  rmw_zenohd  ─listens─┐    │         │  (no router here)             │
  │                       │    │         │                               │
  │  ros2 nodes ─dial─────┴──> 0.0.0.0:7447 <──── dial ──── ros2 nodes    │
  └────────────────────────────┘         └──────────────────────────────┘
                              <router-IP>:7447 (LAN)
```

One router on machine A. Every peer dials it. Discovery, graph data,
and pub/sub traffic flow through it.

## Prerequisites

- Both machines on the same LAN / WiFi (or VPN).
- Machine A's LAN IP — run `ip -4 addr | grep inet` on machine A and
  pick the address on the interface that's on the same network as
  machine B. Example: `192.168.0.121`.
- TCP port `7447` reachable on machine A. If a host firewall is on:
  ```bash
  sudo ufw allow 7447/tcp
  ```
- Machine B has Docker installed:
  ```bash
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker $USER   # log out + back in
  ```

## Machine A (router host)

Already works as-is. Standard workflow:

```bash
./run.sh         # terminal 1 — container shell
./router.sh      # terminal 2 — Zenoh router (leave running)
./exec.sh        # terminal 3 — your nodes
ros2 run demo_nodes_cpp talker
```

`compose.yaml` keeps `ZENOH_SESSION_CONFIG_URI` pointing at
`session.json5` (the localhost config) — peers on machine A reach
their own router via `tcp/localhost:7447`.

## Machine B (robot)

One-time setup:

```bash
git clone git@github.com:ducmngx/ros2_docker.git
cd ros2_docker
```

Two edits — both on the host filesystem, no rebuild required:

**1. `zenoh_config/session.lan.json5`** — find the placeholder line
inside the `connect: { ... }` block (line ~65) and replace
`REPLACE-WITH-ROUTER-IP` with machine A's LAN IP:

```json5
endpoints: [
  "tcp/192.168.0.121:7447"     // <-- machine A's IP
],
```

**2. `compose.yaml`** — change the session config env var to point at
the LAN variant:

```yaml
ZENOH_SESSION_CONFIG_URI: /home/dev/zenoh_config/session.lan.json5
```

Then build the image and start a node:

```bash
./run.sh                              # first run builds the image
ros2 run demo_nodes_cpp listener
```

Machine B **does not** run `./router.sh` — it has no router. It's a
peer that connects to machine A's router.

## Verification

1. Talker on machine A:
   ```bash
   ros2 run demo_nodes_cpp talker
   ```
2. Listener on machine B:
   ```bash
   ros2 run demo_nodes_cpp listener
   ```
3. Listener prints `I heard: [Hello World: N]` matching the talker.
4. From any shell on either machine:
   ```bash
   ros2 node list      # /talker AND /listener
   ros2 topic list     # includes /chatter
   ```

## Troubleshooting

In order of likely failure:

| Check | Command | What it tells you |
|---|---|---|
| TCP reachable | `nc -vz <router-IP> 7447` from machine B host | Network/firewall OK? |
| Router listening | `ss -tlnp \| grep 7447` on machine A host | Router up and bound to all interfaces? |
| Endpoint edited | `grep -A2 'connect: {' zenoh_config/session.lan.json5` | Did you actually replace the placeholder? |
| Right config selected | `docker exec <container> sh -c 'echo $ZENOH_SESSION_CONFIG_URI'` on machine B | Env points at `session.lan.json5`? |
| RMW loads | `docker exec <container> /ros_entrypoint.sh ros2 doctor --report \| grep middleware` | Says `rmw_zenoh_cpp`? |

Common gotchas:
- WiFi access points with "client isolation" / "AP isolation" enabled
  silently block peer traffic. Disable on the AP or use wired/VPN.
- Two different LAN networks (e.g. wired vs WiFi subnets that don't
  route to each other) — pick the IP on the shared network.
- The same `Hello with no locators` and `Starting with no listener
  endpoints!` warnings as the single-machine case still appear — they
  remain harmless (see `TROUBLESHOOTING.md`).

## Moving to a cloud router later

The flow is identical, only the endpoint changes:

1. Run `rmw_zenohd` on a publicly-reachable VM (probably with the
   `zenoh_config/router.json5` defaults plus TLS).
2. On every peer (machine A, machine B, robots in the field), change
   `session.lan.json5`'s `connect.endpoints` to your cloud router's
   address, e.g. `"tcp/router.example.com:7447"`.
3. Nobody runs `./router.sh` anymore — the cloud VM is the only router.

The repo doesn't need other changes; same Docker image, same workflow.
