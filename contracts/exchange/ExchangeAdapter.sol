pragma solidity ^0.4.11;

import './ExchangeInterface.sol';
import '../dependencies/DBC.sol';
import '../dependencies/Owned.sol';
import '../dependencies/ERC20.sol';
import './thirdparty/SimpleMarket.sol';


/// @title ExchangeAdapter Contract
/// @author Melonport AG <team@melonport.com>
/// @notice An adapter between the Melon protocol and DappHubs SimpleMarket
/// @notice The concept of this can be extended to work with Kyber, 0x and many more!
contract ExchangeAdapter is DBC, Owned, ExchangeInterface {

    // FIELDS

    SimpleMarket public EXCHANGE;

    // PRE, POST, INVARIANT CONDITIONS

    /// @dev Pre: Adapter needs to be approved to spend tokens on msg.senders behalf
    /// @dev Post: Transferred tokens to this contract
    function claimAsset(address ofAsset, uint quantity)
        internal
        returns (bool)
    {
        return ERC20(ofAsset).transferFrom(msg.sender, this, quantity);
    }

    /// @dev Pre: Transferred tokens to this contract
    /// @dev Post Approved to spend tokens on EXCHANGE
    function approveSpending(address ofAsset, uint quantity)
        internal
        returns (bool)
    {
        return ERC20(ofAsset).approve(address(EXCHANGE), quantity);
    }

    /// @dev Pre: Adapter needs to be approved to spend tokens on msg.senders behalf
    /// @dev Post Claimed quantitiy of asset and approved EXCHANGE to spend them
    function claimAndApprove(address ofAsset, uint quantity)
        internal
        pre_cond(claimAsset(ofAsset, quantity))
        post_cond(approveSpending(ofAsset, quantity))
    {}

    // CONSTANT METHODS

    function getLastOrderId() constant returns (uint) { return EXCHANGE.last_offer_id(); }
    function isActive(uint id) constant returns (bool) { return EXCHANGE.isActive(id); }
    function getOwner(uint id) constant returns (address) { return EXCHANGE.getOwner(id); }
    function getOrder(uint id) constant returns (address, address, uint, uint) {
        var (
            sellQuantity,
            sellAsset,
            buyQuantity,
            buyAsset
        ) = EXCHANGE.getOffer(id);
        return (
            address(sellAsset),
            address(buyAsset),
            sellQuantity,
            buyQuantity
        );
    }

    // NON-CONSTANT METHODS

    function ExchangeAdapter(
        address ofSimpleMarket
    ) {
        EXCHANGE = SimpleMarket(ofSimpleMarket);
    }

    function makeOrder(
        address sellAsset,
        address buyAsset,
        uint sellQuantity,
        uint buyQuantity
    )
        external
        returns (uint id)
    {
        claimAndApprove(sellAsset, sellQuantity);
        return EXCHANGE.offer(
            sellQuantity,
            ERC20(sellAsset),
            buyQuantity,
            ERC20(buyAsset)
        );
    }

    function takeOrder(uint id, uint quantity)
        external
        returns (bool)
    {
        var (sellAsset, , sellQuantity, ) = getOrder(id);
        claimAndApprove(sellAsset, sellQuantity);
        return EXCHANGE.buy(id, quantity);
    }

    function cancelOrder(uint id)
        external
        returns (bool)
    {
        return EXCHANGE.cancel(id);
    }
}
