# Zenoh config templates

Pristine, unmodified copies of the upstream default configs that ship
with `rmw_zenoh` (humble branch). They are **reference material** —
nothing in the repo or container reads them at runtime.

Use them when you want to:

- See exactly what every config key does (the upstream `///` comments
  are the canonical docs).
- Restore a working config after experimenting:
  ```bash
  cp templates/session.default.json5 ../session.json5
  ```
- Bootstrap a new variant (e.g. `session.cloud.json5`) without copying
  the live config that already has local edits.

## Source

Extracted from the running image at:

```
/opt/rmw_zenoh/install/rmw_zenoh_cpp/share/rmw_zenoh_cpp/config/
  ├── DEFAULT_RMW_ZENOH_SESSION_CONFIG.json5
  └── DEFAULT_RMW_ZENOH_ROUTER_CONFIG.json5
```

Which in turn comes from:
https://github.com/ros2/rmw_zenoh/tree/humble/rmw_zenoh_cpp/config

## Files

| File | What it configures |
|---|---|
| `session.default.json5` | A peer/client Zenoh session (every ROS2 node uses one) |
| `router.default.json5` | A standalone `rmw_zenohd` router |

## When upstream updates

Re-extract after rebuilding the image:

```bash
docker run --rm ros2_humble_zenoh:dev \
  cat /opt/rmw_zenoh/install/rmw_zenoh_cpp/share/rmw_zenoh_cpp/config/DEFAULT_RMW_ZENOH_SESSION_CONFIG.json5 \
  > zenoh_config/templates/session.default.json5

docker run --rm ros2_humble_zenoh:dev \
  cat /opt/rmw_zenoh/install/rmw_zenoh_cpp/share/rmw_zenoh_cpp/config/DEFAULT_RMW_ZENOH_ROUTER_CONFIG.json5 \
  > zenoh_config/templates/router.default.json5
```
