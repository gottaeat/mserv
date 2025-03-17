# mserv
mserv provides a secure out of the box production quality mail server, utilizing
postfix, dovecot and opendkim.

__WARNING__: mserv assumes that you are intending to run a bare domain mail
server, meaning that you have your MX record set to the domain itself e.g.:
```
example.com. 300 IN MX 10 example.com.
```

## features
1. sasl auth is allowed only on submission{,s} ports, auth on smtp is rejected.
2. dovecot only serves imap4, and does so only on tcp port 993.
3. ingress messages are checked for dkim, egress is signed with.
4. user spoofing is mitigated with postfix sender restictions and envelope
   sender mappings.

## installation
### 1. prerequisites
#### 1.1. pull repo
```sh
git clone --depth=1 https://github.com/gottaeat/mserv
cd mserv/
```

#### 1.2. set a domain and define its public v4
```sh
_MYDOMAIN="example.com"
_MYPUBIP="1.1.1.1"
```

#### 1.3. gen a letsencrypt cert
mserv expects valid certs for `$_MYDOMAIN` to be present under
`/etc/letsencrypt`.

#### 1.4. create the bind-mount volume structure
```sh
mkdir -pv ./data/config/{postfix,dovecot/keys,opendkim}
```

### 2. postfix
#### 2.1. register your domain
```sh
echo "${_MYDOMAIN} 20080428" > data/config/postfix/virtual_mailbox_domains
```

#### 2.2. define users and their mailboxes
create as many users as necessary. `admin` is used here so we can alias
`postmaster` to it, can be arbitrary, just ensure that you alias `postmaster` to
it.
```sh
cat << EOF > data/config/postfix/virtual_mailbox_maps
admin@${_MYDOMAIN} ${_MYDOMAIN}/admin/
EOF
```

#### 2.3. map the user(s) to themselves in the envelope senders
```sh
cat << EOF > data/config/postfix/controlled_envelope_senders
admin@${_MYDOMAIN} admin@${_MYDOMAIN}
EOF
```

#### 2.4. define aliases
the `postmaster` alias is necessary.
```sh
cat << EOF > data/config/postfix/virtual_alias_maps
postmaster@${_MYDOMAIN} admin@${_MYDOMAIN}
EOF
```

### 3. dovecot
#### 3.1. create `userdb` entries for the user(s)
get the hashed password via `docker compose run --rm -it mserv doveadm pw -s
SHA512-CRYPT`, edit the `data/config/dovecot/userdb` manually to avoid having
to escape the `$` characters. the end result should look similar to:
```sh
admin@${_MYDOMAIN}:<hash_here>
```

### 4. opendkim
#### 4.1. create the DKIM privkey
set the output as the DKIM record for your domain.
```sh
mkdir -pv data/config/opendkim/keys/"${_MYDOMAIN}"
docker compose run --rm -it mserv ash -c "
    cd /opendkim/keys/${_MYDOMAIN}
    opendkim-genkey -s mail -d ${_MYDOMAIN}
    cat mail.txt"
```

#### 4.2. create KeyTable, SigningTable and TrustedHosts
```sh
cat << EOF > data/config/opendkim/KeyTable
mail._domainkey.${_MYDOMAIN} ${_MYDOMAIN}:mail:/opendkim/keys/${_MYDOMAIN}/mail.private
EOF

cat << EOF > data/config/opendkim/SigningTable
*@${_MYDOMAIN} mail._domainkey.${_MYDOMAIN}
EOF

cat << EOF > data/config/opendkim/TrustedHosts
127.0.0.1
localhost
${_MYDOMAIN}
${_MYPUBIP}
EOF
```

### 5. bringup
#### 5.1. add SPF and DMARC records for maximum deliverability
add the following records to your DNS:
```zone
_dmarc.${_MYDOMAIN}. 300 IN TXT "v=DMARC1; p=reject; rua=mailto:postmaster@${_MYDOMAIN}; ruf=mailto:postmaster@${_MYDOMAIN}; sp=reject; aspf=s; adkim=s; fo=1;"
${_MYDOMAIN}.        300 IN TXT "v=spf1 a mx ip4:${_MYPUBIP} ra=postmaster -all"
```
#### 5.2. action
edit `docker-compose.yml` and set the `hostname:` key to the value of
`$_MYDOMAIN`, then fire up the mail server with:
```sh
docker compose up -d
```

## maintenance
you can follow the steps for postfix and dovecot for adding and removing users
and aliases without bringing the container down. once the files are to your
liking, pop into the container via `docker exec -it mserv ash` and do:
```sh
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
