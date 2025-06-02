FROM alpine:3.22.0

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/gitscan.sh"]

RUN apk add --no-cache --update clamav-libunrar freshclam clamav-scanner \
    bash dumb-init \
    git
RUN git config --global --add safe.directory /scandir
RUN freshclam

COPY gitscan.sh /
WORKDIR /scandir
