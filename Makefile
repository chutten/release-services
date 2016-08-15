.PHONY: help develop build-all build docker \
	deploy-staging-all deploy-staging \
	deploy-production-all deploy-production \
	update-all

APP=
APPS=relengapi_clobberer relengapi_frontend


help:
	@echo "TODO: need to write help for commands"




develop: require-APP
	nix-shell nix/default.nix -A $(APP) --run $$SHELL




develop-run: require-APP develop-run-$(APP)

develop-run-relengapi_clobberer:
	CACHE_TYPE=filesystem \
	CACHE_DIR=$$PWD/src/$(APP)/cache \
	DATABASE_URL=sqlite:///$$PWD/app.db \
	APP_SETTINGS=$$PWD/src/$(APP)/settings.py \
		nix-shell nix/default.nix -A $(APP) \
			--run "gunicorn $(APP):app -w 2 -t 3600 --reload --log-file -"

develop-run-relengapi_frontend:
	nix-shell nix/default.nix -A $(APP) --run "neo start --config webpack.config.js"




build-all: build-$(APPS)

build: require-APP build-$(APP)

build-%:
	nix-build nix/default.nix -A $(subst build-,,$@) -o result-$(subst build-,,$@)



docker: require-APP docker-$(APP)

docker-%:
	rm -f result-$@
	nix-build nix/docker.nix -A $(subst docker-,,$@) -o result-$@



deploy-staging-all: deploy-staging-$(APPS)

deploy-staging: require-APP deploy-staging-$(APP)

deploy-staging-relengapi_clobberer: docker-relengapi_clobberer
	if [[ -n "`docker images -q $(subst deploy-staging-,,$@)`" ]]; then \
		docker rmi -f `docker images -q $(subst deploy-staging-,,$@)`; \
	fi
	cat result-$(subst deploy-staging-,docker-,$@) | docker load
	docker tag `docker images -q \
		$(subst deploy-staging-,,$@)` \
		registry.heroku.com/releng-staging-$(subst deploy-staging-,,$@)/web
	docker push \
		registry.heroku.com/releng-staging-$(subst deploy-staging-,,$@)/web

deploy-staging-relengapi_frontend: require-AWS build-relengapi_frontend tools-awscli
	./result-tools-awscli/bin/aws s3 sync \
		--delete \
		--acl public-read  \
		result-$(subst deploy-staging-,,$@)/ \
		s3://$(subst deploy-,releng-,$(subst _,-,$@))





deploy-production-all: deploy-production-$(APPS)

deploy-production: $(APP) deploy-production-$(APP)

deploy-production-relengapi_clobberer: docker-relengapi_clobberer
	if [[ -n "`docker images -q $(subst deploy-production-,,$@)`" ]]; then \
		docker rmi -f `docker images -q $(subst deploy-production-,,$@)`; \
	fi
	cat result-$(subst deploy-production-,docker-,$@) | docker load
	docker tag `docker images -q \
		$(subst deploy-production-,,$@)` \
		registry.heroku.com/releng-production-$(subst deploy-production-,,$@)/web
	docker push \
		registry.heroku.com/releng-production-$(subst deploy-production-,,$@)/web

deploy-production-relengapi_frontend: require-AWS build-relengapi_frontend tools-awscli
	./result-tools-awscli/bin/aws s3 sync \
		--delete \
		--acl public-read \
		result-$(subst deploy-production-,,$@)/ \
		s3://$(subst deploy-,releng-,$(subst _,-,$@))



update-all: \
	update-nixpkgs \
	update-tools \
	update-$(APPS)

update-%:
	echo $@
	nix-shell nix/update.nix --argstr pkg $(subst update-,,$@)



# --- helpers

tools-awscli:
	nix-build nix/default.nix -A tools.awscli -o result-tools-awscli

require-APP:
	@if [[ -z "$(APP)" ]]; then \
		echo ""; \
		echo "You need to specify which APP, eg:"; \
		echo "  make develop APP=relengapi_clobberer"; \
		echo "  make build APP=relengapi_clobberer"; \
		echo "  ..."; \
		echo ""; \
		echo "Available APPS are: "; \
		for app in "$(APPS)"; do \
			echo " - $$app"; \
		done; \
		echo ""; \
		exit 1; \
	fi


require-AWS:
	@if [[ -z "$$AWS_ACCESS_KEY_ID" ]] || \
		[[ -z "$$AWS_SECRET_ACCESS_KEY" ]]; then \
		echo ""; \
		echo "You need to specify AWS credentials, eg:"; \
		echo "  make deploy-production-relengapi_clobberer \\"; \
	    echo "       AWS_ACCESS_KEY_ID=\"...\" \\"; \
		echo "       AWS_SECRET_ACCESS_KEY=\"...\""; \
		echo ""; \
		echo ""; \
		exit 1; \
	fi