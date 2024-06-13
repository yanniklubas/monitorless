#!/usr/bin/env bash
# +++++++++++++++++++
# ++ CONFIGURATION ++
# +++++++++++++++++++

set -euo pipefail # abort on nonzero exit status, unbound variable and don't hide errors within pipes

PROFILE=""
CPUS=""
MEMORY=""
SERVER_IP=""

# +++++++++++++++++++++++++++++
# ++ BENCHMARK CONFIGURATION ++
# +++++++++++++++++++++++++++++
BENCHMARK_DURATION=""
DIRECTOR_THREADS=""
VIRTUAL_USER=""
TIMEOUT=""
WARMUP_DURATION=""
WARMUP_RPS=""
WARMUP_PAUSE=""
WORKLOAD_FILE=""

for opt in "$@"; do
	case "$opt" in
	--profile=*)
		PROFILE="${opt#*=}"
		shift
		;;
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
	--threads=*)
		DIRECTOR_THREADS="${opt#*=}"
		shift
		;;
	--vuser=*)
		VIRTUAL_USER="${opt#*=}"
		shift
		;;
	--timeout=*)
		TIMEOUT="${opt#*=}"
		shift
		;;
	--wp-duration=*)
		WARMUP_DURATION="${opt#*=}"
		shift
		;;
	--wp-rps=*)
		WARMUP_RPS="${opt#*=}"
		shift
		;;
	--wp-pause=*)
		WARMUP_PAUSE="${opt#*=}"
		shift
		;;
	--workload=*)
		WORKLOAD_FILE="${opt#*=}"
		shift
		;;
	-*)
		printf "Unknown option: %s" "$opt" 1>&2
		exit 1
		;;
	*) ;;
	esac
done

if [ -z "$PROFILE" ]; then
	printf "invalid arguments: profile must be set using --profile=<profile>\n" 1>&2
	exit 1
fi
if [ -z "$CPUS" ]; then
	printf "invalid arguments: cpus must be set using --cpus=<cpus>\n" 1>&2
	exit 1
fi
if [ -z "$MEMORY" ]; then
	printf "invalid arguments: memory must be set using --memory=<memory>\n" 1>&2
	exit 1
fi
if [ -z "$SERVER_IP" ]; then
	printf "invalid arguments: server ip must be set using --ip=<ip>\n" 1>&2
	exit 1
fi
if [ -z "$BENCHMARK_DURATION" ]; then
	printf "invalid arguments: benchmark duration must be set using --duration=<duration>\n" 1>&2
	exit 1
fi
if [ -z "$DIRECTOR_THREADS" ]; then
	printf "invalid arguments: director threads must be set using --threads=<threads>\n" 1>&2
	exit 1
fi
if [ -z "$VIRTUAL_USER" ]; then
	printf "invalid arguments: virtual users must be set using --vuser=<vuser>\n" 1>&2
	exit 1
fi
if [ -z "$TIMEOUT" ]; then
	printf "invalid arguments: timeout must be set using --timeout=<timeout>\n" 1>&2
	exit 1
fi
if [ -z "$WARMUP_DURATION" ]; then
	printf "invalid arguments: warmup duration must be set using --wp-duration=<duration>\n" 1>&2
	exit 1
fi
if [ -z "$WARMUP_RPS" ]; then
	printf "invalid arguments: warmup rps must be set using --wp-rps=<rps>\n" 1>&2
	exit 1
fi
if [ -z "$WARMUP_PAUSE" ]; then
	printf "invalid arguments: warmup pause must be set using --wp-pause=<pause>\n" 1>&2
	exit 1
fi
if [ -z "$WORKLOAD_FILE" ]; then
	printf "invalid arguments: workload must be set using --workload=<file>\n" 1>&2
	exit 1
fi

# +++++++++++++++++++
(
	SCRIPT_PATH=$(dirname -- "${BASH_SOURCE[0]}")
	SCRIPT_PATH=$(readlink -f -- "${SCRIPT_PATH}")
	cd "${SCRIPT_PATH}"

	MEASUREMENTS_DIR="$HOME/measurements/solr"
	mkdir -p "$MEASUREMENTS_DIR"
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
	printf "profile: %s\n" "$PROFILE" >"$CONFIG_FILE"
	{
		printf "cpus: %d\n" "$CPUS"
		printf "memory: %s\n" "$MEMORY"
		printf "server_ip: %s\n" "$SERVER_IP"
		printf "duration: %d\n" "$BENCHMARK_DURATION"
		printf "threads: %d\n" "$DIRECTOR_THREADS"
		printf "virtual_users: %d\n" "$VIRTUAL_USER"
		printf "timeout: %d\n" "$TIMEOUT"
		printf "warmup_duration: %d\n" "$WARMUP_DURATION"
		printf "warmup_rps: %d\n" "$WARMUP_RPS"
		printf "warmup_pause: %d\n" "$WARMUP_PAUSE"
		printf "workload: %s\n" "$WORKLOAD_FILE"
	} >>"$CONFIG_FILE"

	printf "Starting Solr server on %s\n" "$SERVER_IP"
	bash start_server.sh --ip="$SERVER_IP" --user="$USER" --cpus="$CPUS" --memory="$MEMORY"
	printf "Waiting on Solr server.\n"
	bash query.sh "$SERVER_IP"
	YAML_PATH="$WORKLOAD_FILE" BENCHMARK_RUN="$RUN_DIR" PROFILE="$PROFILE" BENCHMARK_DURATION="$BENCHMARK_DURATION" DIRECTOR_THREADS="$DIRECTOR_THREADS" VIRTUAL_USERS="$VIRTUAL_USER" TIMEOUT="$TIMEOUT" WARMUP_DURATION="$WARMUP_DURATION" WARMUP_RPS="$WARMUP_RPS" WARMUP_PAUSE="$WARMUP_PAUSE" docker compose up --build --abort-on-container-exit --force-recreate
	ssh "$USER"@"$SERVER_IP" 'cd monitorless/applications/solr; PROMETHEUS_UID="$(id -u)" PROMETHEUS_GID="$(id -g)" HEAP_MEMORY='"$MEMORY"' CPUS='"$CPUS"'docker compose down; tar --no-xattrs czf metrics.tar.gz metrics/'
	scp "$USER"@"$SERVER_IP":monitorless/applications/solr/metrics.tar.gz "$RUN_DIR/metrics.tar.gz"
)
