// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import "./IRaffle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
//import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Arrays} from "./Arrays.sol";
//import "hardhat/console.sol";

contract Raffle is IRaffle, VRFConsumerBaseV2, ReentrancyGuard, Ownable {
    using Arrays for uint256[];

    address public secret;

    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;

    uint256 public rafflesCount;

    uint8 public constant MAX_TOTAL_DISCOUNT = 50;

    //    uint64 public immutable SUBSCRIPTION_ID = 13657;
    uint64 public immutable SUBSCRIPTION_ID;

    bytes32 public immutable KEY_HASH = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;

    mapping(uint256 => Raffle) public raffles;
    mapping(uint256 => mapping(address => ParticipantStats)) public rafflesParticipantsStats;
    mapping(uint256 => RandomnessRequest) public randomnessRequests;

    constructor(
        uint64 _subscriptionId,
        address _vrfCoordinator
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        SUBSCRIPTION_ID = _subscriptionId;
        VRF_COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
    }

    mapping(address => bool) public controllers;

    function createRaffle(CreateRaffleCalldata calldata params) onlyController external returns (uint256 raffleId)  {
        // Two months is a max cutoff time
        if (block.timestamp > params.cutoffTime || params.cutoffTime > block.timestamp + 8 weeks) {
            revert InvalidCutoffTime();
        }

    unchecked {
        raffleId = ++rafflesCount;
    }
        if (params.prizes.length == 0) {
            revert InvalidPrizesCount();
        }

        Raffle storage raffle = raffles[raffleId];

        _validateAndSetPrizes(raffleId, params.prizes);
        _validateAndSetPricingOptions(raffleId, params.minimumEntries, params.pricingOptions);
        _validateAndSetDiscounts(raffleId, params.discounts);

        raffle.discounts = params.discounts;
        raffle.isMinimumEntriesFixed = params.isMinimumEntriesFixed;
        raffle.owner = msg.sender;
        raffle.cutoffTime = params.cutoffTime;
        raffle.minimumEntries = params.minimumEntries;
        raffle.maximumEntriesPerParticipant = params.maximumEntriesPerParticipant;
        _setRaffleStatus(raffle, raffleId, RaffleStatus.Created);
    }

    function depositPrizes(uint256 raffleId) external payable {
        Raffle storage raffle = raffles[raffleId];

        _validateRaffleStatus(raffle, RaffleStatus.Created);
        _validateCaller(raffle.owner);

        uint256 expectedEthValue;

        for (uint256 i; i < raffle.prizes.length;) {
            for (uint256 j; j < raffle.prizes[i].length;) {
                Prize memory prize = raffle.prizes[i][j];
                TokenType tokenType = prize.tokenType;

                if (tokenType == TokenType.ERC721) {
                    IERC721(prize.prizeAddress).transferFrom(msg.sender, address(this), prize.prizeId);
                } else if (tokenType == TokenType.ERC20) {
                    IERC20(prize.prizeAddress).transferFrom(msg.sender, address(this), prize.prizeAmount);
                } else if (tokenType == TokenType.ETH) {
                    expectedEthValue += prize.prizeAmount;
                } else {
                    IERC1155(prize.prizeAddress).safeTransferFrom(msg.sender, address(this), prize.prizeId, prize.prizeAmount, "");
                }

            unchecked {
                ++j;
            }
            }

        unchecked {
            ++i;
        }
        }

        if (expectedEthValue != msg.value) {
            revert WrongNativeTokensAmountSupplied();
        }

        _setRaffleStatus(raffle, raffleId, RaffleStatus.Open);
    }

    function enterRaffleWithDiscounts(EntryCalldata calldata entryData, EntryDiscountsCalldata calldata entryDiscountsData)
    external payable nonReentrant
    {
        uint8 totalDiscount = _validateDiscounts(entryData.raffleId, entryDiscountsData);
        _enterRaffle(entryData, totalDiscount);
    }

    function enterRaffle(EntryCalldata calldata entryData) external payable nonReentrant
    {
        _enterRaffle(entryData, 0);
    }

    function _enterRaffle(EntryCalldata calldata entryData, uint8 discountsPercentage) private {
        uint256 raffleId = entryData.raffleId;
        Raffle storage raffle = raffles[raffleId];

        _validateRaffleStatus(raffle, RaffleStatus.Open);

        if (block.timestamp >= raffle.cutoffTime) {
            revert CutoffTimeReached();
        }

        uint expectedEthValue;

        uint256 count = entryData.entriesOptions.length;
        for (uint256 i; i < count;) {
            EntryOptionCalldata calldata entry = entryData.entriesOptions[i];

            if (entry.pricingOptionIndex >= raffle.pricingOptions.length) {
                revert InvalidIndex();
            }

            uint40 numberOfEntries;
            uint208 price;
            {
                PricingOption memory pricingOption = raffle.pricingOptions[entry.pricingOptionIndex];

                uint40 multiplier = entry.count;
                if (multiplier == 0) {
                    revert InvalidCount();
                }

                numberOfEntries = pricingOption.numberOfEntries * multiplier;
                price = pricingOption.price * multiplier;

                uint40 newParticipantNumberOfEntries = rafflesParticipantsStats[raffleId][msg.sender].numberOfEntries +
                numberOfEntries;

                if (newParticipantNumberOfEntries > raffle.maximumEntriesPerParticipant) {
                    revert MaximumEntriesPerParticipantReached();
                }
                rafflesParticipantsStats[raffleId][msg.sender].numberOfEntries = newParticipantNumberOfEntries;
            }

            expectedEthValue += price;

            uint256 raffleNumberOfEntries = raffle.entries.length;
            uint40 currentEntryIndex;
            if (raffleNumberOfEntries == 0) {
                currentEntryIndex = uint40(_unsafeSubtract(numberOfEntries, 1));
            } else {
                currentEntryIndex =
                raffle.entries[_unsafeSubtract(raffleNumberOfEntries, 1)].currentEntryIndex +
                numberOfEntries;
            }

            if (raffle.isMinimumEntriesFixed) {
                if (currentEntryIndex >= raffle.minimumEntries) {
                    revert MaximumEntriesReached();
                }
            }

            raffle.entries.push(Entry({currentEntryIndex : currentEntryIndex, participant : msg.sender}));
            raffle.claimableFees += price;

            rafflesParticipantsStats[raffleId][msg.sender].amountPaid += price;

            emit EntrySold(raffleId, msg.sender, numberOfEntries, price);

            if (currentEntryIndex >= _unsafeSubtract(raffle.minimumEntries, 1)) {
                _drawWinners(raffleId, raffle);
            }

        unchecked {
            ++i;
        }
        }

        if (discountsPercentage != 0) {
            expectedEthValue = expectedEthValue * (100 - discountsPercentage) / 100;
        }

        if (expectedEthValue != msg.value) {
            revert WrongNativeTokensAmountSupplied();
        }
    }

    function selectWinners(uint256 requestId) external {
        RandomnessRequest memory randomnessRequest = randomnessRequests[requestId];
        if (!randomnessRequest.exists) {
            revert RandomnessRequestDoesNotExist();
        }

        uint256 raffleId = randomnessRequest.raffleId;
        Raffle storage raffle = raffles[raffleId];
        _validateRaffleStatus(raffle, RaffleStatus.RandomnessFulfilled);

        _setRaffleStatus(raffle, raffleId, RaffleStatus.Drawn);

        Prize[][] storage prizes = raffle.prizes;
        uint256 prizesCount = prizes.length;

        Entry[] memory entries = raffle.entries;
        uint256 entriesCount = entries.length;
        uint256 currentEntryIndex = uint256(entries[entriesCount - 1].currentEntryIndex);

        uint256[] memory winningEntriesBitmap = new uint256[]((currentEntryIndex >> 8) + 1);

        uint256[] memory currentEntryIndexArray = new uint256[](entriesCount);
        for (uint256 i; i < entriesCount;) {
            currentEntryIndexArray[i] = entries[i].currentEntryIndex;
        unchecked {
            ++i;
        }
        }

        uint256 randomWord = randomnessRequest.randomWord;

        for (uint256 i; i < prizesCount;) {
            uint256 winningEntry = randomWord % (currentEntryIndex + 1);
            (winningEntry, winningEntriesBitmap) = _incrementWinningEntryUntilThereIsNotADuplicate(
                currentEntryIndex,
                winningEntry,
                winningEntriesBitmap
            );

            raffle.winners.push(
                Winner({
            participant : entries[currentEntryIndexArray.findUpperBound(winningEntry)].participant,
            claimed : false,
            prizeIndex : i,
            entryIndex : uint40(winningEntry)
            })
            );

            randomWord = uint256(keccak256(abi.encodePacked(randomWord)));

        unchecked {
            ++i;
        }
        }
    }

    function withdrawPrizes(uint256 raffleId) external nonReentrant {
        Raffle storage raffle = raffles[raffleId];
        _validateRaffleStatus(raffle, RaffleStatus.Refundable);

        _setRaffleStatus(raffle, raffleId, RaffleStatus.Cancelled);

        uint256 prizesCount = raffle.prizes.length;
        address raffleOwner = raffle.owner;

        for (uint256 i; i < prizesCount;) {
            Prize[] storage prizes = raffle.prizes[i];
            _transferPrize(prizes, raffleOwner);

        unchecked {
            ++i;
        }
        }
    }

    function claimFees(uint256 raffleId) external nonReentrant {
        Raffle storage raffle = raffles[raffleId];
        _validateRaffleStatus(raffle, RaffleStatus.Drawn);

        _validateCaller(raffle.owner);

        uint208 claimableFees = raffle.claimableFees;

        _setRaffleStatus(raffle, raffleId, RaffleStatus.Complete);

        raffle.claimableFees = 0;

        payable(raffle.owner).transfer(claimableFees);

        emit FeesClaimed(raffleId, claimableFees);
    }

    function claimPrizes(ClaimPrizesCalldata calldata claimPrizesCalldata) external nonReentrant {
        uint256 raffleId = claimPrizesCalldata.raffleId;
        Raffle storage raffle = raffles[raffleId];
        RaffleStatus status = raffle.status;
        if (status != RaffleStatus.Drawn) {
            _validateRaffleStatus(raffle, RaffleStatus.Complete);
        }

        Winner[] storage winners = raffle.winners;
        uint256[] calldata winnerIndices = claimPrizesCalldata.winnerIndices;
        uint256 winnersCount = winners.length;
        uint256 claimsCount = winnerIndices.length;
        for (uint256 i; i < claimsCount;) {
            uint256 winnerIndex = winnerIndices[i];

            if (winnerIndex >= winnersCount) {
                revert InvalidIndex();
            }

            Winner storage winner = winners[winnerIndex];
            if (winner.claimed) {
                revert PrizeAlreadyClaimed();
            }
            _validateCaller(winner.participant);
            winner.claimed = true;

            Prize[] storage prize = raffle.prizes[winner.prizeIndex];
            _transferPrize(prize, msg.sender);

        unchecked {
            ++i;
        }
        }

        emit PrizesClaimed(raffleId, winnerIndices);
    }

    function claimRefund(uint256 raffleId) external nonReentrant {
        Raffle storage raffle = raffles[raffleId];

        if (raffle.status < RaffleStatus.Refundable) {
            revert InvalidRaffleStatus();
        }

        ParticipantStats storage stats = rafflesParticipantsStats[raffleId][msg.sender];

        if (stats.refunded) {
            revert AlreadyRefunded();
        }

        stats.refunded = true;

        uint208 amountPaid = stats.amountPaid;
        payable(msg.sender).transfer(amountPaid);

        emit EntryRefunded(raffleId, msg.sender, amountPaid);
    }

    function drawWinners(uint256 raffleId) external nonReentrant {
        Raffle storage raffle = raffles[raffleId];

        Entry[] storage entries = raffle.entries;
        uint256 entriesCount = entries.length;
        if (entriesCount == 0) {
            revert NotEnoughEntries();
        }

        Prize[][] storage prizes = raffle.prizes;

        if (prizes.length > entries[entriesCount - 1].currentEntryIndex + 1) {
            revert NotEnoughEntries();
        }

        _validateRafflePostCutoffTimeStatusTransferability(raffle);
        _validateCaller(raffle.owner);
        _drawWinners(raffleId, raffle);
    }

    function cancel(uint256 raffleId) external nonReentrant {
        Raffle storage raffle = raffles[raffleId];
        _validateRafflePostCutoffTimeStatusTransferability(raffle);
        if (block.timestamp < raffle.cutoffTime + 1 hours) {
            _validateCaller(raffle.owner);
        }
        _setRaffleStatus(raffle, raffleId, RaffleStatus.Refundable);
    }

    function cancelAfterRandomnessRequest(uint256 raffleId) external nonReentrant {
        Raffle storage raffle = raffles[raffleId];

        _validateRaffleStatus(raffle, RaffleStatus.Drawing);

        if (block.timestamp < raffle.drawnAt + 1 days) {
            revert DrawExpirationTimeNotReached();
        }

        _setRaffleStatus(raffle, raffleId, RaffleStatus.Refundable);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        if (randomnessRequests[_requestId].exists) {
            uint256 raffleId = randomnessRequests[_requestId].raffleId;
            Raffle storage raffle = raffles[raffleId];

            if (raffle.status == RaffleStatus.Drawing) {
                _setRaffleStatus(raffle, raffleId, RaffleStatus.RandomnessFulfilled);
                randomnessRequests[_requestId].randomWord = _randomWords[0];
            }
        }
    }

    modifier onlyController() {
        require(controllers[msg.sender], "Wrong caller");
        _;
    }

    function addController(address controller) external onlyOwner {
        controllers[controller] = true;
    }

    function removeController(address controller) external onlyOwner {
        controllers[controller] = false;
    }

    function getWinners(uint256 raffleId) external view returns (Winner[] memory winners) {
        winners = raffles[raffleId].winners;
    }

    function getPrizes(uint256 raffleId) external view returns (Prize[][] memory prizes) {
        prizes = raffles[raffleId].prizes;
    }

    function getEntries(uint256 raffleId) external view returns (Entry[] memory entries) {
        entries = raffles[raffleId].entries;
    }

    function getPricingOptions(uint256 raffleId)
    external
    view
    returns (PricingOption[] memory pricingOptions)
    {
        pricingOptions = raffles[raffleId].pricingOptions;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function _validateRafflePostCutoffTimeStatusTransferability(Raffle storage raffle) private view {
        _validateRaffleStatus(raffle, RaffleStatus.Open);

        if (raffle.cutoffTime > block.timestamp) {
            revert CutoffTimeNotReached();
        }
    }

    function _transferPrize(
        Prize[] storage prizes,
        address recipient
    ) private {
        for (uint i; i < prizes.length;) {
            TokenType prizeType = prizes[i].tokenType;
            address prizeAddress = prizes[i].prizeAddress;
            uint prizeAmount = prizes[i].prizeAmount;
            uint prizeId = prizes[i].prizeId;

            if (prizeType == TokenType.ERC721) {
                IERC721(prizeAddress).transferFrom(address(this), recipient, prizeId);
            } else if (prizeType == TokenType.ERC1155) {
                IERC1155(prizeAddress).safeTransferFrom(address(this), recipient, prizeId, prizeAmount, "");
            } else if (prizeType == TokenType.ERC20) {
                IERC20(prizeAddress).transferFrom(address(this), recipient, prizeAmount);
            }
            else if (prizeType == TokenType.ETH) {
                payable(recipient).transfer(prizeAmount);
            }

        unchecked {
            ++i;
        }
        }
    }

    function _incrementWinningEntryUntilThereIsNotADuplicate(
        uint256 currentEntryIndex,
        uint256 winningEntry,
        uint256[] memory winningEntriesBitmap
    ) internal pure returns (uint256, uint256[] memory) {
        uint256 bucket = winningEntry >> 8;
        uint256 mask = 1 << (winningEntry & 0xff);
        while (winningEntriesBitmap[bucket] & mask != 0) {
            if (winningEntry == currentEntryIndex) {
                bucket = 0;
                winningEntry = 0;
            } else {
                winningEntry += 1;
                if (winningEntry % 256 == 0) {
                unchecked {
                    bucket += 1;
                }
                }
            }

            mask = 1 << (winningEntry & 0xff);
        }

        winningEntriesBitmap[bucket] |= mask;

        return (winningEntry, winningEntriesBitmap);
    }

    function _drawWinners(uint256 raffleId, Raffle storage raffle) private {
        _setRaffleStatus(raffle, raffleId, RaffleStatus.Drawing);
        raffle.drawnAt = uint40(block.timestamp);

        uint256 requestId = VRF_COORDINATOR.requestRandomWords({
        keyHash : KEY_HASH,
        subId : SUBSCRIPTION_ID,
        minimumRequestConfirmations : uint16(3),
        callbackGasLimit : uint32(500_000),
        numWords : uint32(1)
        });

        if (randomnessRequests[requestId].exists) {
            revert RandomnessRequestAlreadyExists();
        }

        randomnessRequests[requestId].exists = true;
        randomnessRequests[requestId].raffleId = uint80(raffleId);

        emit RandomnessRequested(raffleId, requestId);
    }

    function _unsafeAdd(uint256 a, uint256 b) private pure returns (uint256) {
    unchecked {
        return a + b;
    }
    }

    function _unsafeSubtract(uint256 a, uint256 b) private pure returns (uint256) {
    unchecked {
        return a - b;
    }
    }

    function _setRaffleStatus(
        Raffle storage raffle,
        uint256 raffleId,
        RaffleStatus status
    ) private {
        raffle.status = status;
        emit RaffleStatusUpdated(raffleId, status);
    }

    function _validateCaller(address caller) private view {
        if (msg.sender != caller) {
            revert InvalidCaller();
        }
    }

    function _validateDiscounts(uint raffleId, EntryDiscountsCalldata calldata entryDiscountsData)
    private view returns (uint8) {

        if (block.timestamp > entryDiscountsData.timeOut) {
            revert SignatureIsExpired();
        }

        uint8 totalDiscount;

        for (uint i; i < entryDiscountsData.discounts.length;) {
            if (entryDiscountsData.discounts[i] > raffles[raffleId].discounts.length) {
                revert InvalidIndex();
            }

            totalDiscount += entryDiscountsData.discounts[i];

        unchecked {
            ++i;
        }
        }

        if (!_verifyHashSignature(
            keccak256(
                abi.encode(
                    msg.sender,
                    raffleId,
                    entryDiscountsData.discounts,
                    entryDiscountsData.timeOut
                )
            ),
            entryDiscountsData.signature
        )) {
            revert InvalidSignature();
        }

        return totalDiscount;
    }

    function _validateRaffleStatus(Raffle storage raffle, RaffleStatus status) private view {
        if (raffle.status != status) {
            revert InvalidRaffleStatus();
        }
    }

    function _validateAndSetPricingOptions(
        uint256 raffleId,
        uint40 minimumEntries,
        PricingOption[] calldata pricingOptions
    ) private {
        uint40 lowestEntriesCount = pricingOptions[0].numberOfEntries;

        for (uint256 i; i < pricingOptions.length;) {
            PricingOption memory pricingOption = pricingOptions[i];

            if (i == 0) {
                if (minimumEntries % pricingOption.numberOfEntries != 0) {
                    revert InvalidPricingOption();
                }
            }
            else {
                PricingOption memory lastPricingOption = pricingOptions[_unsafeSubtract(i, 1)];
                uint208 lastPrice = lastPricingOption.price;
                uint40 lastEntriesCount = lastPricingOption.numberOfEntries;

                if (
                    pricingOption.numberOfEntries % lowestEntriesCount != 0 ||
                    pricingOption.price % pricingOption.numberOfEntries != 0 ||
                    pricingOption.numberOfEntries <= lastEntriesCount ||
                    pricingOption.price <= lastPrice ||
                    pricingOption.price / pricingOption.numberOfEntries > lastPrice / lastEntriesCount
                ) {
                    revert InvalidPricingOption();
                }
            }

            raffles[raffleId].pricingOptions.push(pricingOption);

        unchecked {
            ++i;
        }
        }
    }

    function _validateAndSetDiscounts(
        uint256 raffleId,
        uint8[] calldata discounts
    ) private {
        uint totalDiscount;

        for (uint i; i < discounts.length;) {
            if (discounts[i] == 0) {
                revert InvalidDiscount();
            }

            totalDiscount += discounts[i];

        unchecked {
            ++i;
        }
        }

        if (totalDiscount > MAX_TOTAL_DISCOUNT) {
            revert InvalidDiscount();
        }

        raffles[raffleId].discounts = discounts;
    }

    function _validateAndSetPrizes(uint raffleId, Prize[][] calldata prizes) private {
        for (uint j; j < prizes.length;) {
            Prize[] storage prizesForOnePlace = raffles[raffleId].prizes.push();

            for (uint i = 0; i < prizes[j].length;) {
                Prize memory prizeData = prizes[j][i];

                if (prizeData.tokenType == TokenType.ERC721 ||
                prizeData.tokenType == TokenType.ERC1155 ||
                prizeData.tokenType == TokenType.ERC20 ||
                    prizeData.tokenType == TokenType.ETH) {
                    if (prizeData.prizeAmount == 0) {
                        revert InvalidPrize();
                    }
                }

                if (prizeData.tokenType == TokenType.ERC721 ||
                prizeData.tokenType == TokenType.ERC1155 ||
                    prizeData.tokenType == TokenType.ERC20) {
                    if (prizeData.prizeAddress == address(0)) {
                        revert InvalidPrize();
                    }
                }

                if (prizeData.tokenType == TokenType.ERC721) {
                    if (prizeData.prizeAmount != 1) {
                        revert InvalidPrize();
                    }
                }

                Prize memory prize;
                prize.tokenType = prizeData.tokenType;
                prize.prizeAddress = prizeData.prizeAddress;
                prize.prizeId = prizeData.prizeId;
                prize.prizeAmount = prizeData.prizeAmount;

                prizesForOnePlace.push(prize);

            unchecked {
                ++i;
            }
            }

        unchecked {
            ++j;
        }
        }
    }

    function _verifyHashSignature(bytes32 freshHash, bytes memory signature) internal view returns (bool)
    {
        bytes32 hash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", freshHash)
        );
        bytes32 r;
        bytes32 s;
        uint8 v;
        if (signature.length != 65) {
            return false;
        }
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        if (v < 27) {
            v += 27;
        }
        address signer = address(0);
        if (v == 27 || v == 28) {
            // solium-disable-next-line arg-overflow
            signer = ecrecover(hash, v, r, s);
        }
        return secret == signer;
    }
}
