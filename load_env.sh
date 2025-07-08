#!/bin/bash

# Load environment variables from a file

load_env() {
  local env_file="$1"

  if [ -f "$env_file" ]; then
    # Use set -a to automatically export variables, then source the file
    set -a
    source "$env_file"
    set +a
    echo "✅ Environment variables from '$env_file' have been loaded."
  else
    echo "❌ File '$env_file' not found."
    exit 1
  fi
}

# Check if a file was passed
if [ -z "$1" ]; then
  echo "Usage: $0 <env_file>"
  exit 1
fi

# Call the function
load_env "$1"