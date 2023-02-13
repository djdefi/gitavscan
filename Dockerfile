FROM alpine:3.17.2

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/gitscan.sh"]

RUN apk add --no-cache --update clamav-libunrar freshclam clamav-scanner \
    bash dumb-init \
    git 
RUN freshclam

COPY gitscan.sh /
WORKDIR /scandir
