#!/usr/bin/env bash
#/ Usage: gitscan.sh [--full] [--unofficial-sigs] [--options "OPTIONS"]
#/
#/ Scan the latest commit, or the full history of a Git repository.
#/
#/ OPTIONS:
#/   -h | --help                      Show this message.
#/   -f | --full                      Full history scan.      
#/   -u | --unofficial-sigs           Enable unofficial ClamAV signatures (updates them opportunistically).
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
#/    Scan with unofficial signatures.
#/      $ gitscan.sh --unofficial-sigs
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
UNOFFICIAL_SIGS="false"
DETECTIONS_FOUND="false"

# read the options
# read the options
TEMP=$(getopt -o hvfuo: --long help,verbose,full,unofficial-sigs,options: -n "$0" -- "$@") || { usage; exit 1; }
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -h|--help)
            usage; exit 0 ;;
        -v|--verbose)
            VERBOSE_MODE="true"; shift ;;
        -f|--full)
            FULL_SCAN="true"; shift ;;
        -u|--unofficial-sigs)
            UNOFFICIAL_SIGS="true"; shift ;;
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

# Update signatures
echo "Updating ClamAV signatures..."
/usr/bin/freshclam

# Handle unofficial signatures based on flag
if [[ "${UNOFFICIAL_SIGS}" = "true" ]]; then
    echo "Attempting to update unofficial signatures..."
    cd /var/lib/clamav
    updated_count=0
    for sig in badmacro.ndb blurl.ndb junk.ndb jurlbl.ndb jurlbla.ndb lott.ndb malware.ndb phish.ndb rogue.ndb sanesecurity.ftm; do
        echo "Updating $sig..."
        if curl -f -s -o "${sig}.tmp" "https://mirror.rollernet.us/sanesecurity/$sig" && mv "${sig}.tmp" "$sig"; then
            echo "  ✓ Updated $sig"
            ((updated_count++))
        else
            echo "  ✗ Failed to update $sig (using existing version)"
            rm -f "${sig}.tmp"
        fi
    done
    
    if [ $updated_count -gt 0 ]; then
        echo "Successfully updated $updated_count unofficial signature files."
    else
        echo "No unofficial signatures could be updated, using existing versions."
    fi
    
    # Ensure unofficial signatures are active (in case they were disabled previously)
    for sig in badmacro.ndb blurl.ndb junk.ndb jurlbl.ndb jurlbla.ndb lott.ndb malware.ndb phish.ndb rogue.ndb sanesecurity.ftm; do
        if [ -f "/var/lib/clamav/${sig}.disabled" ]; then
            mv "/var/lib/clamav/${sig}.disabled" "/var/lib/clamav/$sig"
        fi
    done
else
    echo "Unofficial signatures disabled. Moving them aside..."
    cd /var/lib/clamav
    for sig in badmacro.ndb blurl.ndb junk.ndb jurlbl.ndb jurlbla.ndb lott.ndb malware.ndb phish.ndb rogue.ndb sanesecurity.ftm; do
        if [ -f "/var/lib/clamav/$sig" ]; then
            mv "/var/lib/clamav/$sig" "/var/lib/clamav/${sig}.disabled"
        fi
    done
fi

echo "Beginning scan..."

# Show loaded signatures information
echo "Checking loaded signatures..."
if command -v clamscan >/dev/null 2>&1; then
    signature_count=$(find /var/lib/clamav -name "*.cvd" -o -name "*.cld" -o -name "*.ndb" -o -name "*.ftm" 2>/dev/null | wc -l)
    echo "Total signature files in database: $signature_count"
    
    # Show unofficial signature status
    echo "Checking unofficial signature status..."
    unofficial_active=0
    unofficial_available=0
    for sig in badmacro.ndb blurl.ndb junk.ndb jurlbl.ndb jurlbla.ndb lott.ndb malware.ndb phish.ndb rogue.ndb sanesecurity.ftm; do
        if [ -f "/var/lib/clamav/$sig" ]; then
            echo "  ✓ Active: $sig"
            ((unofficial_active++))
            ((unofficial_available++))
        elif [ -f "/var/lib/clamav/${sig}.disabled" ]; then
            echo "  - Available but disabled: $sig"
            ((unofficial_available++))
        else
            echo "  ✗ Missing: $sig"
        fi
    done
    
    echo "Unofficial signatures: $unofficial_active active, $unofficial_available available"
    if [[ "${UNOFFICIAL_SIGS}" = "true" ]]; then
        echo "Unofficial signatures are enabled for this scan."
    else
        echo "Unofficial signatures are disabled for this scan (use --unofficial-sigs to enable)."
    fi
fi

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
    DETECTIONS_FOUND="true"
    echo "Found malicious file in ref $(git rev-parse HEAD)"
    echo "$output"
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
      DETECTIONS_FOUND="true"
      echo "Found malicious file in ref $F"
      echo "$output"
    fi
    (( count++ ))
  done

  popd > /dev/null

  rm -rf $TMP
fi

if [[ "${DETECTIONS_FOUND}" = "true" ]]; then
  echo "Scan finished with detections $(date)"
  exit 1
fi

echo "Scan finished $(date)"
