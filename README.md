# mserv
mserv provides a secure-out-of-the-box, production quality, mail server
utilizing postfix, dovecot and opendkim.

## features
1. sasl auth is allowd only on submissions{,s}, and with enforced tls.
2. dovecot only serves imap4, and does so only on tcp port 993.
3. ingress messages are checked for dkim, egress is signed with.
4. `From:` spoofing is mitigated with postfix restrictions and envelope sender
   mappings.

## installation
```
# - - pre flight - - #
# pull repo
git clone https://github.com/gottaeat/mserv
cd mserv/

# set a domain and define its public v4
_MYDOMAIN="example.com"
_MYPUBIP="1.1.1.1"

# create the data volume
mkdir -pv ./data/{postfix,dovecot/keys,opendkim}

# - - postfix - - #
# register domain
cat << EOF > data/postfix/virtual_mailbox_domains
${_MYDOMAIN} 20080428
EOF

# map the mailbox for the admin user
cat << EOF > data/postfix/virtual_mailbox_maps
admin@${_MYDOMAIN} ${_MYDOMAIN}/admin/
EOF

# map the user in the envelope senders to mitigate spoofing
cat << EOF > data/postfix/controlled_envelope_senders
admin@${_MYDOMAIN} admin@${_MYDOMAIN}
EOF

# alias postmaster to admin, necessary
cat << EOF > data/postfix/virtual_alias_maps
postmaster@${_MYDOMAIN} admin@${_MYDOMAIN}
EOF

# - - dovecot - - #
# create userdb entry for the admin user, get the hash via:
# `docker compose run --rm -it mserv doveadm pw -s SHA512-CRYPT`
cat << EOF > data/dovecot/userdb
admin@${_MYDOMAIN}:<hash_here>
EOF

# - - opendkim - - #
# create dkim privkey, get the output and set it as your dkim record
mkdir -pv data/opendkim/keys/"${_MYDOMAIN}"
docker compose run --rm -it \
    -v "${PWD}"/data/opendkim/keys/"${_MYDOMAIN}":/keygen mserv ash -c "
    cd /keygen
    opendkim-genkey -s mail -d ${_MYDOMAIN}
    cat mail.txt"

# create KeyTable, SigningTable and TrustedHosts
cat << EOF > data/opendkim/KeyTable
mail._domainkey.${_MYDOMAIN} ${_MYDOMAIN}:mail:/opendkim/keys/${_MYDOMAIN}/mail.private
EOF

cat << EOF > data/opendkim/SigningTable
*@${_MYDOMAIN} mail._domainkey.${_MYDOMAIN}
EOF

cat << EOF > data/opendkim/TrustedHosts
127.0.0.1
localhost
${_MYDOMAIN}
${_MYPUBIP}
EOF

# - - bringup - - #
# set the hostname: key in the docker-compose.yml to the value of ${_MYDOMAIN}
docker compose up -d
```

## maintenance
for adding/removing users, you can redo/undo the steps we followed for setting
up the admin user, once the files are altered, do:
```
for i in \
    virtual_mailbox_domains \
    controlled_envelope_senders \
    virtual_mailbox_maps \
    virtual_alias_maps; do
        postmap "/postfix/${i}"
done

postfix reload
dovecot reload
```
