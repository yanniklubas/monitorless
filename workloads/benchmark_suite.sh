#!/usr/bin/env bash
set -euo pipefail

parse_config() {
	local file="$1"
	while IFS=$'[ \t]*=[ \t]*' read -r name value; do
		if [ -z "$name" ]; then
			continue
		fi
		case "$name" in
		SERVER_IP)
			SERVER_IP="$value"
			;;
		*)
			printf "unknown configuration %s\n" "$name" >&2
			exit 1
			;;
		esac
	done <"$file"

	local exit_code=0

	log_fatal() {
		local name="$1"
		local option="$2"

		printf "failed to parse configuration file %s: %s must be set using %s\n" "$file" "$name" "$option"
		exit_code=1
	}

	if [ -z "$SERVER_IP" ]; then
		log_fatal "server ip" "SERVER_IP"
	fi

	return $exit_code
}
(
	SCRIPT_PATH=$(dirname -- "${BASH_SOURCE[0]}")
	SCRIPT_PATH=$(readlink -f -- "${SCRIPT_PATH}")
	cd "${SCRIPT_PATH}" || exit 1
	parse_config "config.conf"
	echo "$SERVER_IP"

	START_TIME=$(date +%s)
	MEASUREMENTS_DIR="$HOME/measurements/benchmark-$START_TIME"

	(
		cd solr
		bash benchmark_suite.sh "$MEASUREMENTS_DIR/solr" 2>&1 | tee "solr.log"
	)
	(
		cd memcached
		bash benchmark_suite.sh "$MEASUREMENTS_DIR/memcached" 2>&1 | tee "memcached.log"
	)
	(
		cd cassandra
		bash benchmark_suite.sh "$MEASUREMENTS_DIR/cassandra" 2>&1 | tee "cassandra.log"
	)
	(
		bash parallel.sh "$MEASUREMENTS_DIR/parallel" 2>&1 | tee "parallel.log"
	)
)
