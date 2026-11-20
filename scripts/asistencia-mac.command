#!/bin/bash
set -eu
cd "$(dirname "$0")/.."

# A running fixture owns its ephemeral database and its supervision credential.
# Keep it alive when the app relaunches on the simulator.
if curl --silent --noproxy '*' --max-time 2 --dump-header - --output /dev/null http://127.0.0.1:8789/_jac/attendance-ready |
    grep -Eiq '^x-jac-attendance: (ready|starting)[[:space:]]*$'; then
    echo 'El piloto de Asistencia ya está en ejecución.'
    exit 0
fi

if [ "${1:-}" = "--xcode" ]; then
    exec /usr/bin/open -g -a Terminal "$PWD/scripts/asistencia-mac.command"
fi
# The Mac used for JAC can have its own Node installation outside Terminal's PATH.
if [ -x "$PWD/work/local/toolchain/node/bin/node" ]; then
    export PATH="$PWD/work/local/toolchain/node/bin:$PATH"
fi
if ! command -v npm >/dev/null || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)'; then
    echo 'El piloto necesita Node.js 24 o posterior con npm en work/local/toolchain/node/bin o en el PATH de Terminal.' >&2
    exit 1
fi
if [ ! -x node_modules/.bin/vinext ]; then
    npm ci --no-audit --no-fund
fi
exec npm run asistencia
