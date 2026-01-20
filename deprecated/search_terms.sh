#!/bin/zsh

setopt errexit nounset pipefail extendedglob

# Script to search for terms in markdown files and report counts
# Usage: ./search_terms.sh [--dry-run|-n] <directory_with_markdown_files> <terms_file>

log() {
  local msg="$1"
  echo "$(date +'%Y-%m-%d %H:%M:%S') - ${msg}" >&2
}

# Parse optional --dry-run/-n
DRY_RUN=0
if [[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi

# Check if required arguments are provided
if [ $# -ne 2 ]; then
  echo "Usage: $0 [--dry-run|-n] <directory_with_markdown_files> <terms_file>" >&2
  echo "" >&2
  echo "Arguments:" >&2
  echo "  directory_with_markdown_files - Directory containing .md files to search" >&2
  echo "  terms_file                    - File containing search terms (one per line)" >&2
  exit 1
fi

MARKDOWN_DIR="$1"
TERMS_FILE="$2"

# Check if directory exists
if [ ! -d "$MARKDOWN_DIR" ]; then
  log "Error: Directory not found: $MARKDOWN_DIR"
  exit 1
fi

# Check if terms file exists
if [ ! -f "$TERMS_FILE" ]; then
  log "Error: Terms file not found: $TERMS_FILE"
  exit 1
fi

# Read search terms from file (one per line) into arrays
# Format: "Display Name: pattern1|pattern2|pattern3"
log "Reading search terms from: $TERMS_FILE"
typeset -a DISPLAY_NAMES
typeset -a SEARCH_PATTERNS

while IFS= read -r line || [[ -n $line ]]; do
  # Trim leading/trailing whitespace using sed
  line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  
  # Skip empty lines and comments
  if [[ -z "$line" || "$line" =~ ^# ]]; then
    continue
  fi
  
  # Require format "Display Name: patterns"
  if [[ "$line" =~ ^([^:]+):(.+)$ ]]; then
    display_name="${match[1]}"
    display_name=$(echo "$display_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    patterns="${match[2]}"
    patterns=$(echo "$patterns" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    DISPLAY_NAMES+=("$display_name")
    SEARCH_PATTERNS+=("$patterns")
  else
    log "Warning: Skipping line without 'Name: pattern' format: $line"
  fi
done < "$TERMS_FILE"

if [ ${#DISPLAY_NAMES[@]} -eq 0 ]; then
  log "Error: No search terms found in $TERMS_FILE"
  log "Expected format: 'Display Name: pattern1|pattern2|pattern3'"
  exit 1
fi

# Check if directory exists
if [ ! -d "$MARKDOWN_DIR" ]; then
  log "Error: Directory not found: $MARKDOWN_DIR"
  exit 1
fi

# Count total markdown files
TOTAL_FILES=$(find "$MARKDOWN_DIR" -type f -name "*.md" | wc -l | tr -d ' ')

if [ "$TOTAL_FILES" -eq 0 ]; then
  log "Error: No markdown files found in $MARKDOWN_DIR"
  exit 1
fi

log "Searching $TOTAL_FILES markdown files in: $MARKDOWN_DIR"
log "Searching for ${#DISPLAY_NAMES[@]} term groups"

# Create associative array to store counts (zsh syntax)
typeset -A term_counts

# Search for each term group
for i in {1..${#DISPLAY_NAMES[@]}}; do
  display_name="${DISPLAY_NAMES[$i]}"
  patterns="${SEARCH_PATTERNS[$i]}"
  
  # Split patterns by | and collect unique matching files
  typeset -A matched_files
  
  # Split on | using parameter expansion, then trim each
  for pattern in "${(@s.|.)patterns}"; do
    # Trim whitespace from pattern using sed
    pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Skip empty patterns
    [[ -z "$pattern" ]] && continue
    
    if (( DRY_RUN )); then
      log "Files matching pattern: '$pattern' (group: '$display_name')"
      grep -rilw --include="*.md" -i -e "$pattern" "$MARKDOWN_DIR" 2>/dev/null || true
    else
      # Find files matching this pattern and store them (case-insensitive, whole word)
      while IFS= read -r file; do
        matched_files[$file]=1
      done < <(grep -rilw --include="*.md" -i -e "$pattern" "$MARKDOWN_DIR" 2>/dev/null || true)
    fi
  done
  
  if (( ! DRY_RUN )); then
    # Count unique files
    count=${#matched_files[@]}
    term_counts[$display_name]=$count
  fi
done

# Output results in table format
echo ""
echo "Search Results"
echo "============================================"
echo "Total Markdown files searched: $TOTAL_FILES"
echo "============================================"
echo ""
printf "%-40s | %s\n" "Search Term" "Papers Found"
printf "%-40s-+-%s\n" "----------------------------------------" "------------"

# Sort terms by count (descending) and then alphabetically
for term in "${(k)term_counts[@]}"; do
  printf "%s\t%d\n" "$term" "${term_counts[$term]}"
done | sort -t$'\t' -k2,2nr -k1,1 | while IFS=$'\t' read -r term count; do
  printf "%-40s | %12d\n" "$term" "$count"
done

echo ""
log "Search completed"
