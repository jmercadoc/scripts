#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CHANGE_SHELL=1

usage() {
  cat <<'EOF'
Uso: ./setup-zsh.sh [--no-chsh]

  --no-chsh  Instala todo, pero no cambia el shell predeterminado del usuario.

Para configurar otro usuario: SETUP_USER=nombre ./setup-zsh.sh
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --no-chsh) CHANGE_SHELL=0 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opción desconocida: $1" ;;
  esac
  shift
done

require_ubuntu
init_target_user

apt_install zsh git curl fzf command-not-found
apt_install_optional ripgrep bat fd-find eza zoxide

clone_for_target() {
  local url=$1
  local destination=$2
  local expected_file=$3

  if [[ -f $destination/$expected_file ]]; then
    log "Ya existe, no se modifica: $destination"
    return
  fi
  [[ ! -e $destination ]] || die "$destination existe, pero parece ser una instalación incompleta."
  ensure_target_dir "$(dirname "$destination")"
  log "Clonando $url"
  as_target git clone --depth=1 "$url" "$destination"
}

clone_for_target https://github.com/ohmyzsh/ohmyzsh.git \
  "$TARGET_HOME/.oh-my-zsh" oh-my-zsh.sh
clone_for_target https://github.com/romkatv/powerlevel10k.git \
  "$TARGET_HOME/.oh-my-zsh/custom/themes/powerlevel10k" powerlevel10k.zsh-theme
clone_for_target https://github.com/zsh-users/zsh-autosuggestions.git \
  "$TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" zsh-autosuggestions.zsh
clone_for_target https://github.com/zsh-users/zsh-syntax-highlighting.git \
  "$TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" zsh-syntax-highlighting.zsh

install_target_file "$SCRIPT_DIR/config/zshrc" "$TARGET_HOME/.zshrc" 0644

if (( CHANGE_SHELL == 1 )); then
  zsh_path=$(command -v zsh)
  current_shell=$(getent passwd "$TARGET_USER" | cut -d: -f7)
  if [[ $current_shell != "$zsh_path" ]]; then
    log "Cambiando el shell predeterminado de $TARGET_USER a $zsh_path"
    as_root usermod --shell "$zsh_path" "$TARGET_USER"
  else
    log "zsh ya es el shell predeterminado."
  fi
fi

log "Zsh quedó listo. Abre una sesión nueva; Powerlevel10k iniciará su asistente visual."
warn "Para ver todos los iconos, configura una Nerd Font en la terminal desde la que te conectas por SSH."
