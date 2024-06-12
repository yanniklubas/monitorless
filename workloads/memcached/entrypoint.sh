#!/bin/bash

echo "+++++++++++++++++++"
echo "++ CONFIGURATION ++"
echo "+++++++++++++++++++"

echo "Server Memory: $SERVER_MEMORY MB"
echo "Minimum Requests per Second: $MINIMUM_RPS r/s"
echo "Maximum Requests per Second: $MAXIMUM_RPS r/s"
echo "Total Test Duration: $TEST_DURATION_SEC s"
echo "Constant Load Step Duration: $LOAD_STEP_DURATION s"

/entrypoint.sh --m="S&W" --S=28 -- D="$SERVER_MEMORY" --w=4

for i in {5..1}; do
	echo "Starting load step in $i seconds..."
	sleep 1
done

NUMBER_OF_STEPS=$((TEST_DURATION_SEC / LOAD_STEP_DURATION))
STEP_INCREMENT=$(((MAXIMUM_RPS - MINIMUM_RPS) / NUMBER_OF_STEPS))

for ((CURRENT_RPS = MINIMUM_RPS; CURRENT_RPS <= MAXIMUM_RPS; CURRENT_RPS += STEP_INCREMENT)); do
	/entrypoint.sh --m="RPS" --S=28 --g=0.8 --c=200 --w=4 --T=1 --t="$LOAD_STEP_DURATION" --r="$CURRENT_RPS"
done
