"""Module preprocess implements preprocessing operations, such as scaling and filtering."""

from typing import Optional
import math
from monitorless import constants as c
from monitorless import logging
import itertools as it
import numpy as np
import pandas as pd
import pathlib

from sklearn import preprocessing as sk_pre
from sklearn import ensemble

_RANDOM_STATE: int = 7
DATASET_PATH: pathlib.Path = pathlib.Path("data/dataset.parquet")
MAX_CPUS: int = 16
MIN_CPUS: int = 1
MEMORY_BYTES: int = 35_000 * 10 * 6


log = logging.get_logger("monitorless")


def preprocess(data: pd.DataFrame, n_features: int, label_column: str) -> list[str]:
    """Apply the preprocessing pipeline to the given data.

    Returns the top `n_features` features.
    """
    for column in c.POTENTIALLY_NAN_COLUMNS:
        data[column] = data.get(column, default=0)
    if "Unnamed: 0" in data.columns:
        log.debug('Dropping "Unnamed: 0" column from data')
        data = data.drop(columns=["Unnamed: 0"])

    log.debug("DataFrame Shape: rows: %d, cols: %d", data.shape[0], data.shape[1])
    # Scaling
    data = normalize(
        data=data, max_cpus=MAX_CPUS, min_cpus=MIN_CPUS, memory_bytes=MEMORY_BYTES
    )
    data = log_scale(data=data)
    data = normalize_standard(data=data)

    # Add features
    data = add_binary_features(data=data)
    features = [col for col in map(str, data.columns) if is_feature_column(col)]
    data = add_time_dependent_features(data=data, features=features)
    data = add_feature_combinations(data=data, features=features)

    # Filter
    features = {
        col
        for col in map(str, data.columns)
        if is_feature_column(col) or is_time_or_combination_column(col)
    }
    top_features = random_forst_filter(
        data=data,
        features=list(features),
        n_features=n_features,
        label_column=label_column,
    )
    log.debug("Top Features(%d): %s", len(top_features), top_features)
    return top_features


def normalize(
    data: pd.DataFrame,
    max_cpus: int,
    min_cpus: int,
    memory_bytes: int,
    columns: dict[str, str] = c.LIMIT_COLUMNS,
) -> pd.DataFrame:
    """Normalizes all columns with a known limit."""
    cols = set(columns.keys()).intersection(map(str, data.columns))

    cpu_quota_column: str = "container_spec_cpu_quota"
    memory_limit_column: str = "container_spec_memory_limit_bytes"

    assert (
        data[cpu_quota_column] >= min_cpus
    ).all(), f"expected CPU quotas to be greater than or equal to {min_cpus}"
    assert (
        data[cpu_quota_column] <= max_cpus
    ).all(), f"expected CPU quotas to less than or equal to {max_cpus}"
    assert not (
        data[memory_limit_column] == 0
    ).any(), "expected memory limit to be greater than 0"
    assert (
        data[memory_limit_column] <= memory_bytes
    ).all(), f"expected memory limit to be less than or equal to {memory_bytes}"
    for col in cols:
        data[col] = data[col] / data[columns[col]]
        assert (
            data[col] >= 0
        ).all(), f"invalid minimum values for `{col}` after scaling"
        assert (
            data[col] <= 1.0
        ).all(), f"invalid maximum values for `{col}` after scaling"
    return data


def log_scale(
    data: pd.DataFrame,
    columns: set[str] = c.BYTE_COLUMNS,
) -> pd.DataFrame:
    """Log scale all columns with values measured in bytes."""

    cols = list(columns.intersection(map(str, data.columns)))

    data[cols] = data[cols].replace(0, 1)
    data[cols] = np.log2(data[cols])
    return data


def normalize_standard(
    data: pd.DataFrame,
    columns: set[str] = c.UNLIMITTED_COLUMNS,
) -> pd.DataFrame:
    """Normalize all columns with an unknown limit using a standard scaler."""
    cols = list(columns.intersection(map(str, data.columns)))

    scaler = sk_pre.StandardScaler()
    data.loc[:, cols] = scaler.fit_transform(data.loc[:, cols].values)
    return data


def add_binary_features(
    data: pd.DataFrame, columns: dict[str, tuple[str, float, float]] = c.BINARY_FEATURES
) -> pd.DataFrame:
    """Add binary features for CPU and memory."""
    data[columns] = pd.to_numeric(0, downcast="unsigned")

    for feature, (col, lower, upper) in columns.items():
        data.loc[(data[col] > lower & data[col] <= upper), feature] = 1
    return data


def add_time_dependent_features(
    data: pd.DataFrame,
    features: list[str],
    steps: Optional[list[int]] = None,
) -> pd.DataFrame:
    """Add time dependent features for the given sample steps."""

    if steps is None:
        steps = [1, 3, 15]
    for step in steps:
        data = pd.concat(
            [
                data,
                data[features]
                .rolling(window=step + 1)
                .mean()
                .rename(lambda col: f"{step}_avg_{col}", axis="columns")
                .fillna(value=0),
                data[features]
                .shift(periods=step, fill_value=0)
                .rename(lambda col: f"{step}_lag_{col}", axis="columns"),
            ],
            axis="columns",
        )

    return data


def add_feature_combinations(
    data: pd.DataFrame,
    features: list[str],
    domains: Optional[list[str]] = None,
) -> pd.DataFrame:
    """Add all feature combinations across domains."""
    if domains is None:
        domains = [
            "container_cpu",
            "container_fs",
            "container_memory",
            "container_network",
        ]
    cols = [
        col for col in features if any([col.startswith(domain) for domain in domains])
    ]
    pairs = it.combinations(cols, 2)
    # Remove combinations from the same domain
    for domain in domains:
        pairs = list(
            filter(
                lambda pair: not (
                    pair[0].startswith(domain) and pair[1].startswith(domain)
                ),
                pairs,
            )
        )
    products = math.prod(data[[*pair]].to_numpy() for pair in zip(*pairs))
    pair_columns = ["X".join(pair) for pair in pairs]
    data = pd.concat(
        [
            data.reset_index(drop=True),
            pd.DataFrame(products, columns=pd.Index(pair_columns, dtype="str")),
        ],
        axis="columns",
    )
    return data


def random_forst_filter(
    data: pd.DataFrame, features: list[str], n_features: int, label_column: str
) -> list[str]:
    """Filter the most `n_featues` important features using a random forest clasifier."""
    filter = ensemble.RandomForestClassifier(random_state=_RANDOM_STATE)

    filter.fit(data.loc[:, features], data.loc[:, label_column])

    feature_importances = {
        feature: importance
        for feature, importance in zip(
            filter.feature_names_in_, filter.feature_importances_
        )
    }
    ranks = dict(
        sorted(feature_importances.items(), key=lambda item: item[1], reverse=True)
    )
    return list(ranks.keys())[:n_features]


def is_feature_column(column: str) -> bool:
    """Asserts the given column is a feature column."""
    return (
        column.startswith("container")
        or (column.find("low") != -1)
        or (column.find("medium") != -1)
        or (column.find("high") != -1)
        or (column.find("extreme") != -1)
    )


def is_time_or_combination_column(column: str) -> bool:
    """Asserts the given column is a time or combination feature column."""
    return (
        column.find("_avg_") != -1
        or column.find("_lag_") != -1
        or column.find("X") != -1
    )
