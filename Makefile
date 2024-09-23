-include .env

.PHONY: all build test deploy clean anvil fmt install abi

# Variables
CONTRACT = RevenueDistribution
NETWORK = http://127.0.0.1:8545
TEST_NETWORK = anvil
DEPLOY_SCRIPT = script/DeployRevenueDistribution.s.sol
PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 #Default Anvil private key

# Default target
all: build test

# Build the contracts
build:
	forge build

# Run tests
test:
	forge test
	
ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

# Deploy contract to specified network
deploy:
	forge script $(DEPLOY_SCRIPT) --rpc-url $(NETWORK) --broadcast --private-key $(PRIVATE_KEY)

# Clean compiled contracts and cache
clean:
	forge clean

# Run a local test network (Anvil)
anvil:
	anvil -f

# Format code
fmt:
	forge fmt

# Install dependencies
install:
	forge install

# Show contract ABI
abi:
	forge inspect $(CONTRACT) abi


