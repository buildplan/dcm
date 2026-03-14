
# Docker Compose Manager (dcm)

A POSIX-compliant shell script to manage Docker Compose projects across multiple directories with a single command.

## Features

- **Batch Operations**: Run `up`, `down`, `restart`, or `status` on multiple compose projects simultaneously
- **Multi-File Support**: Automatically detects and merges standard compose files (`compose.yml`, `docker-compose.yml`) and pattern-based files (`compose-*.yml`)
- **Interactive \& Non-Interactive Modes**: Prompt for directories or pass them as arguments
- **Exclusion Filtering**: Skip specific directories during batch operations
- **Dry-Run Mode**: Preview commands before execution
- **Summary Reports**: See which directories succeeded or failed after execution
- **TTY-Aware Colors**: Colored output when run interactively, clean output for scripts/cron
- **POSIX Compliant**: Works with `dash`, `bash --posix`, and other POSIX shells

---

## Requirements

- Docker Engine with Compose v2 plugin installed
- POSIX-compatible shell (`sh`, `dash`, `bash`, `zsh`, etc.)

---

## Installation

### Quick Install

Download directly to your system and make it executable:

```bash
sudo curl -sSL https://raw.githubusercontent.com/buildplan/dcm/refs/heads/main/docker-compose-manager.sh -o /usr/local/bin/dcm && sudo chmod +x /usr/local/bin/dcm
```

### Manual Install

1. Download the script:

```bash
curl -sSL https://raw.githubusercontent.com/buildplan/dcm/refs/heads/main/docker-compose-manager.sh -o dcm
```

2. Make it executable:

```bash
chmod +x dcm
```

3. Move to a directory in your PATH:

```bash
sudo mv dcm /usr/local/bin/
```


### Verify Installation

```bash
dcm --help
```

---

## Usage

### Basic Syntax

```bash
dcm [OPTIONS] [ACTION] [DIR1 DIR2 ...]
```


### Actions

- `up` - Start containers in detached mode
- `down` - Stop and remove containers
- `restart` - Restart containers (down + up)
- `status` - Show container status


### Options

- `-h, --help` - Show help message and exit
- `-v, --version` - Show version and exit
- `-n, --dry-run` - Show what would be done without executing


### Interactive Mode

Run without directory arguments to enter interactive mode:

```bash
dcm up
```

You'll be prompted for:

1. Action to perform
2. Base directory to scan (default: current directory)
3. Space-separated list of folders to exclude

### Non-Interactive Mode

Pass directories as arguments:

```bash
dcm down /home/user/projects/app1 /home/user/projects/app2
```


### Examples

```bash
# Start all compose projects in current directory
dcm up

# Stop specific projects
dcm down ./web-app ./api-server

# Restart projects with dry-run preview
dcm --dry-run restart

# Check status of all projects in a directory, excluding some
dcm status /home/user/docker --exclude dir1 dir2

# Use with cron (no colors, clean output)
0 3 * * * /usr/local/bin/dcm down /home/user/backup-projects
```

---

## File Detection Priority

For each directory, the script detects and merges compose files in this order:

1. `compose.yml`
2. `compose.yaml`
3. `docker-compose.yml`
4. `docker-compose.yaml`
5. `compose-*.yml` (pattern-based)
6. `compose-*.yaml` (pattern-based)
7. `docker-compose-*.yml` (pattern-based)
8. `docker-compose-*.yaml` (pattern-based)

All detected files are passed to `docker compose` with multiple `-f` flags.

---

## Exit Codes

- `0` - All operations succeeded
- `1` - One or more operations failed (see summary output)

---

## License

MIT License - see [LICENSE file](https://github.com/buildplan/dcm/raw/refs/heads/main/LICENSE) for details

---

## Contributing

Contributions are welcome! Please ensure:

- Code remains POSIX-compliant (`shellcheck -s dash script.sh`)
- All printf format strings use `%b` for color variables and `%s` for text
- Tested in both interactive and non-interactive modes
