#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

WITH_NODE_EXPORTER=0

usage() {
  cat <<'EOF'
Uso: ./setup-monitoring.sh [--with-node-exporter]

  --with-node-exporter  Instala Prometheus Node Exporter y habilita su servicio.
                        Normalmente escucha en el puerto TCP 9100; revisa tu firewall.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --with-node-exporter) WITH_NODE_EXPORTER=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opción desconocida: $1" ;;
  esac
  shift
done

require_ubuntu
init_target_user

apt_install \
  procps psmisc iproute2 pciutils usbutils lsof strace jq curl \
  htop sysstat iotop iftop nethogs ncdu \
  lm-sensors smartmontools nvme-cli

apt_install_optional btop nvtop glances duf nmon atop ipmitool

install_root_file "$SCRIPT_DIR/bin/ai-monitor" /usr/local/bin/ai-monitor 0755

# Ubuntu distribuye sysstat deshabilitado en algunas versiones.
if [[ -f /etc/default/sysstat ]]; then
  as_root sed -ri 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
fi

if [[ -d /run/systemd/system ]]; then
  if ! as_root systemctl enable --now sysstat.service; then
    warn "No se pudo habilitar sysstat; puedes revisar: systemctl status sysstat"
  fi
  if command -v atop >/dev/null 2>&1; then
    if ! as_root systemctl enable --now atop.service; then
      warn "atop está instalado, pero su servicio no pudo habilitarse."
    fi
  fi
else
  warn "systemd no está activo; se instalaron las herramientas sin habilitar servicios."
fi

if (( WITH_NODE_EXPORTER == 1 )); then
  apt_install prometheus-node-exporter
  if [[ -d /run/systemd/system ]]; then
    as_root systemctl enable --now prometheus-node-exporter.service
  fi
  warn "Node Exporter puede escuchar en TCP 9100. Limita el acceso mediante firewall o red privada."
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  log "GPU NVIDIA detectada: nvidia-smi y ai-monitor podrán mostrar sus métricas."
elif command -v rocm-smi >/dev/null 2>&1; then
  log "GPU AMD/ROCm detectada: ai-monitor usará rocm-smi."
else
  warn "No se detectó nvidia-smi ni rocm-smi. Este script no instala ni modifica drivers de GPU."
fi

log "Monitoreo listo. Prueba: ai-monitor overview"
log "Panel interactivo: ai-monitor dashboard"
