#!/bin/sh

# Stop when error
set -e

# Default paths
TEMPLATE_DIR="/fluent-bit/etc/templates"
OUTPUT_DIR="/fluent-bit/etc"

# Optional suffix override (default: .template)
TEMPLATE_SUFFIX=".template"

# Render each template if present
for template in "$TEMPLATE_DIR"/*"$TEMPLATE_SUFFIX"; do
  [ -f "$template" ] || continue

  filename="${template##*/}"
  output_file="${OUTPUT_DIR}/${filename%$TEMPLATE_SUFFIX}"

  echo "[fluent-bit entrypoint] Rendering $template → $output_file"
  envsubst < "$template" > "$output_file"
done

## exec command (added as parameter in Dockerfile CMD)
exec "$@"
