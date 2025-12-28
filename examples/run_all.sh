#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

examples=(
  "basic_usage.exs"
  "readme_comprehensive.exs"
  "json_schema_generation.exs"
  "advanced_validation.exs"
  "dspy_integration.exs"
)

echo "Running Sinter examples..."
for example in "${examples[@]}"; do
  echo "=== $example ==="
  elixir "$example"
  echo ""
done
