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
MEASURMENTS_DIR="$HOME/measurments/memcached/benchmark-$START_TIME"
mkdir -p "$MEASURMENTS_DIR"
VOLUME_NAME="prometheus-data-$START_TIME"

# Create docker volume if it does not exist"
ssh "$USER"@"$SERVER_IP" '
docker volume create '"$VOLUME_NAME"'
cd monitorless/applications/memcached
echo MG_PROMETHEUS_VOLUME_NAME='"$VOLUME_NAME"' > .env
'

for t in "${BENCHMARKS[@]}"; do
	oIFS="$IFS"
	IFS=' '
	read -ra RUN <<<"$t"
	IFS="$oIFS"
	unset oIFS
	CPU="${RUN[1]}"
	MEMORY="${RUN[2]}"
	MIN_RPS="${RUN[3]}"
	MAX_RPS="${RUN[4]}"

	bash benchmark.sh \
		--cpus="$CPU" \
		--memory="$MEMORY" \
		--ip="$SERVER_IP" \
		--duration="$DURATION_SEC" \
		--min-rps="$MIN_RPS" \
		--max-rps="$MAX_RPS" \
		--step="$STEP_DURATION_SEC"

done
ssh "$USER"@"$SERVER_IP" 'rm /tmp/metrics.tar.gz 2>/dev/null
docker run \
--rm \
-v /tmp:/backup \
-v '"$VOLUME_NAME"':/data \
busybox \
tar --no-xattrs -czf /data /backup/metrics.tar.gz
rm $HOME/monitorless/applications/memcached/.env'
scp "$USER"@"$SERVER_IP":/tmp/metrics.tar.gz "$RUN_DIR/metrics.tar.gz"
