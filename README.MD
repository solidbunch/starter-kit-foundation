# Starter Kit Foundation

Starter Kit Foundation - is developers tool, server environment for fast and easy start WordPres project with docker containers, convenient credential settings etc

## Requirements
 
1. Docker and Docker-compose
2. To run in proxy mode need `nginx-proxy` (optional)

## How to use

### Development mode
 
1. clone repo
2. copy `.env.dev.sample` to  `.env`
3. edit `.env` file - change options, url and port, passwords, etc
4. run `docker-compose up -d`

### Staging mode
 
1. clone repo
2. copy `.env.stage.sample` to  `.env`
3. edit `.env` file - change options, url and port, passwords, etc
4. run `docker-compose up -d`
    
### Production mode
 
1. clone repo
2. copy `.env.prod.sample` to  `.env`
3. edit `.env` file - change options, url and port, passwords, etc
4. run `docker-compose up -d`

### Proxy mode

1. start nginx-proxy container https://hub.docker.com/r/jwilder/nginx-proxy

```
version: '3.9'
services:
  nginx-proxy:
    image: jwilder/nginx-proxy:alpine
    container_name: nginx-proxy
    ports:
      - "8080:80"
      - "80:80"
      - "8443:443"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
    restart: always

networks:
  default:
    external:
      name: nginx-proxy

```

2. clone repo, copy `.env` file the same as already described for dev, stage or prod mode
3. run `docker-compose -f docker-compose.yml -f docker-compose.proxy.yml up -d`


## Sturcture
 - config/ – config files
 - images/ - docker images (Dockerfiles)
 - logs/ - system and wordpress logs
 - web/ - main project files
    - wordpress-core/ - core wordpress files
    - app/ - application (shared wp-content folder)
        - themes/md-theme/ - main theme
      
