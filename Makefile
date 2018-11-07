
PONYC ?= ponyc
PONYC_FLAGS ?=
config ?= release

BUILD_DIR ?= build/$(config)
SRC_DIR ?= http
EXAMPLES_DIR ?= examples
binary := $(BUILD_DIR)/test
bench_binary := $(BUILD_DIR)/bench

SOURCE_FILES := $(shell find $(SRC_DIR) -name \*.pony)
EXAMPLES_SOURCE_FILES := $(shell find $(EXAMPLES_DIR) -name \*.pony)

ifdef config
  ifeq (,$(filter $(config),debug release))
    $(error Unknown configuration "$(config)")
  endif
endif

ifeq ($(config),debug)
    PONYC_FLAGS += --debug
endif

test: $(binary)
	$(binary)

bench: $(bench_binary)
	$(bench_binary)

$(binary): $(SOURCE_FILES) | $(BUILD_DIR)
	stable env $(PONYC) $(PONYC_FLAGS) $(SRC_DIR)/test -o $(BUILD_DIR)

$(bench_binary): $(SOURCE_FILES) | $(BUILD_DIR)
	stable env $(PONYC) $(PONYC_FLAGS) $(SRC_DIR)/bench -o $(BUILD_DIR)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

examples: $(SOURCE_FILES) $(EXAMPLES_SOURCE_FILES) | $(BUILD_DIR)
	stable env $(PONYC) --path=. $(EXAMPLES_DIR)/httpget -o $(BUILD_DIR) -d -s --checktree --verify
	stable env $(PONYC) --path=. $(EXAMPLES_DIR)/httpserver -o $(BUILD_DIR) -d -s --checktree --verify

.coverage:
	mkdir -p .coverage

coverage: .coverage $(binary)
	kcov --include-pattern="$(SRC_DIR)" --exclude-pattern="*/test/*.pony,*/_test.pony" .coverage $(binary)

clean:
	rm -rf $(BUILD_DIR) .coverage

docs: PONYC_FLAGS += --pass=docs --docs-public --output=docs-tmp
docs:
	rm -rf docs-tmp
	stable env $(PONYC) $(PONYC_FLAGS) $(SRC_DIR)
	cd docs-tmp/http-docs && mkdocs build
	rm -rf docs
	cp -R docs-tmp/http-docs/site docs
	rm -rf docs-tmp

.PHONY: clean test coverage examples docs
