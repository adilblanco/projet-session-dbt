#!/usr/bin/env bash
# Télécharge le jeu de données Olist (Kaggle) et décompresse les CSV dans ctc_olist/data/raw/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAW_DIR="$REPO_ROOT/ctc_olist/data/raw"
ZIP_FILE="$RAW_DIR/brazilian-ecommerce.zip"

mkdir -p "$RAW_DIR"

curl -L -o "$ZIP_FILE" \
  https://www.kaggle.com/api/v1/datasets/download/olistbr/brazilian-ecommerce

unzip -o "$ZIP_FILE" -d "$RAW_DIR"
rm "$ZIP_FILE"

ls -1 "$RAW_DIR"
