# Build a self-contained binary, then run it on a small image with CA certificates
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get
COPY bin bin
COPY lib lib
RUN dart compile exe bin/server.dart -o /app/push-server

FROM debian:stable-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 push \
 && mkdir /data && chown push /data
COPY --from=build /app/push-server /usr/local/bin/push-server
USER push
ENV DATA_DIR=/data PORT=8080
VOLUME /data
EXPOSE 8080
CMD ["push-server"]
