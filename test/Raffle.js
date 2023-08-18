const {expect} = require("chai");
const axios = require("axios");

describe("Raffle", function () {
    let ERC721Example = null;
    let ERC1155Example = null;
    let HardhatVrfCoordinatorV2Mock = null;
    let Raffle = null;
    let signers = null;

    before(async () => {
        signers = await ethers.getSigners();

        const raffleFactory = await ethers.getContractFactory("Raffle");

        ERC721Example = await ethers.deployContract("ERC721Example");
        await ERC721Example.waitForDeployment();

        ERC1155Example = await ethers.deployContract("ERC1155Example");
        await ERC1155Example.waitForDeployment();

        await ERC721Example.mint(5);
        await ERC1155Example.mint(5);

        let vrfCoordinatorV2Mock = await ethers.getContractFactory("VRFCoordinatorV2Mock");

        HardhatVrfCoordinatorV2Mock = await vrfCoordinatorV2Mock.deploy(0, 0);

        await HardhatVrfCoordinatorV2Mock.createSubscription();
        await HardhatVrfCoordinatorV2Mock.fundSubscription(1, ethers.parseEther("7"));

        Raffle = await raffleFactory.deploy(1, HardhatVrfCoordinatorV2Mock.target);
        await HardhatVrfCoordinatorV2Mock.addConsumer(1, Raffle.target);

        await Raffle.addController(signers[0]);

        await ERC721Example.setApprovalForAll(Raffle.target, true);
        await ERC1155Example.setApprovalForAll(Raffle.target, true);
    })

    it("Create raffle with invalid cutoff", async function () {
        await expect(Raffle.createRaffle(
            {
                cutoffTime: 1691876258,
                isMinimumEntriesFixed: true,
                minimumEntries: 500,
                maximumEntriesPerParticipant: 10,
                pricingOptions: [
                    {
                        price: 1000000000000,
                        numberOfEntries: 10
                    },
                    {
                        price: 1700000000000,
                        numberOfEntries: 20
                    }
                ],
                prizes: [
                    [
                        {
                            tokenType: 0,
                            prizeAddress: ERC721Example.target,
                            prizeId: 1,
                            prizeAmount: 1
                        },
                        {
                            tokenType: 0,
                            prizeAddress: ERC721Example.target,
                            prizeId: 2,
                            prizeAmount: 1
                        },
                        {
                            tokenType: 1,
                            prizeAddress: ERC1155Example.target,
                            prizeId: 1,
                            prizeAmount: 1
                        }
                    ],
                    [
                        {
                            tokenType: 2,
                            prizeAddress: '0x0000000000000000000000000000000000000000',
                            prizeId: 36,
                            prizeAmount: 10000000000000
                        }
                    ]
                ],
                discounts: []
            }
        )).to.be.revertedWithCustomError(Raffle, 'InvalidCutoffTime');
    });

    it("Create raffle with invalid number of entries", async function () {
        await expect(Raffle.createRaffle(
            {
                cutoffTime: Math.floor((Date.now() / 1000) + 86400),
                isMinimumEntriesFixed: true,
                minimumEntries: 500,
                maximumEntriesPerParticipant: 10,
                pricingOptions: [
                    {
                        price: 1000000000000,
                        numberOfEntries: 10
                    },
                    {
                        price: 1700000000000,
                        numberOfEntries: 10
                    }
                ],
                prizes: [
                    [
                        {
                            tokenType: 0,
                            prizeAddress: ERC721Example.target,
                            prizeId: 1,
                            prizeAmount: 1
                        },
                        {
                            tokenType: 0,
                            prizeAddress: ERC721Example.target,
                            prizeId: 2,
                            prizeAmount: 1
                        },
                        {
                            tokenType: 1,
                            prizeAddress: ERC1155Example.target,
                            prizeId: 1,
                            prizeAmount: 1
                        }
                    ],
                    [
                        {
                            tokenType: 2,
                            prizeAddress: '0x0000000000000000000000000000000000000000',
                            prizeId: 36,
                            prizeAmount: 10000000000000
                        }
                    ]
                ],
                discounts: []
            }
        )).to.be.revertedWithCustomError(Raffle, 'InvalidPricingOption');
    });

    it("Create raffle with invalid pricing", async function () {
        await expect(Raffle.createRaffle(
            {
                cutoffTime: Math.floor((Date.now() / 1000) + 86400),
                isMinimumEntriesFixed: true,
                minimumEntries: 500,
                maximumEntriesPerParticipant: 10,
                pricingOptions: [
                    {
                        price: 1000000000000,
                        numberOfEntries: 10
                    },
                    {
                        price: 1000000000000,
                        numberOfEntries: 20
                    }
                ],
                prizes: [
                    [
                        {
                            tokenType: 0,
                            prizeAddress: ERC721Example.target,
                            prizeId: 1,
                            prizeAmount: 1
                        },
                        {
                            tokenType: 0,
                            prizeAddress: ERC721Example.target,
                            prizeId: 2,
                            prizeAmount: 1
                        },
                        {
                            tokenType: 1,
                            prizeAddress: ERC1155Example.target,
                            prizeId: 1,
                            prizeAmount: 1
                        }
                    ],
                    [
                        {
                            tokenType: 2,
                            prizeAddress: '0x0000000000000000000000000000000000000000',
                            prizeId: 36,
                            prizeAmount: 10000000000000
                        }
                    ]
                ],
                discounts: []
            }
        )).to.be.revertedWithCustomError(Raffle, 'InvalidPricingOption');
    });

    it("Create raffle with minumum entries", async function () {
        await expect(Raffle.createRaffle(
            {
                cutoffTime: Math.floor((Date.now() / 1000) + 86400),
                isMinimumEntriesFixed: true,
                minimumEntries: 5,
                maximumEntriesPerParticipant: 10,
                pricingOptions: [
                    {
                        price: 1000000000000,
                        numberOfEntries: 10
                    },
                    {
                        price: 1000000000000,
                        numberOfEntries: 20
                    }
                ],
                prizes: [
                    [
                        {
                            tokenType: 0,
                            prizeAddress: ERC721Example.target,
                            prizeId: 1,
                            prizeAmount: 1
                        },
                        {
                            tokenType: 0,
                            prizeAddress: ERC721Example.target,
                            prizeId: 2,
                            prizeAmount: 1
                        },
                        {
                            tokenType: 1,
                            prizeAddress: ERC1155Example.target,
                            prizeId: 1,
                            prizeAmount: 1
                        }
                    ],
                    [
                        {
                            tokenType: 2,
                            prizeAddress: '0x0000000000000000000000000000000000000000',
                            prizeId: 36,
                            prizeAmount: 10000000000000
                        }
                    ]
                ],
                discounts: []
            }
        )).to.be.revertedWithCustomError(Raffle, 'InvalidPricingOption');
    });

    it("Create raffle", async function () {
        await Raffle.createRaffle(
            {
                cutoffTime: Math.floor((Date.now() / 1000) + 86400),
                isMinimumEntriesFixed: true,
                minimumEntries: 500,
                maximumEntriesPerParticipant: 500,
                pricingOptions: [
                    {
                        price: 1000000000000,
                        numberOfEntries: 10
                    },
                    {
                        price: 1700000000000,
                        numberOfEntries: 20
                    }
                ],
                prizes: [
                    [
                        {
                            tokenType: 0,
                            prizeAddress: ERC721Example.target,
                            prizeId: 2,
                            prizeAmount: 1
                        }
                    ],
                    [
                        {
                            tokenType: 1,
                            prizeAddress: ERC1155Example.target,
                            prizeId: 1,
                            prizeAmount: 1
                        },
                        {
                            tokenType: 0,
                            prizeAddress: ERC721Example.target,
                            prizeId: 1,
                            prizeAmount: 1
                        }
                    ],
                    [
                        {
                            tokenType: 2,
                            prizeAddress: '0x0000000000000000000000000000000000000000',
                            prizeId: 0,
                            prizeAmount: 10000000000000
                        }
                    ]
                ],
                discounts: []
            }
        )
    });

    it("Deposit prizes", async function () {
        await Raffle.depositPrizes(1, {value: ethers.parseEther("0.00001")});

        expect(await ethers.provider.getBalance(Raffle.target)).to.equal(ethers.parseEther('0.00001'));
        expect(await ERC721Example.ownerOf(1)).to.be.equal(Raffle.target);
        expect(await ERC721Example.ownerOf(2)).to.be.equal(Raffle.target);
        expect(await ERC1155Example.balanceOf(Raffle.target, 1)).to.be.equal(1);
    });

    it("Enter raffle", async function () {
        await Raffle
            .connect(signers[1])
            .enterRaffle({
                    raffleId: 1,
                    entriesOptions: [
                        {
                            pricingOptionIndex: 1,
                            count: 12
                        }
                    ]
                },
                {value: 1700000000000 * 12}
            );
    });

    it("Withdraw raffle prizes with invalid raffle status", async function () {
        await expect(Raffle.withdrawPrizes(1)).to.be.revertedWithCustomError(Raffle, 'InvalidRaffleStatus');
    });

    it("Claim refund with invalid raffle status", async function () {
        await expect(Raffle.claimRefund(1)).to.be.revertedWithCustomError(Raffle, 'InvalidRaffleStatus');
    });

    it("Enter raffle buying last entries and select winners", async function () {
        const tx = await Raffle.enterRaffle({
                raffleId: 1,
                entriesOptions: [
                    {
                        pricingOptionIndex: 1,
                        count: 13
                    }
                ]
            },
            {value: 1700000000000 * 13}
        );

        const rec = await tx.wait();

        expect(
            tx
        ).to.emit(Raffle, "RandomnessRequested")
            .withArgs(1, 1);

        const [raffleId, requestId] = rec.logs[rec.logs.length - 1].args;

        const tx2 = HardhatVrfCoordinatorV2Mock.fulfillRandomWords(requestId, Raffle.target);

        expect(tx2).to.emit(HardhatVrfCoordinatorV2Mock, "RandomWordsFulfilled");

        await Raffle.selectWinners(requestId);

        const winnersLength = (await Raffle.getWinners(raffleId)).length;

        expect(winnersLength).to.equal(3);
    });

    it("Claim prizes", async () => {
        // await Raffle
        //     .connect(signers[1])
        //     .claimPrizes({
        //         raffleId: 1,
        //         winnerIndices: [1, 2]
        //     });

        await Raffle
            .claimPrizes({
                raffleId: 1,
                winnerIndices: [0]
            });
    });

    // it("Enter raffle with discounts", async function () {
    //     await Raffle.enterRaffleWithDiscounts({
    //             raffleId: 1,
    //             entriesOptions: [
    //                 {
    //                     pricingOptionIndex: 1,
    //                     count: 2
    //                 }
    //             ],
    //             entryDiscountsData:
    //         },
    //         {value: 3400000000000}
    //     );
    // });
});
