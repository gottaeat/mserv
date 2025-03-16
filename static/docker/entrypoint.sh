#!/bin/sh
. /docker/common

set -e
# - - graceful shutdown - - #
stop() {
    pinfo "stopping mserv down"

    pinfo "stopping postfix"
    postfix stop

    while pidof pickup qmgr smtpd proxymap tlsmgr anvil >/dev/null 2>&1; do
        sleep 1
    done

    pinfo "stopping dovecot"
    dovecot stop
    while pidof dovecot >/dev/null 2>&1; do
        sleep 1
    done

    pinfo "stopping opendkim"
    pkill -15 opendkim
    while pidof opendkim >/dev/null 2>&1; do
        sleep 1
    done

    pinfo "going down"
    exit 0
}

trap stop SIGTERM SIGINT

# - - sanity checks - - #
# ensure bind mounts are there
for path in postfix dovecot opendkim etc/letsencrypt; do
    if ! mountpoint "/${i}" >/dev/null 2>&1; then
        perr "/${i} is not a mountpoint"
    fi
done

# - - start - - #
pinfo "started mserv for: ${HOSTNAME}"

# - - template - - #
pinfo "setting postfix tls key and cert file paths"
postconf -e "smtpd_tls_key_file=/etc/letsencrypt/live/${HOSTNAME}/privkey.pem"
postconf -e "smtpd_tls_cert_file=/etc/letsencrypt/live/${HOSTNAME}/fullchain.pem"

pinfo "templating dovecot local.conf"
cat << EOF > /etc/dovecot/local.conf
ssl_cert = </etc/letsencrypt/live/${HOSTNAME}/fullchain.pem
ssl_key = </etc/letsencrypt/live/${HOSTNAME}/privkey.pem
postmaster_address = postmaster@${HOSTNAME}
EOF

# - - sanity check pt.2 - - #
# ensure ownership
pinfo "fixing perms"
chown -Rh vmail:vmail /var/vmail
chown -Rh opendkim:opendkim /opendkim
find /opendkim/keys -type f -name \*.private -exec chmod 0600 {} ';'

# create lmdbs
pinfo "creating lmbdb's for postfix"
for i in \
    virtual_mailbox_domains \
    controlled_envelope_senders \
    virtual_mailbox_maps \
    virtual_alias_maps; do
        postmap "/postfix/${i}"
done

# - - action - - #
pinfo "starting syslogd"
syslogd -O - -n &

pinfo "starting opendkim"
opendkim

pinfo "starting dovecot"
dovecot

pinfo "starting postfix"
postfix start

pinfo "entered final wait"
wait
