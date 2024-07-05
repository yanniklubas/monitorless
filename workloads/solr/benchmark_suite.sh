#!/usr/bin/env bash

# Format: CPU_LIMIT (in cores), HEAP_MEMORY (in GB), PROFILE
# MEMORY_LIMIT := HEAP_MEMORY + 4GB
BENCHMARKS=("3 14 sin1000.csv" "8 14 sin1000.csv" "3 8 sin1000.csv" "3 32 sin1000.csv")
VIRTUAL_USERS=500
TIMEOUT_MS=3000
WARMUP_DURATION_SEC=120
WARMUP_RPS=25
WARMUP_PAUSE_SEC=10
LOAD_GENERATOR_LOC="$HOME/load_generator"
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
	# Download dataset if the web_search_data container does not exist
	ssh "$USER"@"$SERVER_IP" '[ ! "$(docker ps -a | grep "web_search_dataset")" ] && docker run --name web_search_dataset cloudsuite/web-search:dataset'

	# Copy load generator .jar, if not exists
	JAR_NAME="httploadgenerator.jar"
	if [ ! -f "$PWD/$JAR_NAME" ]; then
		if [ ! -f "$LOAD_GENERATOR_LOC/$JAR_NAME" ]; then
			printf "expected load generator jar at %s\n" "$LOAD_GENERATOR_LOC/$JAR_NAME" 1>&2
			exit 1
		fi
		cp "$LOAD_GENERATOR_LOC/$JAR_NAME" "$PWD/$JAR_NAME"
	fi

	START_TIME=$(date +%s)
	mkdir -p "$MEASURMENTS_DIR"
	VOLUME_NAME="prometheus-data-$START_TIME"

	ssh "$USER"@"$SERVER_IP" '
docker volume create '"$VOLUME_NAME"' >/dev/null
cd $HOME/monitorless/applications/solr
echo MG_PROMETHEUS_VOLUME_NAME='"$VOLUME_NAME"' > .env
'

	for t in "${BENCHMARKS[@]}"; do
		oIFS="$IFS"
		IFS=' '
		read -ra RUN <<<"$t"
		IFS="$oIFS"
		unset oIFS
		CPU="${RUN[0]}"
		MEMORY="${RUN[1]}"
		PROFILE="${RUN[2]}"

		bash run_workload.sh \
			--profile="$PWD/$PROFILE" \
			--cpu-limit="$CPU" \
			--heap-memory="$MEMORY" \
			--ip="$SERVER_IP" \
			--threads=256 \
			--vuser="$VIRTUAL_USERS" \
			--timeout="$TIMEOUT_MS" \
			--wp-duration="$WARMUP_DURATION_SEC" \
			--wp-rps="$WARMUP_RPS" \
			--wp-pause="$WARMUP_PAUSE_SEC" \
			--workload-file="$PWD/workload.yml" \
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
rm $HOME/monitorless/applications/solr/.env
docker volume rm '"$VOLUME_NAME"''
	scp "$USER"@"$SERVER_IP":/tmp/metrics.tar.gz "$MEASURMENTS_DIR/metrics.tar.gz"
)
