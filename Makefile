SHELL = /bin/bash -o pipefail

container_runner ?= podman
version          ?= $(shell echo `date +'%Y-%m-%d'`-`git rev-parse --short HEAD`)

build_dir := build
bindir    := $(build_dir)/bin
datadir   := $(build_dir)/share
libdir    := $(build_dir)/lib

archive   := mfa-$(version).tar.zst
image     := ghcr.io/jsks/racket-build:latest

src_files     := $(wildcard src/*.rkt)

all: deploy
.PHONY: deploy build copy exe clean test

deploy: build
	ansible-playbook -i inventory --extra-vars "version=$(version)" deploy.yml

build: exe copy
	tar -C $(build_dir) -acf $(archive) .

copy:
	install -D etc/systemd/system/* -t $(libdir)/systemd/system/
	install -D -m644 sql/* -t $(datadir)/mfa/sql/
	install -D -m644 refs/accounts.csv $(datadir)/mfa/accounts.csv
	install -D -m755 scripts/bootstrap.sh $(bindir)/bootstrap.sh
	@sed -i -e '/^source.*/r scripts/base.sh' -e 's///' $(bindir)/bootstrap.sh

exe:
	$(container_runner) run --rm -v $(CURDIR):/usr/local/src $(image) \
		bash -c "raco exe -o mfa src/main.rkt && raco distribute $(build_dir) mfa"

clean:
	rm -rf $(archive) $(build_dir) mfa

test:
	raco test -j $(shell nproc) test
