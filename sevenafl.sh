#!/usr/bin/env bash
set -euo pipefail

# — Setup —
export GITHUB_OWNER=KingHavok
export GITHUB_REPO=SevenAFL
export GITHUB_PATH=seven_afl.m3u8
export GITHUB_TOKEN=github_pat_*     # replace with real PAT
export GITHUB_BRANCH=main

M3U_URL="https://i.mjh.nz/au/all/raw-tv.m3u8"
OUTPUT_FILE="seven_afl.m3u8"

# temp files
TPL=$(mktemp)
BODY=$(mktemp)
RECS=$(mktemp)
cleanup(){ rm -f "$TPL" "$BODY" "$RECS"; }
trap cleanup EXIT

# 1. fetch master playlist
curl -fsSL "$M3U_URL" > "$TPL"

# 2. split header + body
read -r HEADER < "$TPL"
tail -n +2 "$TPL" > "$BODY"

# 3. parse and filter
while IFS= read -r line; do
  if [[ $line == \#EXTINF:* ]]; then
    EXT="$line"
    read -r URL
    CID=$(sed -n 's/.*channel-id="\([^"]*\)".*/\1/p' <<<"$EXT")
    case "$CID" in
      mjh-7mate-ade)      NAME="7mate Adelaide";      CITY="ade";;
      mjh-7mate-bri)      NAME="7mate Brisbane";      CITY="bri";;
      mjh-7mate-mel)      NAME="7mate Melbourne";     CITY="mel";;
      mjh-7mate-per)      NAME="7mate Perth";         CITY="per";;
      mjh-7mate-regional) NAME="7mate Regional";     CITY="regional";;
      mjh-7mate-syd)      NAME="7mate Sydney";        CITY="syd";;
      mjh-seven-ade)      NAME="7 Adelaide";          CITY="ade";;
      mjh-seven-bri)      NAME="7 Brisbane";          CITY="bri";;
      mjh-seven-cns)      NAME="7 Cairns";            CITY="cns";;
      mjh-seven-mel)      NAME="7 Melbourne";         CITY="mel";;
      mjh-seven-mky)      NAME="7 Mackay";            CITY="mky";;
      mjh-seven-per)      NAME="7 Perth";             CITY="per";;
      mjh-seven-rky)      NAME="7 Rockhampton";       CITY="rky";;
      mjh-seven-ssc)      NAME="7 Sunshine Coast";    CITY="ssc";;
      mjh-seven-syd)      NAME="7 Sydney";            CITY="syd";;
      mjh-seven-tsv)      NAME="7 Townsville";        CITY="tsv";;
      mjh-seven-twb)      NAME="7 Toowoomba";         CITY="twb";;
      mjh-seven-wby)      NAME="7 Wide Bay";          CITY="wby";;
      *) continue;;
    esac
    # strip old group-title, add “Seven AFL”
    NO_G=$(sed -E 's/ *group-title="[^"]*"//g' <<<"$EXT")
    PREFIX=$(cut -d',' -f1 <<<"$NO_G")
    NEW_EXT="$PREFIX group-title=\"Seven AFL\", $NAME"
    # sort index
    case "$CITY" in
      ade) IDX=0;;
      per) IDX=1;;
      bri) IDX=2;;
      syd) IDX=3;;
      mel) IDX=4;;
      *)   IDX=99;;
    esac
    printf '%s|%s|%s|%s\n' "$IDX" "$NAME" "$NEW_EXT" "$URL" >> "$RECS"
  fi
done < "$BODY"

# 4. write filtered playlist
{
  echo "$HEADER"
  sort -t'|' -k1,1n -k2,2 "$RECS" \
    | while IFS='|' read -r _idx _name ext url; do
        echo "$ext"
        echo "$url"
      done
} > "$OUTPUT_FILE"

# 5. base64-encode (cross-platform)
CONTENT=$(base64 < "$OUTPUT_FILE" | tr -d '\n')

# 6. get existing SHA (suppress any 404)
API="https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/contents/$GITHUB_PATH?ref=$GITHUB_BRANCH"
RESP=$(curl -fsSL -H "Authorization: token $GITHUB_TOKEN" "$API" 2>/dev/null || echo "")
SHA=$(sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$RESP" || true)

# 7. build JSON payload
PAYLOAD="{\"message\":\"Update Seven AFL playlist\",\"content\":\"$CONTENT\",\"branch\":\"$GITHUB_BRANCH\""
if [[ -n "$SHA" ]]; then PAYLOAD+=",\"sha\":\"$SHA\""; fi
PAYLOAD+="}"

# 8. push to GitHub (no JSON output)
curl -fsSL -X PUT \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/contents/$GITHUB_PATH" \
  > /dev/null

echo "✓ pushed $OUTPUT_FILE → $GITHUB_OWNER/$GITHUB_REPO/$GITHUB_PATH"
