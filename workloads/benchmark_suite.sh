#!/usr/bin/env bash
set -euo pipefail # abort on nonzero exit status, unbound variable and don't hide errors within pipes

(
	cd solr
	bash benchmark_suite.sh
)
(
	cd memcached
	bash benchmark_suite.sh
)
(
	cd cassandra
	bash benchmark_suite.sh
)
