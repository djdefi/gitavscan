#!/usr/bin/env bash
#/ Usage: gitscan.sh [--full] [--options "OPTIONS"]
#/
#/ Scan the latest commit, or the full history of a Git repository.
#/
#/ OPTIONS:
#/   -h | --help                      Show this message.
#/   -f | --full                      Full history scan.      
#/   -o | --options "OPTIONS"         Additional options for clamscan command.
#/
#/ EXAMPLES: 
#/
#/    Scan the latest commit.
#/      $ gitscan.sh  
#/
#/    Scan the entire history.
#/      $ gitscan.sh --full
#/    
#/    Scan with additional clamscan options.
#/      $ gitscan.sh --options "--max-filesize=1M"
#/        
set -o nounset -o pipefail

usage() {
  grep '^#/' < "$0" | cut -c 4-
}

# set default values
FULL_SCAN="false"
ADDITIONAL_OPTIONS=""

# read the options
TEMP=$(getopt -o vfo: --long verbose,full,options: -n "$0" -- "$@") || { usage; exit 1; }
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--verbose)
            shift ;;
        -f|--full)
            FULL_SCAN="true"; shift ;;
        -o|--options)
            case "$2" in
                "") shift 2 ;;
                # Prepend '--options' to the additional options
                *) ADDITIONAL_OPTIONS="$2"; shift 2 ;;
            esac ;;
        --) shift ; break ;;
        *) echo "Invalid option: $1"; usage; exit 1 ;;
    esac
done

/usr/bin/freshclam &
freshclam_pid=$!
timeout=300
elapsed=0
while kill -0 "$freshclam_pid" 2>/dev/null && [ $elapsed -lt $timeout ]; do
  sleep 5
  elapsed=$((elapsed + 5))
done
if kill -0 "$freshclam_pid" 2>/dev/null; then
  echo "WARNING: freshclam timed out after ${timeout}s, continuing with existing definitions"
  kill "$freshclam_pid" 2>/dev/null || true
fi
wait "$freshclam_pid" 2>/dev/null || true

echo "Beginning scan..."

if ! [ -d ".git" ]; then
  echo "ERROR: Not a git repository, skipping history scan."
  exit 1
fi

EXCLUDE="--exclude=/.git"
SCRIPT="/usr/bin/clamscan -ri --no-summary $ADDITIONAL_OPTIONS"
TMP=$(mktemp -d -q)
REPO=$(pwd)

echo "Scanning working directory (excluding .git)..."
output=$("$SCRIPT" $EXCLUDE "$REPO")
if echo "$output" | grep -q "FOUND"; then
  echo "Found malicious file in ref $(git rev-parse HEAD)" | tee -a /output.txt
  echo "$output" | tee -a /output.txt
fi

# Scan git stashes if they exist
if git rev-parse --verify refs/stash > /dev/null 2>&1; then
  echo "Scanning stashed changes..."
  stash_count=$(git stash list | wc -l)
  echo "Found $stash_count stashes to scan..."
  stash_index=0
  while [ $stash_index -lt "$stash_count" ]; do
    echo "Scanning stash@{$stash_index}..."
    stash_tmp=$(mktemp -d -q)
    git -C "$stash_tmp" init > /dev/null 2>&1
    git stash show -p "stash@{$stash_index}" | git -C "$stash_tmp" apply > /dev/null 2>&1 || true
    if [ -n "$(ls -A "$stash_tmp" 2>/dev/null)" ]; then
      output=$("$SCRIPT" "$stash_tmp")
      if echo "$output" | grep -q "FOUND"; then
        echo "Found malicious file in stash@{$stash_index}" | tee -a /output.txt
        echo "$output" | tee -a /output.txt
      fi
    fi
    rm -rf "$stash_tmp"
    (( stash_index++ ))
  done
fi

# Scan submodules if they exist
if [ -f ".gitmodules" ]; then
  echo "Scanning git submodules..."
  git submodule foreach --recursive "
    echo \"Scanning submodule: \$name at \$sm_path\"
    output=\$(/usr/bin/clamscan -ri --no-summary $ADDITIONAL_OPTIONS --exclude=/.git .)
    if echo \"\$output\" | grep -q \"FOUND\"; then
      echo \"Found malicious file in submodule \$name at \$sm_path\" | tee -a /output.txt
      echo \"\$output\" | tee -a /output.txt
    fi
  " || true
fi

if [[ "${FULL_SCAN:-}" = "true" ]]; then
  # clone the git repository
  pushd "$TMP" > /dev/null 2>&1 || exit 1
  git clone "$REPO" 2>&1 || { echo "ERROR: Failed to clone repository"; exit 1; }
  cd "$(basename "$REPO")" || exit 1

  # count commits and cache the rev-list output
  echo "Collecting revision list..."
  revs_output=$(git rev-list --all --remotes --pretty | grep ^commit\ | sed "s;commit ;;")
  revs=$(echo "$revs_output" | wc -l)
  count=1
  echo "Inspecting $revs revisions..."

  # scan all
  while IFS= read -r F; do
    echo "Scanning commit $count of $revs: $F"
    git checkout "$F" 2> /dev/null 1>&2
    output=$("$SCRIPT" $EXCLUDE)
    if echo "$output" | grep -q "FOUND"; then
      echo "Found malicious file in ref $F" | tee -a /output.txt
      echo "$output" | tee -a /output.txt
    fi
    (( count++ ))
  done <<< "$revs_output"

  popd > /dev/null || exit 1

  rm -rf "$TMP"
fi

if [ -s "/output.txt" ]; then
  echo "Scan finished with detections $(date)"
  cat /output.txt
  exit 1
fi

echo "Scan finished $(date)"
echo ""
echo "NOTE: This scan has the following limitations:"
echo "  - Git objects (loose and packed) in .git/objects/ are not directly scanned"
echo "  - Git reflog entries and deleted commits are not scanned"
echo "  - Git worktrees are not scanned"
echo "  - Git notes are not explicitly scanned"
echo "  - This tool should be used as part of a defense-in-depth strategy"
