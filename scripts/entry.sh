#!/bin/sh
# alpine-linux entry

/setup.sh || exit 1

# start cron:
/usr/sbin/crond -f -l 8 -L /dev/stdout -c /etc/crontabs
