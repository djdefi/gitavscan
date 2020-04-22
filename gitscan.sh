#!/usr/bin/env bash
#/ Usage: gitscan.sh [--full]
#/
#/ Scan the latest commit, or the full history of a Git repository.
#/
#/ OPTIONS:
#/   -h | --help                      Show this message.
#/   -f | --full                      Full history scan.      
#/
#/ EXAMPLES: 
#/
#/    Scan the latest commit.
#/      $ gitscan.sh  
#/
#/    Scan the entire history.
#/      $ gitscan.sh --full
#/    
#/        
set -o nounset -o pipefail

usage() {
  grep '^#/' < "$0" | cut -c 4-
}

if [[ "$@" = "--help" ]] || [[ "$@" = "-h" ]]; then
  usage
  exit 2
fi

/usr/bin/freshclam

echo "Beginning scan..."

if ! [ -d ".git" ]; then
  echo "ERROR: Not a git repository, skipping history scan."
  exit 1
fi

EXCLUDE="--exclude=/.git"
SCRIPT="/usr/bin/clamscan -ri --no-summary"
TMP=$(mktemp -d -q)
REPO=$(pwd)

echo "Scanning working and .git directories..."
output=$($SCRIPT)
  if echo "$output" | grep -q "FOUND"; then
    echo "Found malicious file in ref $(git rev-parse HEAD)" | tee -a /output.txt
    echo "$output" | tee -a /output.txt
  fi

if [[ "$@" = "--full" ]] || [[ "$@" = "-f" ]]; then
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
