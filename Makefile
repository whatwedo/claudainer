.PHONY: test test-build test-bats test-cst test-integration

TEST := tests/bin/test.sh

test:
	$(TEST)

test-build:
	$(TEST) build

test-bats:
	$(TEST) bats

test-cst:
	$(TEST) cst

test-integration:
	$(TEST) integration
