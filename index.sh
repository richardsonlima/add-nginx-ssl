#!/bin/bash

ALL=false
HELP=false

while true; do
  case "$1" in
    --all)             ALL=true; shift ;;
    -a)                ALL=true; shift ;;
    --domain)          DOMAIN="$2"; shift; shift ;;
    -d)                DOMAIN="$2"; shift; shift ;;
    --help)            HELP=true; shift ;;
    -h)                HELP=true; shift ;;
    --key)             KEY="$2"; shift; shift ;;
    -k)                KEY="$2"; shift; shift ;;
    --crt)             CERT="$2"; shift; shift ;;
    --cert)            CERT="$2"; shift; shift ;;
    -c)                CERT="$2"; shift; shift ;;
    --dhparam)         DHPARAM="$2"; shift; shift ;;
    -p)                DHPARAM="$2"; shift; shift ;;
    *)                 break ;;
  esac
done

error () {
  echo "$1" >&2
  exit 1
}

check_file () {
  [ -f "$1" ] && return 0
  error "$1 does not exist"
}

if $HELP; then
  cat <<EOF
Usage: add-nginx-ssl [options]
  --key,     -k  ssl-private-key.key (required)
  --cert,    -c  ssl-certificate.crt (required)
  --dhparam, -p  dhparam.pem
  --all,     -a  (add ssl to all domains)
  --domain,  -d  example.com

EOF
  exit 0
fi

if [ "$DHPARAM" != "" ]; then
  check_file "$DHPARAM"
  SSL_DHPARAM="ssl_dhparam $(realpath $DHPARAM);";
fi

[ "$KEY" == "" ] && error "--key is required"
[ "$CERT" == "" ] && error "--cert is required"
[ "$DOMAIN" == "" ] && ! $ALL && error "--domain or --all is required"

check_file "$KEY"
check_file "$CERT"

SERVER_NAME="server_name *;"

if [ "$DOMAIN" != "" ]; then
  SERVER_NAME="server_name $DOMAIN;"
  [ "*.${DOMAIN:2}" == "$DOMAIN" ] && WILCARD_SERVER_NAME="server_name ${DOMAIN:2};"
fi

cat <<EOF
server {
  listen 80;
  $SERVER_NAME
  $WILCARD_SERVER_NAME
  return 301 https://\$host\$request_uri;
}

# default config (server_name _; makes this 'base' config)
server {
  listen 443 default ssl;
  server_name _;

  ssl_certificate_key $(realpath "$KEY");
  ssl_certificate $(realpath "$CERT");

  # These this next block of settings came directly from the SSLMate recommend nginx configuration
  # Recommended security settings from https://wiki.mozilla.org/Security/Server_Side_TLS
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA';
  ssl_prefer_server_ciphers on;
  ssl_session_timeout 5m;
  ssl_session_cache shared:SSL:5m;
  # Enable this if you want HSTS (recommended)
  add_header Strict-Transport-Security max-age=15768000;

  # from https://gist.github.com/konklone/6532544
  # Generated by OpenSSL with the following command:
  # openssl dhparam -outform pem -out dhparam2048.pem 2048
  $SSL_DHPARAM
}
EOF > /tmp/nginx.ssl.conf

[ ! -O /etc/nginx/conf.d ] && SUDO_MAYBE=sudo
$SUDO_MAYBE mv /tmp/nginx.ssl.conf /etc/nginx/conf.d/ssl.conf
$SUDO_MAYBE nginx -s reload

echo "Wrote nginx SSL config to /etc/nginx/conf.d/ssl.conf"
