## Git AV Scan Action

Action and Dockerfile to scan Git HEAD or commit history using [ClamAV](https://www.clamav.net/). ClamAV® is an open-source antivirus engine for detecting trojans, viruses, malware & other malicious threats.

## Disclaimer

This is a proof of concept, and does not provide any guarantee that carefully hidden objects will be scanned. Strong endpoint security, access, and code review policies and practices are the most effective way to ensure that malicious files or code is not introduced into a repository.

This project is not affiliated with the official ClamAV project.

## Example usage

```
uses: djdefi/gitavscan@main
with:
  full: '--full'
```

## Example workflow

Deep history scan. Scans each commit in the repository history. Slow but thorough:

```yaml
on: [push]

jobs:
  gitavscan:
    runs-on: ubuntu-latest
    name: History AV Scan
    steps:
    - uses: actions/checkout@v3
      with:
        fetch-depth: '0'
    - name: Git AV Scan
      uses: djdefi/gitavscan@main
      with:
        full: '--full'
```  

Scan current HEAD only. Only the most recent commit pushed will be scanned. Best used with an [enforced linear history](https://help.github.com/en/github/administering-a-repository/requiring-a-linear-commit-history), or by disabling PR merges in a repository. Fast but misses deeper history:

```yaml
on: [push]

jobs:
  gitavscan:
    runs-on: ubuntu-latest
    name: AV scan
    steps:
    - uses: actions/checkout@v3
    - name: Git AV Scan
      uses: djdefi/gitavscan@main
``` 

### Passing options to `clamscan`

Setting additional [`clamscan` command line options](https://linux.die.net/man/1/clamscan) is supported. This can be used to limit or exclude directories from the scope of the scan.

```yaml
on: [push]
jobs:
  gitavscan:
    runs-on: ubuntu-latest
    name: History AV Scan
    steps:
    - uses: actions/checkout@main
      with:
        fetch-depth: '0'
    - name: Git AV Scan
      uses: djdefi/gitavscan@main
      with:
        options: '--max-filesize=1M'
```

### Excluding specific file types or patterns

You can exclude specific file types or directories from the scan using the `options` input with clamscan's `--exclude` and `--exclude-dir` options. This is useful for skipping large binary files, log files, or other files that aren't relevant for security checks.

#### Exclude file types by extension

```yaml
on: [push]
jobs:
  gitavscan:
    runs-on: ubuntu-latest
    name: AV scan with exclusions
    steps:
    - uses: actions/checkout@v3
    - name: Git AV Scan
      uses: djdefi/gitavscan@main
      with:
        options: '--exclude=\.(log|tmp|bak)$'
```

#### Exclude multiple patterns

To exclude multiple file types, use multiple `--exclude` options:

```yaml
on: [push]
jobs:
  gitavscan:
    runs-on: ubuntu-latest
    name: AV scan with multiple exclusions
    steps:
    - uses: actions/checkout@v3
    - name: Git AV Scan
      uses: djdefi/gitavscan@main
      with:
        options: '--exclude=\.(log|tmp)$ --exclude=\.(bin|exe|dll)$ --exclude-dir=node_modules'
```

#### Common exclusion patterns

- **Log files**: `--exclude=\.log$`
- **Temporary files**: `--exclude=\.tmp$`
- **Binary files**: `--exclude=\.(bin|exe|dll)$`
- **Media files**: `--exclude=\.(mp4|avi|mkv|mp3)$`
- **Archives**: `--exclude=\.(zip|tar|gz|7z)$`
- **Specific directories**: `--exclude-dir=node_modules --exclude-dir=vendor`

**Note**: Patterns use extended regular expressions. Remember to escape special characters like `.` as `\.` and use `$` to match the end of the filename.        

## Running locally with Docker

Build:

```shell
docker build -t gitavscan .
```

Run full scan:

```shell
docker run --rm -it -v /path/to/repo:/scandir gitavscan --full
```
