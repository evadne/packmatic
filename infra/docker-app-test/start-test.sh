#!/usr/bin/env bash

set -e -o pipefail

if [[ -n "$TEST_COMMAND" ]]; then
  cd /app && sh -c "$TEST_COMMAND"
else
  echo "No TEST_COMMAND set; keeping container alive until Docker Compose exit"
  cd /app && iex
fi
