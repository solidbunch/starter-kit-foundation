# Starter Kit Foundation


## Requirements
 
 1. Docker
 2. Docker-compose
 3. To run in dev mode need `nginx-proxy` on `8080:80` port

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
## How to install

### Development mode
 
 1. clone repo
 2. copy `.env.dev.sample` to  `.env`
 3. edit `.env` file - change options, add passwords, etc
 4. run `docker-compose up -d`

### Staging mode
 
 1. clone repo
 2. copy `.env.stage.sample` to  `.env`
 3. edit `.env` file - change options, add passwords, etc
 4. edit `docker-compose.override.yml` - change network data and ports
 5. run `docker-compose up -d`
    
### Production mode
 
 1. clone repo
 2. copy `.env.prod.sample` to  `.env`
 3. edit `.env` file - change options, add passwords, etc
 4. run `docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d`

## Sturcture
 - config/ – config files
 - images/ - docker images (Dockerfiles)
 - logs/ - system and wordpress logs
 - web/ - main project files
    - wordpress-core/ - core wordpress files
    - app/ - application (shared wp-content folder)
        - themes/md-theme/ - main theme
      
