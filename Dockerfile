FROM alpine:latest AS build

# first build unrar

ENV USER=apk
ENV UID=1000
#ENV GID=23456

RUN apk add --no-cache alpine-sdk sudo 

#RUN addgroup -g "$GID" "$USER"
RUN adduser \
    --disabled-password \
    --gecos "" \
    --ingroup users \
    --ingroup abuild \
    --uid "$UID" \
    "$USER"

RUN mkdir /build
RUN chown apk /build
RUN echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER

# abuild needs to be executed as non-root:
USER "$USER"
WORKDIR /build

RUN git init
RUN git remote add origin https://github.com/alpinelinux/aports
RUN git fetch origin 6fcec524a3bf18d7a7007c380af989765b16e9f0
RUN git reset --hard FETCH_HEAD

WORKDIR /build/non-free/unrar
RUN abuild-keygen -i -a -n
RUN abuild -r

# builds something like:
#   /home/apk/packages/non-free/x86_64/unrar-6.1.4-r0.apk
#   /home/apk/packages/non-free/x86_64/unrar-doc-6.1.4-r0.apk

###########################################
# Final stage:
FROM          alpine:3.18
MAINTAINER    Laur Aliste

ENV LANG=C.UTF-8

ADD scripts/* /usr/local/sbin/
ADD files/*   /
COPY --from=build  /home/apk/packages/non-free/x86_64/unrar-6*.apk  /tmp/unrar.apk

RUN apk update && \
    apk add --no-cache --allow-untrusted /tmp/unrar.apk && \
    apk add --no-cache \
        rclone \
        unzip \
        grep \
        file \
        coreutils \
        findutils \
        iputils \
        curl \
        bash \
        ca-certificates \
        shadow \
        tzdata \
        msmtp \
        logrotate && \
    useradd -u 1000 -U -G users -d /config -s /bin/false abc && \
    chown -R root:root /usr/local/sbin/ && \
    chmod -R 755 /usr/local/sbin/ && \
    ln -s /usr/local/sbin/setup.sh /setup.sh && \
    ln -s /usr/local/sbin/sync.sh /sync.sh && \
    ln -s /usr/local/sbin/common.sh /common.sh && \
    rm -rf /var/cache/apk/* /tmp/* /root/.cache

#USER abc  # continue as root, as we need to set UID & GID in entrypoint!
ENTRYPOINT ["/usr/local/sbin/entry.sh"]

