#!/bin/sh
# shellcheck shell=sh
#
# docker-compose-manager.sh - Manage Docker Compose projects across directories
# POSIX-compliant utility for up/down/restart/status/pull/logs operations
#

set -eu
# shellcheck disable=SC3040
(set -o pipefail 2>/dev/null) && set -o pipefail

export LC_ALL=C

SCRIPT_NAME=$(basename "$0")
VERSION="0.3.4"
UPDATE_URL="https://raw.githubusercontent.com/buildplan/dcm/refs/heads/main/docker-compose-manager.sh"

if [ -t 1 ]; then
    RED='\033[31m' GREEN='\033[32m' YELLOW='\033[33m' BLUE='\033[34m' MAGENTA='\033[35m' CYAN='\033[36m' BOLD='\033[1m' RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' BOLD='' RESET=''
fi

found_any=0
exit_code=0
DRY_RUN=0
FAILED_DIRS=''
SUCCESS_DIRS=''
SKIP_CONFIRM=0
EXCLUDES_INPUT=''
ACTION=''

# shellcheck disable=SC2329
cleanup() {
    exit_status=$?
    if [ "$exit_status" -eq 130 ]; then
        printf '\n%bInterrupted. Exiting.%b\n' "$YELLOW" "$RESET"
    fi
    exit "$exit_status"
}
trap cleanup INT TERM

print_help() {
    printf '%b%bUsage:%b\n' "$BOLD" "$CYAN" "$RESET"
    printf '  ./%s [OPTIONS] [ACTION] [DIR1 DIR2 ...]\n' "$SCRIPT_NAME"
    printf '  ./%s -h | --help\n' "$SCRIPT_NAME"
    printf '  ./%s -v | --version\n\n' "$SCRIPT_NAME"

    printf '%b%bDescription:%b\n' "$BOLD" "$CYAN" "$RESET"
    cat <<'EOF'
  Run 'docker compose' (up/down/restart/status/pull/logs) in one or more directories.
  Discovery is conservative and deterministic:
    1. Choose one canonical base file, first match wins:
       - compose.yaml
       - compose.yml
       - docker-compose.yaml
       - docker-compose.yml
    2. Layer explicit override files in sorted order:
       - compose.*.yaml / compose.*.yml
       - docker-compose.*.yaml / docker-compose.*.yml
  Notes:
    - Base filenames are never added twice as overrides.
    - Relative paths are resolved from the base file Docker Compose sees first.
EOF

    printf '\n%b%bOptions:%b\n' "$BOLD" "$CYAN" "$RESET"
    cat <<EOF
  -h, --help        Show this help message and exit.
  -v, --version     Show version and exit.
  -n, --dry-run     Show what would be done without executing.
  -y, --yes         Skip confirmation prompts for destructive operations.
  -u, --update      Update this script to the latest version from GitHub.
EOF

    printf '\n%b%bActions:%b\n' "$BOLD" "$CYAN" "$RESET"
    cat <<EOF
  up                Start containers in detached mode.
  down              Stop and remove containers.
  restart           Restart containers (down + up) for clean config reload.
  pull              Pull the latest images for the services.
  logs              Follow container logs.
  status            Show container status (docker compose ps).
  update            Update this script to the latest version from GitHub.
EOF

    printf '\n%b%bExamples:%b\n' "$BOLD" "$CYAN" "$RESET"
    cat <<EOF
  ./$SCRIPT_NAME up
  ./$SCRIPT_NAME down dir1 dir2
  ./$SCRIPT_NAME --dry-run restart
  ./$SCRIPT_NAME status ./my-app
EOF
}

print_version() {
    printf '%s %s\n' "$SCRIPT_NAME" "$VERSION"
}

info() {
    printf '%bInfo:%b %s\n' "$BLUE" "$RESET" "$1"
}

warn() {
    printf '%bWarning:%b %s\n' "$YELLOW" "$RESET" "$1" >&2
}

error() {
    printf '%bError:%b %s\n' "$RED" "$RESET" "$1" >&2
}

check_dependency() {
    if ! command -v docker >/dev/null 2>&1; then
        error 'docker is not installed or not in PATH.'
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        error 'Docker daemon is not running.'
        exit 1
    fi
    if ! docker compose version >/dev/null 2>&1; then
        error 'docker compose not available. Install Docker Compose v2 (plugin).'
        exit 1
    fi
}

resolve_script_path() {
    case $0 in
        */*) printf '%s\n' "$0" ;;
        *) command -v "$0" 2>/dev/null || printf '%s\n' "$0" ;;
    esac
}

create_private_dir() {
    parent=$1

    if command -v mktemp >/dev/null 2>&1; then
        mktemp -d "$parent/.dcm-update.XXXXXX"
        return
    fi

    old_umask=$(umask)
    umask 077
    i=0
    while [ "$i" -lt 10 ]; do
        i=$((i + 1))
        candidate=$parent/.dcm-update.$$.$i
        if mkdir "$candidate" 2>/dev/null; then
            umask "$old_umask"
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    umask "$old_umask"
    return 1
}

update_script() {
    info 'Checking for updates...'

    script_path=$(resolve_script_path)
    script_dir=$(dirname "$script_path")

    if [ ! -w "$script_dir" ]; then
        error "No write permission to directory $script_dir."
        printf 'Try running with sudo: %b%s%b\n' "$YELLOW" "sudo $SCRIPT_NAME update" "$RESET" >&2
        exit 1
    fi

    temp_dir=$(create_private_dir "$script_dir") || {
        error 'Failed to create a private temporary directory for update.'
        exit 1
    }
    tmp_file=$temp_dir/$SCRIPT_NAME.new

    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$UPDATE_URL" -o "$tmp_file"; then
            rm -rf "$temp_dir"
            error 'Failed to download update via curl.'
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -qO "$tmp_file" "$UPDATE_URL"; then
            rm -rf "$temp_dir"
            error 'Failed to download update via wget.'
            exit 1
        fi
    else
        rm -rf "$temp_dir"
        error 'curl or wget is required to update.'
        exit 1
    fi

    if ! head -n 1 "$tmp_file" | grep -q '^#!/bin/sh'; then
        rm -rf "$temp_dir"
        error 'Downloaded file is invalid. Update aborted.'
        exit 1
    fi

    chmod +x "$tmp_file"
    if ! mv "$tmp_file" "$script_path"; then
        rm -rf "$temp_dir"
        error 'Failed to replace the current script.'
        exit 1
    fi
    rm -rf "$temp_dir"

    printf '%bSuccess:%b Script updated successfully!\n' "$GREEN" "$RESET"
    exit 0
}

is_excluded() {
    case " $EXCLUDES_INPUT " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

load_config() {
    config_file=$1/.docker-compose-manager.conf
    if [ -f "$config_file" ]; then
        info 'Loading exclusions from config file.'
        while IFS= read -r line || [ -n "$line" ]; do
            case $line in
                \#*|'') continue ;;
                *) EXCLUDES_INPUT=${EXCLUDES_INPUT}${EXCLUDES_INPUT:+ }$line ;;
            esac
        done < "$config_file"
    fi
}

find_base_file() {
    dir=$1
    matches=0
    selected=''

    for name in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
        if [ -f "$dir/$name" ]; then
            matches=$((matches + 1))
            if [ -z "$selected" ]; then
                selected=$dir/$name
            fi
        fi
    done

    if [ "$matches" -gt 1 ]; then
        warn "Multiple base compose files found in $(basename "$dir"); using $(basename "$selected")."
    fi

    if [ -n "$selected" ]; then
        printf '%s\n' "$selected"
        return 0
    fi
    return 1
}

build_compose_args() {
    dir=$1
    base_file=$(find_base_file "$dir") || return 1
    override_list=''

    for pattern in 'compose.*.yml' 'compose.*.yaml' 'docker-compose.*.yml' 'docker-compose.*.yaml'; do
        for f in "$dir"/$pattern; do
            [ -f "$f" ] || continue
            case $(basename "$f") in
                compose.yml|compose.yaml|docker-compose.yml|docker-compose.yaml)
                    continue
                    ;;
            esac
            override_list=${override_list}${f}'
'
        done
    done

    set -- -f "$base_file"
    if [ -n "$override_list" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            set -- "$@" -f "$f"
        done <<EOF
$(printf '%s' "$override_list" | sort)
EOF
    fi

    COMPOSE_ARGS=$*
    COMPOSE_BASE=$base_file
    return 0
}

print_used_files() {
    first=1
    for arg in "$@"; do
        if [ "$arg" = '-f' ]; then
            continue
        fi
        if [ "$first" -eq 1 ]; then
            printf '%b%bUsing files:%b ' "$BOLD" "$CYAN" "$RESET"
            first=0
        fi
        printf '%s ' "$(basename "$arg")"
    done
    if [ "$first" -eq 0 ]; then
        printf '\n'
    fi
}

run_compose_in_dir() {
    dir=${1%/}
    folder_name=$(basename "$dir")
    cmd_success=0

    if [ ! -d "$dir" ]; then
        printf '%b------------------------------------------------%b\n' "$MAGENTA" "$RESET"
        error "directory $folder_name does not exist... skipping."
        return 1
    fi

    if ! build_compose_args "$dir"; then
        return 0
    fi

    found_any=1

    set --
    for token in $COMPOSE_ARGS; do
        set -- "$@" "$token"
    done

    printf '%b------------------------------------------------%b\n' "$MAGENTA" "$RESET"
    printf '%b%bRunning:%b docker compose %b%s%b for %b%s%b\n' \
        "$BOLD" "$BLUE" "$RESET" \
        "$GREEN" "$ACTION" "$RESET" \
        "$CYAN" "$folder_name" "$RESET"

    if [ "$DRY_RUN" -eq 0 ]; then
        print_used_files "$@"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '%b[dry-run]%b docker compose' "$YELLOW" "$RESET"
        for arg in "$@"; do
            printf ' %s' "$arg"
        done
        case $ACTION in
            up)      printf ' up -d --remove-orphans\n' ;;
            down)    printf ' down --remove-orphans\n' ;;
            restart) printf ' down --remove-orphans && docker compose ... up -d --remove-orphans\n' ;;
            pull)    printf ' pull\n' ;;
            logs)    printf ' logs -f\n' ;;
            status)  printf ' ps\n' ;;
        esac
        return 0
    fi

    set -- --project-directory "$dir" "$@"

    case $ACTION in
        up)
            if docker compose "$@" up -d --remove-orphans; then cmd_success=1; fi ;;
        down)
            if docker compose "$@" down --remove-orphans; then cmd_success=1; fi ;;
        restart)
            if docker compose "$@" down --remove-orphans && \
               docker compose "$@" up -d --remove-orphans; then
                cmd_success=1
            fi
            ;;
        pull)
            if docker compose "$@" pull; then cmd_success=1; fi ;;
        logs)
            docker compose "$@" logs -f
            rc=$?
            if [ "$rc" -eq 0 ] || [ "$rc" -eq 130 ]; then cmd_success=1; fi ;;
        status)
            if docker compose "$@" ps; then
                cmd_success=1
            fi
            ;;
    esac

    if [ "$cmd_success" -eq 1 ]; then
        SUCCESS_DIRS=${SUCCESS_DIRS}${SUCCESS_DIRS:+ }$folder_name
    else
        error "Failed to execute $ACTION for $folder_name"
        FAILED_DIRS=${FAILED_DIRS}${FAILED_DIRS:+ }$folder_name
        exit_code=1
    fi
}

confirm_action() {
    target_desc=$1

    if [ "$SKIP_CONFIRM" -eq 1 ] || [ ! -t 0 ]; then
        return 0
    fi

    case $ACTION in
        down|restart)
            printf '%b%bWarning:%b This will run %b%s%b on %s.\n' \
                "$BOLD" "$YELLOW" "$RESET" "$CYAN" "$ACTION" "$RESET" "$target_desc"
            printf 'Continue? (y/N): '
            IFS= read -r confirm || return 1
            case $confirm in
                y|Y|yes|YES) return 0 ;;
                *)
                    printf 'Operation cancelled.\n'
                    exit 0
                    ;;
            esac
            ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case $1 in
        -h|--help)    print_help; exit 0 ;;
        -v|--version) print_version; exit 0 ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -y|--yes)     SKIP_CONFIRM=1; shift ;;
        -u|--update)  update_script ;;
        -*)
            error "unknown option $1"
            print_help
            exit 1
            ;;
        *)
            if [ -z "$ACTION" ]; then
                ACTION=$1
                shift
            else
                break
            fi
            ;;
    esac
done

if [ -z "$ACTION" ]; then
    if [ -t 0 ]; then
        printf 'Select action (up/down/restart/pull/logs/status/update): '
        IFS= read -r ACTION || exit 1
        [ -n "$ACTION" ] || { print_help; exit 1; }
    else
        print_help
        exit 1
    fi
fi

case $ACTION in
    up|down|restart|status|pull|logs)
        ;;
    update)
        update_script
        ;;
    *)
        error "invalid action $ACTION"
        print_help
        exit 1
        ;;
esac

if [ "$DRY_RUN" -eq 0 ]; then check_dependency; fi

if [ "$#" -gt 0 ]; then
    confirm_action 'the specified Docker Compose project directories'
    for name in "$@"; do
        run_compose_in_dir "$name" || true
    done
else
    if [ -t 1 ]; then
        printf '%b%bInteractive mode%b\n' "$BOLD" "$CYAN" "$RESET"
        printf 'Base directory to scan [%s]: ' "$(pwd)"
    fi

    IFS= read -r BASE_DIR || BASE_DIR=''
    if [ -z "$BASE_DIR" ]; then
        BASE_DIR=$(pwd)
    fi

    if [ ! -d "$BASE_DIR" ]; then
        error "$BASE_DIR is not a directory."
        exit 1
    fi

    load_config "$BASE_DIR"

    if [ -t 0 ]; then
        if [ -n "$EXCLUDES_INPUT" ]; then
            printf 'Current exclusions from config: %b%s%b\n' "$CYAN" "$EXCLUDES_INPUT" "$RESET"
            printf 'Additional folders to exclude (space-separated, or press Enter): '
        else
            printf 'Folders to exclude (space-separated names, or press Enter): '
        fi
        IFS= read -r extra_excludes || true
        if [ -n "$extra_excludes" ]; then
            EXCLUDES_INPUT=${EXCLUDES_INPUT}${EXCLUDES_INPUT:+ }$extra_excludes
        fi
    fi

    confirm_action "all discovered Docker Compose projects under $BASE_DIR"

    for dir in "$BASE_DIR"/*/; do
        [ -d "$dir" ] || continue
        dir=${dir%/}
        folder_name=$(basename "$dir")
        if is_excluded "$folder_name"; then
            printf '%b------------------------------------------------%b\n' "$MAGENTA" "$RESET"
            printf '%bSkipping excluded folder:%b %b%s%b\n' \
                "$YELLOW" "$RESET" "$CYAN" "$folder_name" "$RESET"
            continue
        fi
        run_compose_in_dir "$dir" || true
    done
fi

if [ "$found_any" -eq 0 ]; then
    printf '\n%bNo subdirectories with a canonical base compose file found.%b\n' "$YELLOW" "$RESET"
else
    if [ "$ACTION" != 'logs' ]; then
        printf '\n%b%b=== Summary ===%b\n' "$BOLD" "$MAGENTA" "$RESET"
        if [ -n "$SUCCESS_DIRS" ]; then
            printf '%b  [OK] Success:%b %s\n' "$GREEN" "$RESET" "$SUCCESS_DIRS"
        fi
        if [ -n "$FAILED_DIRS" ]; then
            printf '%b  [!!] Failed:%b  %s\n' "$RED" "$RESET" "$FAILED_DIRS"
        fi
        printf '\n'
    fi
fi

exit "$exit_code"
