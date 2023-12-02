#!/usr/bin/env bash
##
## USAGE: __PROG__
##
## __PROG__ prepares a release
##
## Usage example(s):
##
##   ./__PROG__ --chart spire --new-version 0.16.0
##   ./__PROG__ --chart spire-crds --new-version 0.3.0
##
## Options:
##    --help                  Show this help message
##    --chart                 The chart to release
##    --new-version           The new version number
##    --dry-run               Will not actually submit the PR
##
## Prerequisites:
##   - gsed (MacOS)
##   - git
##   - GitHub CLI (gh)
##
## Commands
##
##   ./__PROG__ --chart «chart» --current-version «current-version» --new-version «new-version» [--dry-run]
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

function unreleased_changes_other_charts {
  for chart in "$@" ; do
    latest_tag="$(git --no-pager tag --list "${chart}-[0-9]*.[0-9]*.[0-9]*" | sort -V | tail -n 1)"
    changes="$(git --no-pager log "${latest_tag}..HEAD" --pretty=format:'* %h %s' "charts/${chart}")"
    if [ -n "${changes}" ] ; then
      echo "### Unreleased changes ${chart}"
      echo
      echo "${changes}"
      echo
      echo Please ensure you bump above charts as well before merging main into the release branch.
      echo
      echo '```shell'
      echo ./release-chart.sh --chart "${chart}" --new-version ………
      echo '```'
    fi
  done
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
  --new-version)
    new_version=$2
    shift 2
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

command -v gh >/dev/null 2>&1 || {
  print_error_and_exit 'the GitHub cli (gh) is required to run this script'
}

if [[ $OSTYPE == "darwin"* ]]; then
  command -v gsed >/dev/null 2>&1 || {
    print_error_and_exit 'gsed is required to run this script'
  }
  SED='gsed'
else
  SED='sed'
fi

if [ -z "$chart" ]; then
  usage
  print_error_and_exit 'chart option is missing'
fi

if [ -z "$new_version" ]; then
  usage
  print_error_and_exit 'new-version option is missing'
fi

if [ ! -f "charts/${chart}/Chart.yaml" ] ; then
  print_error_and_exit "no chart named '${chart}' in charts folder"
fi

branch_name="bump-${chart}-version"

git fetch --tags
git checkout main
git pull
git checkout --track -B "${branch_name}" main

current_version="$(grep '^version:' "charts/${chart}/Chart.yaml" | awk '{print $2}')"
commits_since_previous_release="$(git log "${chart}-${current_version}..HEAD" --pretty=format:'* %h %s' "charts/${chart}")"
"${SED}" -i "s/version: ${current_version}/version: ${new_version}/" "charts/${chart}/Chart.yaml"
"${SED}" -i "s/${current_version}/${new_version}/g" "charts/${chart}/README.md"
git add "charts/${chart}/"{Chart.yaml,README.md}
git commit -m "Bump ${chart} Helm Chart version from ${current_version} to ${new_version}" \
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

## Changes in this release

${commits_since_previous_release}
EOF

if [ -n "${dry_run}" ] ; then
  echo >&2
  echo >&2 "If you choose not to submit the PR please run following commands to cleanup the branch:"
  echo >&2
  echo >&2 "  git checkout main"
  echo >&2 "  git push origin :${branch_name}"
  echo >&2 "  git branch -D ${branch_name}"
  echo >&2
  echo >&2 'If you choose to submit the PR, please run following:'
  echo >&2
  echo >&2 "  gh pr merge --auto -r -d"
  exit
fi

gh pr merge --auto -r -d
git checkout main
