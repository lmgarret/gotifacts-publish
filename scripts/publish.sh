#!/usr/bin/env bash
#
# Publish a static site to a gotifacts instance via its machine ingest API.
#
# Inputs are passed as GTF_* environment variables (see action.yml). This script
# is intentionally free of `${{ }}` interpolation so it stays shellcheck-clean
# and immune to workflow-input injection.
set -euo pipefail

die() {
  echo "::error::$*"
  exit 1
}

# --- Required inputs --------------------------------------------------------
: "${GTF_URL:?url is required}"
: "${GTF_API_KEY:?api-key is required}"
: "${GTF_PATH:?path is required}"
: "${GTF_SLUG:?slug is required}"

# --- Mask secrets -----------------------------------------------------------
# Mask the key and the host so they never leak into logs, even when the host is
# supplied as a plain (non-secret) input. We mask the URL as given, its trailing-
# slash-trimmed form, and the bare host, so the returned site URL (which embeds
# the apex host) is masked too.
url="${GTF_URL%/}"
host="${url#*://}"
host="${host%%/*}"
echo "::add-mask::$GTF_API_KEY"
echo "::add-mask::$GTF_URL"
echo "::add-mask::$url"
[ -n "$host" ] && echo "::add-mask::$host"

# --- Build meta.json --------------------------------------------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
meta="$work/meta.json"

# Split tags on commas and newlines, trim whitespace, drop empties -> JSON array.
tags_json="$(
  jq -cn --arg s "${GTF_TAGS:-}" \
    '[ $s | splits("[,\n]") | gsub("^\\s+|\\s+$";"") | select(length > 0) ]'
)"

hidden="false"
case "$(printf '%s' "${GTF_HIDDEN:-false}" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes|on) hidden="true" ;;
esac

jq -n \
  --arg group "${GTF_GROUP:-}" \
  --arg slug "$GTF_SLUG" \
  --arg title "${GTF_TITLE:-}" \
  --arg description "${GTF_DESCRIPTION:-}" \
  --arg date "${GTF_DATE:-}" \
  --arg repo "${GTF_REPO:-}" \
  --arg preview "${GTF_PREVIEW:-}" \
  --argjson tags "$tags_json" \
  --argjson hidden "$hidden" \
  '{group: $group, slug: $slug, title: $title, description: $description,
    date: $date, repo: $repo, preview: $preview, tags: $tags, hidden: $hidden}
   | with_entries(select(.value != "" and .value != null))' \
  > "$meta"

# --- Determine the content part ---------------------------------------------
# Exactly one of `index` (single HTML) or `bundle` (.tar.gz with top-level
# index.html) is sent.
part_name=""
part_arg=""

if [ -d "$GTF_PATH" ]; then
  [ -f "$GTF_PATH/index.html" ] || die "directory '$GTF_PATH' has no top-level index.html"
  bundle="$work/site.tar.gz"
  tar -C "$GTF_PATH" -czf "$bundle" .
  part_name="bundle"
  part_arg="bundle=@${bundle};type=application/gzip"
elif [ -f "$GTF_PATH" ]; then
  case "$GTF_PATH" in
    *.tar.gz|*.tgz)
      part_name="bundle"
      part_arg="bundle=@${GTF_PATH};type=application/gzip"
      ;;
    *)
      part_name="index"
      part_arg="index=@${GTF_PATH};type=text/html"
      ;;
  esac
else
  die "path '$GTF_PATH' does not exist"
fi

# --- Publish ----------------------------------------------------------------
resp="$work/resp.json"
code="$(
  curl -sS \
    -o "$resp" -w '%{http_code}' \
    -H "Authorization: Bearer $GTF_API_KEY" \
    -F "meta=<${meta};type=application/json" \
    -F "$part_arg" \
    "$url/ingest/sites"
)"

if [ "$code" -lt 200 ] || [ "$code" -ge 300 ]; then
  body="$(cat "$resp" 2>/dev/null || true)"
  case "$code" in
    401) hint=" — check the api-key input (publish-scoped gtf_ token)." ;;
    403) hint=" — the key is not permitted to publish to this group." ;;
    400) hint=" — invalid slug/group, too-deep path, or missing index.html." ;;
    *)   hint="" ;;
  esac
  die "publish failed (HTTP $code)$hint Response: $body"
fi

# --- Outputs ----------------------------------------------------------------
out_url="$(jq -r '.url // empty' "$resp")"
out_group="$(jq -r '.group // empty' "$resp")"
out_slug="$(jq -r '.slug // empty' "$resp")"
out_updated="$(jq -r '.updated_at // empty' "$resp")"

[ -n "$out_url" ] || die "publish succeeded (HTTP $code) but response had no url: $(cat "$resp")"

{
  echo "url=$out_url"
  echo "group=$out_group"
  echo "slug=$out_slug"
  echo "updated-at=$out_updated"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"

echo "::notice title=Published to gotifacts::$out_url"
