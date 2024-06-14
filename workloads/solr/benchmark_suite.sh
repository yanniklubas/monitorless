#!/usr/bin/env bash

SERVER_IP="10.128.0.4"
DURATION_SEC=600
VIRTUAL_USERS=500
TIMEOUT_MS=3000
WARMUP_DURATION_SEC=120
WARMUP_RPS=25
WARMUP_PAUSE_SEC=10
LOAD_GENERATOR_LOC="$HOME/load_generator"

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

# Tuple format CPU, Mem, Profile
#        |++++ #1 +++++| |+++++ #2 +++++|
for t in "3 14g sin1000.csv" "8 14g sin1000.csv"; do
	set -- $t
	CPU="$1"
	MEMORY="$2"
	PROFILE="$3"

	bash benchmark.sh \
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
		--workload="$PWD/workload.yml"
done
