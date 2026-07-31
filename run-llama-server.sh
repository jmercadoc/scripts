#!/usr/bin/env bash
set -Eeuo pipefail

LLAMA_SERVER=${LLAMA_SERVER:-"$HOME/ia/llama.cpp/build/bin/llama-server"}
MODELS_DIR=${MODELS_DIR:-"$HOME/ia/models"}
LLAMA_HOST=${LLAMA_HOST:-0.0.0.0}
LLAMA_PORT=${LLAMA_PORT:-8080}
LLAMA_STARTUP_TIMEOUT=${LLAMA_STARTUP_TIMEOUT:-900}
LLAMA_LOG_VERBOSITY=${LLAMA_LOG_VERBOSITY:-3}
LLAMA_LOG_DIR=${LLAMA_LOG_DIR:-"$HOME/.local/state/llama-server"}
LLAMA_HEALTH_URL=${LLAMA_HEALTH_URL:-"http://127.0.0.1:${LLAMA_PORT}/health"}

# Para agregar un modelo, añade su nombre y ruta relativa con el mismo índice.
MODEL_NAMES=(
  "Qwen3.6-35B-A3B"
)

MODEL_FILES=(
  "qwen3_6-35b-A3B/Qwen3.6-35B-A3B-MXFP4_MOE.gguf"
)

log() {
  printf '\033[1;34m[llama]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[aviso]\033[0m %s\n' "$*" >&2
}

die() {
  printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2
  exit 1
}

show_models() {
  local i

  printf 'Modelos disponibles:\n\n'
  for i in "${!MODEL_NAMES[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${MODEL_NAMES[$i]}"
    printf '     %s\n' "${MODEL_FILES[$i]}"
  done

  cat <<EOF

Uso:
  $0 INDICE [OPCIONES EXTRA DE LLAMA-SERVER]

Ejemplos:
  $0 1
  LLAMA_PORT=8081 $0 1
  $0 1 --threads 16

Variables opcionales:
  LLAMA_SERVER, MODELS_DIR, LLAMA_HOST, LLAMA_PORT,
  LLAMA_STARTUP_TIMEOUT, LLAMA_LOG_VERBOSITY, LLAMA_LOG_DIR,
  LLAMA_HEALTH_URL, LLAMA_API_KEY.
EOF
}

validate_configuration() {
  [[ ${#MODEL_NAMES[@]} -eq ${#MODEL_FILES[@]} ]] \
    || die "MODEL_NAMES y MODEL_FILES deben tener la misma cantidad de entradas."
  [[ $LLAMA_PORT =~ ^[0-9]+$ ]] && (( LLAMA_PORT >= 1 && LLAMA_PORT <= 65535 )) \
    || die "LLAMA_PORT debe ser un número entre 1 y 65535."
  [[ $LLAMA_STARTUP_TIMEOUT =~ ^[0-9]+$ ]] && (( LLAMA_STARTUP_TIMEOUT > 0 )) \
    || die "LLAMA_STARTUP_TIMEOUT debe ser un entero mayor que cero."
  [[ -x $LLAMA_SERVER ]] || die "No se encontró un llama-server ejecutable en: $LLAMA_SERVER"
  [[ -d $MODELS_DIR ]] \
    || die "No se encontró $MODELS_DIR. Verifica que ~/ia apunte a la unidad montada."
  command -v curl >/dev/null 2>&1 || die "Se necesita curl para comprobar /health."

  if command -v ss >/dev/null 2>&1 \
    && ss -H -lnt 2>/dev/null | awk -v port=":$LLAMA_PORT" '$4 ~ port "$" { found=1 } END { exit !found }'; then
    die "El puerto $LLAMA_PORT ya está ocupado. Usa LLAMA_PORT=otro_puerto o detén el proceso existente."
  fi

  if [[ $LLAMA_HOST != 127.0.0.1 && $LLAMA_HOST != localhost && -z ${LLAMA_API_KEY:-} ]]; then
    warn "El servidor será accesible por red sin API key. Puedes definir LLAMA_API_KEY antes de iniciarlo."
  fi
}

validate_llama_version() {
  local help_text flag
  local -a missing_flags=()
  local -a required_flags=(
    --fit-target
    --n-cpu-moe
    --reasoning
    --cache-type-k-draft
    --cache-type-v-draft
    --spec-type
    --spec-draft-n-max
    --cache-idle-slots
    --kv-unified
    --metrics
  )

  help_text=$("$LLAMA_SERVER" --help 2>&1 || true)
  for flag in "${required_flags[@]}"; do
    grep -Fq -- "$flag" <<<"$help_text" || missing_flags+=("$flag")
  done

  if (( ${#missing_flags[@]} > 0 )); then
    printf '\033[1;31m[error]\033[0m Tu compilación de llama-server no reconoce:\n' >&2
    printf '  %s\n' "${missing_flags[@]}" >&2
    die "Actualiza/recompila llama.cpp o elimina del launcher las opciones no compatibles."
  fi
}

wait_for_health() {
  local started_at=$SECONDS
  local next_notice=0
  local elapsed http_code

  while true; do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      set +e
      wait "$SERVER_PID"
      SERVER_EXIT_CODE=$?
      set -e
      return 1
    fi

    http_code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --max-time 2 "$LLAMA_HEALTH_URL" 2>/dev/null || true)
    if [[ $http_code == 200 ]]; then
      return 0
    fi

    elapsed=$((SECONDS - started_at))
    if (( elapsed >= LLAMA_STARTUP_TIMEOUT )); then
      return 2
    fi
    if (( elapsed >= next_notice )); then
      if [[ $http_code == 503 ]]; then
        log "El proceso está activo y el modelo sigue cargándose (${elapsed}s)..."
      else
        log "Esperando que el servidor abra el puerto ${LLAMA_PORT} (${elapsed}s)..."
      fi
      next_notice=$((elapsed + 10))
    fi
    sleep 2
  done
}

if [[ ${1:-} == --list || ${1:-} == -l ]]; then
  show_models
  exit 0
fi

if (( $# < 1 )); then
  show_models
  exit 1
fi

MODEL_NUMBER=$1
shift
EXTRA_ARGS=("$@")

[[ $MODEL_NUMBER =~ ^[0-9]+$ ]] || die "El índice debe ser un número entero."
MODEL_INDEX=$((10#$MODEL_NUMBER - 1))
if (( MODEL_INDEX < 0 || MODEL_INDEX >= ${#MODEL_FILES[@]} )); then
  die "El modelo número $MODEL_NUMBER no existe. Usa --list para ver las opciones."
fi

validate_configuration
validate_llama_version

MODEL_ALIAS=${MODEL_NAMES[$MODEL_INDEX]}
MODEL_PATH="${MODELS_DIR%/}/${MODEL_FILES[$MODEL_INDEX]}"
[[ -f $MODEL_PATH ]] || die "No se encontró el modelo: $MODEL_PATH"

mkdir -p "$LLAMA_LOG_DIR"
LOG_FILE="$LLAMA_LOG_DIR/${MODEL_ALIAS}-$(date +%Y%m%d-%H%M%S).log"

SERVER_ARGS=(
  --model "$MODEL_PATH"
  --alias "$MODEL_ALIAS"
  --host "$LLAMA_HOST"
  --port "$LLAMA_PORT"
  --n-gpu-layers all
  --fit on
  --fit-target 1536
  --ctx-size 65536
  --n-cpu-moe 37
  --reasoning on
  --cache-type-k q8_0
  --cache-type-v q8_0
  --cache-type-k-draft q8_0
  --cache-type-v-draft q8_0
  --spec-type draft-mtp
  --spec-draft-n-max 2
  --temp 0.6
  --top-p 0.95
  --top-k 20
  --min-p 0.0
  --presence-penalty 0.0
  --repeat-penalty 1.0
  --parallel 1
  --log-verbosity "$LLAMA_LOG_VERBOSITY"
  --log-timestamps
  --metrics
  --cache-idle-slots
  --kv-unified
)

if (( ${#EXTRA_ARGS[@]} > 0 )); then
  SERVER_ARGS+=("${EXTRA_ARGS[@]}")
fi

printf '\n'
log "Iniciando llama-server"
log "Modelo: $MODEL_ALIAS"
log "Archivo: $MODEL_PATH"
log "Escuchará en: $LLAMA_HOST:$LLAMA_PORT"
log "Comprobación: $LLAMA_HEALTH_URL"
log "Log: $LOG_FILE"
printf '\n'

"$LLAMA_SERVER" "${SERVER_ARGS[@]}" > >(tee -a "$LOG_FILE") 2>&1 &
SERVER_PID=$!
SERVER_EXIT_CODE=0

stop_server() {
  trap - INT TERM
  warn "Deteniendo llama-server (PID $SERVER_PID)..."
  kill -TERM "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  exit 130
}
trap stop_server INT TERM

set +e
wait_for_health
health_status=$?
set -e

case $health_status in
  0)
    printf '\n'
    log "MODELO CARGADO: llama-server está listo para recibir peticiones."
    log "Web/API local: http://127.0.0.1:$LLAMA_PORT/"
    if command -v hostname >/dev/null 2>&1; then
      LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
      [[ -n $LAN_IP ]] && log "Web/API en la red: http://$LAN_IP:$LLAMA_PORT/"
    fi
    log "Métricas: http://127.0.0.1:$LLAMA_PORT/metrics"
    printf '\n'
    ;;
  1)
    die "llama-server terminó durante la carga (código $SERVER_EXIT_CODE). Revisa: $LOG_FILE"
    ;;
  2)
    warn "El proceso sigue activo, pero /health no respondió listo después de ${LLAMA_STARTUP_TIMEOUT}s."
    warn "Revisa el log y prueba: curl -i $LLAMA_HEALTH_URL"
    ;;
esac

set +e
wait "$SERVER_PID"
SERVER_EXIT_CODE=$?
set -e
log "llama-server terminó con código $SERVER_EXIT_CODE."
exit "$SERVER_EXIT_CODE"
