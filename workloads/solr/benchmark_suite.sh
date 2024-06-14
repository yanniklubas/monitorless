#!/usr/bin/env bash

SERVER_IP="10.128.0.4"
DURATION_SEC=600
VIRTUAL_USERS=500
TIMEOUT_MS=3000
WARMUP_DURATION_SEC=120
WARMUP_RPS=25
WARMUP_PAUSE_SEC=10

# Download dataset if the web_search_data container does not exist
ssh "$USER"@"$SERVER_IP" '[ ! "$(docker ps -a | grep "web_search_dataset")" ] && docker run --name web_search_dataset cloudsuite/web-search:dataset'

# Tuple format CPU, Mem, Profile
#        |++++ #1 +++++| |+++++ #2 +++++|
for t in "3 30g sin1000" "16 30g sin1000"; do
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
