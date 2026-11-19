#!/bin/bash
set -eu
cd "$(dirname "$0")/.."

# A running fixture owns its ephemeral database and its supervision credential.
# Keep it alive when the app relaunches on the simulator.
if curl --silent --noproxy '*' --max-time 2 http://127.0.0.1:8789/api/attendance/session |
    grep -Fq '"error":"Inicia sesión en JAC."'; then
    echo 'El piloto de Asistencia ya está en ejecución.'
    exit 0
fi

if [ "${1:-}" = "--xcode" ]; then
    exec /usr/bin/open -a Terminal "$PWD/scripts/asistencia-mac.command"
fi
if ! command -v npm >/dev/null || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)'; then
    echo 'Para iniciar el piloto en este Mac, instala Node.js 24 o posterior con npm.'
    exit 1
fi
if [ ! -x node_modules/.bin/vinext ]; then
    npm ci --no-audit --no-fund
fi
exec npm run asistencia
