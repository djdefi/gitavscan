FROM alpine:3.22.1

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/gitscan.sh"]

RUN apk add --no-cache --update clamav-libunrar freshclam clamav-scanner \
    bash dumb-init \
    git curl
RUN git config --global --add safe.directory /scandir

# Download official signatures first
RUN freshclam

# Download unofficial signatures and add them to the database
# This ensures they're always available, even if updates fail later
RUN mkdir -p /var/lib/clamav/unofficial && \
    cd /var/lib/clamav && \
    echo "Downloading unofficial signatures into base image..." && \
    for sig in badmacro.ndb blurl.ndb junk.ndb jurlbl.ndb jurlbla.ndb lott.ndb malware.ndb phish.ndb rogue.ndb sanesecurity.ftm; do \
        echo "Downloading $sig..."; \
        if curl -f -s -o "$sig" "https://mirror.rollernet.us/sanesecurity/$sig"; then \
            echo "✓ Successfully downloaded $sig"; \
        else \
            echo "✗ Failed to download $sig"; \
        fi; \
    done && \
    echo "Base image unofficial signatures setup complete."

COPY gitscan.sh /
WORKDIR /scandir
