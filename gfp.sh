#!/bin/bash

# GFP -> git fetch prune 
# Script to run git fetch --prune on all git repositories in subdirectories

# Function to check if a directory is a git repository
is_git_repo() {
    [ -d "$1/.git" ]
}

# Function to run git fetch --prune in a directory
fetch_and_prune() {
    local dir="$1"
    echo "Processing: $dir"
    
    if cd "$dir"; then
        if git fetch --prune; then
            echo "✅ Successfully fetched and pruned: $dir"
        else
            echo "❌ Failed to fetch and prune: $dir"
        fi
        cd - > /dev/null
    else
        echo "❌ Could not enter directory: $dir"
    fi
    echo ""
}

# Main script
main() {
    local base_dir="${1:-.}"  # Use current directory if no argument provided
    
    if [ ! -d "$base_dir" ]; then
        echo "Error: Directory '$base_dir' does not exist"
        exit 1
    fi
    
    echo "Searching for git repositories in: $(realpath "$base_dir")"
    echo "----------------------------------------"
    
    # Find all subdirectories and check if they're git repos
    find "$base_dir" -maxdepth 1 -type d -not -path "$base_dir" | while read -r dir; do
        if is_git_repo "$dir"; then
            fetch_and_prune "$dir"
        else
            echo "Skipping (not a git repo): $dir"
        fi
    done
    
    echo "Done!"
}

# Run the main function with all arguments
main "$@"