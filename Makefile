# Two incompatible test worlds. Never run together:
#   test       local EVM: BaseTime predeploy absent
#   test-fork  Base mainnet fork: BaseTime live, real feeds
# Each target selects its suites from an explicit list. check-suites fails if any test contract
# in test/ is not assigned to exactly one list, so a misnamed or new file cannot slip into the wrong world.
SHELL := /bin/bash
FORGE ?= base-forge
CAST ?= base-cast
FORK_BLOCK ?= 54457318
LOCAL_SUITES := BaseTimeLibTest CalldataSuffixTest SessionOracleTest IndexVaultTest SlipstreamAdapterTest
FORK_SUITES := SessionOracleForkTest IndexVaultForkTest IndexVaultSlipstreamForkTest
ACCOUNT := speedrun
SEPOLIA_RPC ?= https://sepolia.base.org
MAINNET_RPC ?= https://mainnet.base.org

.PHONY: check-keystore check-suites test test-fork rehearse-dry rehearse-sepolia deploy-mainnet-dry deploy-mainnet verify-mainnet setup-fork stop-fork fork-weekend fork-states

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

PARAMS ?= deploy/mainnet.params.env
RUN_PARAMS = set -a; . $(PARAMS); set +a;

# Mainnet. All three need deploy/mainnet.params.env with no PENDING / DISPOSABLE value left.
# Simulation only: no keystore, nothing sent. Reads the live chain, runs the whole deployment locally.
deploy-mainnet-dry:
	@$(RUN_PARAMS) $(FORGE) script script/DeployMainnet.s.sol --fork-url $(MAINNET_RPC)

deploy-mainnet: check-keystore
	@echo "WARNING: MAINNET deployment. Ctrl-C within 5 seconds to abort."
	@sleep 5
	@$(RUN_PARAMS) $(FORGE) script script/DeployMainnet.s.sol --rpc-url $(MAINNET_RPC) --account $(ACCOUNT) --broadcast

# Reads the DEPLOYED contracts from the chain and fails on any mismatch. Needs ORACLE, ADAPTER, FACTORY addresses.
verify-mainnet:
	@$(RUN_PARAMS) ORACLE_ADDRESS=$(ORACLE) ADAPTER_ADDRESS=$(ADAPTER) FACTORY_ADDRESS=$(FACTORY) $(FORGE) script script/VerifyMainnet.s.sol --rpc-url $(MAINNET_RPC)

# Local development only: a Base fork at a US session block with oracle, adapter, factory and one funded vault live.
# No keystore, no real keys. Writes .fork/addresses.json for the UI. See docs/fork-dev.md.
setup-fork:
	@scripts/setup_fork.sh

stop-fork:
	@scripts/setup_fork.sh stop

# Moves the running fork to Saturday (oracle CLOSED/WEEKEND) and records a MARKET_CLOSED refusal.
fork-weekend:
	@scripts/fork_weekend.sh

# Stages that make the real oracle classify PAUSED, FAULT and AWAITING_FIRST_PRINT on the fork. Usage: make fork-states STAGE=pause|stale|reopen
fork-states:
	@scripts/fork_states.sh $(STAGE)
