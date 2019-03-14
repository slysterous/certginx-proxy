yes | \cp -rf ./nginx.conf /opt/volumes/nginx/nginx.conf
docker-compose -f nginx-compose.yaml exec nginx nginx -s reload