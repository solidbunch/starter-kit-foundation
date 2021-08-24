.SILENT:

secret:
	bash sh/env/secret-gen.sh

up:
	bash sh/env/init.sh $(t) && docker-compose up -d

upp:
	bash sh/env/init.sh $(t) && docker-compose -f docker-compose.yml -f docker-compose.proxy.yml up -d

down:
	docker-compose down -v

start:
	docker-compose start

stop:
	docker-compose stop

pause:
	docker-compose pause

backup-init:
	sudo bash sh/backup/backup-init.sh