#!/bin/bash

. ../.env.example
volume_path=${VOLUME_PATH}
yes | \cp -rf ../template/template-nginx.conf ${VOLUME_PATH}/nginx/template-nginx.conf
printf "Deploying jenkings!"

docker-compose -p vps -f ../template/template-compose.yaml up --force-recreate -d template
printf "${GREEN}OK${NC}\n"

printf "### Reloading nginx ..."

docker-compose -p vps -f ../nginx/nginx-compose.yaml exec nginx nginx -s reload

printf "${GREEN}OK${NC}\n"