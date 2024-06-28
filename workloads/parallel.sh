#!/usr/bin/env bash
set -eou pipefail

SERVER_IP="10.128.0.5"
# Tuple format
# Solr: Number, CPU, Memory, Profile
# Cassandra: Number, CPU, Memory, Workload, Min-RPS, Max-RPS
# Memcached: Number, CPU, Memory, Min-RPS, Max-RPS
BENCHMARKS=(
	"solr 3 8 8g sinnoise1000.csv"            # 3
	"cassandra 14 6 28 workloada 15000 25000" # 14
	"solr 4 8 8g sinnoise1000.csv"            # 4
	"cassandra 15 6 28 workloadb 10000 15000" # 15
	"solr 5 3 8g sinnoise1000.csv"            # 5
	"cassandra 16 6 28 workloadd 10000 25000" # 16
	"solr 6 1.5 8g sinnoise1000.csv"          # 6
	"cassandra 17 6 28 workloadb 5000 20000"  # 17
	"memcached 10 8 4096 10000 65000"         # 10
	"cassandra 18 6 28 workloadb 10000 10000" # 18
)
DURATION_SEC=600
VIRTUAL_USERS=3000
TIMEOUT_MS=3000
WARMUP_DURATION_SEC=120
WARMUP_RPS=25
WARMUP_PAUSE_SEC=10
LOAD_GENERATOR_LOC="$HOME/load_generator"
SEED="1"
RECORD_COUNT="10000000"
STEP_DURATION="30"
PORT=11211

#+++++++++++++++++++++++++++
#++++ CONFIGURATION END ++++
#+++++++++++++++++++++++++++

# Download dataset if the web_search_data container does not exist
printf "Checking for solr dataset...\n" >&2
ssh "$USER"@"$SERVER_IP" '[ ! "$(docker ps -a | grep "web_search_dataset")" ] && docker run --name web_search_dataset cloudsuite/web-search:dataset || exit 0'

# Copy load generator .jar, if not exists
printf "Checking for load generator...\n" >&2
JAR_NAME="httploadgenerator.jar"
if [ ! -f "$PWD/solr/$JAR_NAME" ]; then
	if [ ! -f "$LOAD_GENERATOR_LOC/$JAR_NAME" ]; then
		printf "expected load generator jar at %s\n" "$LOAD_GENERATOR_LOC/$JAR_NAME" 1>&2
		exit 1
	fi
	cp "$LOAD_GENERATOR_LOC/$JAR_NAME" "$PWD/solr/$JAR_NAME"
fi

printf "Creating volumes...\n" >&2

START_TIME=$(date +%s)
MEASURMENTS_DIR="$1"
mkdir -p "$MEASURMENTS_DIR"
SOLR_VOLUME_NAME="solr-prometheus-data-$START_TIME"
CASSANDRA_VOLUME_NAME="cassandra-prometheus-data-$START_TIME"
MEMCACHED_VOLUME_NAME="memcached-prometheus-data-$START_TIME"

# Create docker volume if it does not exist"
ssh "$USER"@"$SERVER_IP" '
docker volume create '"$SOLR_VOLUME_NAME"' >/dev/null
docker volume create '"$MEMCACHED_VOLUME_NAME"' >/dev/null
docker volume create '"$CASSANDRA_VOLUME_NAME"' >/dev/null
cd $HOME/monitorless/applications/solr
echo MG_PROMETHEUS_VOLUME_NAME='"$SOLR_VOLUME_NAME"' > .env
cd $HOME/monitorless/applications/memcached
echo MG_PROMETHEUS_VOLUME_NAME='"$MEMCACHED_VOLUME_NAME"' > .env
cd $HOME/monitorless/applications/cassandra
echo MG_PROMETHEUS_VOLUME_NAME='"$CASSANDRA_VOLUME_NAME"' > .env
'

printf "Created volumes!\n" >&2

remote_docker() {
	local file="$1/remote_docker.sh"
	local cpus="$2"
	local memory="$3"
	local cmd="$4"
	bash "$file" \
		--ip="$SERVER_IP" \
		--user="$USER" \
		--cpus="$cpus" \
		--memory="$memory" \
		--cmd="$cmd"
}

warmup() {
	local name="$1"
	case "$name" in
	"solr")
		(
			cd "solr"
			bash query.sh "$SERVER_IP"
			WORKLOAD_FILE="$PWD/workload.yml"
			YAML_FILE="$PWD/parsed.yml"
			sed -e 's/{{APPLICATION_HOST}}/'"$SERVER_IP"':8983/g' "$WORKLOAD_FILE" >"$YAML_FILE"
			# TODO
			YAML_PATH="$YAML_FILE" \
				BENCHMARK_RUN="/tmp" \
				PROFILE="$PWD/noop.csv" \
				BENCHMARK_DURATION="0" \
				DIRECTOR_THREADS="256" \
				VIRTUAL_USERS="$VIRTUAL_USERS" \
				TIMEOUT="$TIMEOUT_MS" \
				WARMUP_DURATION="$WARMUP_DURATION_SEC" \
				WARMUP_RPS="$WARMUP_RPS" \
				WARMUP_PAUSE="$WARMUP_PAUSE_SEC" \
				docker compose up \
				--build --abort-on-container-exit --force-recreate
			rm "$YAML_FILE"
		)
		;;
	"cassandra")
		(
			cd "cassandra"
			if [ "$SEED" -eq 1 ]; then
				printf "Seeding cassandra...\n" >&2
				DO_SEED=1 \
					WORKLOAD="workloada" \
					SERVER_IP="$SERVER_IP" \
					RECORD_COUNT="$RECORD_COUNT" \
					docker compose up --force-recreate --build
			fi
			DO_SEED=0 \
				SERVER_IP="$SERVER_IP" \
				RECORD_COUNT="$RECORD_COUNT" \
				WARMUP_DURATION="$WARMUP_DURATION_SEC" \
				WARMUP_RPS="100" \
				WARMUP_PAUSE="$WARMUP_PAUSE_SEC" \
				MINIMUM_RPS="0" \
				MAXIMUM_RPS="0" \
				BENCHMARK_DURATION="0" \
				STEP_DURATION="0" \
				WORKLOAD="workloada" \
				docker compose up \
				--force-recreate --build
		)
		;;
	"memcached")
		(
			cd "memcached"
			local servers_file="$PWD/tmp_servers.txt"
			local memory="$2"
			printf "%s, %d\n" "$SERVER_IP" "$PORT" >"$servers_file"
			SERVERS_FILE="$servers_file" \
				SERVER_MEMORY="$memory" \
				MINIMUM_RPS="0" \
				MAXIMUM_RPS="0" \
				BENCHMARK_DURATION="0" \
				STEP_DURATION="0" \
				docker compose up \
				--force-recreate --build

			rm "$servers_file"
		)
		;;
	esac
}

save_config() {
	local run_dir="$1"
	local config_file="$run_dir/config.yml"
	local name="$2"
	case "$name" in
	"solr")
		local cpu="$4"
		local memory="$5"
		local profile="$6"
		printf "profile: %s\n" "$profile" >"$config_file"
		{
			printf "cpus: %d\n" "$cpu"
			printf "memory: %s\n" "$memory"
			printf "server_ip: %s\n" "$SERVER_IP"
			printf "duration: %d\n" "$DURATION_SEC"
			printf "threads: %d\n" "256"
			printf "virtual_users: %d\n" "$VIRTUAL_USERS"
			printf "timeout: %d\n" "$TIMEOUT_MS"
			printf "warmup_duration: %d\n" "$WARMUP_DURATION_SEC"
			printf "warmup_rps: %d\n" "$WARMUP_RPS"
			printf "warmup_pause: %d\n" "$WARMUP_PAUSE_SEC"
		} >>"$config_file"
		;;
	"cassandra")
		local cpu="$4"
		local memory="$5"
		local workload="$6"
		local min_rps="$7"
		local max_rps="$8"
		printf "workload: %s\n" "$workload" >"$config_file"
		{
			printf "cpus: %d\n" "$cpu"
			printf "memory: %s\n" "$memory"
			printf "server_ip: %s\n" "$SERVER_IP"
			printf "duration: %d\n" "$DURATION_SEC"
			printf "warmup_duration: %d\n" "$WARMUP_DURATION_SEC"
			printf "warmup_rps: %d\n" "100"
			printf "warmup_pause: %d\n" "$WARMUP_PAUSE_SEC"
			printf "minimum_rps: %d\n" "$min_rps"
			printf "maximum_rps: %d\n" "$max_rps"
			printf "step_duration: %d\n" "$STEP_DURATION"
		} >>"$config_file"
		;;
	"memcached")
		local cpu="$4"
		local memory="$5"
		local min_rps="$6"
		local max_rps="$7"
		printf "cpus: %d\n" "$cpu" >"$config_file"
		{
			printf "memory: %s\n" "$memory"
			printf "server_ip: %s\n" "$SERVER_IP"
			printf "duration: %d\n" "$DURATION_SEC"
			printf "minimum_rps: %d\n" "$min_rps"
			printf "maximum_rps: %d\n" "$max_rps"
			printf "step_duration: %d\n" "$STEP_DURATION"
		} >>"$config_file"
		;;
	esac
}

start_workload() {
	local name="$1"
	local run_dir="$2"
	case "$name" in
	"solr")
		(
			cd "solr"
			local profile="$PWD/$3"
			WORKLOAD_FILE="$PWD/workload.yml"
			YAML_FILE="$PWD/parsed.yml"
			sed -e 's/{{APPLICATION_HOST}}/'"$SERVER_IP"':8983/g' "$WORKLOAD_FILE" >"$YAML_FILE"
			YAML_PATH="$YAML_FILE" \
				BENCHMARK_RUN="$run_dir" \
				PROFILE="$profile" \
				BENCHMARK_DURATION="$DURATION_SEC" \
				DIRECTOR_THREADS="256" \
				VIRTUAL_USERS="$VIRTUAL_USERS" \
				TIMEOUT="$TIMEOUT_MS" \
				WARMUP_DURATION="0" \
				WARMUP_RPS="0" \
				WARMUP_PAUSE="0" \
				docker compose up \
				--build --abort-on-container-exit --force-recreate
			rm "$YAML_FILE"
		)
		;;
	"cassandra")
		(
			cd "cassandra"
			local workload="$3"
			local min_rps="$4"
			local max_rps="$5"
			DO_SEED=0 \
				SERVER_IP="$SERVER_IP" \
				RECORD_COUNT="$RECORD_COUNT" \
				WARMUP_DURATION="0" \
				WARMUP_RPS="0" \
				WARMUP_PAUSE="0" \
				MINIMUM_RPS="$min_rps" \
				MAXIMUM_RPS="$max_rps" \
				BENCHMARK_DURATION="$DURATION_SEC" \
				STEP_DURATION="$STEP_DURATION" \
				WORKLOAD="$workload" \
				docker compose up \
				--force-recreate --build

			DO_SEED=0 \
				SERVER_IP="$SERVER_IP" \
				RECORD_COUNT="$RECORD_COUNT" \
				WARMUP_DURATION="0" \
				WARMUP_PAUSE="0" \
				MINIMUM_RPS="$min_rps" \
				MAXIMUM_RPS="$max_rps" \
				BENCHMARK_DURATION="$DURATION_SEC" \
				STEP_DURATION="$STEP_DURATION" \
				WORKLOAD="$workload" \
				docker compose logs --no-log-prefix cassandra-client >"$run_dir/summary.log"
		)
		;;
	"memcached")
		(
			cd "memcached"
			local min_rps="$3"
			local max_rps="$4"
			local memory="$5"
			local servers_file="$PWD/tmp_servers.txt"
			printf "%s, %d\n" "$SERVER_IP" "$PORT" >"$servers_file"
			SERVERS_FILE="$servers_file" \
				SERVER_MEMORY="$memory" \
				MINIMUM_RPS="$min_rps" \
				MAXIMUM_RPS="$max_rps" \
				BENCHMARK_DURATION="$DURATION_SEC" \
				STEP_DURATION="$STEP_DURATION" \
				NO_WARMUP=1 \
				docker compose up \
				--force-recreate --build

			SERVERS_FILE="$servers_file" \
				SERVER_MEMORY="$memory" \
				MINIMUM_RPS="$min_rps" \
				MAXIMUM_RPS="$max_rps" \
				BENCHMARK_DURATION="$DURATION_SEC" \
				STEP_DURATION="$STEP_DURATION" \
				docker compose logs --no-log-prefix memcached-client >"$run_dir/summary.log"
			rm "$servers_file"
		)
		;;
	esac
}

for ((i = 0; i < ${#BENCHMARKS[@]}; i += 2)); do
	t="${BENCHMARKS[i]}"
	oIFS="$IFS"
	IFS=' '
	read -ra RUN_1 <<<"$t"
	NAME_1="${RUN_1[0]}"
	NUMBER_1="${RUN_1[1]}"
	CPU_1="${RUN_1[2]}"
	MEMORY_1="${RUN_1[3]}"
	t="${BENCHMARKS[i + 1]}"
	read -ra RUN_2 <<<"$t"
	NAME_2="${RUN_2[0]}"
	NUMBER_2="${RUN_2[1]}"
	CPU_2="${RUN_2[2]}"
	MEMORY_2="${RUN_2[3]}"
	IFS="$oIFS"
	unset oIFS

	printf "Starting %s with %s CPUS and %s Memory...\n" "$NAME_1" "$CPU_1" "$MEMORY_1" >&2
	remote_docker "$NAME_1" "$CPU_1" "$MEMORY_1" "up"
	printf "Starting %s with %s CPUS and %s Memory...\n" "$NAME_2" "$CPU_2" "$MEMORY_2" >&2
	remote_docker "$NAME_2" "$CPU_2" "$MEMORY_2" "up"

	pids=()
	printf "Starting warmup for %s...\n" "$NAME_1" >&2
	warmup "$NAME_1" "$MEMORY_1" &
	pids+=("$!")
	printf "Starting warmup for %s...\n" "$NAME_2" >&2
	warmup "$NAME_2" "$MEMORY_2" &
	pids+=("$!")

	for pid in "${pids[@]}"; do
		wait "$pid"
	done

	if [ "$NAME_1" = "cassandra" ]; then
		SEED=0
	elif [ "$NAME_2" = "cassandra" ]; then
		SEED=0
	fi

	run_pids=()
	RUN_DIR_1="$MEASURMENTS_DIR/$NAME_1-$NUMBER_1"
	mkdir -p "$RUN_DIR_1"
	RUN_DIR_2="$MEASURMENTS_DIR/$NAME_2-$NUMBER_2"
	mkdir -p "$RUN_DIR_2"
	printf "Saving config for %s\n" "$NAME_1" >&2
	save_config "$RUN_DIR_1" "${RUN_1[@]}"
	printf "Saving config for %s\n" "$NAME_2" >&2
	save_config "$RUN_DIR_2" "${RUN_2[@]}"
	printf "Starting workload for %s\n" "$NAME_1" >&2
	start_workload "$NAME_1" "$RUN_DIR_1" "${RUN_1[@]:4}" "$MEMORY_1" &
	run_pids+=("$!")
	printf "Starting workload for %s\n" "$NAME_2" >&2
	start_workload "$NAME_2" "$RUN_DIR_2" "${RUN_2[@]:4}" "$MEMORY_2" &
	run_pids+=("$!")

	for pid in "${run_pids[@]}"; do
		printf "Waiting for %s\n" "$pid" >&2
		wait "$pid"
	done

	printf "Stopping application %s\n" "$NAME_1" >&2
	remote_docker "$NAME_1" "$CPU_1" "$MEMORY_1" "down"
	printf "Stopping application %s\n" "$NAME_2" >&2
	remote_docker "$NAME_2" "$CPU_2" "$MEMORY_2" "down"
done

ssh "$USER"@"$SERVER_IP" 'rm /tmp/solr_metrics.tar.gz 2>/dev/null
rm /tmp/cassandra_metrics.tar.gz 2>/dev/null
rm /tmp/memcached_metrics.tar.gz 2>/dev/null
docker run \
	--rm \
	--volume /tmp:/backup \
	--volume '"$SOLR_VOLUME_NAME"':/data \
	--user 65534:65534 \
	busybox \
	tar -czf /backup/solr_metrics.tar.gz /data/
docker run \
	--rm \
	--volume /tmp:/backup \
	--volume '"$CASSANDRA_VOLUME_NAME"':/data \
	--user 65534:65534 \
	busybox \
	tar -czf /backup/cassandra_metrics.tar.gz /data/
docker run \
	--rm \
	--volume /tmp:/backup \
	--volume '"$MEMCACHED_VOLUME_NAME"':/data \
	--user 65534:65534 \
	busybox \
	tar -czf /backup/memcached_metrics.tar.gz /data/
rm $HOME/monitorless/applications/solr/.env
rm $HOME/monitorless/applications/memcached/.env
rm $HOME/monitorless/applications/cassandra/.env
cd $HOME/monitorless/applications/cassandra
CPUS=1 docker compose down -v
docker volume rm '"$SOLR_VOLUME_NAME"'
docker volume rm '"$CASSANDRA_VOLUME_NAME"'
docker volume rm '"$MEMCACHED_VOLUME_NAME"''
scp "$USER"@"$SERVER_IP":/tmp/solr_metrics.tar.gz "$MEASURMENTS_DIR/solr_metrics.tar.gz"
scp "$USER"@"$SERVER_IP":/tmp/cassandra_metrics.tar.gz "$MEASURMENTS_DIR/cassandra_metrics.tar.gz"
scp "$USER"@"$SERVER_IP":/tmp/memcached_metrics.tar.gz "$MEASURMENTS_DIR/memcached_metrics.tar.gz"
