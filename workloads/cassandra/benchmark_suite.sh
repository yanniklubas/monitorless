#!/usr/bin/env bash

SERVER_IP="10.128.0.4"
RECORD_COUNT=10000000
SEED="--seed"
DURATION_SEC=600
STEP_DURATION_SEC=30
WARMUP_DURATION_SEC=120
WARMUP_RPS=100
WARMUP_PAUSE_SEC=10

# Tuple format cpu, memory, workload, min-rps, max-rps
# Workload ordering based on https://github.com/brianfrankcooper/YCSB/wiki/Core-Workloads#running-the-workloads
#        |+++++++++++ #11 ++++++++++++| |+++++++++++ #12 +++++++++++| |++++++++ #19 +++++++++| |+++++++ #20 ++++++++| |+++++++++++ #13 +++++++++++|
for t in "16 30 workloada 30000 100000" "16 30 workloadb 20000 70000" "1 30 workloadf 200 200" "1 30 workloadf 20 20" "16 30 workloadd 40000 90000"; do
	set -- $t
	CPU="$1"
	MEMORY="$2"
	WORKLOAD="$3"
	MIN_RPS="$4"
	MAX_RPS="$5"

	bash benchmark.sh \
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
		--wp-pause="$WARMUP_PAUSE_SEC"
	# Only seed on first iteration
	SEED=""
done
