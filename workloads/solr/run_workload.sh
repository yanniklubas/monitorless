#!/usr/bin/env bash
# +++++++++++++++++++
# ++ CONFIGURATION ++
# +++++++++++++++++++

set -euo pipefail # abort on nonzero exit status, unbound variable and don't hide errors within pipes

PROFILE=""
CPU_LIMIT=""
HEAP_MEMORY=""
SERVER_IP=""
THREADS=""
VIRTUAL_USERS=""
TIMEOUT=""
WARMUP_DURATION=""
WARMUP_RPS=""
WARMUP_PAUSE=""
WORKLOAD_FILE=""
SOLR_PORT=8983

for opt in "$@"; do
	case "$opt" in
	--profile=*)
		PROFILE="${opt#*=}"
		shift
		;;
	--cpu-limit=*)
		CPU_LIMIT="${opt#*=}"
		shift
		;;
	--heap-memory=*)
		HEAP_MEMORY="${opt#*=}"
		shift
		;;
	--ip=*)
		SERVER_IP="${opt#*=}"
		shift
		;;
	--threads=*)
		THREADS="${opt#*=}"
		shift
		;;
	--vuser=*)
		VIRTUAL_USERS="${opt#*=}"
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
	--workload-file=*)
		WORKLOAD_FILE="${opt#*=}"
		shift
		;;
	--measurements=*)
		MEASUREMENTS_DIR="${opt#*=}"
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
if [ -z "$CPU_LIMIT" ]; then
	printf "invalid arguments: cpu limit must be set using --cpu-limit=<cpus>\n" 1>&2
	exit 1
fi
if [ -z "$HEAP_MEMORY" ]; then
	printf "invalid arguments: heap memory must be set using --heap-memory=<memory>\n" 1>&2
	exit 1
fi
if [ -z "$SERVER_IP" ]; then
	printf "invalid arguments: server ip must be set using --ip=<ip>\n" 1>&2
	exit 1
fi
if [ -z "$THREADS" ]; then
	printf "invalid arguments: threads must be set using --threads=<threads>\n" 1>&2
	exit 1
fi
if [ -z "$VIRTUAL_USERS" ]; then
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
if [ -z "$MEASUREMENTS_DIR" ]; then
	printf "invalid arguments: measurements direcotry must be set using --measurements=<path>\n" 1>&2
	exit 1
fi

# +++++++++++++++++++
(
	SCRIPT_PATH=$(dirname -- "${BASH_SOURCE[0]}")
	SCRIPT_PATH=$(readlink -f -- "${SCRIPT_PATH}")
	cd "${SCRIPT_PATH}"

	DIR_NAME="cpu-$CPU_LIMIT-memory-$HEAP_MEMORY-duration-$BENCHMARK_DURATION"
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
	BENCHMARK_DURATION=$(wc -l <"$PROFILE")
	BENCHMARK_DURATION=$(echo "$BENCHMARK_DURATION" | xargs)
	printf "profile: %s\n" "$PROFILE" >"$CONFIG_FILE"
	{
		printf "cpus: %d\n" "$CPU_LIMIT"
		printf "memory: %s\n" "$HEAP_MEMORY"
		printf "server_ip: %s\n" "$SERVER_IP"
		printf "duration: %d\n" "$BENCHMARK_DURATION"
		printf "threads: %d\n" "$THREADS"
		printf "virtual_users: %d\n" "$VIRTUAL_USERS"
		printf "timeout: %d\n" "$TIMEOUT"
		printf "warmup_duration: %d\n" "$WARMUP_DURATION"
		printf "warmup_rps: %d\n" "$WARMUP_RPS"
		printf "warmup_pause: %d\n" "$WARMUP_PAUSE"
		printf "workload: %s\n" "$WORKLOAD_FILE"
	} >>"$CONFIG_FILE"

	printf "Starting Solr server on %s\n" "$SERVER_IP"

	MEMORY_LIMIT="$((HEAP_MEMORY + 4))GB"
	HEAP_MEMORY="${HEAP_MEMORY}G"

	bash remote_docker.sh \
		--ip="$SERVER_IP" \
		--user="$USER" \
		--cpu-limit="$CPU_LIMIT" \
		--memory-limit="$MEMORY_LIMIT" \
		--heap-memory="$HEAP_MEMORY" \
		--cmd="up"

	printf "Waiting on Solr server.\n"
	bash query.sh "$SERVER_IP"
	YAML_FILE=$(mktemp)
	sed -e 's/{{APPLICATION_HOST}}/'"$SERVER_IP"':'"$SOLR_PORT"'/g' "$WORKLOAD_FILE" >"$YAML_FILE"
	YAML_PATH="$YAML_FILE" \
		BENCHMARK_RUN="$RUN_DIR" \
		PROFILE="$PROFILE" \
		BENCHMARK_DURATION="$BENCHMARK_DURATION" \
		DIRECTOR_THREADS="$THREADS" \
		VIRTUAL_USERS="$VIRTUAL_USERS" \
		TIMEOUT="$TIMEOUT" \
		WARMUP_DURATION="$WARMUP_DURATION" \
		WARMUP_RPS="$WARMUP_RPS" \
		WARMUP_PAUSE="$WARMUP_PAUSE" \
		docker compose up \
		--build --abort-on-container-exit --force-recreate

	bash remote_docker.sh \
		--ip="$SERVER_IP" \
		--user="$USER" \
		--cpu-limit="$CPU_LIMIT" \
		--memory-limit="$MEMORY_LIMIT" \
		--heap-memory="$HEAP_MEMORY" \
		--cmd="down"
	rm "$YAML_FILE"
)
