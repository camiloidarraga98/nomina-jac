#!/bin/bash
set -eu
cd "$(dirname "$0")/.."

# Xcode does not load an interactive Terminal profile. Prefer the runtime
# installed with this checkout, then the user's usual Node or Homebrew.
for bin in "$PWD/work/local/toolchain/node/bin" "$(dirname "$(command -v node || echo /missing/node)")" \
    /opt/homebrew/opt/node@24/bin /usr/local/opt/node@24/bin /opt/homebrew/bin /usr/local/bin \
    "$HOME/.volta/bin" "$HOME"/.nvm/versions/node/v24.*/bin; do
    if [ -x "$bin/node" ] && [ -x "$bin/npm" ] && "$bin/node" -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)'; then
        export PATH="$bin:$PATH"
        exec "$bin/node" "$PWD/scripts/attendance-launcher.mjs" "${1:---serve}"
    fi
done
umask 077
mkdir -p work/local/asistencia
echo 'Para iniciar Asistencia, instala Node.js 24 con npm en el Mac y vuelve a ejecutar JACNomina.' | tee -a work/local/asistencia/servidor.log >&2
exit 1
