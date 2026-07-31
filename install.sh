#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

NO_CHSH=0
WITH_NODE_EXPORTER=0

usage() {
  cat <<'EOF'
Uso: ./install.sh [opciones]

Instala la configuración de tmux, Zsh/Oh My Zsh y las herramientas de monitoreo.

Opciones:
  --no-chsh             No cambia el shell predeterminado.
  --with-node-exporter  Instala y habilita Prometheus Node Exporter (TCP 9100).
  -h, --help            Muestra esta ayuda.

Para configurar otro usuario:
  SETUP_USER=nombre ./install.sh
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --no-chsh) NO_CHSH=1 ;;
    --with-node-exporter) WITH_NODE_EXPORTER=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Opción desconocida: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

"$SCRIPT_DIR/setup-tmux.sh"
# Evita repetir apt-get update en los siguientes dos instaladores del mismo recorrido.
export SETUP_APT_UPDATED=1

zsh_args=()
(( NO_CHSH == 1 )) && zsh_args+=(--no-chsh)
"$SCRIPT_DIR/setup-zsh.sh" "${zsh_args[@]}"

monitoring_args=()
(( WITH_NODE_EXPORTER == 1 )) && monitoring_args+=(--with-node-exporter)
"$SCRIPT_DIR/setup-monitoring.sh" "${monitoring_args[@]}"

printf '\nTodo quedó instalado. Cierra la sesión SSH y vuelve a entrar para iniciar con Zsh.\n'
