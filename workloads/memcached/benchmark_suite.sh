#!/usr/bin/env bash
set -euo pipefail

# Format:  CPU_LIMIT (in cores), SERVER_MEMORY (in MB), MINIMUM_RPS, MAXIMUM_RPS
# MEMORY_LIMIT := SERVER_MEMORY + 1024 MB
BENCHMARKS=("1 3072 50000 180000" "1 32768 50000 200000" "8 6144 30000 95000" "8 32768 40000 200000")
DURATION_SEC=600
STEP_DURATION_SEC=30

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
if [ -z "$SERVER_IP" ]; then
	print_usage
	exit 1
fi

(
	SCRIPT_PATH=$(dirname -- "${BASH_SOURCE[0]}")
	SCRIPT_PATH=$(readlink -f -- "${SCRIPT_PATH}")
	cd "${SCRIPT_PATH}" || exit 1
	# Download dataset if the web_search_data container does not exist
	START_TIME=$(date +%s)
	mkdir -p "$MEASURMENTS_DIR"
	VOLUME_NAME="prometheus-data-$START_TIME"

	ssh "$USER"@"$SERVER_IP" '
docker volume create '"$VOLUME_NAME"' >/dev/null
cd $HOME/monitorless/applications/memcached
echo MG_PROMETHEUS_VOLUME_NAME='"$VOLUME_NAME"' > .env
'

	for t in "${BENCHMARKS[@]}"; do
		oIFS="$IFS"
		IFS=' '
		read -ra CONFIG <<<"$t"
		IFS="$oIFS"
		unset oIFS
		CPU_LIMIT="${CONFIG[0]}"
		SERVER_MEMORY="${CONFIG[1]}"
		MIN_RPS="${CONFIG[2]}"
		MAX_RPS="${CONFIG[3]}"

		bash run_workload.sh \
			--cpu-limit="$CPU_LIMIT" \
			--server-memory="$SERVER_MEMORY" \
			--ip="$SERVER_IP" \
			--duration="$DURATION_SEC" \
			--min-rps="$MIN_RPS" \
			--max-rps="$MAX_RPS" \
			--step="$STEP_DURATION_SEC" \
			--measurements="$MEASURMENTS_DIR"

	done

	ssh "$USER"@"$SERVER_IP" 'rm /tmp/metrics.tar.gz 2>/dev/null
docker run \
--rm \
--volume /tmp:/backup \
--volume '"$VOLUME_NAME"':/data \
--user 65534:65534 \
busybox \
tar -czf /backup/metrics.tar.gz /data/
rm $HOME/monitorless/applications/memcached/.env
docker volume rm '"$VOLUME_NAME"''
	scp "$USER"@"$SERVER_IP":/tmp/metrics.tar.gz "$MEASURMENTS_DIR/metrics.tar.gz"
)
