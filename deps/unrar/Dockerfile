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

RUN mkdir -p /build/unrar-target
RUN chown -R apk /build 
RUN echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER

# abuild needs to be executed as non-root:
USER "$USER"
WORKDIR /build

# either use our own apkbuild & makefile.patch...
ADD APKBUILD makefile.patch  /build

# ...or pull from aports:
#RUN git init
#RUN git remote add origin https://github.com/alpinelinux/aports
#RUN git fetch origin 6fcec524a3bf18d7a7007c380af989765b16e9f0
#RUN git reset --hard FETCH_HEAD
#WORKDIR /build/non-free/unrar

RUN abuild-keygen -i -a -n
RUN abuild -r
#RUN mv /home/apk/packages/non-free/x86_64/unrar-* /build/unrar-target
RUN mv /home/apk/packages/x86_64/unrar-* /build/unrar-target

# builds something like:
#   /home/apk/packages/non-free/x86_64/unrar-6.1.4-r0.apk
#   /home/apk/packages/non-free/x86_64/unrar-doc-6.1.4-r0.apk
