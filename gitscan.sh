#!/usr/bin/env bash
#/ Usage: gitscan.sh [--full] [--unofficial-sigs] [--options "OPTIONS"]
#/
#/ Scan the latest commit, or the full history of a Git repository.
#/
#/ OPTIONS:
#/   -h | --help                      Show this message.
#/   -f | --full                      Full history scan.      
#/   -u | --unofficial-sigs           Download unofficial ClamAV signatures.
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

# read the options
# read the options
TEMP=$(getopt -o hvfu:o: --long help,verbose,full,unofficial-sigs,options: -n "$0" -- "$@") || { usage; exit 1; }
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

# Configure freshclam for unofficial signatures if requested
if [[ "${UNOFFICIAL_SIGS}" = "true" ]]; then
    echo "Configuring unofficial ClamAV signatures..."
    cat > /tmp/freshclam.conf << 'EOF'
# Official ClamAV database mirror
DatabaseMirror db.local.clamav.net
DatabaseMirror database.clamav.net

# Unofficial signatures from SaneSecurity
DatabaseCustomURL https://mirror.rollernet.us/sanesecurity/badmacro.ndb
DatabaseCustomURL https://mirror.rollernet.us/sanesecurity/blurl.ndb
DatabaseCustomURL https://mirror.rollernet.us/sanesecurity/junk.ndb
DatabaseCustomURL https://mirror.rollernet.us/sanesecurity/jurlbl.ndb
DatabaseCustomURL https://mirror.rollernet.us/sanesecurity/jurlbla.ndb
DatabaseCustomURL https://mirror.rollernet.us/sanesecurity/lott.ndb
DatabaseCustomURL https://mirror.rollernet.us/sanesecurity/malware.ndb
DatabaseCustomURL https://mirror.rollernet.us/sanesecurity/phish.ndb
DatabaseCustomURL https://mirror.rollernet.us/sanesecurity/rogue.ndb
DatabaseCustomURL https://mirror.rollernet.us/sanesecurity/sanesecurity.ftm

# Update settings
UpdateLogFile /var/log/freshclam.log
LogFileMaxSize 50M
LogTime yes
DatabaseDirectory /var/lib/clamav
MaxAttempts 5
EOF
    echo "Downloading official and unofficial signatures..."
    if /usr/bin/freshclam --config-file=/tmp/freshclam.conf; then
        echo "Signatures downloaded successfully."
        
        # Verify unofficial signatures were downloaded
        echo "Verifying unofficial signatures are available..."
        unofficial_count=0
        for sig in badmacro.ndb blurl.ndb junk.ndb jurlbl.ndb jurlbla.ndb lott.ndb malware.ndb phish.ndb rogue.ndb sanesecurity.ftm; do
            if [ -f "/var/lib/clamav/$sig" ]; then
                echo "  ✓ Found unofficial signature: $sig"
                ((unofficial_count++))
            else
                echo "  ✗ Missing unofficial signature: $sig"
            fi
        done
        
        if [ $unofficial_count -gt 0 ]; then
            echo "Successfully downloaded $unofficial_count unofficial signature files."
        else
            echo "WARNING: No unofficial signatures were downloaded. Proceeding with official signatures only."
        fi
    else
        echo "WARNING: Failed to download signatures with custom configuration. Falling back to official signatures only."
        /usr/bin/freshclam
    fi
else
    echo "Downloading official signatures only..."
    /usr/bin/freshclam
fi

echo "Beginning scan..."

# Show loaded signatures information
echo "Checking loaded signatures..."
if command -v clamscan >/dev/null 2>&1; then
    signature_count=$(find /var/lib/clamav -name "*.cvd" -o -name "*.cld" -o -name "*.ndb" -o -name "*.ftm" 2>/dev/null | wc -l)
    echo "Total signature files in database: $signature_count"
    
    if [[ "${UNOFFICIAL_SIGS}" = "true" ]]; then
        unofficial_files=$(find /var/lib/clamav -name "*.ndb" -o -name "*.ftm" 2>/dev/null | grep -E "(badmacro|blurl|junk|jurlbl|jurlbla|lott|malware|phish|rogue|sanesecurity)" | wc -l)
        echo "Unofficial signature files detected: $unofficial_files"
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
