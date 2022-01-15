.SILENT:
# Default values
t?=
INIT_SH=bash sh/init.sh

# Go!
# Generate .env.secret file
.PHONY: secret
secret:
	bash sh/env/secret-gen.sh

# docker-compose build with root .env file concatenation
.PHONY: build
build:
	$(INIT_SH) $(t)
	docker-compose build $(s)

# Regular docker-compose up with root .env file concatenation
.PHONY: up
up:
	$(INIT_SH) $(t)
	docker-compose up -d --build $(s)

# docker-compose up with root .env file concatenation without `-d`
.PHONY: upd
upd:
	$(INIT_SH) $(t)
	docker-compose up --build $(s)

######## Special modes ########
# Root .env file concatenation and docker-compose up. Stage mode
.PHONY: up-stage
up-stage:
	$(INIT_SH) stage
	docker-compose up -d --build $(s)

# Root .env file concatenation and docker-compose up with http > https redirect options. Production mode
.PHONY: up-prod
up-prod:
	$(INIT_SH) prod
	docker-compose up -d --build $(s)
######## Special modes ########


# Just docker-compose down
.PHONY: down
down:
	docker-compose down -v

.PHONY: start
start:
	docker-compose start

.PHONY: stop
stop:
	docker-compose stop

.PHONY: pause
pause:
	docker-compose pause

# Run phpMyadmin docker container
.PHONY: pma-up
pma-up:
	docker-compose -f docker-compose.phpmyadmin.yml up -d --build $(s)

# phpMyadmin down
.PHONY: pma-down
pma-down:
	docker-compose -f docker-compose.phpmyadmin.yml down -v

# Full docker cleanup
.PHONY: docker-clean
docker-clean:
	docker container prune
	docker image prune -a
	docker volume prune
	docker network prune
	docker system prune