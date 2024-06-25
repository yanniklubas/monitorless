#!/usr/bin/env bash
set -euo pipefail # abort on nonzero exit status, unbound variable and don't hide errors within pipes

SERVER_IP="10.128.0.4"
DURATION_SEC=600
STEP_DURATION_SEC=30
# Tuple format cpu, memory, min-rps, max-rps
#          |++++++++ #7 +++++++| |++++++++ #8 +++++++| |+++++++ #9 +++++++|
BENCHMARKS=("8 30720 2000 50000" "1 30720 20000 85000" "8 8192 39000 45000")

#+++++++++++++++++++++++++++
#++++ CONFIGURATION END ++++
#+++++++++++++++++++++++++++

START_TIME=$(date +%s)
MEASURMENTS_DIR="$1"
mkdir -p "$MEASURMENTS_DIR"
VOLUME_NAME="prometheus-data-$START_TIME"

# Create docker volume if it does not exist"
ssh "$USER"@"$SERVER_IP" '
docker volume create '"$VOLUME_NAME"' >/dev/null
cd $HOME/monitorless/applications/memcached
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
	MIN_RPS="${RUN[2]}"
	MAX_RPS="${RUN[3]}"

	bash run_workload.sh \
		--cpus="$CPU" \
		--memory="$MEMORY" \
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
