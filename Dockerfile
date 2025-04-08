# There's not a dedicated image for Zig (read up on the language, pretty neat stuff) so I'll
# just build one capable of using Zig.
FROM alpine:3.21.3

# Download and install Zig. Look at that, how easy.
RUN apk update && \
    apk upgrade --no-cache && \
    apk add zig && \
    rm -rf /var/cache/apk

WORKDIR /app

ENTRYPOINT [ "zig"]
CMD ["build", "run", "--release=fast"]