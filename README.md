# ⚡ Spark PSM ⚡

![Foundry CI](https://github.com/marsfoundation/spark-psm/actions/workflows/master.yml/badge.svg)
[![Foundry][foundry-badge]][foundry]
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/marsfoundation/spark-psm/blob/master/LICENSE)

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Overview

This repository contains the implementation of a Peg Stability Module (PSM) contract, which facilitates the swapping, depositing, and withdrawing of three given assets to maintain stability and ensure the peg of involved assets. The PSM supports both yield-bearing and non-yield-bearing assets.

The PSM contract allows users to swap between USDC, USDS, and sUSDS, deposit any of the assets to mint shares, and withdraw any of the assets by burning shares.

The conversion between a stablecoin and `susds` is provided by a rate provider contract. The rate provider returns the conversion rate between `susds` and the stablecoin in 1e27 precision. The conversion between the stablecoins is one to one.

The conversion rate between assets and shares is based on the total value of assets within the PSM. This includes USDS and sUSDS held custody by the PSM, and USDC held custody by the `pocket`. The total value is calculated by converting the assets to their equivalent value in USD with 18 decimal precision. The shares represent the ownership of the underlying assets in the PSM. Since three assets are used, each with different precisions and values, they are converted to a common USD-denominated value for share conversions.

For detailed implementation, refer to the contract code and `IPSM3` interface documentation.

## Contracts

- **`src/PSM3.sol`**: The core contract implementing the `IPSM3` interface, providing functionality for swapping, depositing, and withdrawing assets.
- **`src/interfaces/IPSM3.sol`**: Defines the essential functions and events that the PSM contract implements.

## [CRITICAL]: First Depositor Attack Prevention on Deployment

On the deployment of the PSM, the deployer **MUST make an initial deposit to get AT LEAST 1e18 shares in order to protect the first depositor from getting attacked with a share inflation attack or DOS attack**. Share inflation attack is outlined further [here](https://github.com/marsfoundation/spark-automations/assets/44272939/9472a6d2-0361-48b0-b534-96a0614330d3). Technical details related to this can be found in `test/InflationAttack.t.sol`.

The DOS attack is performed by:
1. Attacker sends funds directly to the PSM. `totalAssets` now returns a non-zero value.
2. Victim calls deposit. `convertToShares` returns `amount * totalShares / totalValue`. In this case, `totalValue` is non-zero and `totalShares` is zero, so it performs `amount * 0 / totalValue` and returns zero.
3. The victim has `transferFrom` called moving their funds into the PSM, but they receive zero shares so they cannot recover any of their underlying assets. This renders the PSM unusable for all users since this issue will persist. `totalShares` can never be increased in this state.

The deployment library (`deploy/PSM3Deploy.sol`) in this repo contains logic for the deployer to perform this initial deposit, so it is **HIGHLY RECOMMENDED** to use this deployment library when deploying the PSM. Reasoning for the technical implementation approach taken is outlined in more detail [here](https://github.com/marsfoundation/spark-psm/pull/2).

## PSM Contract Details

### State Variables and Immutables

- **`usdc`**: IERC20 interface of USDC.
- **`usds`**: IERC20 interface of USDS.
- **`susds`**: IERC20 interface of sUSDS. Note that this is an ERC20 and not a ERC4626 because it's not on mainnet.
- **`pocket`**: Address that holds custody of USDC. The `pocket` can deploy USDC to yield-bearing strategies. Defaulted to the address of the PSM itself.
- **`rateProvider`**: Contract that returns a conversion rate between and sUSDS and USD in 1e27 precision.
- **`totalShares`**: Total shares in the PSM. Shares represent the ownership of the underlying assets in the PSM.
- **`shares`**: Mapping of user addresses to their shares.

### Functions

#### Admin Functions

- **`setPocket`**: Sets the `pocket` address. Only the `owner` can call this function. This is a very important and sensitive action because it transfers the entire balance of USDC to the new `pocket` address. OZ Ownable is used for this function, and `owner` will always be set to the governance proxy.

#### Swap Functions

- **`swapExactIn`**: Allows swapping of assets based on current conversion rates, specifying an `amountIn` of the asset to swap. Ensures the derived output amount is above the `minAmountOut` specified by the user before executing the transfer and emitting the swap event. Includes a referral code.
- **`swapExactOut`**: Allows swapping of assets based on current conversion rates, specifying an `amountOut` of the asset to receive from the swap. Ensures the derived input amount is below the `maxAmountIn` specified by the user before executing the transfer and emitting the swap event. Includes a referral code.

#### Liquidity Provision Functions

- **`deposit`**: Deposits assets into the PSM, minting new shares. Includes a referral code.
- **`withdraw`**: Withdraws assets from the PSM by burning shares. Ensures the user has sufficient shares for the withdrawal and adjusts the total shares accordingly. Includes a referral code.

#### Preview Functions

- **`previewDeposit`**: Estimates the number of shares minted for a given deposit amount.
- **`previewWithdraw`**: Estimates the number of shares burned and the amount of assets withdrawn for a specified amount.
- **`previewSwapExactIn`**: Estimates the amount of `assetOut` received for a given amount of `assetIn` in a swap.
- **`previewSwapExactOut`**: Estimates the amount of `assetIn` required to receive a given amount of `assetOut` in a swap.

#### Conversion Functions

NOTE: These functions do not round in the same way as preview functions, so they are meant to be used for general quoting purposes.

- **`convertToAssets`**: Converts shares to the equivalent amount of a specified asset.
- **`convertToAssetValue`**: Converts shares to their equivalent value in USD terms with 18 decimal precision.
- **`convertToShares`**: Converts asset values to shares based on the current exchange rate.

#### Asset Value Functions

- **`totalAssets`**: Returns the total value of all assets held by the PSM denominated in USD with 18 decimal precision.

### Events

- **`Swap`**: Emitted on asset swaps.
- **`Deposit`**: Emitted on asset deposits.
- **`Withdraw`**: Emitted on asset withdrawals.

## Running Tests

To run tests in this repo, run:

```bash
forge test
```

***
