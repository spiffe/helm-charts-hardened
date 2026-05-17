#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Dependency:
    name: str
    repository: str
    alias: str | None = None


@dataclass(frozen=True)
class Chart:
    name: str
    path: Path
    dependencies: tuple[Dependency, ...]


def parse_chart_yaml(chart_yaml: Path) -> Chart:
    lines = chart_yaml.read_text().splitlines()
    chart_name: str | None = None
    dependencies: list[Dependency] = []
    in_dependencies = False
    current_dependency: dict[str, str] | None = None

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if not line.startswith(" "):
            if current_dependency is not None:
                dependencies.append(
                    Dependency(
                        name=current_dependency["name"],
                        repository=current_dependency.get("repository", ""),
                        alias=current_dependency.get("alias"),
                    )
                )
                current_dependency = None

            in_dependencies = stripped == "dependencies:"
            if chart_name is None and stripped.startswith("name:"):
                chart_name = stripped.split(":", 1)[1].strip().strip('"')
            continue

        if not in_dependencies:
            continue

        if line.startswith("  - "):
            if current_dependency is not None:
                dependencies.append(
                    Dependency(
                        name=current_dependency["name"],
                        repository=current_dependency.get("repository", ""),
                        alias=current_dependency.get("alias"),
                    )
                )
            current_dependency = {}
            item = stripped[2:].strip()
            if ":" in item:
                key, value = item.split(":", 1)
                current_dependency[key.strip()] = value.strip().strip('"')
            continue

        if current_dependency is None:
            continue

        if line.startswith("    ") and ":" in stripped:
            key, value = stripped.split(":", 1)
            current_dependency[key.strip()] = value.strip().strip('"')

    if current_dependency is not None:
        dependencies.append(
            Dependency(
                name=current_dependency["name"],
                repository=current_dependency.get("repository", ""),
                alias=current_dependency.get("alias"),
            )
        )

    if chart_name is None:
        raise ValueError(f"Could not find chart name in {chart_yaml}")

    return Chart(name=chart_name, path=chart_yaml.parent, dependencies=tuple(dependencies))


def discover_charts(charts_root: Path) -> dict[Path, Chart]:
    charts: dict[Path, Chart] = {}
    for chart_yaml in sorted(charts_root.rglob("Chart.yaml")):
        chart = parse_chart_yaml(chart_yaml)
        charts[chart.path.resolve()] = chart
    return charts


def resolve_local_dependency(source_chart: Chart, dependency: Dependency) -> Path | None:
    if not dependency.repository.startswith("file://"):
        return None
    dependency_path = (source_chart.path / dependency.repository.removeprefix("file://")).resolve()
    chart_yaml = dependency_path / "Chart.yaml"
    if chart_yaml.exists():
        return dependency_path
    return None


def build_graph(charts: dict[Path, Chart]) -> dict[Path, set[Path]]:
    graph: dict[Path, set[Path]] = {path: set() for path in charts}
    for chart_path, chart in charts.items():
        for dependency in chart.dependencies:
            dependency_path = resolve_local_dependency(chart, dependency)
            if dependency_path is not None and dependency_path in charts:
                graph[chart_path].add(dependency_path)
    return graph


def build_reverse_graph(graph: dict[Path, set[Path]]) -> dict[Path, set[Path]]:
    reverse_graph: dict[Path, set[Path]] = {path: set() for path in graph}
    for chart_path, dependency_paths in graph.items():
        for dependency_path in dependency_paths:
            reverse_graph[dependency_path].add(chart_path)
    return reverse_graph


def format_chart(chart: Chart, root: Path) -> str:
    relpath = chart.path.relative_to(root)
    return f"{chart.name} [{relpath}]"


def print_edges(charts: dict[Path, Chart], graph: dict[Path, set[Path]], root: Path) -> None:
    for chart_path in sorted(graph, key=lambda path: str(path.relative_to(root))):
        chart = charts[chart_path]
        print(format_chart(chart, root))
        for dependency_path in sorted(graph[chart_path], key=lambda path: str(path.relative_to(root))):
            dependency_chart = charts[dependency_path]
            print(f"  -> {format_chart(dependency_chart, root)}")


def find_cycles(graph: dict[Path, set[Path]]) -> list[list[Path]]:
    cycles: list[list[Path]] = []
    visited: set[Path] = set()
    stack: list[Path] = []
    on_stack: set[Path] = set()
    seen_cycles: set[tuple[Path, ...]] = set()

    def canonicalize_cycle(cycle: list[Path]) -> tuple[Path, ...]:
        body = cycle[:-1]
        rotations = [tuple(body[i:] + body[:i]) for i in range(len(body))]
        canonical = min(rotations, key=lambda items: [str(item) for item in items])
        return canonical

    def dfs(node: Path) -> None:
        visited.add(node)
        stack.append(node)
        on_stack.add(node)

        for neighbor in sorted(graph[node], key=str):
            if neighbor not in visited:
                dfs(neighbor)
                continue
            if neighbor not in on_stack:
                continue

            cycle_start = stack.index(neighbor)
            cycle = stack[cycle_start:] + [neighbor]
            cycle_key = canonicalize_cycle(cycle)
            if cycle_key not in seen_cycles:
                seen_cycles.add(cycle_key)
                cycles.append(cycle)

        stack.pop()
        on_stack.remove(node)

    for node in sorted(graph, key=str):
        if node not in visited:
            dfs(node)

    return cycles


def print_cycles(charts: dict[Path, Chart], cycles: list[list[Path]], root: Path) -> None:
    if not cycles:
        print("No dependency cycles detected.")
        return

    print("Dependency cycles detected:", file=sys.stderr)
    for cycle in cycles:
        labels = " -> ".join(format_chart(charts[path], root) for path in cycle)
        print(f"  {labels}", file=sys.stderr)


def find_chart_path_by_name(charts: dict[Path, Chart], chart_name: str) -> Path:
    matching_paths = [path for path, chart in charts.items() if chart.name == chart_name]
    if not matching_paths:
        raise ValueError(f"Unknown chart: {chart_name}")
    if len(matching_paths) > 1:
        raise ValueError(
            f"Chart name {chart_name!r} is ambiguous; matching paths: "
            + ", ".join(str(path) for path in sorted(matching_paths))
        )
    return matching_paths[0]


def find_dependents(root_chart_path: Path, reverse_graph: dict[Path, set[Path]]) -> list[Path]:
    dependents: list[Path] = []
    visited: set[Path] = set()
    stack: list[Path] = [root_chart_path]

    while stack:
        current = stack.pop()
        for dependent in sorted(reverse_graph[current], key=str):
            if dependent in visited:
                continue
            visited.add(dependent)
            dependents.append(dependent)
            stack.append(dependent)

    return sorted(dependents, key=str)


def print_dependents(
    charts: dict[Path, Chart], dependents: list[Path], root_chart_path: Path, root: Path
) -> None:
    print(f"Dependents of {format_chart(charts[root_chart_path], root)}:")
    if not dependents:
        print("  (none)")
        return
    for dependent in dependents:
        print(f"  {format_chart(charts[dependent], root)}")


def print_dependents_names(charts: dict[Path, Chart], dependents: list[Path]) -> None:
    for dependent in dependents:
        print(charts[dependent].name)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Print the local Helm chart dependency graph and detect cycles."
    )
    parser.add_argument(
        "--charts-root",
        default="charts",
        help="Path to the charts root directory (default: charts)",
    )
    parser.add_argument(
        "--root-chart",
        help="Print the reverse dependency closure for the given chart name.",
    )
    parser.add_argument(
        "--output",
        choices=("human", "names"),
        default="human",
        help="Output format for --root-chart results (default: human).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    charts_root = Path(args.charts_root).resolve()
    charts = discover_charts(charts_root)
    graph = build_graph(charts)
    reverse_graph = build_reverse_graph(graph)
    cycles = find_cycles(graph)

    if args.root_chart:
        root_chart_path = find_chart_path_by_name(charts, args.root_chart)
        dependents = find_dependents(root_chart_path, reverse_graph)
        if args.output == "names":
            print_dependents_names(charts, dependents)
        else:
            print_dependents(charts, dependents, root_chart_path, charts_root.parent)
    else:
        print_edges(charts, graph, charts_root.parent)

    if args.output == "human":
        print_cycles(charts, cycles, charts_root.parent)
    elif cycles:
        for cycle in cycles:
            labels = " -> ".join(charts[path].name for path in cycle)
            print(f"Dependency cycle detected: {labels}", file=sys.stderr)

    return 1 if cycles else 0


if __name__ == "__main__":
    sys.exit(main())
