config ?= release

PACKAGE := http
GET_DEPENDENCIES_WIITH := corral fetch
CLEAN_DEPENDENCIES_WIITH := corral clean
COMPILE_WITH := corral run -- ponyc

BUILD_DIR ?= build/$(config)
SRC_DIR ?= $(PACKAGE)
EXAMPLES_DIR := examples
TEST_DIR := $(SRC_DIR)/test
BENCH_DIR := bench
tests_binary := $(BUILD_DIR)/test
bench_binary := $(BUILD_DIR)/bench
docs_dir := build/$(PACKAGE)-docs

ifdef config
	ifeq (,$(filter $(config),debug release))
		$(error Unknown configuration "$(config)")
	endif
endif

ifeq ($(config),release)
	PONYC = ${COMPILE_WITH}
else
	PONYC = ${COMPILE_WITH} --debug
endif

ifeq (,$(filter $(MAKECMDGOALS),clean docs realclean TAGS))
  ifeq ($(ssl), 1.1.x)
	  SSL = -Dopenssl_1.1.x
  else ifeq ($(ssl), 0.9.0)
	  SSL = -Dopenssl_0.9.0
  else
    $(error Unknown SSL version "$(ssl)". Must set using 'ssl=FOO')
  endif
endif

PONYC := $(PONYC) $(SSL)

SOURCE_FILES := $(shell find $(SRC_DIR) -name \*.pony)
EXAMPLE_SOURCE_FILES := $(shell find $(EXAMPLES_DIR) -name \*.pony)
BENCH_SOURCE_FILES := $(shell find $(BENCH_DIR) -name \*.pony)

test: unit-tests build-examples

unit-tests: $(tests_binary)
	$^ --exclude=integration --sequential

$(tests_binary): $(SOURCE_FILES) | $(BUILD_DIR)
	${GET_DEPENDENCIES_WIITH}
	${PONYC} -o ${BUILD_DIR} $(TEST_DIR)

build-examples: $(SOURCE_FILES) $(EXAMPLE_SOURCE FILES)| $(BUILD_DIR)
	${GET_DEPENDENCIES_WIITH}
	find examples/*/* -name '*.pony' -print | xargs -n 1 dirname  | sort -u | grep -v ffi- | xargs -n 1 -I {} ${PONYC} -s --checktree -o ${BUILD_DIR} {}

clean:
	${CLEAN_DEPENDENCIES_WIITH}
	rm -rf $(BUILD_DIR)

$(docs_dir): $(SOURCE_FILES)
	rm -rf $(docs_dir)
	${GET_DEPENDENCIES_WIITH}
	${PONYC} --docs-public --pass=docs --output build $(SRC_DIR)

docs: $(docs_dir)

$(bench_binary): $(SOURCE_FILES) $(BENCH_SOURCE_FILES) | $(BUILD_DIR)
	${GET_DEPENDENCIES_WIITH}
	$(PONYC) $(BENCH_DIR) -o $(BUILD_DIR)

bench: $(bench_binary)
	$(bench_binary)

.coverage:
	mkdir -p .coverage

coverage: .coverage $(tests_binary)
	kcov --include-pattern="$(SRC_DIR)" --exclude-pattern="*/test/*.pony,*/_test.pony" .coverage $(tests_binary)

TAGS:
	ctags --recurse=yes $(SRC_DIR)

all: test

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

.PHONY: all clean TAGS test
