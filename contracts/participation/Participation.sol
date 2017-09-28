pragma solidity ^0.4.11;

import '../dependencies/DBC.sol';
import '../dependencies/Owned.sol';
import './ParticipationInterface.sol';

/// @title Participation Contract
/// @author Melonport AG <team@melonport.com>
/// @notice Example for uPort, Zug Gov, Melonport collaboration
contract Participation is ParticipationInterface, DBC, Owned {

    // TYPES

    struct Identity { // Using uPort and attestation from Zug Government
        bool hasUportId; // Whether identiy has registered a uPort identity w Zug Gov
        /* .. additional information
         *   for example how much identity is eligible to invest
         */
    }

    // FIELDS

    // Methods fields
    mapping (address => Identity) public identities;

    // CONSTANT METHODS

    /// @notice Required for Melon protocol interaction.
    /// @param ofParticipant Address requesting to invest in a Melon fund
    /// @param shareQuantity Quantity of shares times 10 ** 18 requested to be received
    /// @param offeredValue Quantity of Melon token times 10 ** 18 offered to receive shareQuantity
    /// @return Whether identity is eligible to invest in a Melon fund.
    function isSubscriptionPermitted(
        address ofParticipant,
        uint256 shareQuantity,
        uint256 offeredValue
    )
        returns (bool isEligible)
    {
        isEligible = identities[ofParticipant].hasUportId; // Eligible iff has uPort identity
    }

    function isSubscriptionPermitted2(
        Request request
    ) returns (bool isEligible) {}

    /// @notice Required for Melon protocol interaction.
    /// @param ofParticipant Address requesting to redeem from a Melon fund
    /// @param shareQuantity Quantity of shares times 10 ** 18 offered to redeem
    /// @param requestedValue Quantity of Melon token times 10 ** 18 requested to receive for shareQuantity
    /// @return Whether identity is eligible to redeem from a Melon fund.
    function isRedemptionPermitted(
        address ofParticipant,
        uint256 shareQuantity,
        uint256 requestedValue
    )
        returns (bool isEligible)
    {
        isEligible = true; // No need for KYC/AML in case of redeeming shares
    }

    // NON-CONSTANT METHODS

    /// @notice Creates attestation of a participant
    /// @dev Maintainer of above identities mapping (== owner) can trigger this function
    /// @param ofParticipant Adresses to receive attestation
    function attestForIdentity(address ofParticipant)
        pre_cond(isOwner())
    {
        identities[ofParticipant].hasUportId = true;
    }

    /// @notice Removes attestation of a participant
    /// @dev Maintainer of above identities mapping (== owner) can trigger this function
    /// @param ofParticipant Adresses to have attestation removed
    function removeAttestation(address ofParticipant)
        pre_cond(isOwner())
    {
        identities[ofParticipant].hasUportId = false;
    }
}
