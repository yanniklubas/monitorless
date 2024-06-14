#!/usr/bin/env bash
# +++++++++++++++++++
# ++ CONFIGURATION ++
# +++++++++++++++++++

set -euo pipefail # abort on nonzero exit status, unbound variable and don't hide errors within pipes

# One of: workloada, workloadb, workloadc, workloadd, workloade, workloadf
WORKLOAD=""
RECORD_COUNT=""
CPUS=""
MEMORY=""
SERVER_IP=""
DO_SEED=0

# +++++++++++++++++++++++++++++
# ++ BENCHMARK CONFIGURATION ++
# +++++++++++++++++++++++++++++
BENCHMARK_DURATION=""
WARMUP_DURATION=""
WARMUP_RPS=""
WARMUP_PAUSE=""
MINIMUM_RPS=""
MAXIMUM_RPS=""
STEP_DURATION=""

for opt in "$@"; do
	case "$opt" in
	--workload=*)
		WORKLOAD="${opt#*=}"
		shift
		;;
	--records=*)
		RECORD_COUNT="${opt#*=}"
		shift
		;;
	--seed)
		DO_SEED=1
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
if [ -z "$RECORD_COUNT" ]; then
	printf "invalid arguments: record count must be set using --records=<count>\n" 1>&2
	exit 1
fi
if [ -z "$MEMORY" ]; then
	printf "invalid arguments: memory must be set using --memory=<memory>\n" 1>&2
	exit 1
fi
if [ -z "$WORKLOAD" ]; then
	printf "invalid arguments: workload must be set using --workload=<workload>\n" 1>&2
	exit 1
fi
if [ -z "$CPUS" ]; then
	printf "invalid arguments: cpus must be set using --cpus=<cpus>\n" 1>&2
	exit 1
fi

# +++++++++++++++++++
(
	SCRIPT_PATH=$(dirname -- "${BASH_SOURCE[0]}")
	SCRIPT_PATH=$(readlink -f -- "${SCRIPT_PATH}")
	cd "${SCRIPT_PATH}"
	if [ "$DO_SEED" -eq 1 ]; then
		printf "Starting seeding the database with %s\n" "$WORKLOAD"
		ssh "$USER"@"$SERVER_IP" 'cd monitorless/applications/cassandra; PROMETHEUS_UID="$(id -u)" PROMETHEUS_GID="$(id -g)" CPUS='"$CPUS"' HEAP_MEMORY='"$MEMORY"' docker compose up --build --detach --force-recreate --wait --quiet-pull cassandra 2>/dev/null >&2'
		DO_SEED="$DO_SEED" WORKLOAD="$WORKLOAD" SERVER_IP="$SERVER_IP" RECORD_COUNT="$RECORD_COUNT" docker compose up --force-recreate --build
		ssh "$USER"@"$SERVER_IP" 'cd monitorless/applications/cassandra; PROMETHEUS_UID="$(id -u)" PROMETHEUS_GID="$(id -g)" CPUS='"$CPUS"' HEAP_MEMORY='"$MEMORY"' docker compose down'
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

	MEASUREMENTS_DIR="$HOME/measurements/cassandra"
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
	printf "workload: %s\n" "$WORKLOAD" >"$CONFIG_FILE"
	{
		printf "cpus: %d\n" "$CPUS"
		printf "memory: %s\n" "$MEMORY"
		printf "server_ip: %s\n" "$SERVER_IP"
		printf "duration: %d\n" "$BENCHMARK_DURATION"
		printf "warmup_duration: %d\n" "$WARMUP_DURATION"
		printf "warmup_rps: %d\n" "$WARMUP_RPS"
		printf "warmup_pause: %d\n" "$WARMUP_PAUSE"
		printf "minimum_rps: %d\n" "$MINIMUM_RPS"
		printf "maximum_rps: %d\n" "$MAXIMUM_RPS"
		printf "step_duration: %d\n" "$STEP_DURATION"
	} >>"$CONFIG_FILE"

	printf "Starting Cassandra server on %s\n" "$SERVER_IP"
	bash start_server.sh --ip="$SERVER_IP" --user="$USER" --cpus="$CPUS" --memory="$MEMORY"
	WAIT=10
	printf "Waiting for %d seconds on server server.\n" "$WAIT"
	sleep "$WAIT"
	DO_SEED=0 SERVER_IP="$SERVER_IP" RECORD_COUNT="$RECORD_COUNT" WARMUP_DURATION="$WARMUP_DURATION" WARMUP_RPS="$WARMUP_RPS" WARMUP_PAUSE="$WARMUP_PAUSE" MINIMUM_RPS="$MINIMUM_RPS" MAXIMUM_RPS="$MAXIMUM_RPS" BENCHMARK_DURATION="$BENCHMARK_DURATION" STEP_DURATION="$STEP_DURATION" WORKLOAD="$WORKLOAD" docker compose up --force-recreate --build
	docker compose logs --no-log-prefix cassandra-client >"$RUN_DIR/summary.log"
	ssh "$USER"@"$SERVER_IP" 'cd monitorless/applications/cassandra; PROMETHEUS_UID="$(id -u)" PROMETHEUS_GID="$(id -g)" CPUS='"$CPUS"' HEAP_MEMORY='"$MEMORY"' docker compose down; tar --no-xattrs -czf metrics.tar.gz metrics/'
	scp "$USER"@"$SERVER_IP":monitorless/applications/cassandra/metrics.tar.gz "$RUN_DIR/metrics.tar.gz"
)
