#!/usr/bin/env bash
##
## USAGE: __PROG__
##
## __PROG__ prepares a release
##
## Usage example(s):
##
##   ./__PROG__ --chart spire --bump patch
##   ./__PROG__ --chart spire-crds --bump minor
##
## Options:
##    --help                  Show this help message
##    --chart                 The chart to release
##    --bump                  The semantic version bump type: major, minor, or patch
##    --from-current-branch   Apply the release bump on the current branch instead of recreating a bump branch from main
##    --dry-run               Will not actually submit the PR
##
## Prerequisites:
##   - gsed (MacOS)
##   - git
##   - helm
##   - GitHub CLI (gh)
##   - npm (if readme-generator is not already installed)
##   - yq
##
## Commands
##
##   ./__PROG__ --chart «chart» --bump «major|minor|patch» [--from-current-branch] [--dry-run]
me=$(basename "$0")

function usage {
  grep '^##' "$0" | sed -e 's/^##//' -e "s/__PROG__/$me/" >&2
}

function print_error {
  echo >&2
  echo >&2 "  ❌ ${*}"
}

function print_error_and_exit {
  print_error "${*}"
  exit 1
}

function require_command {
  command -v "$1" >/dev/null 2>&1 || {
    print_error_and_exit "$2"
  }
}

function unreleased_changes_other_charts {
  local chart latest_tag changes

  for chart in "$@" ; do
    latest_tag="$(latest_chart_tag "${chart}")"
    if [ -n "${latest_tag}" ] ; then
      changes="$(git --no-pager log "${latest_tag}..HEAD" --pretty=format:'* %h %s' -- "charts/${chart}")"
    else
      changes="$(git --no-pager log --pretty=format:'* %h %s' -- "charts/${chart}")"
    fi
    if [ -n "${changes}" ] ; then
      echo "### Unreleased changes ${chart}"
      echo
      echo "${changes}"
      echo
      echo Please ensure you bump above charts as well before merging main into the release branch.
      echo
      echo '```shell'
      echo ./release-chart.sh --chart "${chart}" --bump patch
      echo '```'
    fi
  done
}

function latest_chart_tag {
  local chart_name=$1

  git --no-pager tag --list "${chart_name}-[0-9]*.[0-9]*.[0-9]*" | sort -V | tail -n 1
}

function bump_version {
  local current_version=$1
  local bump_type=$2
  local major minor patch

  IFS=. read -r major minor patch <<< "${current_version}"

  if [[ -z "${major}" || -z "${minor}" || -z "${patch}" ]]; then
    print_error_and_exit "invalid semantic version '${current_version}'"
  fi

  case "${bump_type}" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      print_error_and_exit "invalid bump type '${bump_type}'"
      ;;
  esac

  echo "${major}.${minor}.${patch}"
}

function update_dependency_version {
  local chart_yaml=$1
  local dependency_chart=$2
  local dependency_version=$3

  DEPENDENCY_CHART="${dependency_chart}" DEPENDENCY_VERSION="${dependency_version}" \
    yq e 'with(.dependencies[]? | select(.name == strenv(DEPENDENCY_CHART)); .version = strenv(DEPENDENCY_VERSION))' -i "${chart_yaml}"
}

function update_chart_version {
  local chart_name=$1
  local dependency_version=$2
  local chart_yaml="charts/${chart_name}/Chart.yaml"

  TARGET_VERSION="${dependency_version}" \
    yq e '.version = strenv(TARGET_VERSION)' -i "${chart_yaml}"
}

function ensure_readme_generator {
  local readme_generator_version="2.6.0"
  local readme_generator_exe="readme-generator"

  if ! hash "${readme_generator_exe}" 2>/dev/null; then
    echo >&2 "${readme_generator_exe} not installed. Installing..."
    require_command npm "npm is required to install ${readme_generator_exe}. Please install npm and rerun the script."
    npm install -g "@bitnami/readme-generator-for-helm@${readme_generator_version}"
  fi
}

function refresh_chart_docs {
  local chart_dir

  ensure_readme_generator

  for chart_dir in "$@" ; do
    if [ -f "${chart_dir}/values.yaml" ] && [ -f "${chart_dir}/README.md" ] ; then
      echo >&2 "Generating Chart documentation for ${chart_dir}…"
      readme-generator --values="${chart_dir}/values.yaml" --readme="${chart_dir}/README.md"
    fi
  done
}

function chart_has_remote_dependencies {
  local chart_yaml=$1
  local remote_count

  remote_count="$(yq e '[.dependencies[]? | select(((.repository // "") | test("^file://")) | not)] | length' "${chart_yaml}")"
  [ "${remote_count}" -gt 0 ]
}

function refresh_chart_dependencies {
  local chart_dir
  local refreshed_repos=''

  for chart_dir in "$@" ; do
    if chart_has_remote_dependencies "${chart_dir}/Chart.yaml" && [ -z "${refreshed_repos}" ] ; then
      helm repo update
      refreshed_repos='true'
    fi
    helm dependency update --skip-refresh "${chart_dir}"
  done
}

function collect_dependent_charts {
  local root_chart=$1

  python3 scripts/chart-graph.py --chart "${root_chart}" --output names
}

function get_chart_version {
  local chart_name=$1

  yq e '.version' "charts/${chart_name}/Chart.yaml"
}

while (("$#")); do
  case "$1" in
  --help)
    usage
    exit 0
    ;;
  --chart)
    chart=$2
    shift 2
    ;;
  --bump)
    bump_type=$2
    shift 2
    ;;
  --from-current-branch)
    from_current_branch='true'
    shift 1
    ;;
  --dry-run)
    dry_run='-w'
    shift 1
    ;;
  *)
    usage
    print_error_and_exit 'unexpected option'
    ;;
  esac
done

require_command gh 'the GitHub cli (gh) is required to run this script'
require_command helm 'helm is required to run this script'
require_command yq 'yq is required to run this script'
require_command python3 'python3 is required to run this script'

if [[ $OSTYPE == "darwin"* ]]; then
  require_command gsed 'gsed is required to run this script'
  SED='gsed'
else
  SED='sed'
fi

if [ -z "$chart" ]; then
  usage
  print_error_and_exit 'chart option is missing'
fi

if [ -z "$bump_type" ]; then
  usage
  print_error_and_exit 'bump option is missing'
fi

if [ ! -f "charts/${chart}/Chart.yaml" ] ; then
  print_error_and_exit "no chart named '${chart}' in charts folder"
fi

if [ -n "${from_current_branch}" ] ; then
  branch_name="$(git branch --show-current)"
  if [ -z "${branch_name}" ] ; then
    print_error_and_exit 'unable to determine current branch; please checkout a branch before using --from-current-branch'
  fi
else
  branch_name="bump-${chart}-version"

  git fetch --tags
  git checkout main
  git pull
  git checkout --track -B "${branch_name}" main
fi

current_version="$(grep '^version:' "charts/${chart}/Chart.yaml" | awk '{print $2}')"
new_version="$(bump_version "${current_version}" "${bump_type}")"
release_base_tag="$(latest_chart_tag "${chart}")"
if [ -n "${release_base_tag}" ] ; then
  commits_since_previous_release="$(git log "${release_base_tag}..HEAD" --pretty=format:'* %h %s' -- "charts/${chart}")"
else
  commits_since_previous_release="$(git log --pretty=format:'* %h %s' -- "charts/${chart}")"
fi
update_chart_version "${chart}" "${new_version}"
"${SED}" -i "s/${current_version}/${new_version}/g" "charts/${chart}/README.md"

updated_dependency_charts=()
updated_chart_versions=()
release_charts=("${chart}")
while IFS= read -r dependent_chart ; do
  if [ -z "${dependent_chart}" ] ; then
    continue
  fi

  chart_yaml="charts/${dependent_chart}/Chart.yaml"
  if [ ! -f "${chart_yaml}" ] ; then
    print_error_and_exit "dependent chart '${dependent_chart}' does not have a Chart.yaml at ${chart_yaml}"
  fi

  dependent_current_version="$(grep '^version:' "${chart_yaml}" | awk '{print $2}')"
  dependent_new_version="$(bump_version "${dependent_current_version}" "${bump_type}")"
  update_chart_version "${dependent_chart}" "${dependent_new_version}"
  update_dependency_version "${chart_yaml}" "${chart}" "${new_version}"
  updated_dependency_charts+=("charts/${dependent_chart}")
  updated_chart_versions+=("${dependent_chart}:${dependent_current_version}:${dependent_new_version}")
  release_charts+=("${dependent_chart}")
done < <(collect_dependent_charts "${chart}")

unique_dependency_charts=()
while IFS= read -r chart_dir ; do
  if [ -n "${chart_dir}" ] ; then
    unique_dependency_charts+=("${chart_dir}")
  fi
done < <(printf '%s\n' "${updated_dependency_charts[@]}" | sort -u)

unique_release_charts=()
while IFS= read -r chart_name ; do
  if [ -n "${chart_name}" ] ; then
    unique_release_charts+=("${chart_name}")
  fi
done < <(printf '%s\n' "${release_charts[@]}" | sort -u)

for chart_name in "${unique_release_charts[@]}" ; do
  chart_version="$(get_chart_version "${chart_name}")"
  for chart_dir in "${unique_dependency_charts[@]}" ; do
    update_dependency_version "${chart_dir}/Chart.yaml" "${chart_name}" "${chart_version}"
  done
done

refresh_chart_dependencies "${unique_dependency_charts[@]}"

refresh_chart_docs "charts/${chart}" "${unique_dependency_charts[@]}"

if [ -n "${dry_run}" ] && [ -n "${from_current_branch}" ] ; then
  echo >&2
  echo >&2 "Dry run completed on the current branch (${branch_name})."
  echo >&2 "Inspect the working tree diff before deciding what to keep."
  exit 0
fi

git add release-chart.sh "charts/${chart}/"{Chart.yaml,README.md}
for chart_dir in "${unique_dependency_charts[@]}" ; do
  git add "${chart_dir}/Chart.yaml"
  if [ -f "${chart_dir}/Chart.lock" ] ; then
    git add "${chart_dir}/Chart.lock"
  fi
  if [ -f "${chart_dir}/README.md" ] ; then
    git add "${chart_dir}/README.md"
  fi
done
git commit -m "Bump ${chart} and dependent Helm Chart versions (${bump_type})" \
  -m "${commits_since_previous_release}" \
  -s
git push -u origin --force-with-lease

other_charts=()
for chart_dir in charts/*/; do
  chart_name=$(basename "$chart_dir")
  if [[ "$chart_name" != "$chart" ]]; then
    other_charts+=("$chart_name")
  fi
done

cat <<EOF | gh pr create --base main --body-file - "${dry_run}"
Please review the below changelog to ensure this matches up with the semantic version being applied.

> [!Important]
> Before merging to the release branch, ensure all other changed charts also have their version number bumped.

$(unreleased_changes_other_charts "${other_charts[@]}")

> [!Note]
> **Maintainers** ensure to run following after merging this PR to trigger the release workflow:
>
> \`\`\`shell
> git checkout main
> git pull
> git checkout release
> git pull
> git merge main
> git push
> \`\`\`

## Release set

- ${chart}: ${current_version} -> ${new_version}
$(for version_update in "${updated_chart_versions[@]}" ; do
  IFS=: read -r dependent_chart dependent_current_version dependent_new_version <<< "${version_update}"
  echo "- ${dependent_chart}: ${dependent_current_version} -> ${dependent_new_version}"
done)

## Changes in this release

${commits_since_previous_release}
EOF

if [ -n "${dry_run}" ] ; then
  echo >&2
  if [ -n "${from_current_branch}" ] ; then
    echo >&2 "Dry run completed on the current branch (${branch_name}). Inspect the branch diff before deciding what to keep."
  else
    echo >&2 "If you choose not to submit the PR please run following commands to cleanup the branch:"
    echo >&2
    echo >&2 "  git checkout main"
    echo >&2 "  git push origin :${branch_name}"
    echo >&2 "  git branch -D ${branch_name}"
  fi
  echo >&2
  echo >&2 'If you choose to submit the PR, please run following:'
  echo >&2
  echo >&2 "  gh pr merge --auto -r -d"
  exit
fi

gh pr merge --auto -r -d
if [ -z "${from_current_branch}" ] ; then
  git checkout main
fi
