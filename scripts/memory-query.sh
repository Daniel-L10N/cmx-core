#!/bin/bash
# Memory Query - Consulta decisiones en cmx-memories (JSON backend)
# Uso: memory-query.sh [project] [agent] [type] [limit]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORIES_DB="$PROJECT_ROOT/memories.json"

PROJECT="${1}"
AGENT="${2}"
TYPE="${3}"
LIMIT="${4:-50}"

# Si no existe el archivo, devolver vacío
if [ ! -f "$MEMORIES_DB" ]; then
    echo "[]"
    exit 0
fi

# Construir filtro jq dinámicamente - más simple
if [ -n "$PROJECT" ] && [ -n "$AGENT" ] && [ -n "$TYPE" ]; then
    jq --arg p "$PROJECT" --arg a "$AGENT" --arg t "$TYPE" \
       '[.memories[] | select(.project == $p and .agent == $a and .type == $t)] | sort_by(.created_at) | reverse | limit('$LIMIT'; .)' \
       "$MEMORIES_DB"
elif [ -n "$PROJECT" ] && [ -n "$TYPE" ]; then
    jq --arg p "$PROJECT" --arg t "$TYPE" \
       '[.memories[] | select(.project == $p and .type == $t)] | sort_by(.created_at) | reverse | limit('$LIMIT'; .)' \
       "$MEMORIES_DB"
elif [ -n "$PROJECT" ] && [ -n "$AGENT" ]; then
    jq --arg p "$PROJECT" --arg a "$AGENT" \
       '[.memories[] | select(.project == $p and .agent == $a)] | sort_by(.created_at) | reverse | limit('$LIMIT'; .)' \
       "$MEMORIES_DB"
elif [ -n "$PROJECT" ]; then
    jq --arg p "$PROJECT" \
       '[.memories[] | select(.project == $p)] | sort_by(.created_at) | reverse | limit('$LIMIT'; .)' \
       "$MEMORIES_DB"
else
    jq ".memories | sort_by(.created_at) | reverse | limit($LIMIT; .)" "$MEMORIES_DB"
fi