#!/bin/bash

echo "+++++++++++++++++++"
echo "++ CONFIGURATION ++"
echo "+++++++++++++++++++"

echo "Server Memory: $SERVER_MEMORY MB"
echo "Minimum Requests per Second: $MINIMUM_RPS r/s"
echo "Maximum Requests per Second: $MAXIMUM_RPS r/s"
echo "Benchmark Duration: $BENCHMARK_DURATION s"
echo "Step Duration: $STEP_DURATION s"
NO_WARMUP="${NO_WARMUP:-0}"

if [ "$NO_WARMUP" -ne 1 ]; then
	/entrypoint.sh --m="S&W" --S=28 --D="$SERVER_MEMORY" --w=4
	for i in {5..1}; do
		echo "Starting load step in $i seconds..."
		sleep 1
	done
else
	echo "You are warmed up, sir"
fi

if [ "$BENCHMARK_DURATION" -eq "0" ]; then
	exit 0
fi

NUMBER_OF_STEPS=$((BENCHMARK_DURATION / STEP_DURATION))
NUMBER_OF_STEPS=$((NUMBER_OF_STEPS - 1))
STEP_INCREMENT=$(((MAXIMUM_RPS - MINIMUM_RPS) / NUMBER_OF_STEPS))
NUMBER_OF_STEPS=$((NUMBER_OF_STEPS + 1))

STEP_DURATION=$((STEP_DURATION + 1))
for ((CURRENT_STEP = 0; CURRENT_STEP < NUMBER_OF_STEPS; CURRENT_STEP += 1)); do
	CURRENT_RPS=$((MINIMUM_RPS + (CURRENT_STEP * STEP_INCREMENT)))
	/entrypoint.sh --m="RPS" --S=28 --g=0.8 --c=200 --w=4 --T=1 --t="$STEP_DURATION" --r="$CURRENT_RPS"
done
