TARGET_BRANCH ?= main

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Linting:

.PHONY: lint
lint: ## Lint the charts using chart-testing
	@echo Linting charts…
	@ct lint --config ct.yaml --target-branch $(TARGET_BRANCH) --check-version-increment=false

lint-release: ## Lint the charts using chart-testing for release
	@echo Linting charts…
	@ct lint --config ct.yaml --target-branch $(TARGET_BRANCH)

##@ Testing: (ensure to run on dedicated test cluster)

.PHONY: clean-test-leftovers
clean-test-leftovers: ## Cleans up any lingering resources in case tests fail massively
	@echo Cleanup potential leftovers…
	@-kubectl delete csidrivers.storage.k8s.io csi.spiffe.io \
		&>/dev/null || true
	@-kubectl delete ns \
		$$(kubectl get ns -o json | jq -r '.items[] | .metadata.name' | grep spire) \
		&>/dev/null || true
	@-kubectl delete validatingwebhookconfigurations.admissionregistration.k8s.io \
		$$(kubectl get validatingwebhookconfigurations.admissionregistration.k8s.io -o json | jq -r '.items[] | .metadata.name' | grep spire) \
		&>/dev/null || true

.PHONY: test
test: install-test-deps test-charts test-examples ## Run all chart tests and example tests

.PHONY: install-test-deps
install-test-deps: ## Install test dependency resources
	@echo Installing test dependencies…
	@.github/tests/pre-install.sh

.PHONY: test-charts
test-charts: ## Run tests on charts using Helm chart-testing
	@echo Running tests…
	@ct install --config ct.yaml

.PHONY: cleanup-test-deps
cleanup-test-deps: ## Cleans up all test dependencies resources
	@echo Uninstalling test dependencies…
	@helm uninstall -n cert-manager cert-manager 2>/dev/null || true
	@kubectl delete ns cert-manager 2>/dev/null || true
	@helm uninstall -n prometheus kube-prometheus-stack 2>/dev/null || true
	@kubectl delete ns prometheus 2>/dev/null || true
	@helm uninstall -n mysql mysql 2>/dev/null|| true
	@kubectl delete ns mysql 2>/dev/null || true
	@helm uninstall -n postgresql postgresql 2>/dev/null || true
	@kubectl delete ns postgresql 2>/dev/null || true
	@helm uninstall -n ingress-nginx ingress-nginx 2>/dev/null || true
	@kubectl delete ns ingress-nginx 2>/dev/null || true

test-example-%:
	@echo Running tests for $* example…
	@examples/$*/run-tests.sh
	@echo

.PHONY: test-examples
test-examples: $(patsubst examples/%/values.yaml,test-example-%,$(wildcard examples/*/values.yaml)) ## Run `helm install` and `helm test` for all the examples containing `run-tests.sh`
