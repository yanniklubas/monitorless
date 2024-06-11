import copy as cp
import logging
import sys
import typing


class ColoredFormatter(logging.Formatter):
    _COLOR_MAP: typing.Mapping[str, int] = {
        "DEBUG": 37,  # white text
        "INFO": 36,  # cyan text
        "WARNING": 33,  # yellow text
        "ERROR": 31,  # red text
        "CRITICAL": 41,  # white text on red background
    }
    _PREFIX = "\033["
    _SUFFIX = "\033[0m"

    def format(self, record: logging.LogRecord) -> str:
        colored_record = cp.copy(record)
        levelname = colored_record.levelname
        color = self._COLOR_MAP.get(levelname, 37)
        colored_levelname = f"{self._PREFIX}{color}m{levelname}{self._SUFFIX}"
        colored_record.levelname = colored_levelname
        return logging.Formatter.format(self, colored_record)


def get_logger(name: str) -> logging.Logger:
    logger = logging.getLogger(name=name)
    stream_handler = logging.StreamHandler(stream=sys.stdout)
    fmt = ColoredFormatter(fmt="[%(levelname)s] %(message)s")
    stream_handler.setFormatter(fmt=fmt)
    logger.addHandler(stream_handler)
    return logger
