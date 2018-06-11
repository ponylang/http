
PONYC ?= ponyc

bin/test: bin http/*.pony http/test/*.pony
	stable env $(PONYC) http/test -o bin --debug

bin:
	mkdir -p bin

test: bin/test
	bin/test

examples:
	stable env $(PONYC) examples/httpget -o bin -d -s --checktree --verify
	stable env $(PONYC) examples/httpserver -o bin -d -s --checktree --verify

.coverage:
	mkdir -p .coverage

coverage: .coverage bin/test
	kcov --include-pattern="${PWD}/http" --exclude-pattern="*/test/*.pony,*/_test.pony" .coverage bin/test

clean:
	rm -rf bin .coverage

.PHONY: clean test coverage examples
