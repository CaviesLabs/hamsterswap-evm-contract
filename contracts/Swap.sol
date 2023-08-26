// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./Entity.sol";
import "./Params.sol";
import "./Etherman.sol";

import "hardhat/console.sol";

/**
 * @notice HamsterSwap which is a trustless p2p exchange,
 * handles NFT-NFT, NFT-Currency and Currency-Currency pocket transactions.
 **/
/// @custom:security-contact khang@cavies.xyz
contract HamsterSwap is
	Initializable,
	PausableUpgradeable,
	ReentrancyGuardUpgradeable,
	OwnableUpgradeable,
	MulticallUpgradeable,
	IERC721Receiver
{
	Etherman public etherman;

	/**
	 * @dev Administration configurations.
	 */
	uint256 public maxAllowedItems;
	uint256 public maxAllowedOptions;
	mapping(address => bool) public whitelistedAddresses;

	/**
	 * @dev Storing proposal data inside a mapping
	 */
	mapping(string => Entity.Proposal) public proposals;
	mapping(string => bool) public uniqueStringRegistry;

	/** @dev Events */
	event ConfigurationChanged(
		address actor,
		uint256 timestamp,
		uint256 maxAllowedItems,
		uint256 maxAllowedOptions,
		address[] whitelistedAddresses,
		address[] blacklistedAddresses,
		address ethermanAddress
	);

	event ProposalCreated(string id, address actor, uint256 timestamp);

	event ProposalRedeemed(
		string id,
		address actor,
		uint256 timestamp,
		string optionId
	);

	event ProposalWithdrawn(string id, address actor, uint256 timestamp);

	event ItemDeposited(
		string id,
		address actor,
		address fromAddress,
		uint256 timestamp,
		address contractAddress,
		uint256 amount,
		uint256 tokenId
	);

	event ItemRedeemed(
		string id,
		address actor,
		address fromAddress,
		address toAddress,
		uint256 timestamp,
		address contractAddress,
		uint256 amount,
		uint256 tokenId
	);

	event ItemWithdrawn(
		string id,
		address actor,
		address fromAddress,
		address toAddress,
		uint256 timestamp,
		address contractAddress,
		uint256 amount,
		uint256 tokenId
	);

	/**
	 * @dev Get proposal items and options
	 * @param id: id of the proposal
	 */
	function getProposalItemsAndOptions(string memory id)
		external
		view
		returns (Entity.SwapItem[] memory, Entity.SwapOption[] memory)
	{
		return (proposals[id].offeredItems, proposals[id].swapOptions);
	}

	/**
	 * @dev Configure pocket registry
	 * @param _maxAllowedItems: maximum amount of allowed items
	 * @param _maxAllowedOptions: maximum amount of allowed options
	 * @param _whitelistedItemAddresses: whitelisted addresses
	 * @param _blackListedItemAddresses: blacklisted addresses
	 */
	function configure(
		uint256 _maxAllowedItems,
		uint256 _maxAllowedOptions,
		address[] memory _whitelistedItemAddresses,
		address[] memory _blackListedItemAddresses,
		address payable _ethermanAddress
	) external onlyOwner whenNotPaused {
		/**
		 * @dev Configure values
		 */
		maxAllowedItems = _maxAllowedItems;
		maxAllowedOptions = _maxAllowedOptions;

		/**
		 * @dev Whitelisting addresses
		 */
		for (uint256 i = 0; i < _whitelistedItemAddresses.length; i++) {
			whitelistedAddresses[_whitelistedItemAddresses[i]] = true;
		}

		/**
		 * @dev Blacklisted addresses
		 */
		for (uint256 i = 0; i < _blackListedItemAddresses.length; i++) {
			whitelistedAddresses[_blackListedItemAddresses[i]] = false;
		}

		/**
		 * @dev Set etherman address
		 */
		etherman = Etherman(_ethermanAddress);
		IERC20(etherman.WETH()).approve(_ethermanAddress, type(uint256).max);

		/**
		 * @dev Emit event
		 */
		emit ConfigurationChanged(
			msg.sender,
			block.timestamp,
			_maxAllowedItems,
			_maxAllowedOptions,
			_whitelistedItemAddresses,
			_blackListedItemAddresses,
			_ethermanAddress
		);
	}

	/**
	 * @dev Create proposal and deposit items
	 * @param id: proposal id
	 * @param swapItemsData: pocket item list to be passed into proposal creation
	 * @param swapOptionsData: pocket option list to be passed into proposal creation
	 * @param expiredAt: expiry date of the proposal
	 */
	function createProposal(
		string memory id,
		address owner,
		Params.SwapItemParams[] memory swapItemsData,
		Params.SwapOptionParams[] memory swapOptionsData,
		uint256 expiredAt
	) external nonReentrant whenNotPaused {
		/**
		 * @dev This allow owner can use smart contract to create proposal
		 */
		assert(owner == msg.sender || owner == tx.origin);

		/**
		 * @dev Avoid duplicated proposal id to be recorded in.
		 */
		assert(bytes(proposals[id].id).length == 0);

		/**
		 * @dev Must be unique id
		 */
		assert(uniqueStringRegistry[id] == false);
		uniqueStringRegistry[id] = true;

		/**
		 * @dev Require constraints
		 */
		assert(swapOptionsData.length <= maxAllowedOptions);
		assert(swapItemsData.length <= maxAllowedItems);
		assert(expiredAt > block.timestamp);

		/**
		 * @dev Assign proposal
		 */
		proposals[id].id = id;
		proposals[id].expiredAt = expiredAt;
		proposals[id].status = Entity.ProposalStatus.Deposited;
		proposals[id].owner = owner;

		/**
		 * @dev Populate data
		 */
		for (uint256 i = 0; i < swapOptionsData.length; i++) {
			/**
			 * @dev Ensure the id is unique
			 */
			assert(uniqueStringRegistry[swapOptionsData[i].id] == false);
			uniqueStringRegistry[swapOptionsData[i].id] = true;

			/**
			 * @dev Check for constraints
			 */
			assert(bytes(swapOptionsData[i].id).length > 0);

			/**
			 * @dev Populate pocket option data
			 */
			Entity.SwapOption storage option = proposals[id].swapOptions.push();
			option.id = swapOptionsData[i].id;

			for (
				uint256 j = 0;
				j < swapOptionsData[i].askingItems.length;
				j++
			) {
				/**
				 * @dev Ensure the id is unique
				 */
				assert(
					uniqueStringRegistry[
						swapOptionsData[i].askingItems[j].id
					] == false
				);
				uniqueStringRegistry[
					swapOptionsData[i].askingItems[j].id
				] = true;

				/**
				 * @dev Must be a whitelisted addresses
				 */
				assert(
					whitelistedAddresses[
						swapOptionsData[i].askingItems[j].contractAddress
					] == true
				);

				/**
				 * @dev Populate pocket item data
				 */
				Entity.SwapItem storage item = option.askingItems.push();

				item.id = swapOptionsData[i].askingItems[j].id;
				item.contractAddress = swapOptionsData[i]
					.askingItems[j]
					.contractAddress;
				item.itemType = swapOptionsData[i].askingItems[j].itemType;
				item.tokenId = swapOptionsData[i].askingItems[j].tokenId;
				item.amount = swapOptionsData[i].askingItems[j].amount;
				item.status = Entity.SwapItemStatus.Created;
			}
		}

		/**
		 * @dev Populate data
		 */
		for (uint256 i = 0; i < swapItemsData.length; i++) {
			/**
			 * @dev Must be a whitelisted addresses
			 */
			assert(
				whitelistedAddresses[swapItemsData[i].contractAddress] == true
			);

			/**
			 * @dev Ensure the id is unique
			 */
			assert(uniqueStringRegistry[swapItemsData[i].id] == false);
			uniqueStringRegistry[swapItemsData[i].id] = true;

			/**
			 * @dev Initialize empty struct
			 */
			Entity.SwapItem storage swapItem = proposals[id]
				.offeredItems
				.push();

			/**
			 * @dev Assign data
			 */
			swapItem.id = swapItemsData[i].id;
			swapItem.contractAddress = swapItemsData[i].contractAddress;
			swapItem.itemType = swapItemsData[i].itemType;
			swapItem.amount = swapItemsData[i].amount;
			swapItem.owner = owner;
			swapItem.status = Entity.SwapItemStatus.Deposited;
			swapItem.tokenId = swapItemsData[i].tokenId;
		}

		/**
		 * @dev Transfer items from user address to contract
		 */
		transferSwapItems(
			proposals[id].offeredItems,
			owner,
			address(this),
			Entity.SwapItemStatus.Deposited,
			address(0)
		);

		/**
		 * @dev Emit event
		 */
		emit ProposalCreated(id, owner, block.timestamp);
	}

	/**
	 * @dev Fulfill proposal
	 * @param proposalId: the proposal id that targeted to
	 * @param optionId: the option id that user wants to fulfil with
	 */
	function fulfillProposal(
		string memory proposalId,
		string memory optionId,
		address payable buyer
	) external nonReentrant whenNotPaused {
		/**
		 * @dev This allow owner can use smart contract to create proposal
		 */
		assert(buyer == msg.sender || buyer == tx.origin);

		/**
		 * @dev Must be an existed proposal
		 */
		assert(bytes(proposals[proposalId].id).length > 0);

		/**
		 * @dev The proposal must be at deposited phase.
		 */
		assert(proposals[proposalId].status == Entity.ProposalStatus.Deposited);

		/**
		 * @dev The proposal must be still in time window.
		 */
		assert(proposals[proposalId].expiredAt > block.timestamp);

		/**
		 * @dev Adjust proposal value.
		 */
		proposals[proposalId].fulfilledBy = buyer;
		proposals[proposalId].fulfilledByOptionId = optionId;
		proposals[proposalId].status = Entity.ProposalStatus.Redeemed;

		/**
		 * @dev Find the proposal
		 */
		uint256 index = maxAllowedItems + 1;

		for (uint256 i = 0; i < proposals[proposalId].swapOptions.length; i++) {
			Entity.Proposal memory _proposal = proposals[proposalId];
			Entity.SwapOption memory _option = _proposal.swapOptions[i];
			string memory _optionId = _option.id;

			if (areStringsEqual(_optionId, optionId)) {
				index = i;
				break;
			}
		}

		/**
		 * @dev Check for constraints
		 */
		assert(index != maxAllowedItems + 1);

		/**
		 * @dev Binding option
		 */
		Entity.SwapOption storage option = proposals[proposalId].swapOptions[
			index
		];

		/**
		 * @dev Transfer assets to owner
		 */
		transferSwapItems(
			option.askingItems,
			buyer,
			address(proposals[proposalId].owner),
			Entity.SwapItemStatus.Redeemed,
			buyer
		);

		/**
		 * @dev And then redeem items
		 */
		transferSwapItems(
			proposals[proposalId].offeredItems,
			address(this),
			buyer,
			Entity.SwapItemStatus.Redeemed,
			address(0)
		);

		/**
		 * @dev Emit event
		 */
		emit ProposalRedeemed(
			proposalId,
			msg.sender,
			block.timestamp,
			optionId
		);
	}

	/**
	 * @dev Cancel proposal and withdraw assets
	 * @param proposalId: proposal id that was targeted
	 */
	function cancelProposal(string memory proposalId)
		external
		nonReentrant
		whenNotPaused
	{
		/**
		 * @dev Must be an existed proposal
		 */
		assert(bytes(proposals[proposalId].id).length > 0);

		/**
		 * @dev The proposal owner has the rights to cancel the proposal.
		 */
		assert(proposals[proposalId].owner == msg.sender);

		/**
		 * @dev The proposal must be at deposited phase.
		 */
		assert(proposals[proposalId].status == Entity.ProposalStatus.Deposited);

		/**
		 * @dev Modify value
		 */
		proposals[proposalId].status = Entity.ProposalStatus.Withdrawn;

		/**
		 * @dev Withdraw items
		 */
		transferSwapItems(
			proposals[proposalId].offeredItems,
			address(this),
			msg.sender,
			Entity.SwapItemStatus.Withdrawn,
			address(0)
		);

		/**
		 * @dev Emit event
		 */
		emit ProposalWithdrawn(proposalId, msg.sender, block.timestamp);
	}

	/**
	 * @dev Wrap ETH to WETH
	 */
	function wrapETH(address actor, uint256 amount)
		external
		payable
		nonReentrant
		whenNotPaused
	{
		assert(actor == msg.sender || actor == tx.origin);
		etherman.wrapETH{value: amount}(actor, amount);
	}

	/**
	 * @dev Unwrap WETH to ETH
	 */
	function unwrapETH(address payable actor)
		external
		nonReentrant
		whenNotPaused
	{
		/**
		 * @dev This allow owner can use smart contract to create proposal
		 */
		assert(actor == msg.sender || actor == tx.origin);

		uint256 amount = IWETH9(etherman.WETH()).balanceOf(actor);

		assert(amount > 0);
		assert(
			IWETH9(etherman.WETH()).transferFrom(actor, address(this), amount)
		);

		etherman.unwrapWETH(actor, amount);
	}

	/**
	 * @dev Withdraw assets from contract
	 * @param items: the items that user wants to transfer
	 * @param from: the address that user wants to transfer from
	 * @param to: the address that user wants to transfer to
	 * @param remarkedStatus: the status that user wants to change to
	 * @param remarkedOwner: the owner that user wants to change to
	 */
	function transferSwapItems(
		Entity.SwapItem[] storage items,
		address from,
		address to,
		Entity.SwapItemStatus remarkedStatus,
		address remarkedOwner
	) private {
		/**
		 * @dev And then withdraw items
		 */
		for (uint256 i = 0; i < items.length; i++) {
			/**
			 * @dev Must be a whitelisted addresses
			 */
			require(whitelistedAddresses[items[i].contractAddress] == true);

			/**
			 * @dev Change to remarkedStatus
			 */
			items[i].status = remarkedStatus;

			/**
			 * @dev Change to remarked owner if needed
			 */
			if (remarkedOwner != address(0)) {
				items[i].owner = remarkedOwner;
			}

			/**
			 * @dev transfer ERC721 assets
			 */
			if (items[i].itemType == Entity.SwapItemType.Nft) {
				items[i].amount = 1;

				IERC721(items[i].contractAddress).safeTransferFrom(
					from,
					to,
					items[i].tokenId
				);
			}

			/**
			 * @dev transfer ERC20 assets
			 */
			if (items[i].itemType == Entity.SwapItemType.Currency) {
				/// @dev Mark tokenId as 0 as it's not an ERC721 item
				items[i].tokenId = 0;

				bool shouldUnwrap = items[i].contractAddress ==
					address(etherman.WETH()) &&
					(from == address(this) || to != address(this));

				/// @dev If transferring out of the vault
				if (from == address(this)) {
					/// @dev If it's WETH, unwrap it
					if (shouldUnwrap) {
						etherman.unwrapWETH(payable(to), items[i].amount);
					} else {
						/// @dev Transfer normal ERC20 assets
						assert(
							IERC20(items[i].contractAddress).transfer(
								to,
								items[i].amount
							)
						);
					}
				} else {
					if (shouldUnwrap) {
						uint256 beforeBalance = address(to).balance;

						/// @dev If transferring to the vault and it's WETH, unwrap it
						assert(
							IERC20(items[i].contractAddress).transferFrom(
								from,
								address(this),
								items[i].amount
							)
						);

						etherman.unwrapWETH(payable(to), items[i].amount);
					} else {
						/// @dev If transferring to the vault, process it normally
						assert(
							IERC20(items[i].contractAddress).transferFrom(
								from,
								to,
								items[i].amount
							)
						);
					}
				}
			}

			/**
			 * @dev Emit event
			 */
			if (remarkedStatus == Entity.SwapItemStatus.Deposited) {
				emit ItemDeposited(
					items[i].id,
					msg.sender,
					from,
					block.timestamp,
					items[i].contractAddress,
					items[i].tokenId,
					items[i].amount
				);
			} else if (remarkedStatus == Entity.SwapItemStatus.Redeemed) {
				emit ItemRedeemed(
					items[i].id,
					msg.sender,
					from,
					to,
					block.timestamp,
					items[i].contractAddress,
					items[i].tokenId,
					items[i].amount
				);
			} else if (remarkedStatus == Entity.SwapItemStatus.Withdrawn) {
				emit ItemWithdrawn(
					items[i].id,
					msg.sender,
					from,
					to,
					block.timestamp,
					items[i].contractAddress,
					items[i].tokenId,
					items[i].amount
				);
			}
		}
	}

	/**
	 * @dev Utility function
	 */
	function areStringsEqual(string memory s1, string memory s2)
		private
		pure
		returns (bool)
	{
		return
			keccak256(abi.encodePacked(s1)) == keccak256(abi.encodePacked(s2));
	}

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize() public initializer {
		__Pausable_init();
		__Ownable_init();
	}

	function pause() public onlyOwner {
		_pause();
	}

	function unpause() public onlyOwner {
		_unpause();
	}

	function onERC721Received(
		address,
		address,
		uint256,
		bytes calldata
	) external pure returns (bytes4) {
		return IERC721Receiver.onERC721Received.selector;
	}
}
