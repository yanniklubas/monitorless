#!/usr/bin/env bash
set -euo pipefail # abort on nonzero exit status, unbound variable and don't hide errors within pipes

START_TIME=$(date +%s)
MEASUREMENTS_DIR="$HOME/measurements/benchmark-$START_TIME"
mkdir -p "$MEASUREMENTS_DIR"
(
	cd solr
	bash benchmark_suite.sh "$MEASUREMENTS_DIR/solr"
)
(
	cd memcached
	bash benchmark_suite.sh "$MEASUREMENTS_DIR/memcached"
)
(
	cd cassandra
	bash benchmark_suite.sh "$MEASUREMENTS_DIR/cassandra"
)
