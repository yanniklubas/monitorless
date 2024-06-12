#!/bin/bash

if [[ $DO_SEED -eq 1 ]]; then
	./warmup.sh "$SERVER_IP" "$RECORD_COUNT" 4
else
	echo "+++++++++++++++++++"
	echo "++ CONFIGURATION ++"
	echo "+++++++++++++++++++"

	echo "Record Count: $RECORD_COUNT"
	echo "Warmup Duration: $WARMUP_DURATION s"
	echo "Warmup Rate: $WARMUP_RATE r/s"
	echo "Minimum Requests per Second: $MINIMUM_RPS r/s"
	echo "Maximum Requests per Second: $MAXIMUM_RPS r/s"
	echo "Total Test Duration: $TEST_DURATION_SEC s"
	echo "Constant Load Step Duration: $LOAD_STEP_DURATION s"

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
	WARMUP_OP_COUNT=$((WARMUP_DURATION * WARMUP_RATE))
	/ycsb/bin/ycsb.sh run cassandra-cql -p hosts="$SERVER_IP" -P /ycsb/workloads/workloada \
		-p recordcount="$RECORD_COUNT" -p operationcount="$WARMUP_OP_COUNT" \
		-threads 16 -target "$WARMUP_RATE" -s

	echo "Warmup completed!"

	NUMBER_OF_STEPS=$((TEST_DURATION_SEC / LOAD_STEP_DURATION))
	STEP_INCREMENT=$(((MAXIMUM_RPS - MINIMUM_RPS) / NUMBER_OF_STEPS))

	for ((CURRENT_RPS = MINIMUM_RPS; CURRENT_RPS <= MAXIMUM_RPS; CURRENT_RPS += STEP_INCREMENT)); do
		OP_COUNT=$((CURRENT_RPS * LOAD_STEP_DURATION))
		/ycsb/bin/ycsb.sh run cassandra-cql -p hosts="$SERVER_IP" -P /ycsb/workloads/"$WORKLOAD" \
			-p recordcount="$RECORD_COUNT" -p operationcount="$OP_COUNT" -p status.interval=1 \
			-threads 16 -target "$CURRENT_RPS" -s -p maxexecutiontime="$LOAD_STEP_DURATION"
	done
fi
