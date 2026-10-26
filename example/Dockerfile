FROM ubuntu:24.04 AS build

ARG TARGETARCH
ARG FILC_VERSION=0.686
ARG RUBY_VERSION=4.0.7
ARG RUBY_SHA256=47ef59413f7a4587ba6a6b78b14036eb5e36eec2ec0b90964801e88d56a3d375
ARG BUILD_JOBS=4

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf bison build-essential ca-certificates curl netbase patch pkg-config ruby tzdata xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/build
COPY dist/ /tmp/filc-dist/
RUN case "$TARGETARCH" in \
      arm64) arch=aarch64; sha=ab3365499571b5e62513247467a7450cd8e02bb915d6bd0b5f49433f25c52cf6 ;; \
      amd64) arch=x86_64; sha=3a0ba45283ff29668335d288530f35fe69c28ab8d663b4deb8801474825f117a ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && archive="/tmp/filc-dist/optfil-${FILC_VERSION}-linux-${arch}.tar.xz" \
    && echo "$sha  $archive" | sha256sum -c - \
    && tar -xf "$archive" \
    && cd "optfil-${FILC_VERSION}-linux-${arch}" \
    && ./setup.sh --unattended \
    && ln -s /usr/share/zoneinfo /opt/fil/share/zoneinfo

ENV CC=/opt/fil/bin/filcc \
    CXX=/opt/fil/bin/fil++ \
    PKG_CONFIG=/opt/fil/bin/pkg-config \
    PKG_CONFIG_LIBDIR=/opt/fil/lib/pkgconfig:/opt/fil/share/pkgconfig \
    LANG=C.UTF-8

RUN curl -fL --retry 3 https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz -o yaml.tar.gz \
    && echo 'c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4  yaml.tar.gz' | sha256sum -c - \
    && tar -xf yaml.tar.gz \
    && cd yaml-0.2.5 \
    && ./configure --prefix=/opt/fil \
    && make -j"$BUILD_JOBS" \
    && make install

COPY ruby-4.0.7-filc.patch /tmp/build/
RUN curl -fL --retry 3 "https://cache.ruby-lang.org/pub/ruby/4.0/ruby-${RUBY_VERSION}.tar.xz" -o ruby.tar.xz \
    && echo "$RUBY_SHA256  ruby.tar.xz" | sha256sum -c - \
    && tar -xf ruby.tar.xz \
    && cd "ruby-${RUBY_VERSION}" \
    && patch -p1 < ../ruby-4.0.7-filc.patch \
    && ./configure \
      --prefix=/usr/local \
      --enable-shared \
      --disable-yjit --disable-zjit --without-jit \
      --without-valgrind --without-jemalloc \
      --with-coroutine=ucontext --with-opt-dir=/opt/fil \
      --disable-install-doc \
    && make -j"$BUILD_JOBS" \
    && make install

FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates netbase pkg-config tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/fil /opt/fil
COPY --from=build /usr/local /usr/local

ENV CC=/opt/fil/bin/filcc \
    CXX=/opt/fil/bin/fil++ \
    PKG_CONFIG=/opt/fil/bin/pkg-config \
    PKG_CONFIG_LIBDIR=/opt/fil/lib/pkgconfig:/opt/fil/share/pkgconfig \
    LANG=C.UTF-8 \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    GEM_HOME=/usr/local/bundle \
    BUNDLE_APP_CONFIG=/usr/local/bundle \
    PATH=/usr/local/bundle/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

RUN mkdir -p "$GEM_HOME" \
    && ruby -ropenssl -rpsych -rzlib -rjson -rbundler -rfiddle -e 'puts RUBY_DESCRIPTION; puts OpenSSL::OPENSSL_VERSION; puts "Fil-C Ruby dependencies loaded"' \
    && gem --version && bundle --version

WORKDIR /app
CMD ["irb"]
