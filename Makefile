SHELL := /bin/bash
WP_ENVIRONMENT_TYPE=development

up:
	@bash run-docker-compose.sh -e .env -e .env.development -e .env.local -f docker-compose.yml -f docker-compose.proxy.yml $(type)

down:
	bash run-docker-compose.sh -e .env -e .env.development -e .env.local down

test:
	test