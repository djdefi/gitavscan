# How to Scan Git Objects, Reflog, Worktrees, and Notes

This document explains how to extend gitavscan to scan currently unsupported git storage areas and the technical challenges involved.

## Currently Unsupported Areas

### 1. Git Objects (`.git/objects/`)

**What they are**: Git stores all content as objects - blobs (file content), trees (directory listings), commits, and tags. These are stored in:
- Loose objects: `.git/objects/[0-9a-f]{2}/[0-9a-f]{38}` (zlib compressed)
- Packed objects: `.git/objects/pack/*.pack` (deltified and compressed)

**Why they're not scanned**: They are compressed and often deltified, making them opaque to standard file scanning tools like ClamAV.

**How to scan them**:
```bash
# Option 1: Scan all objects by extracting them (SLOW, HIGH DISK USAGE)
git rev-list --objects --all | cut -d' ' -f1 | while read obj; do
  git cat-file -p "$obj" 2>/dev/null | clamscan --stdin -
done

# Option 2: Unpack all pack files (VERY SLOW, VERY HIGH DISK USAGE)
for pack in .git/objects/pack/*.pack; do
  git unpack-objects < "$pack"
done
# Then scan loose objects
find .git/objects -type f -regex '.*/[0-9a-f]{2}/[0-9a-f]{38}' | while read obj; do
  git cat-file blob "$(echo $obj | sed 's|.git/objects/||;s|/||')" 2>/dev/null | clamscan --stdin -
done

# Option 3: Scan pack files directly as-is (limited effectiveness)
clamscan -ri .git/objects/pack/
```

**Challenges**:
- Extremely slow on large repositories (thousands of objects)
- High disk I/O and memory usage
- Compressed/deltified content may prevent signature matching
- Objects may not represent actual file content (could be trees, commits, tags)
- Need to filter blob objects only

**Recommended implementation**:
```bash
if [[ "${SCAN_OBJECTS:-}" = "true" ]]; then
  echo "WARNING: Scanning git objects (slow on large repos)..."
  # Scan only blob objects to avoid non-file content
  git rev-list --objects --all --filter=blob:limit=0 | \
    awk '{print $1}' | \
    while read -r obj; do
      echo "Scanning object $obj"
      git cat-file blob "$obj" 2>/dev/null | clamscan --stdin - || true
    done
fi
```

### 2. Git Reflog (`.git/logs/`)

**What it is**: Local history of ref changes (HEAD movements, branch updates, checkouts, resets).

**Why it's not scanned**: Reflog entries reference commits that may already be scanned OR have been deleted.

**How to scan it**:
```bash
# Get all commits from reflog (including deleted/unreachable ones)
git reflog --all --pretty=%H | sort -u | while read -r sha; do
  echo "Scanning reflog commit $sha"
  git checkout "$sha" 2>/dev/null && clamscan -ri --exclude=/.git .
done
```

**Challenges**:
- Reflog is local-only (not in remote repos)
- Many entries reference same commits (redundant scanning)
- Commits may no longer exist (dangling/expired)
- Checkout operations change filesystem state (slow)

**Recommended implementation**:
```bash
if [[ "${SCAN_REFLOG:-}" = "true" ]]; then
  echo "Scanning reflog entries..."
  # Get unique commits from reflog not in regular history
  git reflog --all --pretty=%H | sort -u > /tmp/reflog_commits
  git rev-list --all > /tmp/regular_commits
  # Only scan commits in reflog but not in regular history
  comm -23 /tmp/reflog_commits /tmp/regular_commits | while read -r sha; do
    echo "Scanning deleted commit $sha"
    TMP_DIR=$(mktemp -d)
    git --work-tree="$TMP_DIR" checkout "$sha" -- . 2>/dev/null || true
    if [ -d "$TMP_DIR" ]; then
      clamscan -ri "$TMP_DIR"
      rm -rf "$TMP_DIR"
    fi
  done
fi
```

### 3. Git Worktrees (`.git/worktrees/`)

**What they are**: Additional working directories linked to the same repository.

**Why they're not scanned**: Worktrees are separate filesystem locations not in the main repo path.

**How to scan them**:
```bash
# List all worktrees
git worktree list --porcelain | grep '^worktree ' | cut -d' ' -f2 | while read -r worktree; do
  echo "Scanning worktree: $worktree"
  clamscan -ri --exclude=/.git "$worktree"
done
```

**Challenges**:
- Worktrees are fully independent working directories
- May be on different filesystems/mounts
- May have different checked-out branches
- Simple to implement

**Recommended implementation**:
```bash
# Scan all worktrees
if git worktree list >/dev/null 2>&1; then
  echo "Scanning git worktrees..."
  git worktree list --porcelain | grep '^worktree ' | cut -d' ' -f2 | while read -r worktree; do
    if [ -d "$worktree" ]; then
      echo "Scanning worktree: $worktree"
      clamscan -ri --exclude=/.git "$worktree"
    fi
  done
fi
```

### 4. Git Notes (`.git/refs/notes/`)

**What they are**: Metadata attached to commits (annotations, code reviews, etc.).

**Why they're not scanned**: They are typically small text annotations, not executable content.

**How to scan them**:
```bash
# List all notes namespaces
git notes list --all 2>/dev/null | while read -r note_sha commit_sha; do
  echo "Scanning note for commit $commit_sha"
  git notes show "$commit_sha" | clamscan --stdin -
done
```

**Challenges**:
- Notes are usually text, rarely contain malware
- Multiple notes namespaces possible
- Low priority for scanning

**Recommended implementation**:
```bash
if [[ "${SCAN_NOTES:-}" = "true" ]]; then
  echo "Scanning git notes..."
  for namespace in $(git notes list --all 2>/dev/null | cut -d' ' -f2 | sort -u); do
    git notes --ref="$namespace" list 2>/dev/null | while read -r note_sha commit_sha; do
      git notes --ref="$namespace" show "$commit_sha" 2>/dev/null | clamscan --stdin - || true
    done
  done
fi
```

## Additional Missing Areas

### 5. Git LFS (Large File Storage)

**What it is**: Large binary files stored outside the main git repo.

**Risk**: High - large binaries are common malware vectors.

**How to scan**:
```bash
# Pull and scan all LFS objects
git lfs pull
git lfs ls-files | cut -d' ' -f3 | while read -r file; do
  clamscan "$file"
done
```

### 6. Git Attributes and Hooks

**What they are**: 
- `.git/hooks/` - Scripts that run on git events
- `.gitattributes` - Define filters/diff/merge drivers that can execute code

**Risk**: High - hooks are executable scripts, attributes can define filters that execute code.

**How to scan**:
```bash
# Scan hooks directory
clamscan -ri .git/hooks/

# Check for suspicious attributes
grep -r "filter=" .gitattributes .git/info/attributes 2>/dev/null
```

### 7. Git Index (`.git/index`)

**What it is**: Staging area with hashed content ready for commit.

**Risk**: Medium - could contain malware staged but not yet committed.

**How to scan**:
```bash
# Scan staged files
git diff --cached --name-only | while read -r file; do
  clamscan "$file"
done
```

### 8. Git Bundle Files

**What they are**: Portable git repositories in a single file.

**Risk**: Medium - could contain malicious commits.

**How to scan**:
```bash
# Extract and scan bundle
git bundle verify "$bundle_file"
git bundle unbundle "$bundle_file" | xargs git cat-file -p | clamscan --stdin -
```

### 9. Shallow Clone Boundaries

**What they are**: In shallow clones, not all history is fetched.

**Risk**: Low - but full history may contain malware.

**Mitigation**: Always use `fetch-depth: 0` in CI/CD.

### 10. Alternate Object Databases

**What they are**: External object databases referenced in `.git/objects/info/alternates`.

**Risk**: High - could reference malicious external repos.

**How to scan**:
```bash
if [ -f .git/objects/info/alternates ]; then
  while read -r alt; do
    echo "Scanning alternate object database: $alt"
    clamscan -ri "$alt"
  done < .git/objects/info/alternates
fi
```

## Implementation Priority

**High Priority** (implement next):
1. Git worktrees - simple, low cost, real risk
2. Git hooks - executable scripts, high risk
3. Git LFS - large binaries, high risk
4. Git attributes with filters - code execution risk

**Medium Priority**:
5. Git reflog - deleted commits
6. Staged files in index
7. Alternate object databases

**Low Priority** (performance/complexity concerns):
8. Git objects - very slow, compressed/deltified
9. Git notes - usually just text annotations
10. Bundle files - uncommon

## Performance Considerations

- **Git objects scanning**: Can take hours on large repos (Linux kernel: 8M+ objects)
- **Reflog scanning**: Requires many checkout operations (I/O intensive)
- **Worktrees**: Fast, only scans additional working directories
- **Hooks**: Instant, small directory

## Recommended Next Steps

Add flags to enable deep scanning:
```bash
--scan-worktrees     # Scan all worktrees (fast, low risk)
--scan-hooks         # Scan git hooks directory (fast, high value)
--scan-lfs           # Pull and scan LFS objects (medium speed)
--scan-reflog        # Scan deleted commits (slow)
--scan-objects       # Scan all git objects (very slow)
--scan-all           # Enable all deep scans (very slow)
```

## Example Implementation

See `gitscan.sh` lines 110-121 for the submodule scanning pattern, which can be adapted for these features.
