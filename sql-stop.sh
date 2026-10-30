#!/usr/bin/env bash
# Stop or delete SQL Server instances.
# Pass --docker to also stop the Docker daemon afterwards.
set -euo pipefail

PREFIX="mssql-"
LABEL="mssql.managed=true"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS_FILE="$SCRIPT_DIR/passwords.txt"

if ! systemctl is-active --quiet docker; then
  echo "Docker isn't running, so no SQL Server instances are either."
  read -rp "Start Docker anyway to delete an instance? [y/N]: " ans
  [[ "$ans" =~ ^[yY]$ ]] || exit 0
  sudo systemctl start docker
fi

DOCKER="docker"
docker info >/dev/null 2>&1 || DOCKER="sudo docker"

remove_password() {
  [ -f "$PASS_FILE" ] || return 0
  local rest
  rest=$(grep -v "^$1 " "$PASS_FILE" || true)
  printf '%s' "${rest:+$rest$'\n'}" > "$PASS_FILE"
}

stop_instance() {
  local c=$1
  if [ "$($DOCKER inspect -f '{{.State.Running}}' "$c")" = "true" ]; then
    echo "Stopping '${c#$PREFIX}'..."
    $DOCKER stop -t 30 "$c" >/dev/null
    echo "Stopped."
  else
    echo "'${c#$PREFIX}' is already stopped."
  fi
}

delete_instance() {
  local c=$1 name=${1#$PREFIX} confirm
  echo "This permanently deletes '$name' and ALL of its databases."
  read -rp "Type the name to confirm: " confirm
  if [ "$confirm" != "$name" ]; then
    echo "Cancelled."
    return 0
  fi
  $DOCKER rm -f "$c" >/dev/null
  $DOCKER volume rm "$c-data" >/dev/null 2>&1 || true
  remove_password "$name"
  echo "Deleted '$name'."
}

mapfile -t INSTANCES < <($DOCKER ps -a --filter "label=$LABEL" --format '{{.Names}}' | sort)

if [ ${#INSTANCES[@]} -eq 0 ]; then
  echo "No SQL Server instances exist."
else
  echo "SQL Server instances:"
  for i in "${!INSTANCES[@]}"; do
    c=${INSTANCES[$i]}
    port=$($DOCKER inspect -f '{{index .Config.Labels "mssql.port"}}' "$c")
    state=$($DOCKER inspect -f '{{.State.Status}}' "$c")
    printf "  %d) %-20s port %-6s %s\n" $((i + 1)) "${c#$PREFIX}" "$port" "$state"
  done
  echo "  a) Stop all running"
  echo "  q) Quit"
  read -rp "Choose: " choice

  case "$choice" in
    a|A)
      for c in "${INSTANCES[@]}"; do
        [ "$($DOCKER inspect -f '{{.State.Running}}' "$c")" = "true" ] && stop_instance "$c"
      done
      echo "All stopped."
      ;;
    q|Q|"") ;;
    *)
      if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#INSTANCES[@]} ]; then
        c=${INSTANCES[$((choice - 1))]}
        echo "  1) Stop"
        echo "  2) Delete"
        read -rp "What to do with '${c#$PREFIX}'? " action
        case "$action" in
          1) stop_instance "$c" ;;
          2) delete_instance "$c" ;;
          *) echo "Cancelled." ;;
        esac
      else
        echo "Invalid choice."
        exit 1
      fi
      ;;
  esac
fi

if [ "${1:-}" = "--docker" ]; then
  echo "Stopping Docker daemon..."
  sudo systemctl stop docker docker.socket
  echo "Docker stopped."
fi
