#!/usr/bin/env bash
set -euo pipefail # abort on nonzero exit status, unbound variable and don't hide errors within pipes

(
	SERVER_IP="10.128.0.5"
	BENCHMARKS=("linear300" "linear600" "sine20-300" "sine250" "sine150" "sinnoise100")
	VIRTUAL_USERS=1800
	TIMEOUT_MS=3000
	WARMUP_DURATION_SEC=240
	WARMUP_RPS=10
	WARMUP_PAUSE_SEC=10
	LOAD_GENERATOR_LOC="$HOME/load_generator"

	# Copy load generator .jar, if not exists
	JAR_NAME="httploadgenerator.jar"
	if [ ! -f "$PWD/$JAR_NAME" ]; then
		if [ ! -f "$LOAD_GENERATOR_LOC/$JAR_NAME" ]; then
			printf "expected load generator jar at %s\n" "$LOAD_GENERATOR_LOC/$JAR_NAME" 1>&2
			exit 1
		fi
		cp "$LOAD_GENERATOR_LOC/$JAR_NAME" "$PWD/$JAR_NAME"
	fi

	START_TIME=$(date +%s)
	MEASURMENTS_DIR="$HOME/test-data/benchmark-$START_TIME/teastore"
	mkdir -p "$MEASURMENTS_DIR"
	VOLUME_NAME="prometheus-data-$START_TIME"

	# Create docker volume if it does not exist"
	ssh "$USER"@"$SERVER_IP" '
docker volume create '"$VOLUME_NAME"' >/dev/null
cd $HOME/monitorless/applications/teastore
echo MG_PROMETHEUS_VOLUME_NAME='"$VOLUME_NAME"' > .env
'

	for t in "${BENCHMARKS[@]}"; do
		SCRIPT_PATH=$(dirname -- "${BASH_SOURCE[0]}")
		SCRIPT_PATH=$(readlink -f -- "${SCRIPT_PATH}")
		cd "${SCRIPT_PATH}" || exit 1

		DIR_NAME="$t"
		RUN_DIR="$MEASURMENTS_DIR/$DIR_NAME"

		if [ -d "$RUN_DIR" ]; then
			TS=$(date +%s)
			BACKUP="$RUN_DIR-bck-$TS"
			printf "directory %s already exists! Backing up to %s!\n" "$RUN_DIR" "$BACKUP"
			mv "$RUN_DIR" "$BACKUP"
		fi
		mkdir -p "$RUN_DIR"

		PROFILE="$PWD/$t.csv"
		BENCHMARK_DURATION=$(wc -l <"$PROFILE")
		BENCHMARK_DURATION=$(echo "$BENCHMARK_DURATION" | xargs)
		WORKLOAD_FILE="$PWD/workload.yml"
		CONFIG_FILE="$RUN_DIR/config.yml"
		printf "Saving benchmark configuration to %s\n" "$CONFIG_FILE" 1>&2
		touch "$CONFIG_FILE"
		printf "profile: %s\n" "$PROFILE" >"$CONFIG_FILE"
		{
			printf "server_ip: %s\n" "$SERVER_IP"
			printf "duration: %d\n" "$BENCHMARK_DURATION"
			printf "threads: %d\n" "256"
			printf "virtual_users: %d\n" "$VIRTUAL_USERS"
			printf "timeout: %d\n" "$TIMEOUT_MS"
			printf "warmup_duration: %d\n" "$WARMUP_DURATION_SEC"
			printf "warmup_rps: %d\n" "$WARMUP_RPS"
			printf "warmup_pause: %d\n" "$WARMUP_PAUSE_SEC"
			printf "workload: %s\n" "$WORKLOAD_FILE"
		} >>"$CONFIG_FILE"

		printf "Starting TeaStore server on %s\n" "$SERVER_IP"
		bash remote_docker.sh \
			--ip="$SERVER_IP" \
			--user="$USER" \
			--cmd="up"
		ready=0
		printf "Waiting for TeaStore...\n"
		until [ "$ready" -eq 1 ]; do
			ready_count=$(curl --silent "$SERVER_IP:8080/tools.descartes.teastore.webui/status" | grep "OK" -c)
			printf "%s/4\n" "$ready_count"
			if [ "$ready_count" -eq 4 ]; then
				ready=1
			fi
			sleep 5
		done
		YAML_FILE=$(mktemp)
		sed -e 's/{{APPLICATION_HOST}}/'"$SERVER_IP"':8080/g' "$WORKLOAD_FILE" >"$YAML_FILE"
		YAML_PATH="$YAML_FILE" \
			BENCHMARK_RUN="$RUN_DIR" \
			PROFILE="$PWD/linear120.csv" \
			DIRECTOR_THREADS="256" \
			VIRTUAL_USERS="$VIRTUAL_USERS" \
			TIMEOUT="$TIMEOUT_MS" \
			WARMUP_DURATION="0" \
			WARMUP_RPS="0" \
			WARMUP_PAUSE="0" \
			docker compose up \
			--build --abort-on-container-exit --force-recreate
		rm "$RUN_DIR/summary_out.csv"
		rm "$RUN_DIR/request_out.csv"

		YAML_PATH="$YAML_FILE" \
			BENCHMARK_RUN="$RUN_DIR" \
			PROFILE="$PROFILE" \
			DIRECTOR_THREADS="256" \
			VIRTUAL_USERS="$VIRTUAL_USERS" \
			TIMEOUT="$TIMEOUT_MS" \
			WARMUP_DURATION="0" \
			WARMUP_RPS="0" \
			WARMUP_PAUSE="0" \
			docker compose up \
			--build --abort-on-container-exit --force-recreate

		bash remote_docker.sh \
			--ip="$SERVER_IP" \
			--user="$USER" \
			--cmd="down"

		rm "$YAML_FILE"
	done

	ssh "$USER"@"$SERVER_IP" 'rm /tmp/metrics.tar.gz 2>/dev/null
docker run \
	--rm \
	--volume /tmp:/backup \
	--volume '"$VOLUME_NAME"':/data \
	--user 65534:65534 \
	busybox \
	tar -czf /backup/metrics.tar.gz /data/
rm $HOME/monitorless/applications/teastore/.env
docker volume rm '"$VOLUME_NAME"''
	scp "$USER"@"$SERVER_IP":/tmp/metrics.tar.gz "$MEASURMENTS_DIR/metrics.tar.gz"
)
