#!/usr/bin/env bash
# Pick a SQL Server 2025 Express instance to start, or create a new one.
set -euo pipefail

IMAGE="mcr.microsoft.com/mssql/server:2025-latest"
PREFIX="mssql-"
LABEL="mssql.managed=true"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS_FILE="$SCRIPT_DIR/passwords.txt"

# Start the Docker daemon if needed; fall back to sudo if you're not in the docker group
DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
  if ! systemctl is-active --quiet docker; then
    echo "Starting Docker daemon..."
    sudo systemctl start docker
  fi
  docker info >/dev/null 2>&1 || DOCKER="sudo docker"
fi

port_of()  { $DOCKER inspect -f '{{index .Config.Labels "mssql.port"}}' "$1"; }
state_of() { $DOCKER inspect -f '{{.State.Status}}' "$1"; }

port_taken() {
  local p=$1
  [ -n "$($DOCKER ps -a -q --filter "label=$LABEL" --filter "label=mssql.port=$p")" ] && return 0
  ss -Htln "sport = :$p" 2>/dev/null | grep -q . && return 0
  return 1
}

save_password() {
  local name=$1 port=$2 pw=$3 rest
  touch "$PASS_FILE"
  chmod 600 "$PASS_FILE"
  rest=$(grep -v "^$name " "$PASS_FILE" || true)
  {
    [ -n "$rest" ] && printf '%s\n' "$rest"
    printf '%s %s %s\n' "$name" "$port" "$pw"
  } > "$PASS_FILE"
  echo "Password saved to passwords.txt"
}

password_of() {
  grep "^$1 " "$PASS_FILE" 2>/dev/null | cut -d' ' -f3- || true
}

wait_until_ready() {
  local c=$1 port=$2 pw
  echo -n "Waiting for SQL Server to be ready"
  for _ in $(seq 1 90); do
    if [ "$($DOCKER inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
      echo
      echo "Container stopped unexpectedly. Last log lines:"
      $DOCKER logs --tail 20 "$c"
      return 1
    fi
    if $DOCKER logs "$c" 2>&1 | grep -q "SQL Server is now ready for client connections"; then
      echo
      echo "'${c#$PREFIX}' is up on localhost,$port (login: sa)"
      pw=$(password_of "${c#$PREFIX}")
      [ -n "$pw" ] && echo "Password: $pw"
      echo "Connect: sqlcmd -S localhost,$port -U sa -C"
      return 0
    fi
    echo -n "."
    sleep 1
  done
  echo
  echo "Still not ready after 90s. Check: $DOCKER logs $c"
  return 1
}

start_instance() {
  local c=$1 port pw
  port=$(port_of "$c")
  if [ "$(state_of "$c")" = "running" ]; then
    echo "'${c#$PREFIX}' is already running on localhost,$port"
    pw=$(password_of "${c#$PREFIX}")
    [ -n "$pw" ] && echo "Password: $pw"
    return 0
  fi
  echo "Starting '${c#$PREFIX}'..."
  $DOCKER start "$c" >/dev/null
  wait_until_ready "$c" "$port"
}

create_instance() {
  local name c port input pw1 pw2 classes
  while true; do
    read -rp "Name for the new instance (letters, digits, - or _): " name
    if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
      echo "Invalid name."
    elif $DOCKER container inspect "$PREFIX$name" >/dev/null 2>&1; then
      echo "'$name' already exists."
    else
      break
    fi
  done
  c="$PREFIX$name"

  port=1433
  while port_taken "$port"; do port=$((port + 1)); done
  read -rp "Port [$port]: " input
  if [ -n "$input" ]; then
    if [[ ! "$input" =~ ^[0-9]+$ ]] || port_taken "$input"; then
      echo "Port $input is invalid or in use, using $port."
    else
      port=$input
    fi
  fi

  echo "Choose an SA password: 8+ chars, using 3 of: uppercase, lowercase, digits, symbols."
  while true; do
    read -rsp "SA password: " pw1; echo
    classes=0
    [[ "$pw1" =~ [A-Z] ]] && classes=$((classes + 1))
    [[ "$pw1" =~ [a-z] ]] && classes=$((classes + 1))
    [[ "$pw1" =~ [0-9] ]] && classes=$((classes + 1))
    [[ "$pw1" =~ [^A-Za-z0-9] ]] && classes=$((classes + 1))
    if [ ${#pw1} -lt 8 ] || [ $classes -lt 3 ]; then
      echo "Too weak for SQL Server, try again."
      continue
    fi
    read -rsp "Confirm:     " pw2; echo
    [ "$pw1" = "$pw2" ] && break
    echo "Passwords didn't match, try again."
  done

  $DOCKER run -d \
    --name "$c" \
    --restart no \
    -l "$LABEL" \
    -l "mssql.port=$port" \
    -e "ACCEPT_EULA=Y" \
    -e "MSSQL_PID=Express" \
    -e "MSSQL_SA_PASSWORD=$pw1" \
    -p "$port:1433" \
    -v "$c-data:/var/opt/mssql" \
    "$IMAGE" >/dev/null

  # Save first so wait_until_ready can show it; removed again if setup fails
  save_password "$name" "$port" "$pw1"
  unset pw1 pw2

  if ! wait_until_ready "$c" "$port"; then
    echo "Removing the failed instance so you can try again."
    $DOCKER rm -f "$c" >/dev/null
    $DOCKER volume rm "$c-data" >/dev/null 2>&1 || true
    local rest
    rest=$(grep -v "^$name " "$PASS_FILE" || true)
    printf '%s' "${rest:+$rest$'\n'}" > "$PASS_FILE"
    return 1
  fi
}

# Menu
mapfile -t INSTANCES < <($DOCKER ps -a --filter "label=$LABEL" --format '{{.Names}}' | sort)

echo "SQL Server instances:"
if [ ${#INSTANCES[@]} -eq 0 ]; then
  echo "  (none yet)"
fi
for i in "${!INSTANCES[@]}"; do
  c=${INSTANCES[$i]}
  printf "  %d) %-20s port %-6s %s\n" $((i + 1)) "${c#$PREFIX}" "$(port_of "$c")" "$(state_of "$c")"
done
echo "  n) Create a new one"
echo "  q) Quit"

read -rp "Choose: " choice
case "$choice" in
  n|N) create_instance ;;
  q|Q|"") exit 0 ;;
  *)
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#INSTANCES[@]} ]; then
      start_instance "${INSTANCES[$((choice - 1))]}"
    else
      echo "Invalid choice."
      exit 1
    fi
    ;;
esac
