// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Council <council@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.6.12;

import "../../../../infrastructure/price-feeds/derivatives/feeds/IdlePriceFeed.sol";
import "../../../../interfaces/IIdleTokenV4.sol";
import "../../../../utils/AddressArrayLib.sol";
import "../utils/actions/IdleV4ActionsMixin.sol";
import "../utils/AdapterBase.sol";

/// @title IdleAdapter Contract
/// @author Enzyme Council <security@enzyme.finance>
/// @notice Adapter for Idle Lending <https://idle.finance/>
/// @dev There are some idiosyncrasies of reward accrual and claiming in IdleTokens that
/// are handled by this adapter:
/// - Rewards accrue to the IdleToken holder, but the accrued
/// amount is passed to the recipient of a transfer.
/// - Claiming rewards cannot be done on behalf of a holder, but must be done directly.
/// - Claiming rewards occurs automatically upon redeeming, but there are situations when
/// it is difficult to know whether to expect incoming rewards (e.g., after a user mints
/// idleTokens and then redeems before any other user has interacted with the protocol,
/// then getGovTokensAmounts() will return 0 balances). Because of this difficulty -
/// and in keeping with how other adapters treat claimed rewards -
/// this adapter does not report claimed rewards as incomingAssets.
contract IdleAdapter is AdapterBase, IdleV4ActionsMixin {
    using AddressArrayLib for address[];

    address private immutable IDLE_PRICE_FEED;

    constructor(address _integrationManager, address _idlePriceFeed)
        public
        AdapterBase(_integrationManager)
    {
        IDLE_PRICE_FEED = _idlePriceFeed;
    }

    /// @notice Claims rewards for a givenIdleToken
    /// @param _vaultProxy The VaultProxy of the calling fund
    /// @param _encodedCallArgs The encoded parameters for the callOnIntegration
    /// @param _encodedAssetTransferArgs Encoded args for expected assets to spend and receive
    function claimRewards(
        address _vaultProxy,
        bytes calldata _encodedCallArgs,
        bytes calldata _encodedAssetTransferArgs
    )
        external
        onlyIntegrationManager
        postActionSpendAssetsTransferHandler(_vaultProxy, _encodedAssetTransferArgs)
    {
        address idleToken = __decodeClaimRewardsCallArgs(_encodedCallArgs);

        __idleV4ClaimRewards(idleToken);

        __pushFullAssetBalances(_vaultProxy, __idleV4GetRewardsTokens(idleToken));
    }

    /// @notice Lends an amount of a token for idleToken
    /// @param _vaultProxy The VaultProxy of the calling fund
    /// @param _encodedAssetTransferArgs Encoded args for expected assets to spend and receive
    function lend(
        address _vaultProxy,
        bytes calldata,
        bytes calldata _encodedAssetTransferArgs
    )
        external
        onlyIntegrationManager
        postActionIncomingAssetsTransferHandler(_vaultProxy, _encodedAssetTransferArgs)
    {
        // More efficient to parse all from _encodedAssetTransferArgs
        (
            ,
            address[] memory spendAssets,
            uint256[] memory spendAssetAmounts,
            address[] memory incomingAssets
        ) = __decodeEncodedAssetTransferArgs(_encodedAssetTransferArgs);

        __idleV4Lend(incomingAssets[0], spendAssets[0], spendAssetAmounts[0]);
    }

    /// @notice Redeems an amount of idleToken for its underlying asset
    /// @param _vaultProxy The VaultProxy of the calling fund
    /// @param _encodedCallArgs The encoded parameters for the callOnIntegration
    /// @param _encodedAssetTransferArgs Encoded args for expected assets to spend and receive
    /// @dev This will also pay out any due gov token rewards.
    /// We use the full IdleToken balance of the current contract rather than the user input
    /// for the corner case of a prior balance existing in the current contract, which would
    /// throw off the per-user avg price of the IdleToken used by Idle, and would leave the
    /// initial token balance in the current contract post-tx.
    function redeem(
        address _vaultProxy,
        bytes calldata _encodedCallArgs,
        bytes calldata _encodedAssetTransferArgs
    )
        external
        onlyIntegrationManager
        postActionIncomingAssetsTransferHandler(_vaultProxy, _encodedAssetTransferArgs)
    {
        (address idleToken, , ) = __decodeRedeemCallArgs(_encodedCallArgs);

        __idleV4Redeem(idleToken, ERC20(idleToken).balanceOf(address(this)));

        __pushFullAssetBalances(_vaultProxy, __idleV4GetRewardsTokens(idleToken));
    }

    /// @dev Helper to get the underlying for a given IdleToken
    function __getUnderlyingForIdleToken(address _idleToken)
        private
        view
        returns (address underlying_)
    {
        return IdlePriceFeed(IDLE_PRICE_FEED).getUnderlyingForDerivative(_idleToken);
    }

    /////////////////////////////
    // PARSE ASSETS FOR METHOD //
    /////////////////////////////

    /// @notice Parses the expected assets to receive from a call on integration
    /// @param _selector The function selector for the callOnIntegration
    /// @param _encodedCallArgs The encoded parameters for the callOnIntegration
    /// @return spendAssetsHandleType_ A type that dictates how to handle granting
    /// the adapter access to spend assets (`None` by default)
    /// @return spendAssets_ The assets to spend in the call
    /// @return spendAssetAmounts_ The max asset amounts to spend in the call
    /// @return incomingAssets_ The assets to receive in the call
    /// @return minIncomingAssetAmounts_ The min asset amounts to receive in the call
    function parseAssetsForMethod(
        address _vaultProxy,
        bytes4 _selector,
        bytes calldata _encodedCallArgs
    )
        external
        view
        override
        returns (
            IIntegrationManager.SpendAssetsHandleType spendAssetsHandleType_,
            address[] memory spendAssets_,
            uint256[] memory spendAssetAmounts_,
            address[] memory incomingAssets_,
            uint256[] memory minIncomingAssetAmounts_
        )
    {
        if (_selector == CLAIM_REWARDS_SELECTOR) {
            return __parseAssetsForClaimRewards(_vaultProxy, _encodedCallArgs);
        } else if (_selector == LEND_SELECTOR) {
            return __parseAssetsForLend(_encodedCallArgs);
        } else if (_selector == REDEEM_SELECTOR) {
            return __parseAssetsForRedeem(_encodedCallArgs);
        }

        revert("parseAssetsForMethod: _selector invalid");
    }

    /// @dev Helper function to parse spend and incoming assets from encoded call args
    /// during claimRewards() calls
    function __parseAssetsForClaimRewards(address _vaultProxy, bytes calldata _encodedCallArgs)
        private
        view
        returns (
            IIntegrationManager.SpendAssetsHandleType spendAssetsHandleType_,
            address[] memory spendAssets_,
            uint256[] memory spendAssetAmounts_,
            address[] memory incomingAssets_,
            uint256[] memory minIncomingAssetAmounts_
        )
    {
        address idleToken = __decodeClaimRewardsCallArgs(_encodedCallArgs);

        require(
            __getUnderlyingForIdleToken(idleToken) != address(0),
            "__parseAssetsForClaimRewards: Unsupported idleToken"
        );

        (spendAssets_, spendAssetAmounts_) = __parseSpendAssetsForClaimRewardsCalls(
            _vaultProxy,
            idleToken
        );

        return (
            IIntegrationManager.SpendAssetsHandleType.Transfer,
            spendAssets_,
            spendAssetAmounts_,
            new address[](0),
            new uint256[](0)
        );
    }

    /// @dev Helper function to parse spend and incoming assets from encoded call args
    /// during lend() calls
    function __parseAssetsForLend(bytes calldata _encodedCallArgs)
        private
        view
        returns (
            IIntegrationManager.SpendAssetsHandleType spendAssetsHandleType_,
            address[] memory spendAssets_,
            uint256[] memory spendAssetAmounts_,
            address[] memory incomingAssets_,
            uint256[] memory minIncomingAssetAmounts_
        )
    {
        (
            address idleToken,
            uint256 outgoingUnderlyingAmount,
            uint256 minIncomingIdleTokenAmount
        ) = __decodeLendCallArgs(_encodedCallArgs);

        address underlying = __getUnderlyingForIdleToken(idleToken);
        require(underlying != address(0), "__parseAssetsForLend: Unsupported idleToken");

        spendAssets_ = new address[](1);
        spendAssets_[0] = underlying;

        spendAssetAmounts_ = new uint256[](1);
        spendAssetAmounts_[0] = outgoingUnderlyingAmount;

        incomingAssets_ = new address[](1);
        incomingAssets_[0] = idleToken;

        minIncomingAssetAmounts_ = new uint256[](1);
        minIncomingAssetAmounts_[0] = minIncomingIdleTokenAmount;

        return (
            IIntegrationManager.SpendAssetsHandleType.Transfer,
            spendAssets_,
            spendAssetAmounts_,
            incomingAssets_,
            minIncomingAssetAmounts_
        );
    }

    /// @dev Helper function to parse spend and incoming assets from encoded call args
    /// during redeem() calls
    function __parseAssetsForRedeem(bytes calldata _encodedCallArgs)
        private
        view
        returns (
            IIntegrationManager.SpendAssetsHandleType spendAssetsHandleType_,
            address[] memory spendAssets_,
            uint256[] memory spendAssetAmounts_,
            address[] memory incomingAssets_,
            uint256[] memory minIncomingAssetAmounts_
        )
    {
        (
            address idleToken,
            uint256 outgoingIdleTokenAmount,
            uint256 minIncomingUnderlyingAmount
        ) = __decodeRedeemCallArgs(_encodedCallArgs);

        address underlying = __getUnderlyingForIdleToken(idleToken);
        require(underlying != address(0), "__parseAssetsForRedeem: Unsupported idleToken");

        spendAssets_ = new address[](1);
        spendAssets_[0] = idleToken;

        spendAssetAmounts_ = new uint256[](1);
        spendAssetAmounts_[0] = outgoingIdleTokenAmount;

        incomingAssets_ = new address[](1);
        incomingAssets_[0] = underlying;

        minIncomingAssetAmounts_ = new uint256[](1);
        minIncomingAssetAmounts_[0] = minIncomingUnderlyingAmount;

        return (
            IIntegrationManager.SpendAssetsHandleType.Transfer,
            spendAssets_,
            spendAssetAmounts_,
            incomingAssets_,
            minIncomingAssetAmounts_
        );
    }

    /// @dev Helper function to parse spend assets for calls to claim rewards
    function __parseSpendAssetsForClaimRewardsCalls(address _vaultProxy, address _idleToken)
        private
        view
        returns (address[] memory spendAssets_, uint256[] memory spendAssetAmounts_)
    {
        spendAssets_ = new address[](1);
        spendAssets_[0] = _idleToken;

        spendAssetAmounts_ = new uint256[](1);
        spendAssetAmounts_[0] = ERC20(_idleToken).balanceOf(_vaultProxy);

        return (spendAssets_, spendAssetAmounts_);
    }

    ///////////////////////
    // ENCODED CALL ARGS //
    ///////////////////////

    /// @dev Helper to decode callArgs for claiming rewards tokens
    function __decodeClaimRewardsCallArgs(bytes memory _encodedCallArgs)
        private
        pure
        returns (address idleToken_)
    {
        return abi.decode(_encodedCallArgs, (address));
    }

    /// @dev Helper to decode callArgs for lending
    function __decodeLendCallArgs(bytes memory _encodedCallArgs)
        private
        pure
        returns (
            address idleToken_,
            uint256 outgoingUnderlyingAmount_,
            uint256 minIncomingIdleTokenAmount_
        )
    {
        return abi.decode(_encodedCallArgs, (address, uint256, uint256));
    }

    /// @dev Helper to decode callArgs for redeeming
    function __decodeRedeemCallArgs(bytes memory _encodedCallArgs)
        private
        pure
        returns (
            address idleToken_,
            uint256 outgoingIdleTokenAmount_,
            uint256 minIncomingUnderlyingAmount_
        )
    {
        return abi.decode(_encodedCallArgs, (address, uint256, uint256));
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    /// @notice Gets the `IDLE_PRICE_FEED` variable
    /// @return idlePriceFeed_ The `IDLE_PRICE_FEED` variable value
    function getIdlePriceFeed() external view returns (address idlePriceFeed_) {
        return IDLE_PRICE_FEED;
    }
}
