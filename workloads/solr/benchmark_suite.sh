#!/usr/bin/env bash

SERVER_IP="10.128.0.4"
# Tuple format CPU, Mem, Profile
#        |++++ #1 +++++| |+++++ #2 +++++|
BENCHMARKS=("3 14g sin1000.csv" "8 14g sin1000.csv")
DURATION_SEC=600
VIRTUAL_USERS=500
TIMEOUT_MS=3000
WARMUP_DURATION_SEC=120
WARMUP_RPS=25
WARMUP_PAUSE_SEC=10
LOAD_GENERATOR_LOC="$HOME/load_generator"

#+++++++++++++++++++++++++++
#++++ CONFIGURATION END ++++
#+++++++++++++++++++++++++++

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
MEASURMENTS_DIR="$HOME/measurements/solr/benchmark-$START_TIME"
mkdir -p "$MEASURMENTS_DIR"
VOLUME_NAME="prometheus-data-$START_TIME"

# Create docker volume if it does not exist"
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
		--cpus="$CPU" \
		--memory="$MEMORY" \
		--ip="$SERVER_IP" \
		--duration="$DURATION_SEC" \
		--threads=256 \
		--vuser="$VIRTUAL_USERS" \
		--timeout="$TIMEOUT_MS" \
		--wp-duration="$WARMUP_DURATION_SEC" \
		--wp-rps="$WARMUP_RPS" \
		--wp-pause="$WARMUP_PAUSE_SEC" \
		--workload="$PWD/workload.yml" \
		--measurements="$MEASURMENTS_DIR"
done

ssh "$USER"@"$SERVER_IP" 'rm /tmp/metrics.tar.gz 2>/dev/null
docker run \
	--rm \
	-v /tmp:/backup \
	-v '"$VOLUME_NAME"':/data \
	busybox \
	tar -czf /backup/metrics.tar.gz /data/
rm $HOME/monitorless/applications/solr/.env'
scp "$USER"@"$SERVER_IP":/tmp/metrics.tar.gz "$MEASURMENTS_DIR/metrics.tar.gz"
