#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
mode=${1:---serve}
toolchain="$PWD/work/local/toolchain"
version=24.22.3
arch=
portable_bin=

# Pinned entries from https://nodejs.org/dist/v24.22.3/SHASUMS256.txt.
case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)
        arch=arm64
        digest=ff6e17d4874b76d272212b908cc020d6e815fba5a6c7eaaa06add725840307fd ;;
    Darwin/x86_64)
        arch=x64
        digest=977614af0504c81045e7fd85596dbca0e5f951b96681516dadafedcca8c447f7 ;;
esac
if [ -n "${arch:-}" ]; then
    package="node-v$version-darwin-$arch"
    portable_bin="$toolchain/$package/bin"
fi

usable_runtime() {
    local bin="$1"
    [ -n "$bin" ] && [ -x "$bin/node" ] && [ -x "$bin/npm" ] &&
        "$bin/node" -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)' >/dev/null 2>&1 &&
        PATH="$bin:$PATH" "$bin/npm" --version >/dev/null 2>&1
}

if [ "$mode" != --prepare-runtime ]; then
    # Finder and Xcode need to find existing installs without a shell profile.
    path_node=$(command -v node || true)
    for bin in "$portable_bin" "$toolchain/node/bin" "${path_node%/*}" \
        /opt/homebrew/opt/node@24/bin /usr/local/opt/node@24/bin /opt/homebrew/bin /usr/local/bin \
        "${VOLTA_HOME:-$HOME/.volta}/bin" "${NVM_DIR:-$HOME/.nvm}"/versions/node/v24.*/bin; do
        if usable_runtime "$bin"; then
            export PATH="$bin:$PATH"
            exec "$bin/node" "$PWD/scripts/attendance-launcher.mjs" "$mode"
        fi
    done
    if [ "$mode" = --stop ]; then
        if [ -f work/local/asistencia/servidor.pid ]; then
            echo 'Hay un registro del servidor. Recupera Node.js antes de volver a detenerlo.' >&2
            exit 1
        fi
        exit 0
    fi
fi

umask 077
log=work/local/asistencia/servidor.log
mkdir -p "$(dirname "$log")"
notice() { printf '%s\n' "$1" | tee -a "$log" >&2; }
fail() { notice "$1"; exit 1; }

install_runtime() (
    mkdir -p "$toolchain"
    staging=$(mktemp -d "$toolchain/.asistencia-node.XXXXXXXX")
    trap 'rm -rf "$staging"' EXIT
    trap 'exit 1' HUP INT TERM
    archive="$staging/$package.tar.gz"
    notice "Preparando Node.js $version para Asistencia en este Mac. La primera descarga requiere internet."
    if ! curl -q --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 120 --retry 2 --retry-max-time 120 \
        --output "$archive" "https://nodejs.org/dist/v$version/$package.tar.gz"; then
        fail "No se pudo descargar Node.js. Revisa la conexión y vuelve a pulsar Run, o usa el instalador oficial https://nodejs.org/dist/v$version/node-v$version.pkg"
    fi
    checksum=$(shasum -a 256 < "$archive") || fail 'No se pudo comprobar la descarga de Node.js.'
    [ "${checksum%% *}" = "$digest" ] || fail 'La descarga de Node.js no coincide con la oficial. Vuelve a pulsar Run para descargarla otra vez.'
    tar -xzf "$archive" -C "$staging" || fail 'No se pudo extraer Node.js. Comprueba el espacio disponible en el Mac.'
    usable_runtime "$staging/$package/bin" || fail "Este Mac no pudo ejecutar Node.js. Consulta el instalador oficial https://nodejs.org/dist/v$version/node-v$version.pkg"
    # Move the complete archive directory into its parent on the same filesystem.
    # A concurrent Run may already have published the same verified version.
    if ! mv "$staging/$package" "$toolchain/" 2>/dev/null && ! usable_runtime "$portable_bin"; then
        fail "No se pudo guardar Node.js en el proyecto. Revisa los permisos de $toolchain o usa el instalador oficial https://nodejs.org/dist/v$version/node-v$version.pkg"
    fi
)

[ -n "$portable_bin" ] || fail 'Para preparar Node.js automáticamente, abre JACNomina en un Mac Apple Silicon o Intel.'
if ! usable_runtime "$portable_bin"; then install_runtime; fi
if [ "$mode" = --prepare-runtime ]; then
    printf '%s\n' "$portable_bin"
    exit 0
fi
export PATH="$portable_bin:$PATH"
exec "$portable_bin/node" "$PWD/scripts/attendance-launcher.mjs" "$mode"
