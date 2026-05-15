#!/usr/bin/env bash
# Set the LAN/remote Zenoh router endpoint that this machine's peers
# will dial. Edits zenoh_config/session.lan.json5 in place.
#
# Usage:
#   ./set-router-host.sh <host-or-ip>
#   ./set-router-host.sh 192.168.0.121
#   ./set-router-host.sh router.example.com
#   ./set-router-host.sh 192.168.0.121:7447     # override the port too
#
# Idempotent — running again with a new host just overwrites the previous
# endpoint.
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <host-or-ip>[:port]" >&2
    echo "       $0 192.168.0.121" >&2
    echo "       $0 router.example.com" >&2
    exit 1
fi

target="$1"

# Default to port 7447 if the caller didn't specify one.
if [[ "$target" != *:* ]]; then
    target="${target}:7447"
fi

file="$(cd "$(dirname "$0")" && pwd)/zenoh_config/session.lan.json5"
if [ ! -f "$file" ]; then
    echo "Missing $file — are you in the repo root?" >&2
    exit 1
fi

# Only touch endpoints inside the `connect: { ... }` block — leaves
# `listen.endpoints` (which has its own localhost setting) untouched.
# The range matches lines from "  connect: {" to the matching "  }," and
# the substitution only fires on indented "tcp/...:port" strings inside
# it. Comment lines start with `///` so they never match.
if ! sed -nE '/^  connect:/,/^  },/ { /^[[:space:]]+"tcp\/[^"]*:[0-9]+"/p; }' "$file" | grep -q .; then
    echo "No 'tcp/...:<port>' line found inside connect block of $file" >&2
    exit 1
fi

sed -i -E "/^  connect:/,/^  },/ { s|^([[:space:]]+)\"tcp/[^\"]*:[0-9]+\"|\1\"tcp/${target}\"|; }" "$file"

echo "Set router endpoint to tcp/${target} in:"
echo "  $file"
echo
echo "connect.endpoints now:"
sed -nE '/^  connect:/,/^  },/ { /^[[:space:]]+"tcp\/[^"]*:[0-9]+"/{=;p;}; }' "$file" \
    | paste -d':' - - \
    | sed 's/^/  /'
echo
echo "Next: make sure compose.yaml has"
echo "  ZENOH_SESSION_CONFIG_URI: /home/dev/zenoh_config/session.lan.json5"
echo "then ./run.sh to (re)launch the container."
