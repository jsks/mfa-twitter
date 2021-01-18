src_files = $(wildcard src/*.rkt)

all: launcher
.PHONY: clean

app: mfa
	raco distribute $@ $<

mfa: $(src_files)
	raco exe -o $@ src/main.rkt

launcher: | src/compiled
	raco exe -l --exf -U -o $@ src/main.rkt

src/compiled: $(src_files)
	raco make -j $(shell nproc) src/main.rkt

clean:
	rm -rf app launcher mfa src/compiled
