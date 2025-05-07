.PHONY: deploy
deploy-arbitrum-one :; forge script script/Deploy.s.sol:DeployArbitrumOne --sender ${ETH_FROM} --broadcast --verify
deploy-base 	    :; forge script script/Deploy.s.sol:DeployBase --sender ${ETH_FROM} --broadcast --verify
deploy-optimism	    :; forge script script/Deploy.s.sol:DeployOptimism --sender ${ETH_FROM} --broadcast --verify
