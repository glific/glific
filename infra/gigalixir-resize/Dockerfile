FROM alpine:3.20
RUN apk add --no-cache bash curl jq
COPY resize.sh /resize.sh
RUN chmod +x /resize.sh
ENTRYPOINT ["/resize.sh"]
