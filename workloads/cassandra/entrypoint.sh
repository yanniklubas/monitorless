#!/bin/bash

set -euo pipefail # abort on nonzero exit status, unbound variable and don't hide errors within pipes

if [[ $DO_SEED -eq 1 ]]; then
	./warmup.sh "$SERVER_IP" "$RECORD_COUNT" 4
else
	printf "+++++++++++++++++++\n"
	printf "++ CONFIGURATION ++\n"
	printf "+++++++++++++++++++\n"

	printf "Record Count: %d \n" "$RECORD_COUNT"
	printf "Warmup Duration: %d s\n" "$WARMUP_DURATION"
	printf "Warmup Rate: %d r/s\n" "$WARMUP_RPS"
	printf "Minimum Requests per Second: %d r/s\n" "$MINIMUM_RPS"
	printf "Maximum Requests per Second: %d r/s\n" "$MAXIMUM_RPS"
	printf "Total benchmark duration: %d s\n" "$BENCHMARK_DURATION"
	printf "Constant load step duration: %d s\n" "$STEP_DURATION"

	exit=0
	while [ $exit -eq 0 ]; do
		set +e
		if cqlsh "$SERVER_IP" -e exit; then
			exit=1
		else
			echo "Could not connect to server $SERVER_IP."
			for i in {5..1}; do
				echo "Trying again in $i seconds..."
				sleep 1
			done
		fi
		set -e
	done

	echo "Warming up the JIT cache!"
	if [ "$WARMUP_DURATION" -ne "0" ]; then
		WARMUP_OP_COUNT=$((WARMUP_DURATION * WARMUP_RPS))
		/ycsb/bin/ycsb.sh run cassandra-cql -p hosts="$SERVER_IP" -P /ycsb/workloads/workloada \
			-p recordcount="$RECORD_COUNT" -p operationcount="$WARMUP_OP_COUNT" \
			-threads 16 -target "$WARMUP_RPS" -s
	fi

	echo "Warmup completed!"
	sleep "$WARMUP_PAUSE"
	if [ "$BENCHMARK_DURATION" -eq "0" ]; then
		exit 0
	fi

	NUMBER_OF_STEPS=$((BENCHMARK_DURATION / STEP_DURATION))
	NUMBER_OF_STEPS=$((NUMBER_OF_STEPS - 1))
	STEP_INCREMENT=$(((MAXIMUM_RPS - MINIMUM_RPS) / NUMBER_OF_STEPS))
	NUMBER_OF_STEPS=$((NUMBER_OF_STEPS + 1))

	for ((CURRENT_STEP = 0; CURRENT_STEP < NUMBER_OF_STEPS; CURRENT_STEP += 1)); do
		CURRENT_RPS=$((MINIMUM_RPS + (CURRENT_STEP * STEP_INCREMENT)))
		OP_COUNT=$((CURRENT_RPS * STEP_DURATION))
		/ycsb/bin/ycsb.sh run cassandra-cql -p hosts="$SERVER_IP" -P /ycsb/workloads/"$WORKLOAD" \
			-p recordcount="$RECORD_COUNT" -p operationcount="$OP_COUNT" -p status.interval=1 \
			-threads 24 -target "$CURRENT_RPS" -s -p maxexecutiontime="$STEP_DURATION"
	done
fi
