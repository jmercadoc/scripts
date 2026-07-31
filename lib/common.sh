#!/usr/bin/env bash

# Funciones compartidas por los instaladores. Este archivo debe cargarse con source.

log() {
  printf '\033[1;34m[setup]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[aviso]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2
  exit 1
}

require_ubuntu() {
  [[ -r /etc/os-release ]] || die "No se encontró /etc/os-release."

  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == "ubuntu" ]] || die "Este instalador está diseñado para Ubuntu (detectado: ${ID:-desconocido})."
}

init_target_user() {
  if [[ -n ${SETUP_USER:-} ]]; then
    TARGET_USER=$SETUP_USER
  elif [[ -n ${SUDO_USER:-} && ${SUDO_USER} != "root" ]]; then
    TARGET_USER=$SUDO_USER
  else
    TARGET_USER=$(id -un)
  fi

  getent passwd "$TARGET_USER" >/dev/null || die "El usuario '$TARGET_USER' no existe."
  TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
  TARGET_GROUP=$(id -gn "$TARGET_USER")
  export TARGET_USER TARGET_HOME TARGET_GROUP
  log "Configurando al usuario $TARGET_USER ($TARGET_HOME)."
}

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "Se necesita sudo para instalar paquetes."
    sudo "$@"
  fi
}

as_target() {
  if [[ $(id -un) == "$TARGET_USER" ]]; then
    "$@"
  elif (( EUID == 0 )); then
    command -v runuser >/dev/null 2>&1 || die "No se encontró runuser."
    runuser -u "$TARGET_USER" -- "$@"
  else
    sudo -H -u "$TARGET_USER" "$@"
  fi
}

APT_UPDATED=0

apt_update() {
  if (( APT_UPDATED == 0 )); then
    if [[ ${SETUP_APT_UPDATED:-0} == 1 ]]; then
      log "El índice de paquetes ya se actualizó durante esta instalación."
    else
      log "Actualizando el índice de paquetes..."
      as_root env DEBIAN_FRONTEND=noninteractive apt-get update
    fi
    APT_UPDATED=1
  fi
}

apt_install() {
  apt_update
  log "Instalando paquetes: $*"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

apt_install_optional() {
  local package

  apt_update
  for package in "$@"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
      log "Instalando paquete opcional: $package"
      if ! as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$package"; then
        warn "No se pudo instalar el paquete opcional '$package'; se continúa."
      fi
    else
      warn "'$package' no está disponible en esta versión de Ubuntu; se omite."
    fi
  done
}

ensure_target_dir() {
  local directory=$1
  local mode=${2:-0755}
  as_root install -d -m "$mode" -o "$TARGET_USER" -g "$TARGET_GROUP" "$directory"
}

install_target_file() {
  local source_file=$1
  local destination=$2
  local mode=${3:-0644}
  local backup

  [[ -f $source_file ]] || die "No existe el archivo fuente: $source_file"
  ensure_target_dir "$(dirname "$destination")"

  if [[ -f $destination ]] && cmp -s "$source_file" "$destination"; then
    log "Sin cambios: $destination"
    return
  fi

  if [[ -e $destination ]]; then
    backup="${destination}.backup.$(date +%Y%m%d-%H%M%S)"
    as_root cp -a "$destination" "$backup"
    log "Respaldo creado: $backup"
  fi

  as_root install -m "$mode" -o "$TARGET_USER" -g "$TARGET_GROUP" "$source_file" "$destination"
  log "Instalado: $destination"
}

install_root_file() {
  local source_file=$1
  local destination=$2
  local mode=${3:-0755}
  local backup

  [[ -f $source_file ]] || die "No existe el archivo fuente: $source_file"
  if [[ -f $destination ]] && cmp -s "$source_file" "$destination"; then
    log "Sin cambios: $destination"
    return
  fi

  if [[ -e $destination ]]; then
    backup="${destination}.backup.$(date +%Y%m%d-%H%M%S)"
    as_root cp -a "$destination" "$backup"
    log "Respaldo creado: $backup"
  fi

  as_root install -D -m "$mode" -o root -g root "$source_file" "$destination"
  log "Instalado: $destination"
}
