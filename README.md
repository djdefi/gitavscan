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

## Running locally with Docker

Build:

```shell
docker build -t gitavscan .
```

Run full scan:

```shell
docker run --rm -it -v /path/to/repo:/scandir gitavscan --full
```
