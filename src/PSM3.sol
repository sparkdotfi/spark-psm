// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { IERC20 } from "erc20-helpers/interfaces/IERC20.sol";

import { SafeERC20 } from "erc20-helpers/SafeERC20.sol";

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { Math }    from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { IPSM3 }             from "src/interfaces/IPSM3.sol";
import { IRateProviderLike } from "src/interfaces/IRateProviderLike.sol";

/*
    ███████╗██████╗  █████╗ ██████╗ ██╗  ██╗    ██████╗ ███████╗███╗   ███╗
    ██╔════╝██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝    ██╔══██╗██╔════╝████╗ ████║
    ███████╗██████╔╝███████║██████╔╝█████╔╝     ██████╔╝███████╗██╔████╔██║
    ╚════██║██╔═══╝ ██╔══██║██╔══██╗██╔═██╗     ██╔═══╝ ╚════██║██║╚██╔╝██║
    ███████║██║     ██║  ██║██║  ██║██║  ██╗    ██║     ███████║██║ ╚═╝ ██║
    ╚══════╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝     ╚══════╝╚═╝     ╚═╝
*/

contract PSM3 is IPSM3, Ownable {

    using SafeERC20 for IERC20;

    uint256 internal immutable _usdcPrecision;
    uint256 internal immutable _usdsPrecision;
    uint256 internal immutable _susdsPrecision;

    IERC20 public override immutable usdc;
    IERC20 public override immutable usds;
    IERC20 public override immutable susds;

    address public override immutable rateProvider;

    address public override pocket;

    uint256 public override totalShares;

    mapping(address user => uint256 shares) public override shares;

    constructor(
        address owner_,
        address usdc_,
        address usds_,
        address susds_,
        address rateProvider_
    )
        Ownable(owner_)
    {
        require(usdc_         != address(0), "PSM3/invalid-usdc");
        require(usds_         != address(0), "PSM3/invalid-usds");
        require(susds_        != address(0), "PSM3/invalid-susds");
        require(rateProvider_ != address(0), "PSM3/invalid-rateProvider");

        require(usdc_ != usds_,  "PSM3/usdc-usds-same");
        require(usdc_ != susds_, "PSM3/usdc-susds-same");
        require(usds_ != susds_, "PSM3/usds-susds-same");

        usdc  = IERC20(usdc_);
        usds  = IERC20(usds_);
        susds = IERC20(susds_);

        rateProvider = rateProvider_;
        pocket       = address(this);

        require(
            IRateProviderLike(rateProvider_).getConversionRate() != 0,
            "PSM3/rate-provider-returns-zero"
        );

        _usdcPrecision  = 10 ** IERC20(usdc_).decimals();
        _usdsPrecision  = 10 ** IERC20(usds_).decimals();
        _susdsPrecision = 10 ** IERC20(susds_).decimals();

        // Necessary to ensure rounding works as expected
        require(_usdcPrecision <= 1e18, "PSM3/usdc-precision-too-high");
        require(_usdsPrecision <= 1e18, "PSM3/usds-precision-too-high");
    }

    /**********************************************************************************************/
    /*** Owner functions                                                                        ***/
    /**********************************************************************************************/

    function setPocket(address newPocket) external override onlyOwner {
        require(newPocket != address(0), "PSM3/invalid-pocket");

        address pocket_ = pocket;

        require(newPocket != pocket_, "PSM3/same-pocket");

        uint256 amountToTransfer = usdc.balanceOf(pocket_);

        if (pocket_ == address(this)) {
            usdc.safeTransfer(newPocket, amountToTransfer);
        } else {
            usdc.safeTransferFrom(pocket_, newPocket, amountToTransfer);
        }

        pocket = newPocket;

        emit PocketSet(pocket_, newPocket, amountToTransfer);
    }

    /**********************************************************************************************/
    /*** Swap functions                                                                         ***/
    /**********************************************************************************************/

    function swapExactIn(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        uint256 referralCode
    )
        external override returns (uint256 amountOut)
    {
        require(amountIn != 0,          "PSM3/invalid-amountIn");
        require(receiver != address(0), "PSM3/invalid-receiver");

        amountOut = previewSwapExactIn(assetIn, assetOut, amountIn);

        require(amountOut >= minAmountOut, "PSM3/amountOut-too-low");

        _pullAsset(assetIn, amountIn);
        _pushAsset(assetOut, receiver, amountOut);

        emit Swap(assetIn, assetOut, msg.sender, receiver, amountIn, amountOut, referralCode);
    }

    function swapExactOut(
        address assetIn,
        address assetOut,
        uint256 amountOut,
        uint256 maxAmountIn,
        address receiver,
        uint256 referralCode
    )
        external override returns (uint256 amountIn)
    {
        require(amountOut != 0,         "PSM3/invalid-amountOut");
        require(receiver != address(0), "PSM3/invalid-receiver");

        amountIn = previewSwapExactOut(assetIn, assetOut, amountOut);

        require(amountIn <= maxAmountIn, "PSM3/amountIn-too-high");

        _pullAsset(assetIn, amountIn);
        _pushAsset(assetOut, receiver, amountOut);

        emit Swap(assetIn, assetOut, msg.sender, receiver, amountIn, amountOut, referralCode);
    }

    /**********************************************************************************************/
    /*** Liquidity provision functions                                                          ***/
    /**********************************************************************************************/

    function deposit(address asset, address receiver, uint256 assetsToDeposit)
        external override returns (uint256 newShares)
    {
        require(assetsToDeposit != 0, "PSM3/invalid-amount");

        newShares = previewDeposit(asset, assetsToDeposit);

        shares[receiver] += newShares;
        totalShares      += newShares;

        _pullAsset(asset, assetsToDeposit);

        emit Deposit(asset, msg.sender, receiver, assetsToDeposit, newShares);
    }

    function withdraw(address asset, address receiver, uint256 maxAssetsToWithdraw)
        external override returns (uint256 assetsWithdrawn)
    {
        require(maxAssetsToWithdraw != 0, "PSM3/invalid-amount");

        uint256 sharesToBurn;

        ( sharesToBurn, assetsWithdrawn ) = previewWithdraw(asset, maxAssetsToWithdraw);

        // `previewWithdraw` ensures that `sharesToBurn` <= `shares[msg.sender]`
        unchecked {
            shares[msg.sender] -= sharesToBurn;
            totalShares        -= sharesToBurn;
        }

        _pushAsset(asset, receiver, assetsWithdrawn);

        emit Withdraw(asset, msg.sender, receiver, assetsWithdrawn, sharesToBurn);
    }

    /**********************************************************************************************/
    /*** Deposit/withdraw preview functions                                                     ***/
    /**********************************************************************************************/

    function previewDeposit(address asset, uint256 assetsToDeposit)
        public view override returns (uint256)
    {
        // Convert amount to 1e18 precision denominated in value of USD then convert to shares.
        // NOTE: Don't need to check valid asset here since `_getAssetValue` will revert if invalid
        return convertToShares(_getAssetValue(asset, assetsToDeposit, false));  // Round down
    }

    function previewWithdraw(address asset, uint256 maxAssetsToWithdraw)
        public view override returns (uint256 sharesToBurn, uint256 assetsWithdrawn)
    {
        require(_isValidAsset(asset), "PSM3/invalid-asset");

        uint256 assetBalance = IERC20(asset).balanceOf(_getAssetCustodian(asset));

        assetsWithdrawn = assetBalance < maxAssetsToWithdraw
            ? assetBalance
            : maxAssetsToWithdraw;

        // Get shares to burn, rounding up for both calculations
        sharesToBurn = _convertToSharesRoundUp(_getAssetValue(asset, assetsWithdrawn, true));

        uint256 userShares = shares[msg.sender];

        if (sharesToBurn > userShares) {
            assetsWithdrawn = convertToAssets(asset, userShares);
            sharesToBurn    = userShares;
        }
    }

    /**********************************************************************************************/
    /*** Swap preview functions                                                                 ***/
    /**********************************************************************************************/

    function previewSwapExactIn(address assetIn, address assetOut, uint256 amountIn)
        public view override returns (uint256 amountOut)
    {
        // Round down to get amountOut
        amountOut = _getSwapQuote(assetIn, assetOut, amountIn, false);
    }

    function previewSwapExactOut(address assetIn, address assetOut, uint256 amountOut)
        public view override returns (uint256 amountIn)
    {
        // Round up to get amountIn
        amountIn = _getSwapQuote(assetOut, assetIn, amountOut, true);
    }

    /**********************************************************************************************/
    /*** Conversion functions                                                                   ***/
    /**********************************************************************************************/

    function convertToAssets(address asset, uint256 numShares)
        public view override returns (uint256)
    {
        require(_isValidAsset(asset), "PSM3/invalid-asset");

        uint256 assetValue = convertToAssetValue(numShares);

        if      (asset == address(usdc)) return assetValue * _usdcPrecision / 1e18;
        else if (asset == address(usds)) return assetValue * _usdsPrecision / 1e18;

        // NOTE: Multiplying by 1e27 and dividing by 1e18 cancels to 1e9 in numerator
        return assetValue
            * 1e9
            * _susdsPrecision
            / IRateProviderLike(rateProvider).getConversionRate();
    }

    function convertToAssetValue(uint256 numShares) public view override returns (uint256) {
        uint256 totalShares_ = totalShares;

        if (totalShares_ != 0) {
            return numShares * totalAssets() / totalShares_;
        }
        return numShares;
    }

    function convertToShares(uint256 assetValue) public view override returns (uint256) {
        uint256 totalAssets_ = totalAssets();
        if (totalAssets_ != 0) {
            return assetValue * totalShares / totalAssets_;
        }
        return assetValue;
    }

    function convertToShares(address asset, uint256 assets) public view override returns (uint256) {
        require(_isValidAsset(asset), "PSM3/invalid-asset");
        return convertToShares(_getAssetValue(asset, assets, false));  // Round down
    }

    /**********************************************************************************************/
    /*** Asset value functions                                                                  ***/
    /**********************************************************************************************/

    function totalAssets() public view override returns (uint256) {
        return _getUsdcValue(usdc.balanceOf(pocket))
            +  _getUsdsValue(usds.balanceOf(address(this)))
            +  _getSUsdsValue(susds.balanceOf(address(this)), false);  // Round down
    }

    /**********************************************************************************************/
    /*** Internal valuation functions (deposit/withdraw)                                        ***/
    /**********************************************************************************************/

    function _getAssetValue(address asset, uint256 amount, bool roundUp) internal view returns (uint256) {
        if      (asset == address(usdc))  return _getUsdcValue(amount);
        else if (asset == address(usds))  return _getUsdsValue(amount);
        else if (asset == address(susds)) return _getSUsdsValue(amount, roundUp);
        else revert("PSM3/invalid-asset-for-value");
    }

    function _getUsdcValue(uint256 amount) internal view returns (uint256) {
        return amount * 1e18 / _usdcPrecision;
    }

    function _getUsdsValue(uint256 amount) internal view returns (uint256) {
        return amount * 1e18 / _usdsPrecision;
    }

    function _getSUsdsValue(uint256 amount, bool roundUp) internal view returns (uint256) {
        // NOTE: Multiplying by 1e18 and dividing by 1e27 cancels to 1e9 in denominator
        if (!roundUp) return amount
            * IRateProviderLike(rateProvider).getConversionRate()
            / 1e9
            / _susdsPrecision;

        return Math.ceilDiv(
            Math.ceilDiv(amount * IRateProviderLike(rateProvider).getConversionRate(), 1e9),
            _susdsPrecision
        );
    }

    /**********************************************************************************************/
    /*** Internal preview functions (swaps)                                                     ***/
    /**********************************************************************************************/

    function _getSwapQuote(address asset, address quoteAsset, uint256 amount, bool roundUp)
        internal view returns (uint256 quoteAmount)
    {
        if (asset == address(usdc)) {
            if      (quoteAsset == address(usds))  return _convertOneToOne(amount, _usdcPrecision, _usdsPrecision, roundUp);
            else if (quoteAsset == address(susds)) return _convertToSUsds(amount, _usdcPrecision, roundUp);
        }

        else if (asset == address(usds)) {
            if      (quoteAsset == address(usdc))  return _convertOneToOne(amount, _usdsPrecision, _usdcPrecision, roundUp);
            else if (quoteAsset == address(susds)) return _convertToSUsds(amount, _usdsPrecision, roundUp);
        }

        else if (asset == address(susds)) {
            if      (quoteAsset == address(usdc)) return _convertFromSUsds(amount, _usdcPrecision, roundUp);
            else if (quoteAsset == address(usds)) return _convertFromSUsds(amount, _usdsPrecision, roundUp);
        }

        revert("PSM3/invalid-asset");
    }

    function _convertToSUsds(uint256 amount, uint256 assetPrecision, bool roundUp)
        internal view returns (uint256)
    {
        uint256 rate = IRateProviderLike(rateProvider).getConversionRate();

        if (!roundUp) return amount * 1e27 / rate * _susdsPrecision / assetPrecision;

        return Math.ceilDiv(
            Math.ceilDiv(amount * 1e27, rate) * _susdsPrecision,
            assetPrecision
        );
    }

    function _convertFromSUsds(uint256 amount, uint256 assetPrecision, bool roundUp)
        internal view returns (uint256)
    {
        uint256 rate = IRateProviderLike(rateProvider).getConversionRate();

        if (!roundUp) return amount * rate / 1e27 * assetPrecision / _susdsPrecision;

        return Math.ceilDiv(
            Math.ceilDiv(amount * rate, 1e27) * assetPrecision,
            _susdsPrecision
        );
    }

    function _convertOneToOne(
        uint256 amount,
        uint256 assetPrecision,
        uint256 convertAssetPrecision,
        bool roundUp
    )
        internal pure returns (uint256)
    {
        if (!roundUp) return amount * convertAssetPrecision / assetPrecision;

        return Math.ceilDiv(amount * convertAssetPrecision, assetPrecision);
    }

    /**********************************************************************************************/
    /*** Internal helper functions                                                              ***/
    /**********************************************************************************************/

    function _convertToSharesRoundUp(uint256 assetValue) internal view returns (uint256) {
        uint256 totalValue = totalAssets();
        if (totalValue != 0) {
            return Math.ceilDiv(assetValue * totalShares, totalValue);
        }
        return assetValue;
    }

    function _isValidAsset(address asset) internal view returns (bool) {
        return asset == address(usdc) || asset == address(usds) || asset == address(susds);
    }

    function _getAssetCustodian(address asset) internal view returns (address custodian) {
        custodian = asset == address(usdc) ? pocket : address(this);
    }

    function _pullAsset(address asset, uint256 amount) internal {
        IERC20(asset).safeTransferFrom(msg.sender, _getAssetCustodian(asset), amount);
    }

    function _pushAsset(address asset, address receiver, uint256 amount) internal {
        if (asset == address(usdc) && pocket != address(this)) {
            usdc.safeTransferFrom(pocket, receiver, amount);
        } else {
            IERC20(asset).safeTransfer(receiver, amount);
        }
    }

}
