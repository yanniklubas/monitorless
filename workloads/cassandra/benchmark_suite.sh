#!/usr/bin/env bash

SERVER_IP="10.128.0.4"
RECORD_COUNT=10000000
# Tuple format cpu, memory, workload, min-rps, max-rps
# Workload ordering based on https://github.com/brianfrankcooper/YCSB/wiki/Core-Workloads#running-the-workloads
#           |++++++++++ #11 ++++++++++++| |++++++++++ #12 +++++++++++| |++++++++ #19 +++++++++| |+++++++ #20 ++++++++| |++++++++++ #13 +++++++++++|
BENCHMARKS=("8 28 workloada 30000 100000" "8 28 workloadb 20000 70000" "1 28 workloadf 200 200" "1 28 workloadf 20 20" "8 28 workloadd 40000 90000")
DURATION_SEC=600
STEP_DURATION_SEC=30
WARMUP_DURATION_SEC=120
WARMUP_RPS=100
WARMUP_PAUSE_SEC=10

#+++++++++++++++++++++++++++
#++++ CONFIGURATION END ++++
#+++++++++++++++++++++++++++

START_TIME=$(date +%s)
SEED="--seed"
MEASURMENTS_DIR="$1"
mkdir -p "$MEASURMENTS_DIR"
VOLUME_NAME="prometheus-data-$START_TIME"

# Create docker volume if it does not exist"
ssh "$USER"@"$SERVER_IP" '
docker volume create '"$VOLUME_NAME"' >/dev/null
cd $HOME/monitorless/applications/cassandra
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
	WORKLOAD="${RUN[2]}"
	MIN_RPS="${RUN[3]}"
	MAX_RPS="${RUN[4]}"

	bash run_workload.sh \
		--workload="$WORKLOAD" \
		--records="$RECORD_COUNT" \
		"$SEED" \
		--cpus="$CPU" \
		--memory="$MEMORY" \
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
	-v /tmp:/backup \
	-v '"$VOLUME_NAME"':/data \
	busybox \
	tar -czf /backup/metrics.tar.gz /data/
rm $HOME/monitorless/applications/cassandra/.env
docker volume rm '"$VOLUME_NAME"''
scp "$USER"@"$SERVER_IP":/tmp/metrics.tar.gz "$MEASURMENTS_DIR/metrics.tar.gz"
