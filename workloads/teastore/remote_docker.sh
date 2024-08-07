#!/usr/bin/env bash

SERVER_IP=""
USER=""
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
	printf "invalid arguments: server ip must be set using --ip=<ip>" 1>&2
	exit 1
fi
if [ -z "$USER" ]; then
	printf "invalid arguments: user must be set using --user=<user>" 1>&2
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
cd monitorless/applications/teastore
'"$DOCKER_CMD"' 2>/dev/null >&2'
