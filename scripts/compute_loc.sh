#!/usr/bin/env bash
set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

: "${GH_TOKEN:?GH_TOKEN is required}"

TOTAL_ADDED=0
TOTAL_REMOVED=0

declare -A REPO_ADDED
declare -A REPO_REMOVED
declare -A YEAR_ADDED
declare -A YEAR_REMOVED

declare -A PROJECT_REPOS
declare -A PROJECT_COMMITS
declare -A PROJECT_LOC_ADDED
declare -A PROJECT_LOC_REMOVED

fetch_user_repos() {
  local page=1
  while true; do
    local response
    response=$(curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GH_TOKEN" \
      "https://api.github.com/user/repos?per_page=100&page=${page}&affiliation=owner")

    local count
    count=$(echo "$response" | jq 'length')
    [[ "$count" -eq 0 ]] && break

    echo "$response" | jq -r '.[] | select(.fork == false) | .full_name'
    page=$((page + 1))
  done
}

fetch_org_repos() {
  local org=$1
  local page=1

  while true; do
    local response
    response=$(curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GH_TOKEN" \
      "https://api.github.com/orgs/${org}/repos?per_page=100&page=${page}&type=all")

    local count
    count=$(echo "$response" | jq 'length')
    [[ "$count" -eq 0 ]] && break

    echo "$response" | jq -r '.[] | select(.fork == false) | .full_name'
    page=$((page + 1))
  done
}

clone_and_analyze() {
  local full_name=$1
  local owner=${full_name%%/*}
  local name=${full_name##*/}
  local repo_dir="$TMP/${owner}__${name}"

  echo "Processing ${full_name}"

  git -c http.extraheader="AUTHORIZATION: bearer ${GH_TOKEN}" \
    clone --quiet "https://github.com/${full_name}.git" "$repo_dir" || return

  cd "$repo_dir"

  PROJECT_REPOS[$owner]=$(( ${PROJECT_REPOS[$owner]:-0} + 1 ))

  local repo_commits
  repo_commits=$(git rev-list --count HEAD)
  PROJECT_COMMITS[$owner]=$(( ${PROJECT_COMMITS[$owner]:-0} + repo_commits ))

  while read -r added removed file; do
    [[ -z "${added:-}" ]] && continue
    [[ "$added" == "-" ]] && continue

    REPO_ADDED[$name]=$(( ${REPO_ADDED[$name]:-0} + added ))
    REPO_REMOVED[$name]=$(( ${REPO_REMOVED[$name]:-0} + removed ))

    TOTAL_ADDED=$((TOTAL_ADDED + added))
    TOTAL_REMOVED=$((TOTAL_REMOVED + removed))

    PROJECT_LOC_ADDED[$owner]=$(( ${PROJECT_LOC_ADDED[$owner]:-0} + added ))
    PROJECT_LOC_REMOVED[$owner]=$(( ${PROJECT_LOC_REMOVED[$owner]:-0} + removed ))
  done < <(git log --pretty=tformat: --numstat)

  while read -r year added removed; do
    YEAR_ADDED[$year]=$(( ${YEAR_ADDED[$year]:-0} + added ))
    YEAR_REMOVED[$year]=$(( ${YEAR_REMOVED[$year]:-0} + removed ))
  done < <(
    git log --pretty="%ad" --date=format:%Y --numstat |
    awk '
      NF==1 {year=$1}
      NF==3 && $1 != "-" {
        added[year]+=$1
        removed[year]+=$2
      }
      END {
        for (y in added) {
          print y, added[y], removed[y]
        }
      }'
  )

  cd - >/dev/null
}

repos=$((
  fetch_user_repos
  fetch_org_repos "clous-ai"
  fetch_org_repos "sentyl-ai"
) | sort -u)

TOTAL_REPOS=$(echo "$repos" | sed '/^$/d' | wc -l | tr -d ' ')

for repo in $repos; do
  clone_and_analyze "$repo"
done

NET=$((TOTAL_ADDED - TOTAL_REMOVED))

mkdir -p metrics

CONTAINERS=$(yq '.production.containers' metrics/system.yml)
PROVIDERS=$(yq -r '.production.cloud_providers | join(" + ")' metrics/system.yml)
SERVICES=$(yq -r '.services | join(" / ")' metrics/system.yml)

{
  echo "## Engineering Metrics"
  echo ""

  echo "### Yearly LOC"
  echo ""
  echo "| Year | +LOC | -LOC | Net |"
  echo "|---|---:|---:|---:|"

  for y in "${!YEAR_ADDED[@]}"; do
    add=${YEAR_ADDED[$y]}
    rem=${YEAR_REMOVED[$y]}
    net=$((add - rem))
    printf "| %s | %'\''d | %'\''d | %+d |\n" "$y" "$add" "$rem" "$net"
  done | sort -r

  echo ""
  echo "### Repo Breakdown"
  echo ""
  echo "| Repo | +LOC | -LOC |"
  echo "|---|---:|---:|"

  for r in "${!REPO_ADDED[@]}"; do
    printf "%012d| %s | %'\''d | %'\''d |\n" "${REPO_ADDED[$r]}" "$r" "${REPO_ADDED[$r]}" "${REPO_REMOVED[$r]}"
  done | sort -r | cut -d'|' -f2-

  echo ""
  echo "### Production Systems"
  echo ""
  echo "| Metric | Value |"
  echo "|---|---|"
  echo "| Repos maintained | $TOTAL_REPOS |"
  echo "| Containers running | $CONTAINERS |"
  echo "| Cloud providers | $PROVIDERS |"
  echo "| Services | $SERVICES |"

  echo ""
  echo "### Project Impact"
  echo ""

  for owner in clous-ai sentyl-ai alvarovillalbaa; do
    repos_count=${PROJECT_REPOS[$owner]:-0}
    commits_count=${PROJECT_COMMITS[$owner]:-0}
    loc_added=${PROJECT_LOC_ADDED[$owner]:-0}
    loc_removed=${PROJECT_LOC_REMOVED[$owner]:-0}
    loc_net=$((loc_added - loc_removed))

    case "$owner" in
      clous-ai)
        project_name="Clous AI"
        tech=$(yq -r '.projects."clous-ai".tech | join(" / ")' metrics/system.yml)
        ;;
      sentyl-ai)
        project_name="Sentyl AI"
        tech=$(yq -r '.projects."sentyl-ai".tech | join(" / ")' metrics/system.yml)
        ;;
      alvarovillalbaa)
        project_name="Personal Repos"
        tech="Various"
        ;;
    esac

    echo "#### $project_name"
    echo ""
    echo "| Metric | Value |"
    echo "|---|---|"
    echo "| Repositories | $repos_count |"
    echo "| Commits | $commits_count |"
    echo "| LOC | $loc_net |"
    echo "| Tech | $tech |"
    echo ""
  done
} > metrics/loc.md
