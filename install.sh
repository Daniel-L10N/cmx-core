#!/bin/bash
# CMX-CORE — Script de Instalación Rápida
# Uso: curl -fsSL https://raw.githubusercontent.com/Daniel-L10N/cmx-core/feature/working/install.sh | bash
# O: bash <(curl -fsSL https://raw.githubusercontent.com/Daniel-L10N/cmx-core/feature/working/install.sh)

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║${NC}       🚀 CMX-CORE — INSTALACIÓN RÁPIDA               ${CYAN}${BOLD}║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# DETECTAR SISTEMA
# ============================================================

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        OS="unknown"
    fi
    
    case "$OS" in
        fedora|rhel|centos) PKG_MANAGER="dnf" ;;
        debian|ubuntu|mint) PKG_MANAGER="apt" ;;
        arch) PKG_MANAGER="pacman" ;;
        *) PKG_MANAGER="unknown" ;;
    esac
    
    echo -e "${BLUE}Sistema detectado:${NC} $OS $VER ($PKG_MANAGER)"
}

# ============================================================
# INSTALAR DEPENDENCIAS
# ============================================================

install_deps() {
    echo ""
    echo -e "${BOLD}▶ Instalando dependencias...${NC}"
    
    case "$PKG_MANAGER" in
        dnf)
            sudo dnf install -y git jq curl 2>/dev/null || \
            sudo yum install -y git jq curl
            ;;
        apt)
            sudo apt update -qq && \
            sudo apt install -y git jq curl
            ;;
        pacman)
            sudo pacman -Sy --noconfirm git jq curl
            ;;
        *)
            echo -e "${YELLOW}No se pudo instalar automáticamente. Instala: git, jq, curl${NC}"
            ;;
    esac
    
    echo -e "${GREEN}✅ Dependencias instaladas${NC}"
}

# ============================================================
# CLONAR O ACTUALIZAR
# ============================================================

clone_or_update() {
    echo ""
    echo -e "${BOLD}▶ Configurando CMX-CORE...${NC}"
    
    if [ -d "$HOME/cmx-core" ]; then
        echo -e "${YELLOW}CMX-CORE ya existe. Actualizando...${NC}"
        cd "$HOME/cmx-core"
        git pull origin feature/working
    else
        echo "Clonando repositorio..."
        git clone -b feature/working https://github.com/Daniel-L10N/cmx-core.git "$HOME/cmx-core"
        cd "$HOME/cmx-core"
    fi
    
    # Permisos de ejecución
    chmod +x *.sh agents/*.sh orchestrator/*.sh 2>/dev/null || true
    
    echo -e "${GREEN}✅ CMX-CORE configurado${NC}"
}

# ============================================================
# CONFIGURAR SUDO (OPCIONAL)
# ============================================================

setup_sudo() {
    echo ""
    echo -e "${BOLD}▶ Configurar modo Dangerous? (opcional)${NC}"
    echo -e "   Esto permite acceso sudo sin contraseña para CMX-CORE"
    echo ""
    read -n1 -p "   ¿Configurar? [y/N]: " choice
    echo ""
    
    if [ "$choice" == "y" ] || [ "$choice" == "Y" ]; then
        echo -e "${YELLOW}Ingresa tu contraseña de sudo:${NC}"
        read -s -p "   Contraseña: " SUDO_PASS
        echo ""
        
        # Crear directorio seguro
        mkdir -p "$HOME/.cmx-secrets"
        chmod 700 "$HOME/.cmx-secrets"
        
        # Guardar contraseña
        echo "$SUDO_PASS" > "$HOME/.cmx-secrets/sudo.pass"
        chmod 600 "$HOME/.cmx-secrets/sudo.pass"
        
        # Agregar a gitignore si no existe
        if [ ! -f "$HOME/cmx-core/.gitignore" ] || ! grep -q ".cmx-secrets" "$HOME/cmx-core/.gitignore" 2>/dev/null; then
            echo "" >> "$HOME/cmx-core/.gitignore"
            echo "# CMX-CORE Secrets" >> "$HOME/cmx-core/.gitignore"
            echo ".cmx-secrets/" >> "$HOME/cmx-core/.gitignore"
        fi
        
        echo -e "${GREEN}✅ Contraseña guardada en ~/.cmx-secrets/sudo.pass${NC}"
    fi
}

# ============================================================
# INICIALIZAR GIT
# ============================================================

init_git() {
    echo ""
    echo -e "${BOLD}▶ Inicializando Git Manager...${NC}"
    
    cd "$HOME/cmx-core"
    
    # Solo si es un nuevo clone
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        git init
        git config user.email "cmx-agent@local"
        git config user.name "CMX-Agent"
        echo -e "${GREEN}✅ Git inicializado${NC}"
    else
        echo -e "${GREEN}✅ Git ya configurado${NC}"
    fi
    
    # Verificar remote
    if ! git remote get-url origin > /dev/null 2>&1; then
        echo -e "${YELLOW}No hay remote configurado. ¿Conectar a GitHub?${NC}"
        read -n1 -p "   [y/N]: " choice
        echo ""
        if [ "$choice" == "y" ] || [ "$choice" == "Y" ]; then
            echo "Ejecuta: git remote add origin https://github.com/Daniel-L10N/cmx-core.git"
        fi
    fi
}

# ============================================================
# FINAL
# ============================================================

finalize() {
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║${NC}              ✅ INSTALACIÓN COMPLETADA                  ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}CMX-CORE instalado en:${NC} $HOME/cmx-core"
    echo ""
    echo -e "  ${BOLD}Comandos:${NC}"
    echo -e "    cd ~/cmx-core"
    echo -e "    ./set-mode.sh              # Cambiar modo"
    echo -e "    ./full-auto.sh <feature>   # Modo peligroso"
    echo -e "    ./agents/git-manager.sh init  # Inicializar git"
    echo ""
    echo -e "${GREEN}¡Listo para trabajar! 🚀${NC}"
    echo ""
}

# ============================================================
# EJECUTAR
# ============================================================

main() {
    detect_os
    install_deps
    clone_or_update
    setup_sudo
    init_git
    finalize
}

main "$@"
