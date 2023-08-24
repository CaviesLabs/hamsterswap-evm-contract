import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

import {
  Etherman,
  HamsterSwap,
  IWETH9__factory,
  Multicall3,
} from "../typechain-types";

/**
 * @dev Define the item type
 */
enum SwapItemType {
  Nft,
  Currency,
}

/**
 * @dev Define status enum
 */
enum SwapItemStatus {
  Created,
  Deposited,
  Redeemed,
  Withdrawn,
}

/**
 * @dev Define proposal status
 */
enum ProposalStatus {
  Created,
  Deposited,
  Fulfilled,
  Canceled,
  Redeemed,
  Withdrawn,
}

describe("HamsterSwap", async function () {
  let fixtures: Awaited<ReturnType<typeof deployFixtures>>;

  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshopt in every test.
  async function deployFixtures() {
    const [owner, buyer, seller] = await ethers.getSigners();

    /**
     * @dev Initializes mocked erc contracts
     */
    const ERC20_WETH = IWETH9__factory.connect(
      "0xe4f05A66Ec68B54A58B17c22107b02e0232cC817",
      owner
    );
    const MockedERC721Contract = await ethers.getContractFactory(
      "MockedERC721"
    );
    const ERC721 = await MockedERC721Contract.deploy();
    await ERC721.connect(owner).safeMint(buyer.address, "1");
    await ERC721.connect(owner).safeMint(seller.address, "2");

    /**
     * @dev Deploy multicall3
     */
    const Multicall3Factory = await ethers.getContractFactory("Multicall3");
    const Multicall3Contract =
      (await Multicall3Factory.deploy()) as unknown as Multicall3;

    /**
     * @dev Deploy etherman
     */
    const EthermanFactory = await ethers.getContractFactory("Etherman");
    const EthermanContract = (await EthermanFactory.deploy(
      ERC20_WETH.address
    )) as unknown as Etherman;

    /**
     * @dev Deploy contract
     */
    const SwapContract = await ethers.getContractFactory("HamsterSwap");
    const Swap = (await upgrades.deployProxy(SwapContract.connect(owner), [], {
      unsafeAllow: ["constructor", "delegatecall"],
    })) as unknown as HamsterSwap;

    /**
     * @dev Transfer ownership
     */
    await EthermanContract.connect(owner).transferOwnership(Swap.address);

    /**
     * @dev Configure registry
     */
    await Swap.connect(owner).configure(
      "4",
      "4",
      [ERC20_WETH.address, ERC721.address],
      [],
      EthermanContract.address
    );

    /**
     * @dev return
     */
    return {
      Multicall3: Multicall3Contract,
      Swap,
      ERC20_WETH,
      ERC721,
      owner,
      seller,
      buyer,
    };
  }

  before(async () => {
    fixtures = await loadFixture(deployFixtures);
  });

  it("Should: anyone can create proposal and deposit items with multicall", async () => {
    const { Multicall3, Swap, ERC20_WETH, ERC721, seller } = fixtures;

    /**
     * @dev Approve first
     */
    await ERC20_WETH.connect(seller).approve(
      Swap.address,
      ethers.BigNumber.from(ethers.constants.MaxInt256)
    );
    await ERC721.connect(seller).setApprovalForAll(Swap.address, true);

    /**
     * @dev Expect initial values
     */
    expect(await ERC20_WETH.balanceOf(seller.address)).eq(
      ethers.utils.parseEther("0")
    );
    expect(await ERC721.balanceOf(seller.address)).eq(1);
    expect(await ERC721.ownerOf(2)).eq(seller.address);

    expect(await ERC20_WETH.balanceOf(Swap.address)).eq(0);
    expect(await ERC721.balanceOf(Swap.address)).eq(0);

    /**
     * @dev Create and deposit proposal
     */
    const proposalId = "proposal_1";
    const offeredItems = [
      {
        id: "offeredItem_1",
        contractAddress: ERC20_WETH.address,
        itemType: SwapItemType.Currency,
        amount: ethers.BigNumber.from((10 * 10 ** 18).toString()),
        tokenId: 1,
      },
      {
        id: "offeredItem_2",
        contractAddress: ERC20_WETH.address,
        itemType: SwapItemType.Currency,
        amount: ethers.BigNumber.from((10 * 10 ** 18).toString()),
        tokenId: 1,
      },
      {
        id: "offeredItem_3",
        contractAddress: ERC721.address,
        itemType: SwapItemType.Nft,
        amount: 1,
        tokenId: 2,
      },
    ];
    const askingItems = [
      {
        id: "option_1",
        askingItems: [
          {
            id: "askingItem_1",
            contractAddress: ERC721.address,
            amount: 1,
            tokenId: 1,
            itemType: SwapItemType.Nft,
          },
        ],
      },
      {
        id: "option_2",
        askingItems: [
          {
            id: "askingItem_2",
            contractAddress: ERC20_WETH.address,
            amount: 1,
            tokenId: 1,
            itemType: SwapItemType.Currency,
          },
        ],
      },
    ];
    const expiredAt =
      parseInt((new Date().getTime() / 1000).toString()) + 60 * 60;

    /**
     * @dev Call contract
     */
    await Multicall3.connect(seller).aggregate3Value(
      [
        {
          target: Swap.address,
          callData: Swap.interface.encodeFunctionData("wrapETH", [
            seller.address,
            ethers.utils.parseEther("20"),
          ]),
          value: ethers.utils.parseEther("20"),
          allowFailure: false,
        },
        {
          target: Swap.address,
          callData: Swap.interface.encodeFunctionData("createProposal", [
            proposalId,
            seller.address,
            offeredItems,
            askingItems,
            expiredAt,
          ]),
          allowFailure: false,
          value: 0,
        },
      ],
      { value: ethers.utils.parseEther("20") }
    );

    /**
     * @dev Expect
     */
    const proposal = await Swap.proposals(proposalId);

    /**
     * @dev Expect initial values
     */
    expect(proposal.id).eq(proposalId);
    expect(proposal.status).eq(ProposalStatus.Deposited); // which means the status is deposited
    expect(proposal.expiredAt).eq(expiredAt);
    expect(proposal.owner).eq(seller.address);
    expect(proposal.fulfilledBy).eq(ethers.constants.AddressZero);
    expect(proposal.fulfilledByOptionId).eq("");

    /**
     * @dev Expect items and options
     */
    const [items, options] = await Swap.getProposalItemsAndOptions(proposalId);

    /**
     * @dev Expect offered items have been recoded properly
     */
    offeredItems.map((item, index) => {
      expect(item.id).eq(items[index].id);
      expect(item.itemType).eq(items[index].itemType);
      expect(item.amount).eq(items[index].amount);
      expect(item.contractAddress).eq(items[index].contractAddress);
      expect(items[index].owner).eq(seller.address); // owner is recorded properly
      expect(items[index].status).eq(ProposalStatus.Deposited); // status changed to deposited

      if (item.itemType === 1) {
        expect(items[index].tokenId).eq(0);
      } else {
        expect(item.tokenId).eq(items[index].tokenId);
      }
    });

    /**
     * @dev Expect options have been recorded properly
     */
    askingItems.map((elm, index) => {
      expect(elm.id).eq(options[index].id);

      elm.askingItems.map((item, itemIndex) => {
        expect(item.id).eq(options[index].askingItems[itemIndex].id);
        expect(item.itemType).eq(
          options[index].askingItems[itemIndex].itemType
        );
        expect(item.amount).eq(options[index].askingItems[itemIndex].amount);
        expect(item.contractAddress).eq(
          options[index].askingItems[itemIndex].contractAddress
        );
        expect(item.tokenId).eq(options[index].askingItems[itemIndex].tokenId);

        expect(options[index].askingItems[itemIndex].status).eq(
          ProposalStatus.Created
        ); // status has been recoded as created
        expect(options[index].askingItems[itemIndex].owner).eq(
          ethers.constants.AddressZero
        ); // status has been recoded as created
      });
    });

    /**
     * @dev After transferring to the contract, the balance will be empty
     */
    expect(await ERC20_WETH.balanceOf(seller.address)).eq(0);
    expect(await ERC721.balanceOf(seller.address)).eq(0);

    expect(await ERC20_WETH.balanceOf(Swap.address)).eq(
      ethers.BigNumber.from(ethers.constants.WeiPerEther).mul(20)
    );
    expect(await ERC721.balanceOf(Swap.address)).eq(1);
    expect(await ERC721.ownerOf(2)).eq(Swap.address);
  });

  it("should: anyone can fulfill proposal if he/she owns the required items and exec the pocket, using multicall", async () => {
    const { Swap, ERC20_WETH, ERC721, seller, buyer } = fixtures;

    /**
     * @dev Before fulfilling the proposal, the balance will be empty
     */
    expect(await ERC20_WETH.balanceOf(buyer.address)).eq(0);
    expect(await ERC721.balanceOf(buyer.address)).eq(1);
    expect(await ERC721.ownerOf(1)).eq(buyer.address);

    expect(await ERC20_WETH.balanceOf(seller.address)).eq(0);
    expect(await ERC721.balanceOf(seller.address)).eq(0);

    expect(await ERC20_WETH.balanceOf(Swap.address)).eq(
      ethers.BigNumber.from(ethers.constants.WeiPerEther).mul(20)
    );
    expect(await ERC721.balanceOf(Swap.address)).eq(1);
    expect(await ERC721.ownerOf(2)).eq(Swap.address);

    /**
     * @dev Approve first
     */
    await ERC721.connect(buyer).setApprovalForAll(Swap.address, true);
    await ERC20_WETH.connect(buyer).approve(
      Swap.address,
      ethers.constants.MaxUint256
    );

    const balance = await buyer.getBalance();

    /**
     * @dev Call contract
     */
    await Swap.connect(buyer).multicall(
      [
        Swap.interface.encodeFunctionData("fulfillProposal", [
          "proposal_1",
          "option_1",
          buyer.address,
        ]),
      ],
      { gasPrice: 0 }
    );

    /**
     * @dev Expect
     */
    const proposal = await Swap.proposals("proposal_1");
    const [items, options] = await Swap.getProposalItemsAndOptions(
      "proposal_1"
    );

    expect(proposal.status).eq(ProposalStatus.Redeemed); // Redeemed
    expect(proposal.fulfilledByOptionId).eq("option_1");
    expect(proposal.fulfilledBy).eq(buyer.address);

    /**
     * @dev Expect offered items have been recoded properly
     */
    items.map((item, index) => {
      expect(items[index].owner).eq(seller.address); // owner is recorded properly
      expect(items[index].status).eq(SwapItemStatus.Redeemed); // status changed to REDEEMED
    });

    /**
     * @dev Expect options have been recorded properly
     */
    options
      .filter((elm) => elm.id === "option_1")
      .map((elm, index) => {
        elm.askingItems.map((item, itemIndex) => {
          expect(options[index].askingItems[itemIndex].status).eq(
            SwapItemStatus.Redeemed
          ); // status has been recoded as REDEEMED
          expect(options[index].askingItems[itemIndex].owner).eq(buyer.address); // owner has been updated to buyer address
        });
      });

    const balanceAfter = await buyer.getBalance();
    /**
     * @dev Before fulfilling the proposal, the balance will be empty
     */
    expect(balanceAfter.sub(balance)).eq(ethers.utils.parseEther("20"));
    expect(await ERC721.balanceOf(buyer.address)).eq(1);
    expect(await ERC721.ownerOf(2)).eq(buyer.address);

    expect(await ERC20_WETH.balanceOf(seller.address)).eq(0);
    expect(await ERC721.balanceOf(seller.address)).eq(1);
    expect(await ERC721.ownerOf(1)).eq(seller.address);

    expect(await ERC20_WETH.balanceOf(Swap.address)).eq(0);
    expect(await ERC721.balanceOf(Swap.address)).eq(0);
  });
});
