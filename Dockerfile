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
# Build continues even if signature downloads fail to ensure CI reliability
RUN mkdir -p /var/lib/clamav/unofficial && \
    cd /var/lib/clamav && \
    echo "Attempting to download unofficial signatures into base image..." && \
    downloaded_count=0 && \
    # Test network connectivity first
    if curl -s --connect-timeout 10 --max-time 30 -f "https://mirror.rollernet.us/" >/dev/null 2>&1; then \
        echo "Network connectivity confirmed, proceeding with downloads..."; \
        for sig in badmacro.ndb blurl.ndb junk.ndb jurlbl.ndb jurlbla.ndb lott.ndb malware.ndb phish.ndb rogue.ndb sanesecurity.ftm; do \
            echo "Downloading $sig..."; \
            if curl --connect-timeout 10 --max-time 30 -f -s -o "$sig" "https://mirror.rollernet.us/sanesecurity/$sig" 2>/dev/null; then \
                if [ -f "$sig" ] && [ -s "$sig" ]; then \
                    echo "✓ Successfully downloaded $sig"; \
                    downloaded_count=$((downloaded_count + 1)); \
                else \
                    echo "✗ Failed to download $sig (empty file)"; \
                    rm -f "$sig"; \
                fi; \
            else \
                echo "✗ Failed to download $sig"; \
            fi; \
        done; \
    else \
        echo "Network connectivity to signature source unavailable during build."; \
        echo "Unofficial signatures will be downloaded/updated at runtime if possible."; \
    fi && \
    echo "Base image unofficial signatures setup complete. Downloaded: $downloaded_count/10 signatures."

COPY gitscan.sh /
WORKDIR /scandir
