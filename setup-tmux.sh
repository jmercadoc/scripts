#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_ubuntu
init_target_user

apt_install tmux
apt_install_optional wl-clipboard xclip xsel

install_target_file "$SCRIPT_DIR/config/tmux.conf" "$TARGET_HOME/.tmux.conf" 0644
install_target_file "$SCRIPT_DIR/bin/tmux-copy" "$TARGET_HOME/.local/bin/tmux-copy" 0755

if as_target tmux list-sessions >/dev/null 2>&1; then
  if ! as_target tmux source-file "$TARGET_HOME/.tmux.conf"; then
    warn "No se pudo recargar una sesión existente. La configuración se aplicará en la próxima sesión."
  fi
fi

log "tmux quedó configurado. Inicia una sesión con: tmux new -s trabajo"
