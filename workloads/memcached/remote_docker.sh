#!/usr/bin/env bash

SERVER_IP=""
USER=""
CPU_LIMIT=""
MEMORY_LIMIT=""
SERVER_MEMORY=""
DOCKER_CMD=""

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
	--cpu-limit=*)
		CPU_LIMIT="${opt#*=}"
		shift
		;;
	--memory-limit=*)
		MEMORY_LIMIT="${opt#*=}"
		shift
		;;
	--server-memory=*)
		SERVER_MEMORY="${opt#*=}"
		shift
		;;
	--cmd=*)
		DOCKER_CMD="${opt#*=}"
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
	printf "invalid arguments: server ip must be set using --ip=<ip>\n" 1>&2
	exit 1
fi
if [ -z "$USER" ]; then
	printf "invalid arguments: user must be set using --user=<user>\n" 1>&2
	exit 1
fi
if [ -z "$CPU_LIMIT" ]; then
	printf "invalid arguments: cpu limit must be set using --cpu-limit=<limit>\n" 1>&2
	exit 1
fi
if [ -z "$MEMORY_LIMIT" ]; then
	printf "invalid arguments: memory limit must be set using --memory-limit=<limit>\n" 1>&2
	exit 1
fi
if [ -z "$SERVER_MEMORY" ]; then
	printf "invalid arguments: user must be set using --memory=<memory>\n" 1>&2
	exit 1
fi
if [ "$DOCKER_CMD" = "up" ]; then
	DOCKER_CMD="docker compose up --build --detach --force-recreate --wait --quiet-pull"
elif [ "$DOCKER_CMD" = "down" ]; then
	DOCKER_CMD="docker compose down"
else
	printf "invalid arguments: docker command must be set using --cmd={up | down}\n" >&2
	exit 1
fi

ssh "$USER"@"$SERVER_IP" '
cd $HOME/monitorless/applications/memcached
SERVER_MEMORY='"$SERVER_MEMORY"' CPU_LIMIT='"$CPU_LIMIT"' MEMORY_LIMIT='"$MEMORY_LIMIT"' '"$DOCKER_CMD"' 2>/dev/null >&2'
