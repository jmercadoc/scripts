# Scripts para servidor Ubuntu de IA

Este repositorio prepara una cuenta de usuario en Ubuntu con:

- `tmux` configurado como en la estación de trabajo original: mouse, ventanas y paneles desde 1, historial de 50,000 líneas, divisiones conservando el directorio actual y atajos de navegación/redimensión.
- Zsh, Oh My Zsh y Powerlevel10k, con sugerencias, resaltado de sintaxis, `fzf` y los plugins usados en la máquina original.
- Herramientas ligeras de monitoreo para CPU, RAM, disco, red y GPU, más un panel específico para procesos de `llama.cpp`/GGML.

Los instaladores están pensados para Ubuntu, se pueden ejecutar más de una vez y crean un respaldo con fecha antes de reemplazar una configuración existente. No instalan ni modifican drivers de GPU y no abren puertos por defecto.

## Instalación completa

Ejecuta el instalador como el usuario que utilizará el servidor; él solicitará `sudo` cuando sea necesario:

```bash
chmod +x install.sh setup-*.sh bin/*
./install.sh
```

Si recibes los archivos siendo `root` pero quieres configurar otra cuenta:

```bash
SETUP_USER=antonio ./install.sh
```

Opciones disponibles:

```bash
./install.sh --no-chsh
./install.sh --with-node-exporter
```

`--with-node-exporter` habilita Prometheus Node Exporter, que normalmente escucha en TCP 9100. Úsalo solamente si ya tienes un Prometheus que recogerá las métricas y limita el puerto mediante la red privada o el firewall.

También puedes instalar cada parte por separado:

```bash
./setup-tmux.sh
./setup-zsh.sh
./setup-monitoring.sh
```

## tmux

La tecla prefijo sigue siendo la predeterminada: `Ctrl-b`.

| Acción | Atajo |
|---|---|
| Dividir horizontalmente | `Ctrl-b`, luego `|` |
| Dividir verticalmente | `Ctrl-b`, luego `-` |
| Panel izquierdo/derecho/arriba/abajo | `Ctrl-b`, luego flecha |
| Redimensionar | `Ctrl-b`, luego `H`, `J`, `K` o `L` |
| Ventana nueva en el directorio actual | `Ctrl-b`, luego `c` |

Al seleccionar texto con el mouse, la selección siempre queda en el buffer de `tmux`. Si existe un portapapeles gráfico (`Wayland` o `X11`) también se copia allí. Sobre SSH, la propagación al portapapeles local depende de que el emulador de terminal permita la integración de portapapeles de `tmux`.

## Zsh y Powerlevel10k

Al entrar por primera vez en una sesión nueva, Powerlevel10k mostrará su asistente. Para que sus iconos se vean correctamente debes elegir una **Nerd Font** en la computadora cliente desde la que abres SSH; la fuente no se instala en el servidor.

El archivo `~/.zshrc` es administrado por estos scripts. Agrega aliases, variables privadas o ajustes exclusivos del servidor en `~/.zshrc.local`; ese archivo no será reemplazado.

## Monitoreo del servidor de IA

Comandos principales:

```bash
ai-monitor overview     # resumen de recursos y procesos llama.cpp
ai-monitor gpu          # NVIDIA, AMD/ROCm o sensores disponibles
ai-monitor processes    # procesos llama.cpp/GGML
ai-monitor ports        # puertos TCP en escucha
ai-monitor dashboard    # panel continuo de 4 vistas dentro de tmux
```

También quedan disponibles, dependiendo de la versión de Ubuntu: `btop`, `htop`, `nvtop`, `iostat`, `iotop`, `iftop`, `nethogs`, `atop`, `glances`, `sensors`, `smartctl` y `nvme`.

El panel detecta `nvidia-smi` o `rocm-smi`, pero los controladores deben instalarse por separado siguiendo las indicaciones del fabricante y la versión concreta de Ubuntu/GPU.

## Transferencia sin acceso directo al servidor

Puedes comprimir el repositorio, transferir el archivo por el medio disponible y luego extraerlo en Ubuntu:

```bash
tar -czf ubuntu-ai-scripts.tar.gz --exclude=.git --exclude=ubuntu-ai-scripts.tar.gz .
mkdir -p ubuntu-ai-scripts
tar -xzf ubuntu-ai-scripts.tar.gz -C ubuntu-ai-scripts
cd ubuntu-ai-scripts
./install.sh
```
