# Bash completion for dcm / docker-compose-manager.sh
_dcm_completions() {
    local cur prev words cword
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion || return
    else
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    fi

    local actions="up down restart status pull logs update completion"
    local options="-h --help -v --version -n --dry-run -y --yes -p --priority -u --update --install-completion"

    # Complete after -p or --priority
    if [ "$prev" = "-p" ] || [ "$prev" = "--priority" ]; then
        COMPREPLY=( $(compgen -d -- "$cur") )
        return 0
    fi

    # Sub-arguments for completion action
    local is_completion=0
    local i
    for ((i=1; i<cword; i++)); do
        if [ "${words[i]}" = "completion" ]; then
            is_completion=1
            break
        fi
    done
    if [ "$is_completion" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "bash zsh install" -- "$cur") )
        return 0
    fi

    # Check if an action is already in arguments
    local action=""
    for ((i=1; i<cword; i++)); do
        case "${words[i]}" in
            up|down|restart|status|pull|logs|update)
                action="${words[i]}"
                break
                ;;
        esac
    done

    # If completing a flag
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$options" -- "$cur") )
        return 0
    fi

    # If no action chosen yet, offer actions and options
    if [ -z "$action" ]; then
        COMPREPLY=( $(compgen -W "$actions $options" -- "$cur") )
        return 0
    fi

    # If action is specified, complete project directories containing compose files
    local comp_dirs=""
    local dir
    local base_path="."
    if [[ "$cur" == */* ]]; then
        base_path="${cur%/*}"
    fi

    for dir in "$base_path"/*/; do
        [ -d "$dir" ] || continue
        local clean_dir="${dir%/}"
        clean_dir="${clean_dir#./}"
        for pattern in "$dir"compose*.yml "$dir"compose*.yaml "$dir"docker-compose*.yml "$dir"docker-compose*.yaml "$dir"*compose.yml "$dir"*compose.yaml; do
            if [ -f "$pattern" ]; then
                comp_dirs="$comp_dirs $clean_dir"
                break
            fi
        done
    done

    if [ -n "$comp_dirs" ]; then
        COMPREPLY=( $(compgen -W "$comp_dirs" -- "$cur") )
    else
        COMPREPLY=( $(compgen -d -- "$cur") )
    fi
}
complete -F _dcm_completions dcm docker-compose-manager.sh
