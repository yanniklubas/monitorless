#!/usr/bin/env bash
set -euo pipefail

# Format: CPU_LIMIT (in cores), HEAP_MEMORY (in GB), WORKLOAD, MINIMUM-RPS, MAXIMUM_RPS
# MEMORY_LIMIT := HEAP_MEMORY + 4GB
# Workload ordering based on https://github.com/brianfrankcooper/YCSB/wiki/Core-Workloads#running-the-workloads
BENCHMARKS=("6 28 workloada 10 300" "8 28 workloada 10 300" "8 28 workloadb 10 300" "6 28 workloadb 10 300" "1 28 workloadf 200 200" "1 28 workloadf 20 20" "6 28 workloadd 10 300")
RECORD_COUNT=20000000
DURATION_SEC=600
STEP_DURATION_SEC=30
WARMUP_DURATION_SEC=120
WARMUP_RPS=100
WARMUP_PAUSE_SEC=10
#+++++++++++++++++++++++++++
#++++ CONFIGURATION END ++++
#+++++++++++++++++++++++++++

MEASURMENTS_DIR="$1"
SERVER_IP="$2"

print_usage() {
	printf "Usage: %s DIR IP
    DIR - The directory used for saving the measurements
    IP  - The IP of the Solr server
" "$0" >&2
}

if [ -z "$MEASURMENTS_DIR" ]; then
	print_usage
	exit 1
fi
if [ -z "$IP" ]; then
	print_usage
	exit 1
fi

(
	SCRIPT_PATH=$(dirname -- "${BASH_SOURCE[0]}")
	SCRIPT_PATH=$(readlink -f -- "${SCRIPT_PATH}")
	cd "${SCRIPT_PATH}" || exit 1

	START_TIME=$(date +%s)
	SEED="--seed"
	mkdir -p "$MEASURMENTS_DIR"
	VOLUME_NAME="prometheus-data-$START_TIME"

	ssh "$USER"@"$SERVER_IP" '
docker volume create '"$VOLUME_NAME"' >/dev/null
cd $HOME/monitorless/applications/cassandra
echo MG_PROMETHEUS_VOLUME_NAME='"$VOLUME_NAME"' > .env
'

	for t in "${BENCHMARKS[@]}"; do
		oIFS="$IFS"
		IFS=' '
		read -ra CONFIG <<<"$t"
		IFS="$oIFS"
		unset oIFS
		CPU_LIMIT="${CONFIG[0]}"
		HEAP_MEMORY="${CONFIG[1]}"
		WORKLOAD="${CONFIG[2]}"
		MIN_RPS="${CONFIG[3]}"
		MAX_RPS="${CONFIG[4]}"

		bash run_workload.sh \
			--workload="$WORKLOAD" \
			--records="$RECORD_COUNT" \
			"$SEED" \
			--cpu-limit="$CPU_LIMIT" \
			--heap-memory="$HEAP_MEMORY" \
			--ip="$SERVER_IP" \
			--duration="$DURATION_SEC" \
			--min-rps="$MIN_RPS" \
			--max-rps="$MAX_RPS" \
			--step="$STEP_DURATION_SEC" \
			--wp-duration="$WARMUP_DURATION_SEC" \
			--wp-rps="$WARMUP_RPS" \
			--wp-pause="$WARMUP_PAUSE_SEC" \
			--measurements="$MEASURMENTS_DIR"
		# Only seed on first iteration
		SEED=""
	done

	ssh "$USER"@"$SERVER_IP" 'rm /tmp/metrics.tar.gz 2>/dev/null
docker run \
	--rm \
	--volume /tmp:/backup \
	--volume '"$VOLUME_NAME"':/data \
	--user 65534:65534 \
	busybox \
	tar -czf /backup/metrics.tar.gz /data/
rm $HOME/monitorless/applications/cassandra/.env
cd $HOME/monitorless/applications/cassandra
CPU_LIMIT=1 MEMORY_LIMIT=1GB docker compose down -v
docker volume rm '"$VOLUME_NAME"''
	scp "$USER"@"$SERVER_IP":/tmp/metrics.tar.gz "$MEASURMENTS_DIR/metrics.tar.gz"
)
