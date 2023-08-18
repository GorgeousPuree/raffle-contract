// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

interface IRaffle {
    enum RaffleStatus {
        None,
        Created,
        Open,
        Drawing,
        RandomnessFulfilled,
        Drawn,
        Complete,
        Refundable,
        Cancelled
    }

    struct Raffle {
        bool isMinimumEntriesFixed;
        address owner;
        RaffleStatus status;
        uint208 claimableFees;
        uint40 cutoffTime;
        uint40 drawnAt;
        uint40 minimumEntries;
        uint40 maximumEntriesPerParticipant;
        uint8[] discounts;
        PricingOption[] pricingOptions;
        Prize[][] prizes;
        Entry[] entries;
        Winner[] winners;
    }

    struct Entry {
        uint40 currentEntryIndex;
        address participant;
    }

    struct Winner {
        address participant;
        bool claimed;
        uint256 prizeIndex;
        uint40 entryIndex;
    }

    struct CreateRaffleCalldata {
        uint40 cutoffTime;
        bool isMinimumEntriesFixed;
        uint40 minimumEntries;
        uint40 maximumEntriesPerParticipant;
        PricingOption[] pricingOptions;
        Prize[][] prizes;
        uint8[] discounts;
    }

    struct ClaimPrizesCalldata {
        uint256 raffleId;
        uint256[] winnerIndices;
    }

    struct EntryCalldata {
        uint256 raffleId;
        EntryOptionCalldata[] entriesOptions;
    }

    struct EntryDiscountsCalldata {
        bytes signature;
        uint256 timeOut;
        uint8[] discounts;
    }

    struct EntryOptionCalldata {
        uint256 pricingOptionIndex;
        uint40 count;
    }

    struct ParticipantStats {
        uint208 amountPaid;
        uint40 numberOfEntries;
        bool refunded;
    }

    struct PricingOption {
        uint208 price;
        uint40 numberOfEntries;
    }

    struct Prize {
        TokenType tokenType;
        address prizeAddress;
        uint256 prizeId;
        uint256 prizeAmount;
    }

    enum TokenType {
        ERC721,
        ERC1155,
        ETH,
        ERC20
    }

    struct RandomnessRequest {
        bool exists;
        uint256 randomWord;
        uint256 raffleId;
    }

    error InvalidCutoffTime();
    error InvalidPrizesCount();
    error InvalidPrize();
    error InvalidDiscount();
    error InvalidPricingOption();
    error InvalidRaffleStatus();
    error InvalidCaller();
    error WrongNativeTokensAmountSupplied();
    error CutoffTimeReached();
    error MaximumEntriesPerParticipantReached();
    error MaximumEntriesReached();
    error InvalidCount();
    error InvalidIndex();
    error RandomnessRequestDoesNotExist();
    error RandomnessRequestAlreadyExists();
    error NothingToClaim();
    error AlreadyRefunded();
    error CutoffTimeNotReached();
    error DrawExpirationTimeNotReached();
    error NotEnoughEntries();
    error InvalidSignature();
    error SignatureIsExpired();
    error PrizeAlreadyClaimed();

    event RaffleStatusUpdated(uint256 raffleId, RaffleStatus status);
    event EntrySold(uint256 raffleId, address buyer, uint40 entriesCount, uint208 price);
    event RandomnessRequested(uint256 raffleId, uint256 requestId);
    event PrizeClaimed(uint256 raffleId, uint256 prizeId);
    event PrizesClaimed(uint256 raffleId, uint256[] winnerIndex);
    event EntryRefunded(uint256 raffleId, address buyer, uint208 amount);
    event FeesClaimed(uint256 raffleId, uint256 amount);
}
