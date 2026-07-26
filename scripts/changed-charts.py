#!/usr/bin/env python3

"""Detect top-level charts needing release and order them dependencies-first.

A companion to chart-graph.py / release-chart.sh. Given the repo as-is, this
reports which top-level charts under the charts root need releasing and prints
them so that a chart always appears after the charts it depends on. The first
entries are charts with no local dependencies.

Change detection is per-chart and uses git release tags of the form
``<chart>-<X.Y.Z>`` (the same scheme as release-chart.sh's latest_chart_tag):

* no matching tag                              -> NEW
* commits touching charts/<chart> since tag    -> CHANGED
* otherwise                                    -> UNCHANGED

By default the output is the full release blast radius: every chart that
changed itself or is new, *plus* every chart that (transitively) depends on one
of those -- because releasing a base chart cascades version bumps to its
dependents (as release-chart.sh does). Those pulled-in charts are labelled
DEPENDENT. Pass --direct-only for just the charts with their own changes.

Notes:
* Requires local tags to be present/current. Pass --fetch-tags (or run
  ``git fetch --tags`` beforehand) if your local tags may be stale.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from ruamel.yaml import YAML


yaml = YAML(typ="safe")

NEW = "NEW"
CHANGED = "CHANGED"
DEPENDENT = "DEPENDENT"
UNCHANGED = "UNCHANGED"


@dataclass(frozen=True)
class Chart:
    name: str
    path: Path
    # Names of other top-level charts this chart depends on (via file:// deps).
    dependencies: tuple[str, ...]


def parse_args() -> argparse.Namespace:
    """Parse CLI arguments for the changed-chart lookup."""
    parser = argparse.ArgumentParser(
        description="Print top-level charts needing release, dependencies first."
    )
    parser.add_argument(
        "--charts-root",
        default="charts",
        help="Path to the charts root directory (default: charts)",
    )
    parser.add_argument(
        "--output",
        choices=("names", "detail"),
        default="names",
        help="Output format (default: names).",
    )
    parser.add_argument(
        "--direct-only",
        action="store_true",
        help="Only charts with their own changes/newness; skip the dependents expansion.",
    )
    parser.add_argument(
        "--no-status",
        action="store_true",
        help="In --output detail, omit the status column.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Include UNCHANGED charts too (full topo-ordered inventory).",
    )
    parser.add_argument(
        "--fetch-tags",
        action="store_true",
        help="Run 'git fetch --tags' before detecting changes.",
    )
    return parser.parse_args()


def main() -> int:
    """Detect changed/new top-level charts and print them dependencies-first."""
    args = parse_args()
    charts_root = Path(args.charts_root).resolve()
    if not charts_root.is_dir():
        print(f"Charts root not found: {charts_root}", file=sys.stderr)
        return 1

    if args.fetch_tags:
        run_git(["fetch", "--tags"], charts_root)

    charts = discover_charts(charts_root)
    if not charts:
        print(f"No charts found under {charts_root}", file=sys.stderr)
        return 1

    dependents = build_dependents(charts)
    ordered = topological_order(charts, dependents)
    status = {
        name: chart_status(charts[name], charts_root) for name in ordered
    }

    # Seed with charts that changed themselves / are new, then (unless
    # --direct-only) expand to every chart that transitively depends on the
    # seed -- the full set a release will cascade-bump.
    seed = {name for name, state in status.items() if state in (NEW, CHANGED)}
    release_set = seed if args.direct_only else dependents_closure(seed, dependents)

    for name in ordered:
        if args.all:
            pass
        elif name not in release_set:
            continue

        label = classify(name, status[name], release_set, charts)

        if args.output == "detail":
            deps = ", ".join(charts[name].dependencies) or "-"
            if args.no_status:
                print(f"{name}\tdeps: {deps}")
            else:
                print(f"{name}\t{label}\tdeps: {deps}")
        else:
            print(name)

    return 0


def classify(
    name: str, status: str, release_set: set[str], charts: dict[str, Chart]
) -> str:
    """Label a chart by why it is being released (own change vs. dependency)."""
    if status in (NEW, CHANGED):
        return status
    if name in release_set:
        via = [dep for dep in charts[name].dependencies if dep in release_set]
        return f"{DEPENDENT} (via {', '.join(via)})" if via else DEPENDENT
    return status


def dependents_closure(
    seed: set[str], dependents: dict[str, set[str]]
) -> set[str]:
    """Expand a seed set to include every chart that transitively depends on it."""
    closure = set(seed)
    stack = list(seed)
    while stack:
        current = stack.pop()
        for dependent in dependents.get(current, ()):
            if dependent not in closure:
                closure.add(dependent)
                stack.append(dependent)
    return closure


def parse_dependency_owners(
    chart_yaml: Path, chart_dir: Path, charts_root: Path
) -> tuple[str, ...]:
    """Resolve a chart's file:// dependencies to owning top-level chart names."""
    with chart_yaml.open() as fp:
        data = yaml.load(fp)

    if not isinstance(data, dict):
        raise ValueError(f"Could not parse chart at {chart_yaml}")

    self_name = chart_dir.name
    owners: list[str] = []
    for dependency in data.get("dependencies", []) or []:
        if not isinstance(dependency, dict):
            continue
        repository = str(dependency.get("repository", ""))
        if not repository.startswith("file://"):
            continue

        target = (chart_dir / repository.removeprefix("file://")).resolve()
        owner = top_level_owner(target, charts_root)
        if owner is not None and owner != self_name and owner not in owners:
            owners.append(owner)

    return tuple(owners)


def top_level_owner(target: Path, charts_root: Path) -> str | None:
    """Map a resolved path to the top-level chart directory that contains it."""
    try:
        relative = target.relative_to(charts_root)
    except ValueError:
        return None
    if not relative.parts:
        return None
    return relative.parts[0]


def discover_charts(charts_root: Path) -> dict[str, Chart]:
    """Discover every top-level chart (charts/*/) and index it by directory name."""
    charts: dict[str, Chart] = {}
    for chart_dir in sorted(p for p in charts_root.iterdir() if p.is_dir()):
        chart_yaml = chart_dir / "Chart.yaml"
        if not chart_yaml.is_file():
            continue
        name = chart_dir.name
        dependencies = parse_dependency_owners(chart_yaml, chart_dir, charts_root)
        charts[name] = Chart(
            name=name, path=chart_dir.resolve(), dependencies=dependencies
        )
    return charts


def build_dependents(charts: dict[str, Chart]) -> dict[str, set[str]]:
    """Build the reverse map {chart -> set of charts that depend on it}."""
    dependents: dict[str, set[str]] = {name: set() for name in charts}
    for name, chart in charts.items():
        for dep in chart.dependencies:
            if dep in charts:
                dependents[dep].add(name)
    return dependents


def topological_order(
    charts: dict[str, Chart], dependents: dict[str, set[str]]
) -> list[str]:
    """Order charts so each appears after its local dependencies (base-first)."""
    remaining_deps = {
        name: {dep for dep in chart.dependencies if dep in charts}
        for name, chart in charts.items()
    }

    ready = sorted(name for name, deps in remaining_deps.items() if not deps)
    order: list[str] = []
    while ready:
        current = ready.pop(0)
        order.append(current)
        for dependent in sorted(dependents[current]):
            remaining_deps[dependent].discard(current)
            if not remaining_deps[dependent]:
                ready.append(dependent)
        ready.sort()

    if len(order) != len(charts):
        cyclic = sorted(set(charts) - set(order))
        raise ValueError(f"Dependency cycle detected among: {', '.join(cyclic)}")

    return order


def chart_status(chart: Chart, charts_root: Path) -> str:
    """Classify a chart as NEW, CHANGED, or UNCHANGED against its latest tag."""
    tag = latest_chart_tag(chart.name, charts_root)
    if tag is None:
        return NEW

    # git resolves the pathspec relative to run_git's cwd (charts_root), so
    # scope it to the chart directory name rather than a repo-root path.
    chart_relpath = chart.path.relative_to(charts_root)
    log = run_git(
        ["log", "--oneline", f"{tag}..HEAD", "--", str(chart_relpath)],
        charts_root,
    )
    return CHANGED if log.strip() else UNCHANGED


def latest_chart_tag(chart_name: str, charts_root: Path) -> str | None:
    """Return the highest-versioned <chart>-X.Y.Z tag, or None if untagged."""
    tags = run_git(
        ["tag", "--list", f"{chart_name}-[0-9]*.[0-9]*.[0-9]*"], charts_root
    ).split()
    if not tags:
        return None
    return sorted(tags, key=_version_key)[-1]


def _version_key(tag: str) -> tuple[int, ...]:
    """Sort key that orders <chart>-X.Y.Z tags by numeric version."""
    version = tag.rsplit("-", 1)[-1]
    parts: list[int] = []
    for component in version.split("."):
        number = "".join(ch for ch in component if ch.isdigit())
        parts.append(int(number) if number else 0)
    return tuple(parts)


def run_git(git_args: list[str], cwd: Path) -> str:
    """Run a git command in the repo containing the charts root, return stdout."""
    result = subprocess.run(
        ["git", *git_args],
        cwd=cwd,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(git_args)} failed: {result.stderr.strip()}"
        )
    return result.stdout


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
