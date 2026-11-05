#!/usr/bin/env python3
"""Compare measured app chrome from the same binary on macOS 26 and 27."""
import argparse
import json
from pathlib import Path


def compare(root):
    captures = sorted(Path(root).glob("*/appearance-metrics.json"))
    if len(captures) != 2:
        raise ValueError("Expected captures from exactly two macOS versions")
    first, second = [json.loads(path.read_text()) for path in captures]
    expected = {theme + "-" + page for theme in ["light", "dark"]
                for page in ["metrics", "thermal", "sensors", "optimization", "electricity", "metric", "settings", "popover"]}
    if set(first) != expected or set(second) != expected:
        raise ValueError("Incomplete light/dark layout captures")
    for name in sorted(expected):
        a, b = first[name], second[name]
        for field in ["width", "height", "sidebarWidth", "sidebarHeight", "sidebarTop", "settingsTop"]:
            x,y=a.get(field),b.get(field)
            if (x is None or y is None) and (field in ["width", "height"] or not name.endswith("popover")):
                raise ValueError(f"Missing layout measurement: {name}/{field}")
            if x != y:
                raise ValueError(f"Layout drift in {name}/{field}: {x} vs {y}")
        for field in ["selectedColor", "sidebarColor", "contentTopColor"]:
            x,y=a.get(field),b.get(field)
            if x is None and y is None:
                if not name.endswith("popover"):
                    raise ValueError(f"Missing chrome measurement: {name}/{field}")
                continue
            if x is None or y is None or len(x) != 4 or len(y) != 4:
                raise ValueError(f"Missing color measurement: {name}/{field}")
            if any(abs(left - right) > 3 for left, right in zip(x,y)):
                raise ValueError(f"Color drift in {name}/{field}: {x} vs {y}")
    return len(expected)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    print(f"PASS: {compare(args.directory)} cross-version layouts retain geometry and measured sidebar/selection colors")
