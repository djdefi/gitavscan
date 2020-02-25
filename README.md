## Git AV Scan Action

Action to scan Git HEAD or history using [ClamAV](https://www.clamav.net/). 

## Example usage

```
uses: djdefi/gitavscan@v1
with:
  full: '--full'
```

## Example workflow

Deep history scan (slow but thorough):

```yaml
on: [push]

jobs:
  gitavscan:
    runs-on: ubuntu-latest
    name: History AV Scan
    steps:
    - uses: actions/checkout@v2
      with:
        fetch-depth: '0'
    - name: Git AV Scan
      uses: djdefi/gitavscan@v1
      with:
        full: '--full'
```  

Scan current HEAD only (fast but misses history):

```yaml
on: [push]

jobs:
  gitavscan:
    runs-on: ubuntu-latest
    name: AV scan
    steps:
    - uses: actions/checkout@v2
    - name: Git AV Scan
      uses: djdefi/gitavscan@v1
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
