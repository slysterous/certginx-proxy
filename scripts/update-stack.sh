#!/bin/bash

. ../.env.example

printenv

IFS=', ' read -r -a domains <<< "${DOMAINS}"

rsa_key_size=${RSA_SIZE}

volume_path=${VOLUME_PATH}

#data_path="./data/certbot"

certbot_data_path="$volume_path/certbot"
dh_param_path="$volume_path/certbot/conf/ssl-dhparams.pem"

#rm -Rf ${VOLUME_PATH}/nginx/*

envsubst '\$DOMAINS \$CERT_FOLDER' < ../nginx/nginx.conf > ${VOLUME_PATH}/nginx/nginx.conf 

yes | \cp -rf ../nginx/404.html ${VOLUME_PATH}/nginx-pages/404.html

email=${CERTBOT_EMAIL}

read -p "Create debug ssl certificates?(y/N) " createdebug

staging=1 # Set to 1 if you're testing your setup to avoid hitting request limits on letsencrypt

if [ "$createdebug" != "Y" ] && [ "$createdebug" != "y" ]; then
  staging=0 
fi


if [ -d "$certbot_data_path" ]; then
  read -p "Existing data found for $domains. Continue and replace existing certificate? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit
  fi
fi


printf "### Generating recommended TLS parameters ...\n"
mkdir -p "$certbot_data_path/conf"
read -p "1. This is a time consuming process. Generate new DH parameters? (y/N):" decision
if [ "$decision" != "N" ] && [ "$decision" != "n" ]; 
then
    printf "Generating new DH parameters...\n"
    openssl dhparam -out ${VOLUME_PATH}/certbot/conf/ssl-dhparams.pem ${RSA_SIZE}
    printf "${GREEN}OK${NC}\n"

else
    if [ -e "$dh_param_path" ]; then
        printf "Using existing DH parameters..."
        printf "${GREEN}OK${NC}\n"
    else
        printf "Using Default DH parameters..."
        yes | \cp -rf ../nginx/ssl-dhparams.pem ${VOLUME_PATH}/certbot/conf/ssl-dhparams.pem
        printf "${GREEN}OK${NC}\n"
    fi
fi

printf "2. Copying new nginx configuration to appropriate volume..."
yes | \cp -rf ../nginx/options-ssl-nginx.conf ${VOLUME_PATH}/certbot/conf/options-ssl-nginx.conf
printf "${GREEN}OK${NC}\n"


printf "### Creating a dummy certificate for $domains ...\n"

path="/etc/letsencrypt/live/$domains"
mkdir -p "$certbot_data_path/conf/live/$domains"
docker-compose -p vps -f ../nginx/nginx-compose.yaml run  --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:1024 -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot

printf "${GREEN}OK${NC}\n"

printf "### Starting nginx...\n"
docker-compose -p vps -f ../nginx/nginx-compose.yaml up --force-recreate -d nginx
printf "${GREEN}OK${NC}\n"

printf "### Deleting dummy certificate for $domains ...\n"
#TODO change here?
docker-compose -p vps -f ../nginx/nginx-compose.yaml run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domains && \
  rm -Rf /etc/letsencrypt/archive/$domains && \
  rm -Rf /etc/letsencrypt/renewal/$domains.conf" certbot
printf "${GREEN}OK${NC}\n"

printf "### Requesting Let's Encrypt certificate for $domains ...\n"
#Join $domains to -d args
domain_args=""
for domain in "${domains[@]}"; do
  printf "$domain\n"
  domain_args="$domain_args -d $domain"
done
printf "${GREEN}OK${NC}\n"

# Select appropriate email arg
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

docker-compose -p vps -f ../nginx/nginx-compose.yaml run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
printf

printf "### Reloading nginx ..."

docker-compose -p vps -f ../nginx/nginx-compose.yaml exec nginx nginx -s reload

printf "${GREEN}OK${NC}\n"


#printf "### Deploying everything else"

#for file in ../deployment_scripts/*; do
    #[ -f "$file" ] && [ -x "$file" ] && "$file"
#done