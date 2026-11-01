.PHONY: build up down shell logs cli help

build:
	docker compose build

up:
	docker compose up -d --build

down:
	docker compose down

shell:
	docker compose exec agent-browser bash

logs:
	docker compose logs -f agent-browser

# Usage: make cli CMD='open https://example.com --headed'
cli:
	@test -n "$(CMD)" || (echo 'Usage: make cli CMD='\''open https://example.com --headed'\''' >&2; exit 1)
	docker compose exec agent-browser playwright-cli $(CMD)

help:
	@echo "Targets: up down build shell logs cli"
	@echo "  make up"
	@echo "  make cli CMD='open https://example.com --headed'"
	@echo "  Live view: http://localhost:6080/vnc.html?autoconnect=true&resize=scale"
