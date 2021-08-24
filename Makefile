.SILENT:

secret:
	bash sh/env/secret-gen.sh

up:
	bash sh/env/init.sh $(t) && docker-compose up -d $(s)

upp:
	bash sh/env/init.sh $(t) && docker-compose -f docker-compose.yml -f docker-compose.proxy.yml up -d $(s)

down:
	docker-compose down -v

start:
	docker-compose start

stop:
	docker-compose stop

pause:
	docker-compose pause

pma-up:
	docker-compose -f docker-compose.phpmyadmin.yml up -d $(s)

pma-down:
	docker-compose -f docker-compose.phpmyadmin.yml down -v

backup-init:
	sudo bash sh/backup/backup-init.sh