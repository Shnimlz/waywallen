#!/usr/bin/env bash
set -e

# Configuración de los repositorios Fork
# Cambia estos enlaces por los tuyos si renombras tus repositorios en GitHub.
REPO_WAYWALLEN_DISPLAY="https://github.com/Shnimlz/waywallen-display.git"
REPO_OPEN_WALLPAPER_ENGINE="https://github.com/Shnimlz/open-wallpaper-engine.git"

# Colores para la salida
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Waywallen Ecosystem Installer ===${NC}"

# 1. Comprobación de dependencias
echo -e "${BLUE}[1/6] Comprobando dependencias...${NC}"
for cmd in git cmake clang++ ninja sudo; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: El comando '$cmd' no está instalado o no está en el PATH.${NC}"
        echo "Por favor instálalo e inténtalo de nuevo (ej. sudo pacman -S git cmake clang ninja sudo)."
        exit 1
    fi
done
echo -e "${GREEN}Dependencias verificadas.${NC}"

# Pedir permisos de sudo por adelantado
echo -e "${BLUE}Se requieren permisos de administrador para instalar los archivos en /usr/${NC}"
sudo -v

# Entorno base: asumimos que estamos dentro del repositorio principal 'waywallen'
BASE_DIR="$(dirname "$(realpath "$0")")/.."
cd "$BASE_DIR"

# 2. Clonado de repositorios faltantes
echo -e "${BLUE}[2/6] Preparando repositorios...${NC}"

if [ ! -d "waywallen-display" ]; then
    echo "Clonando waywallen-display..."
    git clone "$REPO_WAYWALLEN_DISPLAY" waywallen-display
else
    echo "Directorio waywallen-display ya existe."
fi

if [ ! -d "open-wallpaper-engine" ]; then
    echo "Clonando open-wallpaper-engine..."
    git clone "$REPO_OPEN_WALLPAPER_ENGINE" open-wallpaper-engine
else
    echo "Directorio open-wallpaper-engine ya existe."
fi

# Variable para saber si debemos reiniciar el servicio al final
RESTART_NEEDED=false

# 3. Compilar e Instalar waywallen (Daemon)
echo -e "${BLUE}[3/6] Compilando e instalando waywallen (Daemon & UI)...${NC}"
cd waywallen
cmake --preset clang-release -DCMAKE_INSTALL_PREFIX=/usr
BUILD_OUT=$(cmake --build build/clang-release -j$(nproc))
echo "$BUILD_OUT"
if ! echo "$BUILD_OUT" | grep -q "ninja: no work to do."; then
    echo "Instalando waywallen en el sistema..."
    sudo cmake --install build/clang-release
    RESTART_NEEDED=true
else
    echo "Sin cambios en waywallen, saltando instalación."
fi
cd ..

# 4. Compilar e Instalar open-wallpaper-engine (wescene-renderer y weweb-renderer)
echo -e "${BLUE}[4/6] Compilando e instalando open-wallpaper-engine...${NC}"
cd open-wallpaper-engine
cmake --preset clang-release -DBUILD_WEWEB=ON -DBUILD_VIEWER=OFF -DBUILD_TESTS=OFF -DCMAKE_INSTALL_PREFIX=/usr
BUILD_OUT=$(cmake --build build/clang-release -j$(nproc))
echo "$BUILD_OUT"
if ! echo "$BUILD_OUT" | grep -q "ninja: no work to do."; then
    echo "Instalando open-wallpaper-engine en el sistema..."
    sudo cmake --install build/clang-release
    RESTART_NEEDED=true
else
    echo "Sin cambios en open-wallpaper-engine, saltando instalación."
fi
cd ..

# 5. Compilar e Instalar waywallen-display (KDE kpackage)
echo -e "${BLUE}[5/6] Compilando e instalando waywallen-display (KPackage para Plasma)...${NC}"
cd waywallen-display
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=~/.local
BUILD_OUT=$(cmake --build build -j$(nproc))
echo "$BUILD_OUT"
if ! echo "$BUILD_OUT" | grep -q "ninja: no work to do."; then
    echo "Instalando módulo de display en Plasma..."
    sudo cmake --install build
    echo "Creando enlace simbólico para el módulo QML en /usr/lib/qt6/qml/Waywallen..."
    sudo ln -sf /usr/local/lib/qt6/qml/Waywallen /usr/lib/qt6/qml/Waywallen
    RESTART_NEEDED=true
else
    echo "Sin cambios en waywallen-display, saltando instalación."
fi
cd ..

# 6. Configuración de Systemd
echo -e "${BLUE}[6/6] Configurando e iniciando el servicio de sistema (Systemd)...${NC}"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/waywallen.service"

if [ ! -f "$SERVICE_FILE" ]; then
    mkdir -p "$SERVICE_DIR"
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Waywallen Wallpaper Daemon
After=plasma-workspace.target

[Service]
ExecStart=/usr/bin/waywallen
Restart=on-failure
RestartSec=5
Environment="WAYLAND_DISPLAY=wayland-0"

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable waywallen.service
    RESTART_NEEDED=true
fi

if [ "$RESTART_NEEDED" = true ]; then
    echo "Reiniciando el servicio waywallen..."
    systemctl --user daemon-reload
    systemctl --user restart waywallen.service
else
    echo "No hubo cambios en los binarios, el servicio sigue corriendo sin interrupción."
fi

echo -e "${GREEN}=== Instalación completada exitosamente ===${NC}"
echo -e "El demonio de Waywallen ha sido iniciado en segundo plano."
echo -e "Para aplicar los fondos en tu escritorio KDE:"
echo -e "1. Haz clic derecho en tu escritorio -> 'Configurar escritorio y fondo de pantalla'"
echo -e "2. Cambia el tipo de fondo a 'Waywallen'"
