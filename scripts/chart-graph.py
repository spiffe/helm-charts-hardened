#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

from ruamel.yaml import YAML


yaml = YAML(typ="safe")


@dataclass(frozen=True)
class Dependency:
    name: str
    repository: str


@dataclass(frozen=True)
class Chart:
    name: str
    path: Path
    dependencies: tuple[Dependency, ...]


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments for the root chart lookup."""
    parser = argparse.ArgumentParser(
        description="Print charts that depend on a given root chart."
    )
    parser.add_argument(
        "--chart",
        required=True,
        help="Chart name whose dependent chart closure should be printed.",
    )
    parser.add_argument(
        "--charts-root",
        default="charts",
        help="Path to the charts root directory (default: charts)",
    )
    parser.add_argument(
        "--output",
        choices=("names", "print-graph"),
        default="names",
        help="Output format (default: names).",
    )
    return parser.parse_args()


def main() -> int:
    """Execute the dependent-chart lookup and print the selected output format."""
    args = parse_args()
    charts_root = Path(args.charts_root).resolve()
    charts = discover_charts(charts_root)

    if args.chart not in charts:
        print(f"Unknown chart: {args.chart}", file=sys.stderr)
        return 1

    reverse_dependencies = build_reverse_dependencies(charts)
    dependents = find_dependents(args.chart, reverse_dependencies)

    if args.output == "print-graph":
        print(f"Dependents of {args.chart}:")
        if not dependents:
            print("  (none)")
        else:
            for dependent in dependents:
                relpath = charts[dependent].path.relative_to(charts_root.parent)
                print(f"  {dependent} [{relpath}]")
    else:
        for dependent in dependents:
            print(dependent)

    return 0


def parse_chart_yaml(chart_yaml: Path) -> Chart:
    """Read one Chart.yaml file into the lightweight Chart structure."""
    with chart_yaml.open() as fp:
        data = yaml.load(fp)

    if not isinstance(data, dict) or "name" not in data:
        raise ValueError(f"Could not find chart name in {chart_yaml}")

    dependencies: list[Dependency] = []
    for dependency in data.get("dependencies", []) or []:
        if not isinstance(dependency, dict) or "name" not in dependency:
            continue
        dependencies.append(
            Dependency(
                name=str(dependency["name"]),
                repository=str(dependency.get("repository", "")),
            )
        )

    return Chart(
        name=str(data["name"]),
        path=chart_yaml.parent.resolve(),
        dependencies=tuple(dependencies),
    )


def discover_charts(charts_root: Path) -> dict[str, Chart]:
    """Discover every chart under the charts root and index them by chart name."""
    charts: dict[str, Chart] = {}
    for chart_yaml in sorted(charts_root.rglob("Chart.yaml")):
        chart = parse_chart_yaml(chart_yaml)
        if chart.name in charts:
            raise ValueError(f"Duplicate chart name detected: {chart.name}")
        charts[chart.name] = chart
    return charts


def resolve_local_dependency(
    source_chart: Chart, dependency: Dependency, charts: dict[str, Chart]
) -> str | None:
    """Resolve a file:// dependency reference back to a known local chart name."""
    if not dependency.repository.startswith("file://"):
        return None

    dependency_path = (
        source_chart.path / dependency.repository.removeprefix("file://")
    ).resolve()
    chart_yaml = dependency_path / "Chart.yaml"
    if not chart_yaml.exists():
        return None

    for chart_name, chart in charts.items():
        if chart.path == dependency_path:
            return chart_name
    return None


def build_reverse_dependencies(charts: dict[str, Chart]) -> dict[str, set[str]]:
    """Build a reverse dependency index for walking from a chart to its dependents."""
    reverse_dependencies: dict[str, set[str]] = {
        chart_name: set() for chart_name in charts
    }

    for chart_name, chart in charts.items():
        for dependency in chart.dependencies:
            dependency_name = resolve_local_dependency(chart, dependency, charts)
            if dependency_name is not None:
                reverse_dependencies[dependency_name].add(chart_name)

    return reverse_dependencies


def find_dependents(root_chart: str, reverse_dependencies: dict[str, set[str]]) -> list[str]:
    """Traverse the reverse dependency graph and fail fast on reachable cycles."""
    dependents: list[str] = []
    visited: set[str] = set()
    on_stack: set[str] = {root_chart}
    stack: list[tuple[str, list[str]]] = [
        (root_chart, sorted(reverse_dependencies[root_chart]))
    ]

    while stack:
        current, children = stack[-1]
        if not children:
            on_stack.remove(current)
            stack.pop()
            continue

        child = children.pop(0)
        if child in on_stack:
            cycle = " -> ".join([item[0] for item in stack] + [child])
            raise ValueError(f"Dependency cycle detected: {cycle}")
        if child in visited:
            continue

        visited.add(child)
        dependents.append(child)
        on_stack.add(child)
        stack.append((child, sorted(reverse_dependencies[child])))

    return dependents


if __name__ == "__main__":
    sys.exit(main())
