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

LOG_FILE="gitscan.log"
echo "Starting Git Repository Scan" > "$LOG_FILE"

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
  echo "ERROR: Not a git repository, skipping history scan." | tee -a "$LOG_FILE"
  exit 1
fi

EXCLUDE="--exclude=/.git"
SCRIPT="/usr/bin/clamscan -ri --no-summary $ADDITIONAL_OPTIONS"
TMP=$(mktemp -d -q)
REPO=$(pwd)

echo "Scanning working and .git directories..." | tee -a "$LOG_FILE"
output=$($SCRIPT)
if [ $? -ne 0 ]; then
  echo "Error during scanning working and .git directories" | tee -a "$LOG_FILE"
else
  if echo "$output" | grep -q "FOUND"; then
    echo "Found malicious file in ref $(git rev-parse HEAD)" | tee -a /output.txt
    echo "$output" | tee -a /output.txt
  fi
fi

if [[ "${FULL_SCAN:-}" = "true" ]]; then
  # clone the git repository
  pushd $TMP > /dev/null 2>&1
  if ! git clone $REPO 2>> "$LOG_FILE" 1>&2; then
    echo "Failed to clone repository: $REPO" | tee -a "$LOG_FILE"
    exit 1
  fi
  cd $(basename $REPO)

  # Process all blobs
  blobs=$(git rev-list --objects --all)
  echo "Inspecting $blobs blobs..." | tee -a "$LOG_FILE"
  
  for blob in ${blobs}; do
    objtype=$(git cat-file -t ${blob})
    if [[ ${objtype} == "blob" ]]; then
      output=$(${SCRIPT} <(git cat-file blob ${blob}))
      if [ $? -ne 0 ]; then
        echo "Error scanning blob: ${blob}" | tee -a "$LOG_FILE"
      elif echo "${output}" | grep -q "FOUND"; then
        echo "Found malicious file in blob ${blob}" | tee -a /output.txt
        echo "${output}" | tee -a /output.txt
      fi
    else
      echo "Skipping non-blob object: ${blob}" | tee -a "$LOG_FILE"
    fi
  done

  popd > /dev/null

  rm -rf $TMP
fi

if [ -s "/output.txt" ]; then
  echo "Scan finished with detections $(date)" | tee -a "$LOG_FILE"
  cat /output.txt | tee -a "$LOG_FILE"
  exit 1
else
  echo "Scan finished without detections $(date)" | tee -a "$LOG_FILE"
fi
