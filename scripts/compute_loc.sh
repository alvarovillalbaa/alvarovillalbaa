#!/usr/bin/env bash
set -e

TMP=$(mktemp -d)

TOTAL_ADDED=0
TOTAL_REMOVED=0

declare -A REPO_ADDED
declare -A REPO_REMOVED
declare -A YEAR_ADDED
declare -A YEAR_REMOVED

CLOUS_LOC_ADDED=0
CLOUS_LOC_REMOVED=0

fetch_repos () {
  ORG=$1
  curl -s "https://api.github.com/users/$ORG/repos?per_page=100" \
  | jq -r '.[] | select(.fork==false) | .clone_url'
}

get_commits_for_org () {

ORG=$1

curl -s "https://api.github.com/orgs/$ORG/repos?per_page=100" \
| jq -r '.[] | select(.fork==false) | .clone_url' \
| while read repo; do

git clone --quiet --depth 1 "$repo" "$TMP/tmprepo" 2>/dev/null || continue

git -C "$TMP/tmprepo" rev-list --count HEAD

rm -rf "$TMP/tmprepo"

done | awk '{sum+=$1} END {print sum}'
}

clone_and_analyze () {

URL=$1
NAME=$(basename "$URL" .git)

git clone --quiet "$URL" "$TMP/$NAME" || return

cd "$TMP/$NAME"

while read added removed file; do

[[ "$added" == "-" ]] && continue

REPO_ADDED[$NAME]=$(( ${REPO_ADDED[$NAME]:-0} + added ))
REPO_REMOVED[$NAME]=$(( ${REPO_REMOVED[$NAME]:-0} + removed ))

TOTAL_ADDED=$((TOTAL_ADDED + added))
TOTAL_REMOVED=$((TOTAL_REMOVED + removed))

if [[ "$URL" == *"clous-ai"* ]]; then
CLOUS_LOC_ADDED=$((CLOUS_LOC_ADDED + added))
CLOUS_LOC_REMOVED=$((CLOUS_LOC_REMOVED + removed))
fi

done < <(git log --pretty=tformat: --numstat)

while read year added removed; do

YEAR_ADDED[$year]=$(( ${YEAR_ADDED[$year]:-0} + added ))
YEAR_REMOVED[$year]=$(( ${YEAR_REMOVED[$year]:-0} + removed ))

done < <(

git log --pretty="%ad" --date=format:%Y --numstat |
awk '

NF==1 {year=$1}

NF==3 {added[year]+=$1; removed[year]+=$2}

END {

for (y in added)
print y, added[y], removed[y]

}'

)

cd -
}

repos=$((
fetch_repos alvarovillalbaa
fetch_repos clous-ai
fetch_repos sentyl-ai
) | sort -u)

TOTAL_REPOS=$(echo "$repos" | wc -l)

for repo in $repos; do
echo "Processing $repo"
clone_and_analyze "$repo"
done

NET=$((TOTAL_ADDED - TOTAL_REMOVED))
CLOUS_NET=$((CLOUS_LOC_ADDED - CLOUS_LOC_REMOVED))

CLOUS_REPOS=$(curl -s https://api.github.com/orgs/clous-ai/repos \
| jq '[.[] | select(.fork==false)] | length')

CLOUS_COMMITS=$(get_commits_for_org clous-ai)

mkdir -p metrics

CONTAINERS=$(yq '.production.containers' metrics/system.yml)
PROVIDERS=$(yq '.production.cloud_providers | join(" + ")' metrics/system.yml)
SERVICES=$(yq '.services | join(" / ")' metrics/system.yml)

{

echo "## Engineering Metrics"
echo ""

echo "### Yearly LOC"
echo ""
echo "| Year | +LOC | -LOC | Net |"
echo "|----|----|----|----|"

for y in "${!YEAR_ADDED[@]}"; do
add=${YEAR_ADDED[$y]}
rem=${YEAR_REMOVED[$y]}
net=$((add-rem))
printf "| %s | %'d | %'d | %+d |\n" "$y" "$add" "$rem" "$net"
done | sort -r

echo ""
echo "### Repo Breakdown"
echo ""
echo "| Repo | +LOC | -LOC |"
echo "|----|----|----|"

for r in "${!REPO_ADDED[@]}"; do
printf "| %s | %'d | %'d |\n" "$r" "${REPO_ADDED[$r]}" "${REPO_REMOVED[$r]}"
done | sort -t'|' -k2 -nr

echo ""

echo "### Production Systems"
echo ""
echo "| Metric | Value |"
echo "|------|------|"
echo "| Repos maintained | $TOTAL_REPOS |"
echo "| Containers running | $CONTAINERS |"
echo "| Cloud providers | $PROVIDERS |"
echo "| Services | $SERVICES |"

echo ""

echo "### Project Impact"
echo ""
echo "#### Clous AI"
echo ""
echo "| Metric | Value |"
echo "|------|------|"
echo "| Repositories | $CLOUS_REPOS |"
echo "| Commits | $CLOUS_COMMITS+ |"
echo "| LOC | $CLOUS_NET+ |"
echo "| Tech | Django / Next.js / Agents / MCP |"

echo ""

} > metrics/loc.md
