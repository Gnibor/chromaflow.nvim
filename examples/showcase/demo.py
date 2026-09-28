"""ChromaFlow showcase: compact Python / Tree-sitter / LSP inspection surface."""

from __future__ import annotations

import math
from enum import Enum
from pathlib import Path
from typing import ClassVar, Final


# LSP-dependent: readonly / variable (pyright may mark Final differently by version)
READONLY_CONSTANT: Final[int] = 42
module_variable = "module"


class DemoKind(Enum):
    ZERO = 0
    ONE = 1


def decorate(function):
    """Decorator and documentation capture."""
    return function


class DemoRecord:
    # LSP-dependent: static / property
    category: ClassVar[str] = "showcase"

    def __init__(self, name: str, count: int = 0) -> None:
        self.name = name
        self.count = count

    @property
    def label(self) -> str:
        """Read-only property syntax; no LSP modifier is assumed here."""
        return f"{self.name}:{self.count}"

    @staticmethod
    def static_method(value: int) -> int:
        # LSP-dependent: static / method
        return value * 2

    @decorate
    def method(self, amount: int) -> int:
        self.count += amount
        return self.count


# LSP-dependent: definition / function
def function(parameter: str, /, *, enabled: bool = True) -> str:
    local_value = parameter.upper() if enabled else parameter.lower()
    return local_value


# LSP-dependent: async / function
async def async_function(path: Path) -> list[str]:
    return [part for part in path.parts if part]


def basics() -> None:
    record = DemoRecord("demo", READONLY_CONSTANT)
    # LSP-dependent: defaultLibrary / function
    size = len(record.label)
    # LSP-dependent: defaultLibrary / function
    rounded = round(math.pi, 3)
    text = "quoted"
    formatted = f"{text} {size} {rounded}"
    number = 0x2A + 1.5e2

    try:
        if number > 0 and DemoKind.ONE is not DemoKind.ZERO:
            print(function(formatted))  # LSP-dependent: defaultLibrary / function
    except ValueError as error:
        print(error)

    record.method(DemoRecord.static_method(1))
