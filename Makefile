SHELL = /bin/bash -o pipefail

version   := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "alpha")

archive   := mfa-$(version).tar.gz
build_dir := bundle
image     := ghcr.io/jsks/racket-build:latest

src_files     := $(wildcard src/*.rkt)
systemd_files := $(wildcard etc/systemd/system/*)

all: dist
.PHONY: deploy dist build clean test

deploy: dist
	ansible-playbook -i inventory --extra-vars "version=$(version)" deploy.yml

dist: build
	tar -C $(build_dir) -acf $(archive) .

build: clean
	podman pull $(image)
	podman run --rm -v $(CURDIR):/usr/local/src -it $(image) \
		bash -c "raco exe -o mfa src/main.rkt && raco distribute $(build_dir) mfa"
	cp -r etc/systemd $(build_dir)/lib/

clean:
	rm -rf $(archive) $(build_dir) mfa

test: clean
	raco test -j $(shell nproc) test
