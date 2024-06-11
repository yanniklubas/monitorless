"""Module constants defines various constants, such as column names."""

BYTE_COLUMNS: set[str] = {
    "container_blkio_device_usage_total",
    "container_fs_usage_bytes",
    "container_memory_cache",
    "container_fs_reads_bytes_total",
    "container_fs_writes_bytes_total",
    "container_network_receive_bytes_total",
    "container_network_transmit_bytes_total",
    "container_memory_mapped_file",
}

LIMIT_COLUMNS: dict[str, str] = {
    "container_cpu_system_seconds_total": "container_spec_cpu_quota",
    "container_cpu_usage_seconds_total": "container_spec_cpu_quota",
    "container_cpu_user_seconds_total": "container_spec_cpu_quota",
    "container_memory_rss": "container_spec_memory_limit_bytes",
    "container_memory_usage_bytes": "container_spec_memory_limit_bytes",
    "container_memory_working_set_bytes": "container_spec_memory_limit_bytes",
}

UNLIMITTED_COLUMNS: set[str] = {
    "container_cpu_cfs_periods_total",
    "container_cpu_cfs_throttled_periods_total",
    "container_cpu_cfs_throttled_seconds_total",
    "container_fs_inodes_total",
    "container_fs_io_current",
    "container_fs_io_time_seconds_total",
    "container_fs_io_time_weighted_seconds_total",
    "container_fs_read_seconds_total",
    "container_fs_reads_total",
    "container_fs_sector_reads_total",
    "container_fs_sector_writes_total",
    "container_fs_write_seconds_total",
    "container_fs_writes_total",
    "container_memory_failures_total",
    "container_network_receive_packets_total",
    "container_network_transmit_packets_total",
    "container_network_receive_packets_dropped_total",
}

BINARY_FEATURES: dict[str, tuple[str, float, float]] = {
    "memory_low": ("container_memory_usage_bytes", -0.1, 0.5),
    "memory_medium": ("container_memory_usage_bytes", 0.5, 0.8),
    "memory_high": ("container_memory_usage_bytes", 0.8, 1.0),
    "cpu_low": ("container_cpu_usage_seconds_total", -0.1, 0.5),
    "cpu_medium": ("container_cpu_usage_seconds_total", 0.5, 0.8),
    "cpu_high": ("container_cpu_usage_seconds_total", 0.8, 0.9),
    "cpu_very_high": ("container_cpu_usage_seconds_total", 0.9, 0.95),
    "cpu_extreme": ("container_cpu_usage_seconds_total", 0.95, 1.0),
}

POTENTIALLY_NAN_COLUMNS: set[str] = {
    "container_start_time_seconds",
    "container_spec_cpu_shares",
    "container_fs_reads_bytes_total",
    "container_cpu_cfs_throttled_seconds_total",
    "container_cpu_cfs_throttled_periods_total",
    "container_spec_memory_swap_limit_bytes",
    "container_blkio_device_usage_total",
    "container_spec_memory_reservation_limit_bytes",
    "container_spec_cpu_period",
    "container_fs_writes_bytes_total",
    "container_cpu_cfs_periods_total",
}

LABEL_COLUMN: str = "label"
