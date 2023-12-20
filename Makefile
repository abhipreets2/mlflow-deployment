#Make all targets PHONY 
#https://stackoverflow.com/questions/44492805/declare-all-targets-phony
.PHONY: $(shell sed -n -e '/^$$/ { n ; /^[^ .\#][^ ]*:/ { s/:.*$$// ; p ; } ; }' $(MAKEFILE_LIST))

include .envs/.gcp
include .envs/.tracking-server
export

SHELL := /usr/bin/env bash
HOSTNAME := $(shell hostname)

ifeq (, $(shell which docker-compose))
		DOCKER_COMPOSE_COMMAND = docker compose
else
		DOCKER_COMPOSE_COMMAND = docker-compose
endif

lock-dependencies: BUILD_POETRY_LOCK = /root/poetry.lock.build

# Returns true if the stem is a non-empty environment variable, or else raises an error.
guard-%:
	@#$(or ${$*}, $(error $* is not set))

deploy: push
	./scripts/create-server.sh

mlflow-tunnel:
	gcloud compute ssh "$${VM_NAME}" --zone "$${ZONE}" --tunnel-through-iap -- -N -L "$${MLFLOW_PORT}:localhost:$${MLFLOW_PORT}"

build:
	${DOCKER_COMPOSE_COMMAND} build

_build-for-dependencies:
	rm -f *lock
	${DOCKER_COMPOSE_COMMAND} build

push: guard-IMAGE_TAG build
	@gcloud auth configure-docker asia.gcr.io --quiet
	@docker tag "${DOCKER_IMAGE_NAME}:latest" "$${GCP_DOCKER_REGISTERY_URL}:$${IMAGE_TAG}"
	@docker push "$${GCP_DOCKER_REGISTERY_URL}:$${IMAGE_TAG}"

up:
	${DOCKER_COMPOSE_COMMAND} up

upd:
	${DOCKER_COMPOSE_COMMAND} up -d

down:
	$(DOCKER_COMPOSE_COMMAND) down

exec-in: upd
	docker exec -it mlflow-tracking-server bash

lock-dependencies: _build-for-dependencies
	$(DOCKER_COMPOSE_COMMAND) run --entrypoint "" --rm app bash -c "if [ -e $(BUILD_POETRY_LOCK) ]; then cp $(BUILD_POETRY_LOCK) ./poetry.lock; else poetry lock; fi"

clean:
	find . -type f -name "*.py[co]" -delete
	find . -type d -name "__pycache__" -delete

.DEFAULT_GOAL := help

#http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=23 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')
