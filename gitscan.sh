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
TEMP=$(getopt -o vf:o: --long verbose,full,options: -n "$0" -- "$@")
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
output=$($SCRIPT)
  if echo "$output" | grep -q "FOUND"; then
    echo "Found malicious file in ref $(git rev-parse HEAD)" | tee -a /output.txt
    echo "$output" | tee -a /output.txt
  fi

if [[ "${FULL_SCAN:-}" = "true" ]]; then
  # clone the git repository
  pushd $TMP > /dev/null 2>&1
  git clone $REPO 2> /dev/null 1>&2
  cd $(basename $REPO)

  # count commits 
  revs=$(git rev-list --all --remotes --pretty | grep ^commit\ | sed "s;commit ;;" | wc -l)
  count=1
  echo "Inspecting $revs revisions..."

  # scan all
  for F in $(git rev-list --all --remotes --pretty | grep ^commit\ | sed "s;commit ;;"); do
    echo "Scanning commit $count of $revs: $F"
    git checkout $F 2> /dev/null 1>&2
    output=$($SCRIPT $EXCLUDE)
    if echo "$output" | grep -q "FOUND"; then
      echo "Found malicious file in ref $F" | tee -a /output.txt
      echo "$output" | tee -a /output.txt
    fi
    (( count++ ))
  done

  popd > /dev/null

  rm -rf $TMP
fi

if [ -s "/output.txt" ]; then
  echo "Scan finished with detections $(date)"
  cat /output.txt
  exit 1
fi

echo "Scan finished $(date)"
