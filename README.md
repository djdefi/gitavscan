## Git AV Scan Action

Action and Dockerfile to scan Git HEAD or commit history using [ClamAV](https://www.clamav.net/). 

## Example usage

```
uses: djdefi/gitavscan@master
with:
  full: '--full'
```

## Example workflow

Deep history scan. Scans each commit in the repositry history. Slow but thorough:

```yaml
on: [push]

jobs:
  gitavscan:
    runs-on: ubuntu-latest
    name: History AV Scan
    steps:
    - uses: actions/checkout@master
      with:
        fetch-depth: '0'
    - name: Git AV Scan
      uses: djdefi/gitavscan@master
      with:
        full: '--full'
```  

Scan current HEAD only. Only the most recent commit pushed will be scanned. Fast but misses history:

```yaml
on: [push]

jobs:
  gitavscan:
    runs-on: ubuntu-latest
    name: AV scan
    steps:
    - uses: actions/checkout@master
    - name: Git AV Scan
      uses: djdefi/gitavscan@master
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
