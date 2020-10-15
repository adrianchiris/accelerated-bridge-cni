# Package related
BINARY_NAME     = sriov
PACKAGE         = switchdev-cni
ORG_PATH        = github.com/DmytroLinkin
REPO_PATH       = $(ORG_PATH)/$(PACKAGE)
GOPATH          = $(CURDIR)/.gopath
GOBIN           = $(CURDIR)/bin
BUILDDIR        = $(CURDIR)/build
BASE            = $(GOPATH)/src/$(REPO_PATH)
GOFILES         = $(shell find . -name *.go | grep -vE "(\/vendor\/)|(_test.go)")
PKGS            = $(or $(PKG),$(shell cd $(BASE) && env GOPATH=$(GOPATH) $(GO) list ./... | grep -v "^$(PACKAGE)/vendor/"))
TESTPKGS        = $(shell env GOPATH=$(GOPATH) $(GO) list -f '{{ if or .TestGoFiles .XTestGoFiles }}{{ .ImportPath }}{{ end }}' $(PKGS))

export GOPATH
export GOBIN

# Version
VERSION?        = master
DATE            = `date -Iseconds`
COMMIT?         = `git rev-parse --verify HEAD`
LDFLAGS         = "-X main.version=$(VERSION) -X main.commit=$(COMMIT) -X main.date=$(DATE)"

# Docker
IMAGE_BUILDER  ?= @docker
IMAGEDIR        = $(BASE)/images
DOCKERFILE      = $(CURDIR)/Dockerfile
TAG             = mellanox/sriov-cni-test
# Accept proxy settings for docker
# To pass proxy for Docker invoke it as 'make image HTTP_POXY=http://192.168.0.1:8080'
DOCKERARGS      =
ifdef HTTP_PROXY
	DOCKERARGS += --build-arg http_proxy=$(HTTP_PROXY)
endif
ifdef HTTPS_PROXY
	DOCKERARGS += --build-arg https_proxy=$(HTTPS_PROXY)
endif

# Go tools
GO              = go
TIMEOUT         = 15
V               = 0
Q               = $(if $(filter 1,$V),,@)

.PHONY: all
all: build test-coverage

$(BASE): ; $(info  setting GOPATH...)
	@mkdir -p $(dir $@)
	@ln -sf $(CURDIR) $@

$(GOBIN):
	@mkdir -p $@

$(BUILDDIR): | $(BASE) ; $(info Creating build directory...)
	@cd $(BASE) && mkdir -p $@

build: $(BUILDDIR)/$(BINARY_NAME) ; $(info Building $(BINARY_NAME)...) ## Build executable file
	$(info Done!)

$(BUILDDIR)/$(BINARY_NAME): $(GOFILES) | $(BUILDDIR)
	@cd $(BASE)/cmd/$(BINARY_NAME) && CGO_ENABLED=0 $(GO) build -o $(BUILDDIR)/$(BINARY_NAME) -tags no_openssl -ldflags $(LDFLAGS) -v


# Tests
TEST_TARGETS := test-default test-bench test-short test-verbose test-race
.PHONY: $(TEST_TARGETS) test-xml check test tests
test-bench:   ARGS=-run=__absolutelynothing__ -bench=. ## Run benchmarks
test-short:   ARGS=-short        ## Run only short tests
test-verbose: ARGS=-v            ## Run tests in verbose mode with coverage reporting
test-race:    ARGS=-race         ## Run tests with race detector
$(TEST_TARGETS): NAME=$(MAKECMDGOALS:test-%=%)
$(TEST_TARGETS): test
check test tests: $(BASE) ; $(info  running $(NAME:%=% )tests...) @ ## Run tests
	$Q cd $(BASE) && $(GO) test -timeout $(TIMEOUT)s $(ARGS) $(TESTPKGS)

test-xml: $(BASE) $(GO2XUNIT) ; $(info  running $(NAME:%=% )tests...) @ ## Run tests with xUnit output
	$Q cd $(BASE) && 2>&1 $(GO) test -timeout 20s -v $(TESTPKGS) | tee test/tests.output
	$(GO2XUNIT) -fail -input test/tests.output -output test/tests.xml

COVERAGE_MODE = count
test-coverage-tools: | $(GOVERALLS)
test-coverage: test-coverage-tools | $(BASE) ; $(info  running coverage tests...) @ ## Run coverage tests
	$Q cd $(BASE); $(GO) test -covermode=$(COVERAGE_MODE) -coverprofile=sriov-cni.cover ./...

# Docker image
.PHONY: image
image: | $(BASE) ; $(info Building Docker image...)
	$(IMAGE_BUILDER) build -t $(TAG) -f $(DOCKERFILE)  $(CURDIR) $(DOCKERARGS)

# Dependency management
.PHONY: deps-update
deps-update: ; $(info  updating dependencies...)
	@$(GO) mod tidy && $(GO) mod vendor

# Misc
.PHONY: clean
clean: ; $(info  Cleaning...)	@ ## Cleanup everything
	@$(GO) clean -modcache
	@rm -rf $(GOPATH)
	@rm -rf $(BUILDDIR)
	@rm -rf test
	@rm -rf bin

.PHONY: help
help: ## Show this message
	@grep -E '^[ a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
