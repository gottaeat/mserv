FROM alpine:3.22.1 AS mserv

# add virtual mail user and install packages
RUN \
    addgroup -g 700 vmail && \
    adduser -h /var/vmail -H -D -s /sbin/nologin -u 700 -G vmail -g '' \
        vmail && \
    install -d -o vmail -g vmail -m 700 /var/vmail && \
    apk update && apk upgrade --no-cache && apk add --no-cache \
        postfix dovecot dovecot-pigeonhole-plugin opendkim opendkim-utils \
        dumb-init

# copy over conf
COPY ./static/files/dovecot.conf  /etc/dovecot
COPY ./static/files/header_checks /etc/postfix
COPY ./static/files/main.cf       /etc/postfix
COPY ./static/files/master.cf     /etc/postfix
COPY ./static/files/opendkim.conf /etc/opendkim

# entrypoint
COPY ./static/docker /docker
RUN chmod +x /docker/entrypoint.sh

# smtp
EXPOSE 25/tcp
EXPOSE 465/tcp
EXPOSE 587/tcp
# imap
EXPOSE 993/tcp

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/docker/entrypoint.sh"]
