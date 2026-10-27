FROM ubuntu:24.04 AS build

ARG TARGETARCH
ARG FILC_VERSION=0.687
ARG RUBY_VERSION=4.0.9
ARG RUBY_SHA256=a8057adb39f51ad6dc3106237504c93dd792bb515837b4fe7817ae21ed7e51f4
ARG BUILD_JOBS=4

RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf bison build-essential ca-certificates curl netbase patch pkg-config ruby tzdata xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/build
COPY dist/ /tmp/filc-dist/
RUN case "$TARGETARCH" in \
      arm64) arch=aarch64; sha=375995867dcd3e91533efba6328a5057e51cf7db5a1ffa413ad391d0336ade6e ;; \
      amd64) arch=x86_64; sha=2dc295715dc3347c1cc1b41f7a937b13a076e651e71db42f3adf00d5fb075bfe ;; \
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

COPY ruby-4.0.9-filc.patch /tmp/build/
RUN curl -fL --retry 3 "https://cache.ruby-lang.org/pub/ruby/4.0/ruby-${RUBY_VERSION}.tar.xz" -o ruby.tar.xz \
    && echo "$RUBY_SHA256  ruby.tar.xz" | sha256sum -c - \
    && tar -xf ruby.tar.xz \
    && cd "ruby-${RUBY_VERSION}" \
    && patch -p1 < ../ruby-4.0.9-filc.patch \
    && XLDFLAGS="-Wl,-z,pack-relative-relocs" ./configure \
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
