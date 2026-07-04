#!/usr/bin/env bash
# Fetch the OpenGrm source tarballs that conda-forge does not build for aarch64.
# The image builds them from source. Run it once before `docker build`.
set -euo pipefail
cd "$(dirname "$0")/sources"

fetch() {
  local name="$1" url="$2" sha="$3"
  if [[ -f "$name" ]] && echo "$sha  $name" | sha256sum -c --status 2>/dev/null; then
    echo "ok (cached): $name"; return
  fi
  echo "downloading: $name"
  curl -fSL --retry 3 --max-time 180 -o "$name" "$url"
  echo "$sha  $name" | sha256sum -c -
}

fetch baumwelch-0.3.11.tar.gz \
  "https://www.opengrm.org/twiki/pub/GRM/BaumWelchDownload/baumwelch-0.3.11.tar.gz" \
  dce976c0a7952ebdeb700e7c0ac1dc199c28b097825afc296cf713d1a0337a51

fetch ngram-1.3.17.tar.gz \
  "https://www.opengrm.org/twiki/pub/GRM/NGramDownload/ngram-1.3.17.tar.gz" \
  0426b808119ad4b7a7095acd538afe6cfc69bd3227842104f086912e8dced8d4

echo "sources ready in $(pwd)"
