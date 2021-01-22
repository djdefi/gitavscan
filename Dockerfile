FROM alpine:3.13.0

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/gitscan.sh"]

RUN apk add --no-cache --update clamav-libunrar freshclam clamav-scanner \
    clamav-unofficial-sigs \
    bash dumb-init \
    git 
RUN freshclam

COPY gitscan.sh /
WORKDIR /scandir
