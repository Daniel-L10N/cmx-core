#!/bin/bash
# CMX-CORE — Agent: Git Manager
# Automatización de operaciones Git y integración con GitHub CLI
# Usage: git-manager.sh <command> [args]

# Note: No 'set -e' to allow proper error handling with validation functions
# Each function handles its own errors and returns appropriate exit codes

WORKSPACE="${WORKSPACE:-$(dirname "$0")/..}"
COMMAND="${1:-help}"
FORCE_PUSH=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log() { echo -e "${BLUE}[GM]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }

REPO_ROOT=$(git -C "$WORKSPACE" rev-parse --show-toplevel 2>/dev/null || echo "")
DEFAULT_REMOTE="${DEFAULT_REMOTE:-origin}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

mask_token() {
    local token="$1"
    if [ ${#token} -gt 4 ]; then
        echo "****${token: -4}"
    else
        echo "****"
    fi
}

validate_github_token() {
    if [ -z "$GITHUB_TOKEN" ]; then
        log_error "GITHUB_TOKEN no está configurado"
        echo ""
        echo "=========================================="
        echo "INSTRUCCIONES DE CONFIGURACIÓN"
        echo "=========================================="
        echo "1. Genera un token en:"
        echo "   https://github.com/settings/tokens"
        echo ""
        echo "2. Tokens requeridos:"
        echo "   - repo (acceso completo a repositorios)"
        echo ""
        echo "3. Configura el token:"
        echo "   export GITHUB_TOKEN='ghp_xxxxx'"
        echo ""
        echo "4. Opcionalmente en ~/.bashrc o ~/.zshrc:"
        echo "   echo 'export GITHUB_TOKEN=\"ghp_xxxxx\"' >> ~/.bashrc"
        echo "=========================================="
        return 1
    fi
    
    MASKED=$(mask_token "$GITHUB_TOKEN")
    log_info "Token configurado: $MASKED"
    return 0
}

require_git_repo() {
    if [ ! -d "$WORKSPACE/.git" ]; then
        log_error "No es un repositorio Git: $WORKSPACE"
        return 1
    fi
    return 0
}

require_gh() {
    if ! command -v gh &>/dev/null; then
        log_error "GitHub CLI (gh) no está instalado"
        echo ""
        echo "=========================================="
        echo "INSTALACIÓN DE GITHUB CLI"
        echo "=========================================="
        echo "macOS: brew install gh"
        echo "Linux: sudo apt install gh || sudo dnf install gh"
        echo "Windows: winget install GitHub.cli"
        echo ""
        echo "O descarga desde: https://cli.github.com/"
        echo "=========================================="
        return 1
    fi
    return 0
}

git_init() {
    log "Inicializando repositorio Git..."
    
    if [ -d "$WORKSPACE/.git" ]; then
        log_ok "Repositorio existente detectado"
        
        CURRENT_BRANCH=$(git -C "$WORKSPACE" branch --show-current 2>/dev/null || echo "main")
        log_info "Branch actual: $CURRENT_BRANCH"
        
        if git -C "$WORKSPACE" remote get-url "$DEFAULT_REMOTE" &>/dev/null; then
            REMOTE_URL=$(git -C "$WORKSPACE" remote get-url "$DEFAULT_REMOTE")
            log_info "Remote '$DEFAULT_REMOTE': $REMOTE_URL"
            
            if [[ "$REMOTE_URL" == git@* ]]; then
                log_warn "Remote usa SSH (git@). Se recomienda HTTPS para usar GITHUB_TOKEN"
                log_info "Cambiar a HTTPS: git remote set-url $DEFAULT_REMOTE https://github.com/owner/repo.git"
            fi
        else
            log_warn "No se encontró remote '$DEFAULT_REMOTE'"
        fi
        
        echo ""
        echo "{\"initialized\": true, \"has_remote\": $(git -C "$WORKSPACE" remote get-url "$DEFAULT_REMOTE" &>/dev/null && echo "true" || echo "false"), \"current_branch\": \"$CURRENT_BRANCH\", \"message\": \"Repository already initialized\"}"
        return 0
    fi
    
    log_info "Creando repositorio Git en $WORKSPACE"
    git -C "$WORKSPACE" init
    git -C "$WORKSPACE" config user.email "cmx-agent@localhost"
    git -C "$WORKSPACE" config user.name "CMX-Agent"
    
    CURRENT_BRANCH=$(git -C "$WORKSPACE" branch --show-current 2>/dev/null || echo "main")
    log_ok "Repositorio inicializado (branch: $CURRENT_BRANCH)"
    
    echo ""
    echo "{\"initialized\": true, \"has_remote\": false, \"current_branch\": \"$CURRENT_BRANCH\", \"message\": \"Repository initialized\"}"
    return 0
}

git_status() {
    require_git_repo || return 1
    
    CURRENT_BRANCH=$(git -C "$WORKSPACE" branch --show-current)
    
    if git -C "$WORKSPACE" rev-parse --verify --abbrev-ref HEAD@{upstream} &>/dev/null 2>&1; then
        AHEAD=$(git -C "$WORKSPACE" rev-list --count "@{upstream}..HEAD" 2>/dev/null || echo "0")
        BEHIND=$(git -C "$WORKSPACE" rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo "0")
        HAS_UPSTREAM=true
    else
        AHEAD=0
        BEHIND=0
        HAS_UPSTREAM=false
    fi
    
    STAGED=$(git -C "$WORKSPACE" diff --cached --name-only 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    MODIFIED=$(git -C "$WORKSPACE" diff --name-only 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    UNTRACKED=$(git -C "$WORKSPACE" ls-files --others --exclude-standard --name-only 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    DELETED=$(git -C "$WORKSPACE" diff --diff-filter=D --name-only 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    
    echo ""
    echo "=========================================="
    echo " Git Status — $CURRENT_BRANCH"
    echo "=========================================="
    
    if [ "$HAS_UPSTREAM" = true ]; then
        if [ "$AHEAD" -gt 0 ]; then
            echo -e " ${GREEN}↑${NC} Ahead: $AHEAD commit(s)"
        fi
        if [ "$BEHIND" -gt 0 ]; then
            echo -e " ${YELLOW}↓${NC} Behind: $BEHIND commit(s)"
        fi
    else
        echo -e " ${MAGENTA}○${NC} No upstream configured"
    fi
    
    if [ -n "$STAGED" ]; then
        echo -e " ${GREEN}Staged:${NC}"
        echo "$STAGED" | tr ',' '\n' | sed 's/^/   /'
    fi
    if [ -n "$MODIFIED" ]; then
        echo -e " ${YELLOW}Modified:${NC}"
        echo "$MODIFIED" | tr ',' '\n' | sed 's/^/   /'
    fi
    if [ -n "$DELETED" ]; then
        echo -e " ${RED}Deleted:${NC}"
        echo "$DELETED" | tr ',' '\n' | sed 's/^/   /'
    fi
    if [ -n "$UNTRACKED" ]; then
        echo -e " ${CYAN}Untracked:${NC}"
        echo "$UNTRACKED" | tr ',' '\n' | sed 's/^/   /'
    fi
    
    if [ -z "$STAGED" ] && [ -z "$MODIFIED" ] && [ -z "$UNTRACKED" ] && [ -z "$DELETED" ]; then
        log_ok "Working tree clean"
    fi
    
    echo "=========================================="
    echo ""
    
    STAGED_COUNT=$(git -C "$WORKSPACE" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED_COUNT=$(git -C "$WORKSPACE" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    UNTRACKED_COUNT=$(git -C "$WORKSPACE" ls-files --others --exclude-standard --name-only 2>/dev/null | wc -l | tr -d ' ')
    DELETED_COUNT=$(git -C "$WORKSPACE" diff --diff-filter=D --name-only 2>/dev/null | wc -l | tr -d ' ')
    
    echo "{\"branch\": \"$CURRENT_BRANCH\", \"has_upstream\": $HAS_UPSTREAM, \"ahead\": $AHEAD, \"behind\": $BEHIND, \"staged\": [${STAGED:+"$STAGED"}], \"modified\": [${MODIFIED:+"$MODIFIED"}], \"deleted\": [${DELETED:+"$DELETED"}], \"untracked\": [${UNTRACKED:+"$UNTRACKED"}], \"counts\": {\"staged\": $STAGED_COUNT, \"modified\": $MODIFIED_COUNT, \"deleted\": $DELETED_COUNT, \"untracked\": $UNTRACKED_COUNT}}"
    return 0
}

git_add() {
    require_git_repo || return 1
    
    local pattern="${1:-.}"
    local interactive="${2:-false}"
    
    if [ "$pattern" == "." ]; then
        log "Añadiendo todos los archivos al staging..."
        git -C "$WORKSPACE" add -A
        STAGED_FILES=$(git -C "$WORKSPACE" diff --cached --name-only)
        COUNT=$(echo "$STAGED_FILES" | grep -c . || echo "0")
        log_ok "Añadidos $COUNT archivo(s) al staging"
    elif [[ "$pattern" == *"*"* ]] || [[ "$pattern" == *"?"* ]]; then
        log "Añadiendo archivos con patrón glob: $pattern"
        mapfile -t MATCHED_FILES < <(git -C "$WORKSPACE" ls-files --others --exclude-standard -z | xargs -0 -I{} sh -c 'echo {} | grep -E '"'$pattern'"' | head -1' 2>/dev/null | grep -v '^$')
        if [ ${#MATCHED_FILES[@]} -gt 0 ]; then
            for file in "${MATCHED_FILES[@]}"; do
                [ -n "$file" ] && git -C "$WORKSPACE" add "$file" 2>/dev/null
            done
            log_ok "Añadidos ${#MATCHED_FILES[@]} archivo(s) al staging"
        else
            git -C "$WORKSPACE" add "$pattern"
        fi
        STAGED_FILES=$(git -C "$WORKSPACE" diff --cached --name-only)
        COUNT=$(echo "$STAGED_FILES" | grep -c . || echo "0")
    else
        log "Añadiendo: $pattern"
        if git -C "$WORKSPACE" add "$pattern" 2>/dev/null; then
            COUNT=1
            log_ok "Archivo añadido al staging"
        else
            log_error "No se pudo añadir: $pattern"
            return 1
        fi
    fi
    
    STAGED_OUTPUT=$(git -C "$WORKSPACE" diff --cached --name-only)
    echo ""
    echo "{\"staged_files\": $COUNT, \"files\": [\"${STAGED_OUTPUT//$'\n'/\"\,\"}\"], \"message\": \"Added $COUNT files to staging\"}"
    return 0
}

git_commit() {
    require_git_repo || return 1
    
    local message="${1:-}"
    local allow_empty="${2:-false}"
    
    if [ "$allow_empty" != "true" ]; then
        DIFF_SUMMARY=$(git -C "$WORKSPACE" diff --cached --stat 2>/dev/null | head -5)
        if [ -z "$DIFF_SUMMARY" ]; then
            log_error "Nada que commitear. Usa 'git-manager.sh add' primero."
            return 1
        fi
    fi
    
    if [ -z "$message" ]; then
        log_info "Analizando diff para generar mensaje Conventional Commits..."
        
        CHANGED_FILES=$(git -C "$WORKSPACE" diff --cached --name-only 2>/dev/null)
        FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
        
        DIFF_CONTENT=$(git -C "$WORKSPACE" diff --cached 2>/dev/null)
        
        ADDITIONS=$(echo "$DIFF_CONTENT" | grep -c '^+' || echo "0")
        DELETIONS=$(echo "$DIFF_CONTENT" | grep -c '^-' || echo "0")
        
        TYPE="feat"
        SCOPE=""
        
        if echo "$CHANGED_FILES" | grep -qiE '(test|spec|__tests__|jest|vitest|mocha)'; then
            TYPE="test"
        elif echo "$CHANGED_FILES" | grep -qiE '(docs?|readme|changelog|license)'; then
            TYPE="docs"
        elif echo "$CHANGED_FILES" | grep -qiE '(docker|nginx|ci|cd|gitlab|github|jenkins|config)'; then
            TYPE="chore"
        elif echo "$DIFF_CONTENT" | grep -qiE '(fix|bug|hotfix|patch)'; then
            TYPE="fix"
        elif echo "$CHANGED_FILES" | grep -qiE '(style|css|scss|tailwind|theme)'; then
            TYPE="style"
        elif echo "$CHANGED_FILES" | grep -qiE '(refactor|restructure)'; then
            TYPE="refactor"
        elif echo "$CHANGED_FILES" | grep -qiE '(perf|optimize|benchmark)'; then
            TYPE="perf"
        elif echo "$CHANGED_FILES" | grep -qiE '(security|auth|oauth|jwt|crypto)'; then
            TYPE="security"
        elif echo "$CHANGED_FILES" | grep -qiE '(api|endpoint|route|controller)'; then
            TYPE="feat"
            SCOPE="api"
        elif echo "$CHANGED_FILES" | grep -qiE '(db|migration|model|schema|sql)'; then
            TYPE="db"
        fi
        
        FIRST_FILE=$(echo "$CHANGED_FILES" | head -1 | xargs basename 2>/dev/null)
        if [ -n "$SCOPE" ]; then
            DESCRIPTION=$(echo "$FIRST_FILE" | sed 's/\.[^.]*$//' | sed 's/[-_]/ /g' | sed 's/\b\(.\)/\U\1/g')
        else
            DESCRIPTION=$(echo "$FIRST_FILE" | sed 's/\.[^.]*$//' | sed 's/[-_]/ /g' | sed 's/\b\(.\)/\U\1/g')
        fi
        
        if [ -n "$SCOPE" ]; then
            message="$TYPE($SCOPE): $DESCRIPTION"
        else
            message="$TYPE: $DESCRIPTION"
        fi
        
        if [ "$FILE_COUNT" -gt 1 ]; then
            message="$message (+$((FILE_COUNT - 1)) more)"
        fi
        
        log_info "Mensaje: Conventional Commits: $message"
        log_info "Archivos: $FILE_COUNT (+$ADDITIONS, -$DELETIONS)"
    fi
    
    log "Creando commit..."
    COMMIT_OUTPUT=$(git -C "$WORKSPACE" commit -m "$message" 2>&1)
    HASH=$(echo "$COMMIT_OUTPUT" | grep -oE '[a-f0-9]{7,}' | head -1 || echo "")
    
    if [ -n "$HASH" ]; then
        AUTHOR=$(git -C "$WORKSPACE" log -1 --format='%an' "$HASH" 2>/dev/null || echo "Unknown")
        TIMESTAMP=$(git -C "$WORKSPACE" log -1 --format='%ci' "$HASH" 2>/dev/null | cut -d' ' -f1 || echo "")
        log_ok "Commit creado: $HASH"
        echo ""
        echo "{\"hash\": \"$HASH\", \"message\": \"$message\", \"filesChanged\": $FILE_COUNT, \"author\": \"$AUTHOR\", \"timestamp\": \"$TIMESTAMP\"}"
    else
        if echo "$COMMIT_OUTPUT" | grep -qi "nothing to commit"; then
            log_warn "Nada que commitear"
        else
            log_error "Error al crear commit: $COMMIT_OUTPUT"
        fi
        return 1
    fi
    return 0
}

git_push() {
    require_git_repo || return 1
    
    validate_github_token || return 1
    
    if ! git -C "$WORKSPACE" remote get-url "$DEFAULT_REMOTE" &>/dev/null; then
        log_error "No existe remote '$DEFAULT_REMOTE'"
        return 1
    fi
    
    REMOTE_URL=$(git -C "$WORKSPACE" remote get-url "$DEFAULT_REMOTE")
    
    # SECURITY: Reject SSH remotes - only HTTPS allowed
    if [[ "$REMOTE_URL" == git@* ]]; then
        log_error "SSH remote detectado: $REMOTE_URL"
        log_error "Solo se permiten remotes HTTPS para usar GITHUB_TOKEN"
        log_info "Cambiar a HTTPS:"
        log_info "  git remote set-url $DEFAULT_REMOTE https://github.com/owner/repo.git"
        return 1
    fi
    
    # Use only environment variables - NO temp files with token
    export GH_TOKEN="$GITHUB_TOKEN"
    export GITHUB_TOKEN="$GITHUB_TOKEN"
    
    PUSH_ARGS=""
    [ "$FORCE_PUSH" == true ] && PUSH_ARGS="--force"
    
    CURRENT_BRANCH=$(git -C "$WORKSPACE" branch --show-current)
    log "Push a $DEFAULT_REMOTE/$CURRENT_BRANCH..."
    
    PUSH_OUTPUT=$(git -C "$WORKSPACE" push $PUSH_ARGS -u "$DEFAULT_REMOTE" "$CURRENT_BRANCH" 2>&1)
    PUSH_EXIT=$?
    
    if [ $PUSH_EXIT -eq 0 ]; then
        COMMITS_PUSHED=$(git -C "$WORKSPACE" log --oneline "$DEFAULT_REMOTE/$CURRENT_BRANCH..HEAD" 2>/dev/null | wc -l | tr -d ' ')
        [ -z "$COMMITS_PUSHED" ] && COMMITS_PUSHED=0
        log_ok "Push exitoso a $DEFAULT_REMOTE/$CURRENT_BRANCH ($COMMITS_PUSHED commits)"
        echo ""
        echo "{\"pushed\": true, \"remote\": \"$DEFAULT_REMOTE\", \"branch\": \"$CURRENT_BRANCH\", \"commits_pushed\": $COMMITS_PUSHED, \"url\": \"$(echo "$PUSH_OUTPUT" | grep -oE 'https://github.com/[^ ]+' | head -1 || echo '')\"}"
    else
        if echo "$PUSH_OUTPUT" | grep -qi "rejected"; then
            log_error "Push rechazado - posibles cambios remotos"
            log_info "Solución: git pull --rebase o merge manual"
        elif echo "$PUSH_OUTPUT" | grep -qi "permission denied"; then
            log_error "Permiso denegado - verificar GITHUB_TOKEN"
        else
            log_error "Error en push: $PUSH_OUTPUT"
        fi
        return 1
    fi
    return 0
}

git_branch() {
    require_git_repo || return 1
    
    local branch_name="${1:-}"
    local action="${2:-}"
    
    if [ -z "$branch_name" ]; then
        log_info "Ramas locales:"
        git -C "$WORKSPACE" branch
        echo ""
        log_info "Ramas remotas:"
        git -C "$WORKSPACE" branch -r
        return 0
    fi
    
    case "$action" in
        delete|d|destroy)
            log "Eliminando rama local: $branch_name"
            git -C "$WORKSPACE" branch -d "$branch_name" 2>/dev/null || {
                git -C "$WORKSPACE" branch -D "$branch_name"
            }
            log_ok "Rama eliminada: $branch_name"
            echo ""
            echo "{\"deleted\": true, \"branch\": \"$branch_name\"}"
            return 0
            ;;
        list|l)
            if git -C "$WORKSPACE" branch -a | grep -q "$branch_name"; then
                log_info "Ramas que contienen '$branch_name':"
                git -C "$WORKSPACE" branch -a | grep "$branch_name"
            else
                log_warn "No se encontraron ramas con: $branch_name"
            fi
            return 0
            ;;
        *)
            ;;
    esac
    
    if [[ "$branch_name" != feature/* ]] && [[ "$branch_name" != fix/* ]] && [[ "$branch_name" != release/* ]]; then
        log_warn "Se recomienda naming: feature/*, fix/*, release/*"
        branch_name="feature/$branch_name"
    fi
    
    if git -C "$WORKSPACE" rev-parse --verify --quiet "$branch_name" &>/dev/null; then
        log "Cambiando a rama existente: $branch_name"
    else
        log "Creando nueva rama: $branch_name"
    fi
    
    git -C "$WORKSPACE" checkout "$branch_name" 2>/dev/null || {
        git -C "$WORKSPACE" checkout -b "$branch_name"
    }
    
    CURRENT_BRANCH=$(git -C "$WORKSPACE" branch --show-current)
    log_ok "En rama: $CURRENT_BRANCH"
    echo ""
    echo "{\"created\": true, \"branch\": \"$branch_name\", \"current\": \"$CURRENT_BRANCH\"}"
    return 0
}

git_pr() {
    require_git_repo || return 1
    require_gh || return 1
    validate_github_token || return 1
    
    local title="${1:-}"
    local body="${2:-}"
    local base="${3:-$DEFAULT_BRANCH}"
    local reviewers="${4:-}"
    
    if [ -z "$title" ]; then
        log_error "Título requerido: git-manager.sh pr '<título>' [body]"
        return 1
    fi
    
    export GH_TOKEN="$GITHUB_TOKEN"
    
    CURRENT_BRANCH=$(git -C "$WORKSPACE" branch --show-current)
    
    if ! git -C "$WORKSPACE" rev-parse --verify --abbrev-ref HEAD@{upstream} &>/dev/null 2>&1; then
        log_warn "Rama no tiene upstream. Ejecuta: git push -u origin $CURRENT_BRANCH"
    fi
    
    local -a PR_ARGS=("--title" "$title" "--base" "$base" "--head" "$CURRENT_BRANCH")
    [ -n "$body" ] && PR_ARGS+=("--body" "$body")
    [ -n "$reviewers" ] && PR_ARGS+=("--reviewer" "$reviewers")
    
    log "Creando PR: $title"
    log_info "Base: $base <- Head: $CURRENT_BRANCH"
    
    PR_OUTPUT=$(gh pr create "${PR_ARGS[@]}" 2>&1) || {
        log_error "Error al crear PR: $PR_OUTPUT"
        return 1
    }
    
    PR_URL=$(echo "$PR_OUTPUT" | grep -oE 'https://github.com/[^ )]+' | head -1)
    PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$' | head -1)
    
    log_ok "PR #$PR_NUMBER creado: $PR_URL"
    echo ""
    echo "{\"pr_number\": $PR_NUMBER, \"pr_url\": \"$PR_URL\", \"title\": \"$title\", \"base\": \"$base\", \"head\": \"$CURRENT_BRANCH\", \"created\": true}"
    return 0
}

git_merge() {
    require_git_repo || return 1
    
    local source="${1:-}"
    local target="${2:-}"
    local strategy="${3:-}"
    
    if [ -z "$source" ] || [ -z "$target" ]; then
        log_error "Uso: git-manager.sh merge <source> <target> [strategy]"
        return 1
    fi
    
    ORIGINAL_BRANCH=$(git -C "$WORKSPACE" branch --show-current)
    
    if ! git -C "$WORKSPACE" rev-parse --verify "$source" &>/dev/null; then
        log_error "Rama source no existe: $source"
        return 1
    fi
    
    if ! git -C "$WORKSPACE" rev-parse --verify "$target" &>/dev/null; then
        log_error "Rama target no existe: $target"
        return 1
    fi
    
    log "Fusionando $source → $target"
    log_info "Estrategia: ${strategy:-merge (default)}"
    
    git -C "$WORKSPACE" checkout "$target"
    
    MERGE_MSG="Merge branch '$source' into $target"
    case "$strategy" in
        ff|fast-forward)
            MERGE_CMD="git -C '$WORKSPACE' merge '$source' --ff-only"
            MERGE_MSG="Fast-forward merge $source into $target"
            ;;
        squash|sq)
            MERGE_CMD="git -C '$WORKSPACE' merge '$source' --squash"
            MERGE_MSG="Squash merge $source into $target"
            ;;
        no-ff)
            MERGE_CMD="git -C '$WORKSPACE' merge '$source' --no-ff -m '$MERGE_MSG'"
            ;;
        *)
            MERGE_CMD="git -C '$WORKSPACE' merge '$source' -m '$MERGE_MSG'"
            ;;
    esac
    
    eval "$MERGE_CMD" 2>&1 || {
        log_error "Conflicto en merge"
        log_info "Para abortar: git merge --abort"
        git -C "$WORKSPACE" checkout "$ORIGINAL_BRANCH"
        return 1
    }
    
    MERGED_HASH=$(git -C "$WORKSPACE" rev-parse --short HEAD)
    
    log_ok "Merge completado: $MERGED_HASH"
    log "Restaurando rama original: $ORIGINAL_BRANCH"
    git -C "$WORKSPACE" checkout "$ORIGINAL_BRANCH"
    
    echo ""
    echo "{\"merged\": true, \"source\": \"$source\", \"target\": \"$target\", \"commit_hash\": \"$MERGED_HASH\", \"strategy\": \"${strategy:-merge}\"}"
    return 0
}

git_sync() {
    require_git_repo || return 1
    
    validate_github_token || return 1
    
    export GH_TOKEN="$GITHUB_TOKEN"
    
    log "Sincronizando con $DEFAULT_REMOTE..."
    
    git -C "$WORKSPACE" fetch "$DEFAULT_REMOTE" --prune 2>&1 | head -10
    
    CURRENT_BRANCH=$(git -C "$WORKSPACE" branch --show-current)
    
    UPSTREAM="${DEFAULT_REMOTE}/${CURRENT_BRANCH}"
    
    if git -C "$WORKSPACE" rev-parse --verify "$UPSTREAM" &>/dev/null 2>&1; then
        BEHIND=$(git -C "$WORKSPACE" rev-list --count "HEAD..$UPSTREAM" 2>/dev/null || echo "0")
        AHEAD=$(git -C "$WORKSPACE" rev-list --count "$UPSTREAM..HEAD" 2>/dev/null || echo "0")
        
        log_info "Estado: ahead=$AHEAD, behind=$BEHIND"
        
        if [ "$BEHIND" -gt 0 ] && [ "$AHEAD" -gt 0 ]; then
            log_warn "Diverged: $AHEAD ahead, $BEHIND behind"
            log_info "Opciones: rebase (git pull --rebase) o merge"
            echo ""
            echo "{\"diverged\": true, \"commits_ahead\": $AHEAD, \"commits_behind\": $BEHIND, \"upstream\": \"$UPSTREAM\"}"
        elif [ "$BEHIND" -gt 0 ]; then
            log_info "Commits remotos nuevos: $BEHIND"
            log "Ejecutando rebase..."
            git -C "$WORKSPACE" rebase "$UPSTREAM" 2>&1 || {
                log_error "Rebase falló, resolviendo conflictos manualmente"
                return 1
            }
            log_ok "Rebase completado"
            echo ""
            echo "{\"updated\": true, \"rebased\": true, \"commits_behind\": $BEHIND, \"upstream\": \"$UPSTREAM\"}"
        else
            log_ok "Repositorio actualizado"
            echo ""
            echo "{\"updated\": true, \"commits_ahead\": 0, \"commits_behind\": 0, \"upstream\": \"$UPSTREAM\"}"
        fi
    else
        log_warn "No hay upstream configurado para $CURRENT_BRANCH"
        log_info "Push inicial: git push -u $DEFAULT_REMOTE $CURRENT_BRANCH"
        echo ""
        echo "{\"updated\": false, \"reason\": \"no_upstream\", \"branch\": \"$CURRENT_BRANCH\"}"
        return 1
    fi
    
    return 0
}

git_tag() {
    require_git_repo || return 1
    
    local version="${1:-}"
    local message="${2:-}"
    local annotate="${3:-true}"
    
    if [ -z "$version" ]; then
        log_info "Tags existentes:"
        echo ""
        git -C "$WORKSPACE" tag -l --sort=-v:refname | while read -r tag; do
            ANNOTATED=$(git -C "$WORKSPACE" tag -l "$tag" -n1 2>/dev/null | head -1)
            DATE=$(git -C "$WORKSPACE" log -1 --format="%ci" "$tag" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
            echo -e "  ${CYAN}$tag${NC} - $ANNOTATED ($DATE)"
        done
        echo ""
        return 0
    fi
    
    SEMVER_REGEX='^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$'
    if [[ "$version" =~ $SEMVER_REGEX ]]; then
        if [[ "$version" != v* ]]; then
            version="v$version"
        fi
    else
        log_warn "Versión no es semver válido: $version"
        log_info "Formato esperado: v1.0.0, 1.2.3, v2.0.0-beta"
        if [[ "$version" != v* ]]; then
            version="v$version"
        fi
    fi
    
    if git -C "$WORKSPACE" rev-parse --verify "$version" &>/dev/null 2>&1; then
        log_warn "Tag ya existe: $version"
        echo ""
        echo "{\"tag\": \"$version\", \"created\": false, \"reason\": \"already_exists\"}"
        return 1
    fi
    
    if [ -z "$message" ]; then
        message="Release $version"
    fi
    
    log "Creando tag: $version"
    log_info "Mensaje: $message"
    
    if [ "$annotate" == "true" ]; then
        TAG_OUTPUT=$(git -C "$WORKSPACE" tag -a "$version" -m "$message" 2>&1)
    else
        TAG_OUTPUT=$(git -C "$WORKSPACE" tag "$version" 2>&1)
    fi
    
    TAG_HASH=$(git -C "$WORKSPACE" rev-parse --short "$version")
    
    log_ok "Tag creado: $version ($TAG_HASH)"
    echo ""
    echo "{\"tag\": \"$version\", \"hash\": \"$TAG_HASH\", \"created\": true, \"message\": \"$message\", \"annotated\": $annotate}"
    return 0
}

git_tag_push() {
    require_git_repo || return 1
    require_gh || return 1
    validate_github_token || return 1
    
    export GH_TOKEN="$GITHUB_TOKEN"
    
    log "Push tags a $DEFAULT_REMOTE..."
    git -C "$WORKSPACE" push "$DEFAULT_REMOTE" --tags 2>&1
    
    log_ok "Tags empujados"
    return 0
}

show_help() {
    cat << 'HELP'
==========================================
 CMX-Git-Manager — Automatización Git
==========================================

USO:
  git-manager.sh <comando> [argumentos]

COMANDOS:
  init              Inicializar/revisar repo Git
  status            Mostrar estado del repositorio
  add [pattern]     Añadir archivos al staging (. por defecto)
  commit [msg]      Crear commit (auto-genera mensaje si no se provee)
  push [--force]    Subir commits al remote
  branch [name]     Crear/cambiar a rama feature/*
  branch <name> d   Eliminar rama local
  branch <name> l   Buscar ramas por nombre
  pr <title> [body] [base] [reviewers] Crear PR via gh CLI
  merge <src> <dst> [strategy] Fusionar source → target
  sync              Fetch + rebase desde remote
  tag [version] [msg] Crear tag semántico (vX.Y.Z)
  tag-push          Empujar tags al remote

ESTRATEGIAS DE MERGE:
  (ninguna)         Merge normal
  ff                Fast-forward only
  squash            Squash merge
  no-ff             No fast-forward (merge commit)

EJEMPLOS:
  ./git-manager.sh init
  ./git-manager.sh status
  ./git-manager.sh add '*.ts'
  ./git-manager.sh commit
  ./git-manager.sh push
  ./git-manager.sh branch mi-feature
  ./git-manager.sh branch fix/bug-login d
  ./git-manager.sh pr "feat: nueva funcionalidad" "Detalles del PR"
  ./git-manager.sh merge feature/test main
  ./git-manager.sh merge feature/test main squash
  ./git-manager.sh sync
  ./git-manager.sh tag v1.0.0 "Initial release"
  ./git-manager.sh tag-push

VARIABLES DE ENTORNO:
  GITHUB_TOKEN      Token de GitHub (requerido para gh CLI y push HTTPS)
  DEFAULT_REMOTE    Remote a usar (default: origin)
  DEFAULT_BRANCH    Rama base (default: main)

SEGURIDAD:
  - Solo permite remotes HTTPS
  - Token mostrado solo últimos 4 caracteres en logs

==========================================
HELP
}

case "$COMMAND" in
    init)
        git_init
        ;;
    status|stat)
        git_status
        ;;
    add)
        git_add "${2:-.}"
        ;;
    commit)
        git_commit "${2:-}"
        ;;
    push)
        [ "${2:-}" == "--force" ] || [ "${2:-}" == "-f" ] && FORCE_PUSH=true
        git_push
        ;;
    branch)
        git_branch "${2:-}" "${3:-}"
        ;;
    pr)
        git_pr "${2:-}" "${3:-}" "${4:-}" "${5:-}"
        ;;
    merge)
        git_merge "${2:-}" "${3:-}" "${4:-}"
        ;;
    sync)
        git_sync
        ;;
    tag)
        git_tag "${2:-}" "${3:-}" "${4:-}"
        ;;
    tag-push)
        git_tag_push
        ;;
    --help|-h|help)
        show_help
        ;;
    *)
        log_error "Comando desconocido: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac
