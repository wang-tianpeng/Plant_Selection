#!/bin/zsh -l
#SBATCH --time=2:00:00
#SBATCH --ntasks=1
#SBATCH --mem=32g
#SBATCH --tmp=32g
#SBATCH --mail-type=ALL
#SBATCH --mail-user=pmorrell@umn.edu
#SBATCH -o %j.out
#SBATCH -e %j.err

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Find new papers similar to a curated set using PubMed elink/efetch.
Ranks candidates by how many seed papers link to them.

Environment Variables:
  OUTPUT_DIR           Output directory for results (default: ./pubmed_results)
  MAX_SEEDS            Limit number of seed papers to process (for testing)
  STRICT               Error handling mode: 1=strict, 0=relaxed (default: 1)
  
Filtering & Scoring:
  REQUIRE_POS          Require positive WGS patterns (default: 1)
  POS_PATTERNS         Regex for required keywords (default: whole[-]?genome|WGS|resequenc)
  NEG_PATTERNS         Regex for excluded keywords
  EXCL_PT              Exclude publication types (Review, Editorial, etc.)
  ASSEMBLY_ONLY_EXCLUDE Exclude assembly-only papers (default: 1)
  
Weighting:
  AGE_BETA             Max age penalty: 0-1 (default: 0.4)
  AGE_GAMMA            Age curve exponent (default: 0.7)
  COMPARATIVE_BOOST    Score multiplier for comparative studies (default: 1.15)
  COMPARATIVE_PATTERNS Regex for comparative evidence
  
Rate Limiting:
  BATCH_SIZE           PMIDs per efetch batch (default: 200)

Example:
  $(basename "$0")                          # Run with all defaults
  MAX_SEEDS=10 $(basename "$0")             # Test with 10 seeds
  REQUIRE_POS=0 $(basename "$0")            # Don't require WGS keywords

Output Files:
  - candidates_ranked.txt                   All candidates with scores
  - candidates_min{N}_seeds.txt             Candidates meeting threshold N
  - .pmid_to_pmcid.txt                      PMID→PMCID mapping cache

EOF
    exit "${1:-0}"
}

[[ "$*" == *"-h"* ]] || [[ "$*" == *"--help"* ]] && usage

set -e
set -o pipefail
# Optional relaxed error handling for local tests
STRICT="${STRICT:-1}"
if [ "$STRICT" = "0" ]; then
    set +e
fi

# Detect shell flavor and re-exec under zsh when local bash <4 (macOS)
if [ -n "$BASH_VERSION" ]; then
    BASH_MAJ=${BASH_VERSION%%.*}
    if [ "$BASH_MAJ" -lt 4 ]; then
        if command -v zsh >/dev/null 2>&1; then
            exec zsh "$0" "$@"
        else
            echo "Error: Bash <4 detected and zsh not available. Please run this script with zsh." >&2
            exit 1
        fi
    fi
fi

# Shell flavor for associative array helpers
if [ -n "$ZSH_VERSION" ]; then SHELL_FLAVOR=zsh; else SHELL_FLAVOR=bash; fi

# Helper: list keys of an associative array by name
keys() {
    local arrname="$1"
    if [ "$SHELL_FLAVOR" = "zsh" ]; then
        eval "printf \"%s\\n\" \${(k)$arrname}" | tr -d '"'
    else
        eval "printf \"%s\\n\" \${!$arrname[@]}" | tr -d '"'
    fi
}

# Peter L. Morrell - 24 December 2024 - St. Paul, MN
# PubMed Iterative Expansion
# Find new papers similar to a curated set using elink/efetch
# Uses all curated papers as seeds and ranks candidates by similarity score

# Your full list of curated PMIDs (papers to use as seeds)
INCLUDE_PMIDS=(32514106 38068624 40399895 27085183 29025393 34240169 39611775 27357660 31862875 25641359 39149812 27294617 37019898 36467269 25901015 30044522 24967630 39316046 30861529 30950186 33931610 31570895 36266506 38012346 35883045 33073445 40186008 31300020 22660545 34497122 37770615 34289200 39107305 29983312 38689695 35060228 30318590 33477542 35787713 36862793 28473417 35337259 31462776 31366935 32941604 36864629 40269167 37797086 34797710 35513577 28256021 34294107 33247723 30384830 34172741 30411828 39472552 39325737 31676863 36932922 21980108 38221758 26549859 38414075 31298732 34498072 38606833 34980919 35484301 38978318 38809753 34473873 22660546 34706738 32422187 33100219 40307323 34493868 33397978 30806624 40097782 27301592 31653677 32681796 31570613 36480621 35037853 34806764 38150485 40587577 29301967 38991084 37210585 31394003 34106529 36071507 34502156 38988615 23984715 30791928 33687945 34786880 36946261 30867414 35012630 33878927 37335936 36578210 28087781 37173729 40148071 39496880 23793030 40415256 30523281 30858362 36477175 39006000 29736016 34934047 33020633 27500524 38504651 39510980 34479604 37253933 26569124 32503111 37647532 35154199 34191029 28416819 34272249 34329481 39279509 40651977 32973000 37883717 35298255 39906956 38263403 31114806 38069099 31002209 36477810 33950177 41206694 25817433 38232726 30217779 26825293 29575353 40770574 33139952 34971791 39719589 39945053 32641831 38990113 32794321 35527235 32514036 27029319 28530677 31036963 34759320 27707802 37079743 40435003 36684744 32341525 36426120 29866176 36435453 28263319 38898961 36260744 36415319 37339133 38396942 38755313 37524773 36419182 33846635 39187610 31624088 36018239 30472326 34999019 38720463 32377351 40708030 38768215 27595476 38033071 38883333 31570620 40098183 24443444 33539781 34240238 30573726 35551309 35361112 33430931 35654976 38578160 38479835 31676864 36928772 31519986 33144942 35366022 39349447 33106631 25643055 29284515)

# List of PMIDs to exclude (known false positives)
EXCLUDE_PMIDS=(29476024 34828432 35075727 29409859 24760390 34165082 23990800 36546413 22231484 30051843 37043536 34354260 32913300 32821413 39634061 35710823 31549477 33439857 23267105 28992310 35138897 31048485 39056474 27258693 33512726 32969558 37974527 36109148 39582196 33166746 30710646 35152499 35676481 26865341 38166629 33973633 33837962 16649157 20345635 35180846 29183772 35031793 29018458 4383925 4822723 4978888 5015928 5026255 5569476 5646786 5811809 5831853 5853444 5873934 6046548 6162604 6169392 6304691 6431195 6523605 6553533 6895062 7247153 7721174 7947771 7959735 7959735 8428838 8550333 8550333 9226155 9541791 9590452 9590488 9680854 9821504 9905331 9943071 9979274 10091845 11628880)

# Minimum PMID (exclude older papers)
MIN_PMID=21980108

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Output directory (configurable, default to pubmed_results)
OUTPUT_DIR="${OUTPUT_DIR:-.}/pubmed_results"
mkdir -p "$OUTPUT_DIR"

# Create temp working directory for intermediate processing
WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT  # Cleanup on exit (even if error)

log "=== PubMed Iterative Expansion ==="
log "Using all ${#INCLUDE_PMIDS[@]} papers as seeds"
log "Estimated time: ~$((${#INCLUDE_PMIDS[@]} / 2)) minutes"
log "Output directory: $OUTPUT_DIR"

# Optional: limit number of seeds to process (for quick tests)
MAX_SEEDS="${MAX_SEEDS:-}"

# Convert arrays to associative arrays for fast lookups
if [ "$SHELL_FLAVOR" = "zsh" ]; then
    typeset -A include_set exclude_set candidate_seeds candidate_scores comparative_hits
else
    declare -A include_set exclude_set candidate_seeds candidate_scores comparative_hits
fi

for pmid in "${INCLUDE_PMIDS[@]}"; do
    include_set[$pmid]=1
done

for pmid in "${EXCLUDE_PMIDS[@]}"; do
    exclude_set[$pmid]=1
done

log "Querying PubMed (this will take a while)..."
log "Progress will be shown every 10 papers"

# Query similar articles for each seed (all in memory)
count=0
for seed in "${INCLUDE_PMIDS[@]}"; do
    count=$((count + 1))

    # Test mode: stop early if MAX_SEEDS is set
    if [[ -n "$MAX_SEEDS" ]] && [ "$count" -gt "$MAX_SEEDS" ]; then
        log "Stopping early after $MAX_SEEDS seeds (test mode)"
        break
    fi

    # Show progress every 10 papers
    if [ $((count % 10)) -eq 0 ]; then
        pct=$((count * 100 / ${#INCLUDE_PMIDS[@]}))
        log "  Progress: $count/${#INCLUDE_PMIDS[@]} ($pct%)"
    fi

    # Get similar articles and accumulate in memory (using temp file to avoid subshell in zsh)
    elink -db pubmed -id "$seed" -related 2>/dev/null | \
    efetch -format uid 2>/dev/null > "$WORKDIR/related_$seed.txt"
    
    while read pmid; do
        pmid=${pmid//\"/}
        # Skip if empty
        pmid=$(printf "%s" "$pmid" | tr -d '"')
        [[ -z "$pmid" ]] && continue
        # Skip if in include or exclude sets
        [[ -n "${include_set[$pmid]}" ]] && continue
        [[ -n "${exclude_set[$pmid]}" ]] && continue
        # Skip if PMID is older than cutoff
        if [[ "$pmid" =~ ^[0-9]+$ ]] && [ "$pmid" -lt "$MIN_PMID" ]; then
            continue
        fi
        # Add to candidates (accumulate seed references)
        if [[ -z "${candidate_seeds[$pmid]}" ]]; then
            candidate_seeds[$pmid]="$seed"
        else
            candidate_seeds[$pmid]="${candidate_seeds[$pmid]},$seed"
        fi
    done < "$WORKDIR/related_$seed.txt"

    # Rate limiting: ~2 requests per second
    sleep 0.5
done

log "Complete: ${#INCLUDE_PMIDS[@]}/${#INCLUDE_PMIDS[@]} (100%)"

if [ ${#candidate_seeds[@]} -eq 0 ]; then
    log "Error: No similar articles found. Check your network connection."
    log "DEBUG: candidate_seeds array is empty"
    log "DEBUG: WORKDIR=$WORKDIR"
    ls -la "$WORKDIR" 2>&1 | head -10 | while read line; do log "DEBUG: $line"; done
    rm -rf "$WORKDIR"
    exit 1
fi

log "Processing results..."

# Calculate scores (number of seeds per candidate) in memory
for pmid in $(keys candidate_seeds); do
    seed_list="${candidate_seeds[$pmid]}"
    [[ -z "$seed_list" ]] && continue
    # Count seeds linked to this PMID (comma-separated list)
    typeset -a seeds_arr
    seeds_arr=(${(s:,:)seed_list})
    score=${#seeds_arr[@]}
    candidate_scores["$pmid"]="$score"
done

# Filter by content to remove non-WGS papers before weighting
# - NEG_PATTERNS: regex of unwanted terms (case-insensitive)
# - EXCL_PT: unwanted publication types (Review, Editorial, etc.)
# - REQUIRE_POS: when set to 1, require WGS-positive keywords (POS_PATTERNS)
# - BATCH_SIZE: number of PMIDs per efetch batch
NEG_PATTERNS="${NEG_PATTERNS:-0K-exome|targeted|amplicon|panel|GBS|genotyping( by sequencing)?|GenomeStudio|SNP([ -]?array)?|microarray|Infinium|Axiom|expression|transcriptome|RNA[ -]?seq|mRNA|SSR(s)?|microsatellite|RAD[ -]?seq|ddRAD|SLAF|reduced representation|capture|hybrid[ -]?capture|chloroplast|chloroplast genome|mitochondri|mitochondrial genome|plastid|plastid genome|plastome|mitogenome}"
ASSEMBLY_ONLY_EXCLUDE="${ASSEMBLY_ONLY_EXCLUDE:-1}"
COMPARATIVE_PATTERNS="${COMPARATIVE_PATTERNS:-variant|polymorphism|SNP|indel|SV|structural variant|copy number|CNV|haplotype|diversity|population|comparative|resequenc|association|GWAS|selection|adaptation|introgression|domestication|pangenome|pan[ -]?genome|phylogeny|evolution}"
COMPARATIVE_BOOST="${COMPARATIVE_BOOST:-1.15}"
EXCL_PT="${EXCL_PT:-Review|Editorial|Letter|Meta-Analysis|News|Comment}"
POS_PATTERNS="${POS_PATTERNS:-whole[ -]?genome|WGS|resequenc}"
REQUIRE_POS="${REQUIRE_POS:-1}"
BATCH_SIZE="${BATCH_SIZE:-200}"

# Build list of candidate PMIDs
pmids_all=()
for pmid in $(keys candidate_scores); do
    pmids_all+=("$pmid")
done

removed_count=0
pmids_to_remove_file=$(mktemp)
if [ ${#pmids_all[@]} -gt 0 ]; then
    for ((i=0; i<${#pmids_all[@]}; i+=BATCH_SIZE)); do
        batch=("${pmids_all[@]:$i:$BATCH_SIZE}")
        # Join batch PMIDs into comma-separated list for efetch
        ids=$(printf "%s\n" "${batch[@]}" | tr -d '"' | paste -sd , -)
        # Fetch XML and extract fields (PMID, Title, Abstract, PublicationTypes)
        batch_file="$OUTPUT_DIR/batch_$i.txt"
        set +e
        efetch -db pubmed -id "$ids" -format xml 2>/dev/null | \
        xtract -pattern PubmedArticle \
               -element MedlineCitation/PMID \
               -element Article/ArticleTitle \
               -element Article/Abstract/AbstractText \
               -element Article/PublicationTypeList/PublicationType > "$batch_file"
        fetch_status=$?
        set -e
        
        # Skip batch if efetch failed or file is empty
        if [ $fetch_status -ne 0 ] || [ ! -s "$batch_file" ]; then
            log "Warning: Batch $i failed to fetch or is empty, skipping these PMIDs"
            rm -f "$batch_file"
            continue
        fi
        
        # Process batch results (this while loop is NOT in a subshell - reading from file)
        while IFS=$'\t' read -r pid title abstract pubtypes; do
            pid=$(printf "%s" "$pid" | tr -d '"')
            # Skip empty lines
            [[ -z "$pid" ]] && continue
            
            content="${title} ${abstract}"
            # Track comparative evidence for optional boost later
            if echo "$content" | grep -E -iq "$COMPARATIVE_PATTERNS"; then
                comparative_hits["$pid"]=1
            fi
            # Special case: exclude assembly-only papers if enabled
            if [ "$ASSEMBLY_ONLY_EXCLUDE" = "1" ]; then
                if echo "$content" | grep -E -iq "(de[ -]?novo )?assembly|genome assembly"; then
                    if ! echo "$content" | grep -E -iq "$COMPARATIVE_PATTERNS"; then
                        echo "$pid" >> "$pmids_to_remove_file"
                        continue
                    fi
                fi
            fi
            # Exclude unwanted publication types
            if [[ -n "$pubtypes" ]] && echo "$pubtypes" | grep -E -iq "$EXCL_PT"; then
                echo "$pid" >> "$pmids_to_remove_file"
                continue
            fi
            # Exclude if negative patterns present
            if [[ -n "$content" ]] && echo "$content" | grep -E -iq "$NEG_PATTERNS"; then
                echo "$pid" >> "$pmids_to_remove_file"
                continue
            fi
            # Optionally require positive WGS terms
            if [ "$REQUIRE_POS" = "1" ]; then
                if ! echo "$content" | grep -E -iq "$POS_PATTERNS"; then
                    echo "$pid" >> "$pmids_to_remove_file"
                    continue
                fi
            fi
        done < "$batch_file"
        rm -f "$batch_file"
        # Be kind to servers
        sleep 0.5
    done
fi

# Now remove filtered candidates from arrays (outside any subshell)
if [ -f "$pmids_to_remove_file" ]; then
    while read -r pid; do
        [ -n "$pid" ] && unset "candidate_scores[$pid]" && unset "candidate_seeds[$pid]"
        ((removed_count++))
    done < "$pmids_to_remove_file" || true
    rm -f "$pmids_to_remove_file"
fi
log "Content filter removed ${removed_count} candidates not matching WGS criteria"

# Relax error exit for reporting/output stage
set +e

# Rebuild candidate_scores to ensure consistency after filtering
# Clear the associative array without destroying its type
for key in $(keys candidate_scores); do
    unset "candidate_scores[$key]"
done

log "DEBUG: Rebuilding scores from $(keys candidate_seeds | wc -l) seed entries"
local rebuild_count=0
for pmid in $(keys candidate_seeds); do
    seed_list="${candidate_seeds[$pmid]}"
    [[ -z "$seed_list" ]] && continue
    # Count seeds linked to this PMID (comma-separated list)
    typeset -a seeds_arr
    seeds_arr=(${(s:,:)seed_list})
    score=${#seeds_arr[@]}
    candidate_scores["$pmid"]="$score"
    ((rebuild_count++))
done
log "DEBUG: Rebuilt $rebuild_count scores"

# Optional age downweighting: newer PMIDs score higher
# Intermediate weighting with exponent curve:
# Weighted = Score * (1 - AGE_BETA * ageNorm^AGE_GAMMA)
# Defaults: AGE_BETA=0.4 (40% max), AGE_GAMMA=0.7 (smooth)
AGE_BETA="${AGE_BETA:-0.4}"
AGE_GAMMA="${AGE_GAMMA:-0.7}"

# Compute min/max PMIDs among candidates for normalized scaling
max_pmid=0
min_pmid=999999999
for pmid in $(keys candidate_scores); do
    if [ "$pmid" -gt "$max_pmid" ]; then max_pmid=$pmid; fi
    if [ "$pmid" -lt "$min_pmid" ]; then min_pmid=$pmid; fi
done

# Apply age weighting and optional comparative boost
for pmid in $(keys candidate_scores); do
    score="${candidate_scores[$pmid]}"
    if [ "$max_pmid" -eq "$min_pmid" ]; then
        weighted="$score"
    else
        ageNorm=$(awk -v p="$pmid" -v minp="$min_pmid" -v maxp="$max_pmid" 'BEGIN{printf "%.6f", (maxp - p) / (maxp - minp)}')
        weighted=$(awk -v s="$score" -v beta="$AGE_BETA" -v gamma="$AGE_GAMMA" -v age="$ageNorm" 'BEGIN{printf "%.6f", s * (1 - beta * (age^gamma))}')
    fi
    if [[ -n "${comparative_hits[$pmid]}" ]]; then
        weighted=$(awk -v w="$weighted" -v b="$COMPARATIVE_BOOST" 'BEGIN{printf "%.6f", w*b}')
    fi
    weighted_scores["$pmid"]="$weighted"
done

log "Age weighting parameters: AGE_BETA=${AGE_BETA}, AGE_GAMMA=${AGE_GAMMA}"
log "Comparative boost factor: COMPARATIVE_BOOST=${COMPARATIVE_BOOST}"

# Find max score and recommended threshold
max_score=0
for score in "${candidate_scores[@]}"; do
    if [ "$score" -gt "$max_score" ]; then
        max_score=$score
    fi
done

recommended_threshold=$((max_score / 10))
if [ "$recommended_threshold" -lt 2 ]; then
    recommended_threshold=2
fi

log ""
log "=== RESULTS ==="
log "Total unique candidate papers found: ${#candidate_seeds[@]}"
log ""

# Show score distribution
log "Score Distribution (how many seeds found each candidate):"
for score in "${candidate_scores[@]}"; do
    echo "$score"
done | sort -nr | uniq -c | \
    awk '{printf "  %3d seeds: %4d candidates\n", $2, $1}' | head -20
log ""

log "Maximum score: $max_score"
log "Recommended threshold: >=$recommended_threshold (captures high-confidence matches)"
log ""

# Create output files with different thresholds
log "=== OUTPUT FILES ===" 

# Debug: check if scores exist
debug_count=0
for pmid in $(keys candidate_scores); do
    score="${candidate_scores[$pmid]}"
    [[ -n "$score" ]] && ((debug_count++))
done
log "DEBUG: candidate_scores has $debug_count non-empty entries"

for threshold in 2 3 5 10 $recommended_threshold; do
    if [ "$threshold" -le "$max_score" ]; then
        outfile="$OUTPUT_DIR/candidates_min${threshold}_seeds.txt"
        for pmid in $(keys candidate_scores); do
            score="${candidate_scores[$pmid]}"
            # Skip if score is empty or not a number
            [[ -z "$score" || ! "$score" =~ ^[0-9]+$ ]] && continue
            if [ "$score" -ge "$threshold" ]; then
                echo "$pmid"
            fi
        done | sort -n > "$outfile"
        count=$(wc -l < "$outfile")
        log "  candidates_min${threshold}_seeds.txt: $count candidates (≥$threshold seeds)"
    fi
done

# Create ranked list with full details
# Create ranked list with full details (includes weighted score)
{
    printf "%s\t%s\t%s\t%s\n" "PMID" "Score" "WeightedScore" "Seeds"
    for pmid in $(keys candidate_scores); do
        score="${candidate_scores[$pmid]}"
        seeds="${candidate_seeds[$pmid]}"
        # Fallback: recompute score from seeds if missing
        if [[ -z "$score" && -n "$seeds" ]]; then
            typeset -a seeds_arr
            seeds_arr=(${(s:,:)seeds})
            score=${#seeds_arr[@]}
            candidate_scores["$pmid"]="$score"
        fi
        weighted="${weighted_scores[$pmid]}"
        printf "%s\t%s\t%s\t%s\n" "$pmid" "$score" "$weighted" "$seeds"
    done | sort -k3,3nr -k2,2nr -k1,1n
} > "$OUTPUT_DIR/candidates_ranked.txt"
log "  candidates_ranked.txt: All ${#candidate_seeds[@]} candidates with weighted and raw scores"
log ""

# Calculate recommendations
high_conf=0
med_conf=0
low_conf=0
for score in "${candidate_scores[@]}"; do
    [[ -z "$score" ]] && continue
    if [ "$score" -ge "$recommended_threshold" ]; then
        ((high_conf++))
    elif [ "$score" -ge 3 ]; then
        ((med_conf++))
    else
        ((low_conf++))
    fi
done

log "=== RECOMMENDATIONS ==="
log "High confidence (≥$recommended_threshold seeds): $high_conf papers"
log "  → START HERE - these are most likely true positives"
log ""
log "Medium confidence (3-$((recommended_threshold-1)) seeds): $med_conf papers"
log "  → Review these after high confidence papers"
log ""
log "Low confidence (1-2 seeds): $low_conf papers"
log "  → Likely many false positives"
log ""
log "Next steps:"
log "  1. Review $OUTPUT_DIR/candidates_min${recommended_threshold}_seeds.txt"
log "  2. If you need more papers, lower the threshold"
log "  3. If you find false positives, raise the threshold"
log ""

log "Done! Output files are in: $OUTPUT_DIR"
exit 0
