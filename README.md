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

### Using unofficial ClamAV signatures

Enable unofficial ClamAV signatures for enhanced detection. Unofficial signatures from trusted sources like SaneSecurity are pre-packaged in the Docker image and updated opportunistically:

```
uses: djdefi/gitavscan@main
with:
  unofficial-sigs: '--unofficial-sigs'
```

**How it works:**
- Unofficial signatures are pre-downloaded during Docker image build for reliability
- When `--unofficial-sigs` is used, the tool attempts to update these signatures to the latest versions
- If updates fail (due to network issues), the pre-packaged signatures are still used
- This ensures consistent operation even in restricted network environments

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

### Using unofficial ClamAV signatures

Scan with unofficial signatures from SaneSecurity and other trusted sources for enhanced malware detection. Signatures are pre-packaged and updated opportunistically:

```yaml
on: [push]

jobs:
  gitavscan:
    runs-on: ubuntu-latest
    name: Enhanced AV Scan
    steps:
    - uses: actions/checkout@v3
    - name: Git AV Scan with Unofficial Signatures
      uses: djdefi/gitavscan@main
      with:
        unofficial-sigs: '--unofficial-sigs'
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

## Running locally with Docker

Build:

```shell
docker build -t gitavscan .
```

Run full scan:

```shell
docker run --rm -it -v /path/to/repo:/scandir gitavscan --full
```

Run scan with unofficial signatures:

```shell
docker run --rm -it -v /path/to/repo:/scandir gitavscan --unofficial-sigs
```

**Note:** Unofficial signatures are pre-packaged in the image and updated opportunistically when `--unofficial-sigs` is used.
