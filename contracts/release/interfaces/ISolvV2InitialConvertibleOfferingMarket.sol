// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.
    (c) Enzyme Council <council@enzyme.finance>
    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

/// @title ISolvV2InitialConvertibleOfferingMarket Interface
/// @author Enzyme Council <security@enzyme.finance>
/// @dev Source: https://github.com/solv-finance/solv-v2-ivo/blob/main/vouchers/convertible-voucher/contracts/ConvertiblePool.sol

interface ISolvV2InitialConvertibleOfferingMarket {
    enum VoucherType {STANDARD_VESTING, FLEXIBLE_DATE_VESTING, BOUNDING}

    struct Market {
        VoucherType voucherType;
        address voucherPool;
        address asset;
        uint8 decimals;
        uint16 feeRate;
        bool onlyManangerOffer;
        bool isValid;
    }

    /**
     * @param lowestPrice Lower price bound of the voucher (8 decimals)
     * @param highestPrice Upper price bound of the voucher (8 decimals)
     * @param tokenInAmount Amount of underlying tokens sent as collateral for minting (determined the amount of tokens )
     * @param effectiveTime Effective timestamp. Refers to when the bond takes effect (like startTime)
     * @param maturity Maturity timestamp of the voucher
     */
    struct MintParameter {
        uint128 lowestPrice;
        uint128 highestPrice;
        uint128 tokenInAmount;
        uint64 effectiveTime;
        uint64 maturity;
    }

    enum PriceType {FIXED, DECLIINING_BY_TIME}

    struct Offering {
        uint24 offeringId;
        uint32 startTime;
        uint32 endTime;
        PriceType priceType;
        uint128 totalUnits;
        uint128 units;
        uint128 min;
        uint128 max;
        address voucher;
        address currency;
        address issuer;
        bool useAllowList;
        bool isValid;
    }

    function buy(uint24 offeringId_, uint128 units_)
        external
        returns (uint256 amount_, uint128 fee_);

    function getPrice(uint24 offeringId_) external returns (uint256 price_);

    function markets(address voucher_) external returns (Market memory market_);

    function offerings(uint24 _offerId) external returns (Offering memory offering_);
}
