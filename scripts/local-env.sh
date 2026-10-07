#!/bin/sh
# Herramientas locales de JAC; no cambia el PATH global del Mac.
set -eu
JAC_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -x "$JAC_ROOT/work/local/toolchain/node/bin/node" ]; then
  PATH="$JAC_ROOT/work/local/toolchain/node/bin:$PATH"
  export PATH
fi
if ! command -v node >/dev/null 2>&1 || [ "$(node -p 'process.versions.node.split(".")[0]')" != 24 ]; then
  echo 'JAC necesita Node 24. Consulta EMPIEZA_AQUI.md.' >&2
  exit 1
fi
export WRANGLER_SEND_METRICS=false
export WRANGLER_LOG_PATH="$JAC_ROOT/.wrangler/logs"
export MINIFLARE_REGISTRY_PATH="$JAC_ROOT/.wrangler/registry"
cd "$JAC_ROOT"
exec "$@"
