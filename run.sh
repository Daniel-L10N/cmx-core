#!/bin/bash
# Cognitive Stack — Comando único para ejecutar el pipeline
# Uso: ./run.sh [comando] [opciones]

WORKSPACE="/home/cmx/cmx-core"
PIPELINE="$WORKSPACE/orchestrator/pipeline.sh"
VALIDATOR="$WORKSPACE/validators/validate.sh"

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

show_banner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         Cognitive Stack — SDD Pipeline Engine             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_help() {
    show_banner
    cat << 'EOF'

USO: ./run.sh <comando> [opciones]

COMANDOS:
  init              Inicializar pipeline y directorios
  status            Ver estado actual del pipeline
  run <name> [top]  Ejecutar pipeline completo
  explore <top>     Solo fase de exploración
  propose <name>    Solo propuesta
  spec <name>       Solo especificación
  design <name>     Solo diseño
  tasks <name>      Solo planificación
  apply <name>      Solo implementación
  verify <name>     Solo verificación
  archive <name>    Solo archivo
  validate <s> <f>  Validar archivo contra schema
  reset             Resetear estado
  help              Mostrar esta ayuda

EJEMPLOS:
  ./run.sh init
  ./run.sh run mi-feature "mi nueva funcionalidad"
  ./run.sh status
  ./run.sh validate proposal schemas/examples/proposal.valid.json

ALIAS DISPONIBLES:
  cs-pipeline       → ./run.sh
  cs-run            → ./run.sh run
  cs-status         → ./run.sh status

EOF
}

case "${1:-help}" in
    init)
        show_banner
        $PIPELINE init
        ;;
    status)
        $PIPELINE status
        ;;
    run)
        show_banner
        $PIPELINE init
        $PIPELINE run "$@"
        ;;
    explore|propose|spec|design|tasks|apply|verify|archive)
        show_banner
        $PIPELINE init
        $PIPELINE phase "$1" "$2"
        ;;
    validate)
        show_banner
        $VALIDATOR "$2" "$3"
        ;;
    reset)
        $PIPELINE reset
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        ;;
esac
