// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Interface for WETH9
interface IWETH9 is IERC20 {
	/// @notice Deposit ether to get wrapped ether
	function deposit() external payable;

	/// @notice Withdraw wrapped ether to get ether
	function withdraw(uint256) external;
}

contract Etherman is Ownable {
	address public immutable WETH;

	constructor(address _weth) Ownable() {
		WETH = _weth;
	}

	/// @notice Wrap ETH for owner
	function wrapETH(address target, uint256 amount)
		external
		payable
		onlyOwner
	{
		assert(msg.value == amount);
		assert(msg.value > 0);

		/// @dev Deposit ETH
		IWETH9(WETH).deposit{value: amount}();

		/// @dev Now transfer WETH
		assert(IERC20(WETH).transfer(target, amount));
	}

	/// @notice Unwrap WETH for owner
	function unwrapWETH(address payable target, uint256 amount)
		external
		onlyOwner
	{
		assert(amount > 0);

		/// @dev Deposit ERC-20 of WETH
		IWETH9(WETH).transferFrom(msg.sender, address(this), amount);

		/// @dev Now call unwrap
		IWETH9(WETH).withdraw(amount);

		(bool success, ) = target.call{value: amount}("");
		require(success, "Error: cannot unwrap WETH");
	}

	/// @dev To receive
	receive() external payable {}
}
