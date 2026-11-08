# Two incompatible test worlds. Never run together:
#   test       local EVM: BaseTime predeploy absent
#   test-fork  Base mainnet fork: BaseTime live, real feeds
# Each target selects its suites from an explicit list. check-suites fails if any test contract
# in test/ is not assigned to exactly one list, so a misnamed or new file cannot slip into the wrong world.
SHELL := /bin/bash
FORGE ?= base-forge
CAST ?= base-cast
FORK_BLOCK ?= 54457318
LOCAL_SUITES := BaseTimeLibTest CalldataSuffixTest SessionOracleTest IndexVaultTest
FORK_SUITES := SessionOracleForkTest IndexVaultForkTest
ACCOUNT := speedrun
SEPOLIA_RPC ?= https://sepolia.base.org
MAINNET_RPC ?= https://mainnet.base.org

.PHONY: check-keystore check-suites test test-fork rehearse-dry rehearse-sepolia deploy-oracle-sepolia deploy-oracle-mainnet

check-keystore:
	@$(CAST) wallet list | grep -q "^$(ACCOUNT)" || (echo "keystore $(ACCOUNT) not found" && exit 1)

check-suites:
	@all=$$(grep -rhoE "^contract [A-Za-z0-9_]+ is Test" test | awk '{print $$2}' | sort); \
	known=$$(printf '%s\n' $(LOCAL_SUITES) $(FORK_SUITES) | sort); \
	if [ "$$all" != "$$known" ]; then echo "test contracts not assigned to exactly one world:"; diff <(echo "$$all") <(echo "$$known") || true; exit 1; fi

test: check-suites
	$(FORGE) test --match-contract "^($(shell echo $(LOCAL_SUITES) | tr ' ' '|'))$$"

test-fork: check-suites
	$(FORGE) test --fork-url $(MAINNET_RPC) --fork-block-number $(FORK_BLOCK) --match-contract "^($(shell echo $(FORK_SUITES) | tr ' ' '|'))$$"

# Simulation only: nothing is broadcast and no keystore is needed.
rehearse-dry:
	$(FORGE) script script/RehearseSepolia.s.sol --fork-url $(SEPOLIA_RPC)

# Sepolia only, disposable parameters. Prompts for the keystore password.
rehearse-sepolia: check-keystore
	$(FORGE) script script/RehearseSepolia.s.sol --rpc-url $(SEPOLIA_RPC) --account $(ACCOUNT) --broadcast

deploy-oracle-sepolia: check-keystore
	$(FORGE) script script/DeploySessionOracle.s.sol --rpc-url $(SEPOLIA_RPC) --account $(ACCOUNT) --broadcast

deploy-oracle-mainnet: check-keystore
	@echo "WARNING: MAINNET deployment. Ctrl-C within 5 seconds to abort."
	@sleep 5
	$(FORGE) script script/DeploySessionOracle.s.sol --rpc-url $(MAINNET_RPC) --account $(ACCOUNT) --broadcast
