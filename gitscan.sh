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
VERBOSE_MODE="false"

# read the options
TEMP=$(getopt -o vf:o: --long verbose,full,options: -n "$0" -- "$@") || { usage; exit 1; }
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -v|--verbose)
            VERBOSE_MODE="true"; shift ;;
        -f|--full)
            FULL_SCAN="true"; shift ;;
        -o|--options)
            case "$2" in
                "") shift 2 ;;
                *) ADDITIONAL_OPTIONS="$2"; shift 2 ;;
            esac ;;
        --) shift ; break ;;
        *) echo "Invalid option: $1"; usage; exit 1 ;;
    esac
done

/usr/bin/freshclam

echo "Beginning scan..."

if ! [ -d ".git" ]; then
  echo "ERROR: Not a git repository, skipping history scan."
  exit 1
fi

EXCLUDE="--exclude=/.git"
SCRIPT="/usr/bin/clamscan -ri --no-summary $ADDITIONAL_OPTIONS"
TMP=$(mktemp -d -q)
REPO=$(pwd)

echo "Scanning working and .git directories..."
output=$($SCRIPT 2>&1)
if [ $? -ne 0 ]; then
  echo "ClamScan Output: $output"
else
  if echo "$output" | grep -q "FOUND"; then
    echo "Found malicious file in ref $(git rev-parse HEAD)"
    echo "$output"
  fi
fi

if [[ "${FULL_SCAN:-}" = "true" ]]; then
  # Ensure we are in a Git repository
  if ! [ -d ".git" ]; then
    echo "ERROR: Not a git repository, cannot perform full scan."
    exit 1
  fi

  REPO=$(pwd)

  # Get a list of all objects (blobs, trees, commits, etc.)
  objects=$(git rev-list --objects --all)

  # Process each object
  for object in ${objects}; do
    # Check if the object is a blob
    if [[ $(git cat-file -t "$object" 2>/dev/null) == "blob" ]]; then
      # It's a blob, proceed with scanning
      output=$(${SCRIPT} <(git cat-file blob "$object"))
      if [ $? -ne 0 ]; then
        echo "Error scanning blob: ${object}"
      elif echo "${output}" | grep -q "FOUND"; then
        echo "Found malicious file in blob ${object}"
        echo "${output}"
      fi
    fi
  done
  
  # Find and scan unreachable objects
  echo "Scanning for unreachable objects..."
  unreachable_objects=$(git fsck --unreachable | awk '/blob/ {print $3}')
  for object in $unreachable_objects; do
    git cat-file -p $object | $SCRIPT
  done

fi

if [ -s "/output.txt" ]; then
  echo "Scan finished with detections $(date)"
  cat /output.txt
  exit 1
else
  echo "Scan finished without detections $(date)"
fi
