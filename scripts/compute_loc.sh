#!/usr/bin/env bash
set -e

TMP_DIR=$(mktemp -d)
TOTAL_ADDED=0
TOTAL_REMOVED=0

fetch_repos () {
  ORG=$1
  curl -s "https://api.github.com/users/$ORG/repos?per_page=100" \
  | jq -r '.[] | select(.fork==false) | .clone_url'
}

process_repo () {
  REPO=$1
  NAME=$(basename "$REPO" .git)

  git clone --quiet --depth 1 "$REPO" "$TMP_DIR/$NAME" || return

  STATS=$(git -C "$TMP_DIR/$NAME" log --pretty=tformat: --numstat \
    | awk '{added+=$1; removed+=$2} END {print added, removed}')

  ADDED=$(echo $STATS | awk '{print $1}')
  REMOVED=$(echo $STATS | awk '{print $2}')

  TOTAL_ADDED=$((TOTAL_ADDED + ADDED))
  TOTAL_REMOVED=$((TOTAL_REMOVED + REMOVED))
}

echo "Collecting repos..."

repos=$((
  fetch_repos "alvarovillalbaa"
  fetch_repos "clous-ai"
  fetch_repos "sentyl-ai"
) | sort -u)

for repo in $repos; do
  echo "Processing $repo"
  process_repo "$repo"
done

NET=$((TOTAL_ADDED - TOTAL_REMOVED))

mkdir -p metrics

cat <<EOF > metrics/loc.md
### Code Metrics (auto-generated)

| Metric | Value |
|------|------|
| Lines Added | $(printf "%'d" $TOTAL_ADDED) |
| Lines Removed | $(printf "%'d" $TOTAL_REMOVED) |
| Net LOC | $(printf "%'d" $NET) |

Updated: $(date -u +"%Y-%m-%d %H:%M UTC")
EOF
