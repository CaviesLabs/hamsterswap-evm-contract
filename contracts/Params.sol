pragma solidity >=0.8.17;

import "./Entity.sol";

library Params {
	/**
	 * @dev Define pocket item
	 */
	struct SwapItemParams {
		string id;
		address contractAddress;
		uint256 amount;
		uint256 tokenId;
		Entity.SwapItemType itemType;
	}

	/**
	 * @dev Define pocket option
	 */
	struct SwapOptionParams {
		string id;
		SwapItemParams[] askingItems;
	}

	/**
	 * @dev Define proposal
	 */
	struct ProposalParams {
		string id;
		uint256 expiredAt;
		SwapItemParams[] offeredItems;
		SwapOptionParams[] swapOptions;
	}
}
