#!/usr/bin/env bash

set -euo pipefail # abort on nonzero exit status, unbound variable and don't hide errors within pipes

BENCHMARK_DURATION=""
MINIMUM_RPS=""
MAXIMUM_RPS=""
STEP_DURATION=""
CPUS=""
MEMORY=""
SERVER_IP=""
PORT=11211
MEASUREMENTS_DIR=""

for opt in "$@"; do
	case "$opt" in
	--cpus=*)
		CPUS="${opt#*=}"
		shift
		;;
	--memory=*)
		MEMORY="${opt#*=}"
		shift
		;;
	--ip=*)
		SERVER_IP="${opt#*=}"
		shift
		;;
	--duration=*)
		BENCHMARK_DURATION="${opt#*=}"
		shift
		;;
	--min-rps=*)
		MINIMUM_RPS="${opt#*=}"
		shift
		;;
	--max-rps=*)
		MAXIMUM_RPS="${opt#*=}"
		shift
		;;
	--step=*)
		STEP_DURATION="${opt#*=}"
		shift
		;;
	--measurements=*)
		MEASUREMENTS_DIR="${opt#*=}"
		shift
		;;
	-*)
		printf "Unknown option: %s\n" "$opt" 1>&2
		exit 1
		;;
	*) ;;
	esac
done

if [ -z "$SERVER_IP" ]; then
	printf "invalid arguments: server ip must be set using --ip=<ip>\n" 1>&2
	exit 1
fi
if [ -z "$MEMORY" ]; then
	printf "invalid arguments: memory must be set using --memory=<memory>\n" 1>&2
	exit 1
fi
if [ -z "$CPUS" ]; then
	printf "invalid arguments: cpus must be set using --cpus=<cpus>\n" 1>&2
	exit 1
fi
if [ -z "$BENCHMARK_DURATION" ]; then
	printf "invalid arguments: benchmark duration must be set using --duration=<duration>\n" 1>&2
	exit 1
fi
if [ -z "$MINIMUM_RPS" ]; then
	printf "invalid arguments: minimum rps must be set using --min-rps=<rps>\n" 1>&2
	exit 1
fi
if [ -z "$MAXIMUM_RPS" ]; then
	printf "invalid arguments: maximum rps must be set using --max-rps=<rps>\n" 1>&2
	exit 1
fi
if [ -z "$STEP_DURATION" ]; then
	printf "invalid arguments: step duration must be set using --step=<duration>\n" 1>&2
	exit 1
fi
if [ -z "$MEASUREMENTS_DIR" ]; then
	printf "invalid arguments: measurements directory must be set using --measurements=<path>\n" 1>&2
	exit 1
fi
# +++++++++++++++++++
(
	SCRIPT_PATH=$(dirname -- "${BASH_SOURCE[0]}")
	SCRIPT_PATH=$(readlink -f -- "${SCRIPT_PATH}")
	cd "${SCRIPT_PATH}"

	DIR_NAME="cpu-$CPUS-memory-$MEMORY-duration-$BENCHMARK_DURATION"
	RUN_DIR="$MEASUREMENTS_DIR/$DIR_NAME"

	if [ -d "$RUN_DIR" ]; then
		TS=$(date +%s)
		BACKUP="$RUN_DIR-bck-$TS"
		printf "directory %s already exists! Backing up to %s!\n" "$RUN_DIR" "$BACKUP"
		mv "$RUN_DIR" "$BACKUP"
	fi
	mkdir -p "$RUN_DIR"
	CONFIG_FILE="$RUN_DIR/config.yml"
	printf "Saving benchmark configuration to %s\n" "$CONFIG_FILE" 1>&2
	touch "$CONFIG_FILE"
	printf "cpus: %d\n" "$CPUS" >"$CONFIG_FILE"
	{
		printf "memory: %s\n" "$MEMORY"
		printf "server_ip: %s\n" "$SERVER_IP"
		printf "duration: %d\n" "$BENCHMARK_DURATION"
		printf "minimum_rps: %d\n" "$MINIMUM_RPS"
		printf "maximum_rps: %d\n" "$MAXIMUM_RPS"
		printf "step_duration: %d\n" "$STEP_DURATION"
	} >>"$CONFIG_FILE"

	printf "Starting Memcached server on %s\n" "$SERVER_IP"
	bash start_server.sh --ip="$SERVER_IP" --user="$USER" --cpus="$CPUS" --memory="$MEMORY"
	WAIT=10
	printf "Waiting for %d seconds on server server.\n" "$WAIT"
	sleep "$WAIT"
	SERVERS_FILE="$PWD/tmp_servers.txt"
	printf "%s, %d\n" "$SERVER_IP" "$PORT" >"$SERVERS_FILE"
	SERVERS_FILE="$SERVERS_FILE" \
		SERVER_MEMORY="$MEMORY" \
		MINIMUM_RPS="$MINIMUM_RPS" \
		MAXIMUM_RPS="$MAXIMUM_RPS" \
		BENCHMARK_DURATION="$BENCHMARK_DURATION" \
		STEP_DURATION="$STEP_DURATION" \
		docker compose up \
		--force-recreate --build
	SERVERS_FILE="$SERVERS_FILE" \
		SERVER_MEMORY="$MEMORY" \
		MINIMUM_RPS="$MINIMUM_RPS" \
		MAXIMUM_RPS="$MAXIMUM_RPS" \
		BENCHMARK_DURATION="$BENCHMARK_DURATION" \
		STEP_DURATION="$STEP_DURATION" \
		docker compose logs --no-log-prefix memcached-client >"$RUN_DIR/summary.log"
	ssh "$USER"@"$SERVER_IP" '
cd $HOME/monitorless/applications/memcached
docker compose down
'
	rm "$SERVERS_FILE"
)
