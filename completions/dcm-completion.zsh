#compdef dcm docker-compose-manager.sh

_dcm_compose_dirs() {
    local -a dirs hits
    local d
    # (N) = null glob: no error output when a directory has no compose file
    for d in *(/N); do
        hits=( "$d"/(compose*.yml|compose*.yaml|docker-compose*.yml|docker-compose*.yaml|*compose.yml|*compose.yaml)(N) )
        if (( ${#hits} > 0 )); then
            dirs+=("$d")
        fi
    done
    if (( ${#dirs} > 0 )); then
        _describe 'compose directory' dirs
    else
        _directories
    fi
}

_dcm() {
    local -a actions
    actions=(
        'up:Start containers in detached mode'
        'down:Stop and remove containers'
        'restart:Restart containers (down + up)'
        'pull:Pull the latest images for the services'
        'logs:Follow container logs'
        'status:Show container status'
        'update:Update this script to latest version'
        'completion:Generate shell autocompletion script'
    )

    _arguments -s -S \
        '(-h --help)'{-h,--help}'[Show help message and exit]' \
        '(-v --version)'{-v,--version}'[Show version and exit]' \
        '(-n --dry-run)'{-n,--dry-run}'[Show what would be done without executing]' \
        '(-y --yes)'{-y,--yes}'[Skip confirmation prompts]' \
        '(-p --priority)'{-p,--priority}'[Directories to start first]:directories:_directories' \
        '(-u --update)'{-u,--update}'[Update this script to latest version]' \
        '--install-completion[Install tab completion for bash and zsh]' \
        '1:action:->action' \
        '*:directory:->dir' && return 0

    case "$state" in
        action)
            _describe -t actions 'action' actions
            ;;
        dir)
            case "${line[1]}" in
                completion)
                    local -a shells
                    shells=('bash:Generate Bash completion' 'zsh:Generate Zsh completion' 'install:Install shell completion')
                    _describe -t shells 'shell' shells
                    ;;
                *)
                    _dcm_compose_dirs
                    ;;
            esac
            ;;
    esac
}

_dcm "$@"
