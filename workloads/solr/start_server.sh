#!/usr/bin/env bash

SERVER_IP=""
USER=""
CPUS=""
MEMORY=""

for opt in "$@"; do
	case "$opt" in
	--ip=*)
		SERVER_IP="${opt#*=}"
		shift
		;;
	--user=*)
		USER="${opt#*=}"
		shift
		;;
	--cpus=*)
		CPUS="${opt#*=}"
		shift
		;;
	--memory=*)
		MEMORY="${opt#*=}"
		shift
		;;
	-*)
		printf "unknown option: %s" "$opt"
		exit 1
		;;
	*) ;;
	esac
done

if [ -z "$SERVER_IP" ]; then
	printf "invalid arguments: server ip must be set using --ip=<ip>" 1>&2
	exit 1
fi
if [ -z "$USER" ]; then
	printf "invalid arguments: user must be set using --user=<user>" 1>&2
	exit 1
fi
if [ -z "$CPUS" ]; then
	printf "invalid arguments: cpus must be set using --cpus=<cpus>" 1>&2
	exit 1
fi
if [ -z "$MEMORY" ]; then
	printf "invalid arguments: user must be set using --memory=<memory>" 1>&2
	exit 1
fi

ssh "$USER"@"$SERVER_IP" 'cd monitorless/applications/solr; mkdir -p metrics; PROMETHEUS_UID="$(id -u)" PROMETHEUS_GID="$(id -g)" HEAP_MEMORY='"$MEMORY"' CPUS='"$CPUS"' docker compose up --build --detach --force-recreate --wait --quiet-pull'
