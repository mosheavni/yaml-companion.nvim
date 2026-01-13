#!/usr/bin/env bash
set -e
cd "$(git rev-parse --show-toplevel)"

# Create doc directory if it doesn't exist
mkdir -p doc

# =============================================================================
# 1. Generate API docs with lemmy-help (to temp file)
# =============================================================================

# Detect OS and download lemmy-help
case "$(uname)" in
  Darwin) RELEASE="x86_64-apple-darwin" ;;
  Linux)  RELEASE="x86_64-unknown-linux-gnu" ;;
  *)      echo "Unsupported OS: $(uname)"; exit 1 ;;
esac

LEMMY_VERSION="v0.11.0"
echo "Downloading lemmy-help ${LEMMY_VERSION} for ${RELEASE}..."
curl -sL "https://github.com/numToStr/lemmy-help/releases/download/${LEMMY_VERSION}/lemmy-help-${RELEASE}.tar.gz" | tar xz

API_DOCS=$(mktemp)
echo "Generating API documentation..."
./lemmy-help -f -a -c -t \
  lua/yaml-companion/init.lua \
  lua/yaml-companion/meta.lua \
  > "$API_DOCS"

rm -f lemmy-help

# =============================================================================
# 2. Generate vimdoc from README with panvimdoc
# =============================================================================

if ! command -v pandoc &> /dev/null; then
  echo "Warning: pandoc not found, skipping README vimdoc generation"
  echo "Install pandoc to generate doc/yaml-companion.txt locally"
  rm -f "$API_DOCS"
  exit 0
fi

echo "Generating vimdoc from README..."

# Clone panvimdoc to temp directory
PANVIMDOC_DIR=$(mktemp -d)
trap "rm -rf $PANVIMDOC_DIR $API_DOCS" EXIT
git clone --depth 1 --quiet https://github.com/kdheepak/panvimdoc.git "$PANVIMDOC_DIR"

# Create a temporary README with:
# - Emojis stripped (they render poorly in vimdoc)
# - Main heading simplified to avoid duplicate "yaml-companion-yaml-companion" tags
# - Table of Contents section removed (panvimdoc generates its own)
README_CLEAN=$(mktemp).md
perl -CSD -0777 -pe '
  s/[\x{1F300}-\x{1FAF8}\x{2600}-\x{26FF}\x{2700}-\x{27BF}\x{2328}\x{23CF}\x{23E9}-\x{23F3}\x{23F8}-\x{23FA}]\x{FE0F}?//g;
  s/^# yaml-companion\.nvim$/# Introduction/m;
  s/^## Table of Contents\n(?:.*\n)*?(?=^## |\z)//m;
' README.md > "$README_CLEAN"

# Run panvimdoc
pandoc \
  --metadata=project:yaml-companion \
  --metadata=description:"YAML schema companion for Neovim" \
  --metadata=toc:true \
  --metadata=treesitter:true \
  --metadata=vimversion:"Neovim >= 0.11.0" \
  --metadata=incrementheadinglevelby:0 \
  --metadata=dedupsubheadings:true \
  --metadata=ignorerawblocks:true \
  --metadata=docmapping:false \
  --metadata=docmappingproject:true \
  --lua-filter="$PANVIMDOC_DIR/scripts/skip-blocks.lua" \
  --lua-filter="$PANVIMDOC_DIR/scripts/include-files.lua" \
  -t "$PANVIMDOC_DIR/scripts/panvimdoc.lua" \
  "$README_CLEAN" \
  -o doc/yaml-companion.txt

rm -f "$README_CLEAN"

# Post-process the generated vimdoc:
# - Simplify tag names by removing redundant "-introduction" from tags
# - Flatten TOC numbering (convert nested "  - Item" to numbered list)
perl scripts/fix-vimdoc-toc.pl doc/yaml-companion.txt

# =============================================================================
# 3. Append API docs to the main vimdoc
# =============================================================================

echo "Appending API reference..."
cat >> doc/yaml-companion.txt << 'EOF'

==============================================================================
API Reference                                        *yaml-companion-api*

Generated from Lua source annotations using lemmy-help.

EOF

cat "$API_DOCS" >> doc/yaml-companion.txt

echo "Generated doc/yaml-companion.txt"
