# Setup Postmortem

Chronological record of every issue hit while bringing up the
ROS2 Humble + rmw_zenoh dev container, what the symptom was, the root
cause, and the fix.

## 1. `ros-humble-rmw-zenoh-cpp` does not exist as an apt package

**Symptom**

```
E: Unable to locate package ros-humble-rmw-zenoh-cpp
```

during `docker compose build`.

**Root cause**

`rmw_zenoh` is only released as an apt binary for Iron, Jazzy, and Rolling.
On Humble it has to be built from source from the `humble` branch of
[`ros2/rmw_zenoh`](https://github.com/ros2/rmw_zenoh/tree/humble).

**Fix** (commit `86b4d56`)

The Dockerfile now clones the repo, runs `rosdep install`, and
`colcon build`s it into `/opt/rmw_zenoh/install` instead of installing
from apt. `ros-humble-zenoh-cpp-vendor` (the zenoh-c vendor package) is
still installed from apt because it is available.

```dockerfile
RUN mkdir -p /opt/rmw_zenoh/src \
    && git clone --depth 1 --branch humble https://github.com/ros2/rmw_zenoh.git /opt/rmw_zenoh/src/rmw_zenoh \
    && cd /opt/rmw_zenoh \
    && . /opt/ros/humble/setup.sh \
    && rosdep update --rosdistro=humble \
    && apt-get update \
    && rosdep install --from-paths src --ignore-src -y --rosdistro humble \
    && colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release \
    && rm -rf /var/lib/apt/lists/* /opt/rmw_zenoh/build /opt/rmw_zenoh/log
```

## 2. Docker compose tried to pull the locally-tagged image

**Symptom**

```
! ros2 Warning pull access denied for ros2_humble_zenoh, repository does
  not exist or may require 'docker login'
```

on first `docker compose run`.

**Root cause**

`compose.yaml` declared `image: ros2_humble_zenoh:dev` *and* a `build:`
block. Compose's default policy is to pull the image by tag before
building. The tag only exists locally, so the pull fails.

**Fix** (commit `86b4d56`)

- Added `pull_policy: build` to the service definition.
- `run.sh` now runs `docker compose build ros2` explicitly before
  `docker compose run`, so first launches behave predictably.

## 3. `librmw_zenoh_cpp.so` not loadable in non-interactive shells

**Symptom**

```
[ERROR] [...] [rcl]: Error getting RMW implementation identifier /
  RMW implementation not installed (expected identifier of
  'rmw_zenoh_cpp'), with error message
  'failed to load shared library "librmw_zenoh_cpp.so"'
```

from `ros2 doctor` and any `ros2 ...` command run through
`docker compose run ... bash -c '...'` (non-interactive).

**Root cause**

The rmw_zenoh overlay was only sourced via `~/.bashrc`. Non-interactive
shells (`bash -c`, `bash -lc`) do **not** source `~/.bashrc` by default,
so `LD_LIBRARY_PATH` / `AMENT_PREFIX_PATH` never picked up
`/opt/rmw_zenoh/install`.

**Fix** (commit `872fa9a`)

Source the overlay in `/ros_entrypoint.sh` (which *is* executed for every
`docker run` invocation), right after the base ROS setup line:

```dockerfile
RUN sed -i '/source "\/opt\/ros\/\$ROS_DISTRO\/setup.bash"/a source "/opt/rmw_zenoh/install/setup.bash" --' /ros_entrypoint.sh
```

## 4. `router.sh`: `ros2: command not found`

**Symptom**

```
bash: line 1: ros2: command not found
```

when running `./router.sh`.

**Root cause**

`docker exec` does **not** run the image entrypoint, only `docker run`
does. Inside the exec'd `bash -lc 'ros2 ...'`:

- A login bash sources `/etc/profile` and `~/.bash_profile`, **not**
  `~/.bashrc`.
- The ROS setup was therefore never sourced for this shell, so `ros2`
  was missing from `PATH`.

**Fix** (commit `006e5ad`)

Invoke the entrypoint script explicitly so the ROS env is loaded the
same way `docker run` would load it:

```bash
docker exec -it "$container" /ros_entrypoint.sh ros2 run rmw_zenoh_cpp rmw_zenohd
```

## 5. session.json5 was missing `connect.endpoints` → peers never dialed router

**Symptom (early)**

```
[WARN] [rmw_zenoh_cpp]: Unable to connect to a Zenoh router. Have you
started a router with `ros2 run rmw_zenoh_cpp rmw_zenohd`?
```

Even though `rmw_zenohd` was running and listening on `0.0.0.0:7447`.

**Root cause**

Our initial minimal `zenoh_config/session.json5` set
`connect.endpoints: []`. With no endpoints to dial, peers never tried
to connect to the local router and only relied on multicast/gossip
scouting, which in a host-networked container produces self-echoes
with empty locators.

**Fix attempt (commit `1e057c8`)**

Added `"tcp/localhost:7447"` to `connect.endpoints`. That cleared the
warning — peers' TCP sockets to the router were now `ESTABLISHED`. But…

## 6. **The big one** — partial session.json5 silently broke discovery

**Symptom**

`ros2 run demo_nodes_cpp talker` clearly printed
`Publishing: 'Hello World: N'`, the talker had a working TCP connection
to `rmw_zenohd` on `127.0.0.1:7447`, the listener also had a working
TCP connection to the same router — yet the listener never received
anything, `ros2 topic list` showed only `/parameter_events` and
`/rosout`, `ros2 node list` was empty.

Both peers spammed:

```
Received Hello with no locators: HelloProto { ..., locators: [] }
```

at 2-second intervals.

**Root cause**

The minimal `session.json5` only declared
`mode`, `connect`, `listen`, and `scouting.{multicast,gossip}.enabled`.
The upstream config has **820 lines** covering routing peer/router
behaviour, QoS, transport, queries, timestamping, gossip propagation
rules, link weights, and more. Many of those keys are interdependent.

The very first lines of the upstream default warn:

> Note that the values here are correctly typed, but may not be sensible,
> so copying this file to change only the parts that matter to you is
> not good practice.

When required keys are missing, Zenoh falls back to defaults that
**happen to break the rmw_zenoh graph-publication flow**: peers connect
to the router but never publish graph (node/topic/QoS) data through it,
so no other node ever learns of their existence.

Verification of root cause: `env -u ZENOH_SESSION_CONFIG_URI ros2 run
demo_nodes_cpp talker` (forcing rmw_zenoh to fall back to its built-in
default) immediately produced a working setup — `/chatter` appeared in
`topic list`, `/talker` in `node list`.

**Fix** (commit `c98b977`)

Replaced `zenoh_config/session.json5` with a verbatim copy of the
upstream `DEFAULT_RMW_ZENOH_SESSION_CONFIG.json5` and added a short
header pointing at the `connect.endpoints` block where a cloud router
endpoint should be added later.

## 7. Cross-machine: remote peer can reach router but `/chatter` never appears

**Symptom**

On the remote machine (the one that does NOT host `rmw_zenohd`):
- `nc -vz <router-host> 7447` succeeds.
- `docker exec ... ros2 topic echo /chatter --once` from a fresh
  process *sometimes* receives a message.
- `ros2 run demo_nodes_cpp listener` started in an interactive shell
  prints `Unable to connect to a Zenoh router` warnings forever, and
  never prints `I heard:`.
- The remote peer's listener logs:
  ```
  Unable to connect to any locator of scouted peer <zid>: [tcp/127.0.0.1:<port>]
  ```

**Root cause**

The upstream session config has `listen.endpoints: ["tcp/localhost:0"]`
and `mode: "peer"`. On the router-host machine that's fine — colocalized
peers connect to each other directly. But over a router, that local
listen address gets gossiped to *remote* peers, who then try to dial
`tcp/127.0.0.1:<port>` against their **own** loopback (which has
nothing). The failed direct connection blocks the remote peer's graph
state from converging.

**Fix** (commit `1c63d44`)

`zenoh_config/session.lan.json5` is set to `mode: "client"`. A
client-mode Zenoh session:

- only opens an outbound session to the router,
- never accepts inbound peer connections,
- never gossips a local peer locator that other hosts would dial.

The router-host machine keeps `mode: "peer"` in `session.json5` so
colocalized peers on that host still benefit from direct P2P. Remote
peers always use `session.lan.json5`.

**Don't** try to "fix" this by setting `listen.endpoints: []` —
that prevents rmw_zenoh's liveliness/graph queries from working at
all, even on a single machine. We tried; it failed in commit `b014694`
and was immediately reverted.

## 8. `Unable to connect to a Zenoh router after 1 attempt(s)`

**Symptom**

A peer launches, prints exactly one `Unable to connect to a Zenoh
router` warning, then "proceeds with initialization but other peers
will not discover or receive data from peers in this session until a
router is started." After this, even if TCP to the router establishes
moments later, the subscription is silently dead.

**Root cause**

`ZENOH_ROUTER_CHECK_ATTEMPTS` defaults to `1`. Over LAN, the
TCP/handshake to a remote router can take longer than the one
attempt's window — the peer gives up and degrades to "no router
mode," and that degraded session never recovers, even after TCP
later establishes.

**Fix** (commit `99e7cf6`)

`compose.yaml` sets `ZENOH_ROUTER_CHECK_ATTEMPTS: "10"`. With 10
attempts (~10 seconds), the peer is patient enough to find a remote
router on any normal LAN.

If you see `after 10 attempt(s)` in a deploy, bump it higher —
e.g. `20` for slow links or hot starts.

## 9. **The really nasty one** — `.bashrc` silently overrides compose env

**Symptom**

After updating `compose.yaml` (e.g. flipping
`ZENOH_SESSION_CONFIG_URI` from `session.json5` to
`session.lan.json5`) and restarting the container, **non-interactive
`docker exec` shows the right env, but interactive shells started via
`./run.sh` or `./exec.sh` still have the OLD value**.

For example:
```
$ docker exec <container> sh -c 'echo $ZENOH_SESSION_CONFIG_URI'
/home/dev/zenoh_config/session.lan.json5

$ docker exec <container> bash -lc 'echo $ZENOH_SESSION_CONFIG_URI'
/home/dev/zenoh_config/session.json5     ← WRONG
```

This produces the most confusing class of symptom: `topic echo`
"works" but a `ros2 run ... listener` in your shell doesn't, even
though they should share the same env.

**Root cause**

The Dockerfile used to append these to `/home/dev/.bashrc`:

```bash
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
export ZENOH_SESSION_CONFIG_URI=/home/dev/zenoh_config/session.json5
```

Interactive bash sources `.bashrc` **after** docker has applied the
compose-supplied env, so the export overrides whatever
`compose.yaml` set. Non-interactive `docker exec` does not source
`.bashrc`, so it sees the correct env. Hence the asymmetry.

**Fix** (commit `6fe7c8d`)

`.bashrc` only sources the ROS overlays now — it does not export
`RMW_IMPLEMENTATION` or any `ZENOH_*_CONFIG_URI`. `compose.yaml` is
the single source of truth for those.

**Diagnostic**

If two shells in the "same" container behave differently, check the
env of the actual offending process:

```bash
pid=$(docker exec <container> pgrep -f 'demo_nodes_cpp listener')
docker exec <container> cat /proc/$pid/environ | tr '\0' '\n' | grep -E 'ZENOH|RMW'
```

That reads the env from the running process itself — bypasses
`.bashrc`, bypasses compose, shows what's actually loaded.

## Cosmetic warnings that are NOT problems

Even with everything working, you will still see these. They are
harmless:

| Warning | Why it appears | What to do |
|---|---|---|
| `Starting with no listener endpoints!` | rmw_zenoh peers don't accept inbound connections by default; only the router listens. | Ignore. Add `"tcp/0.0.0.0:0"` to `listen.endpoints` only if some other peer needs to dial *into* this node. |
| `Received Hello with no locators` | Gossip/multicast scouting echoing back peers (often the same node hearing itself via host networking) that have no listen address. | Ignore. To silence completely, set `scouting.multicast.enabled: false` in `session.json5` — router-based discovery still works. |
| `Scouting delay elapsed before start conditions are met.` | Zenoh waited the configured `scouting.delay` for peers before giving up and starting. | Ignore. Tune `scouting.delay` lower if you want faster startup. |

## Workflow that actually works

1. `./run.sh` — opens a container shell. Leave open.
2. From a separate host terminal: `./router.sh`. Leave open — this is the
   Zenoh router. Do not Ctrl+C unless you want to bring the fleet down.
3. From more host terminals: `./exec.sh` to attach to the running
   container, then run your ros2 nodes.

`Unable to connect to a Zenoh router` warning means step 2 isn't running
(or you killed it). Restart `./router.sh`.
