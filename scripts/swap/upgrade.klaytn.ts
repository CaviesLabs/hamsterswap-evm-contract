import { ethers, upgrades } from "hardhat";
import { HamsterSwap } from "../../typechain-types";

async function main() {
  const Addresses = {
    HamsterSwapAddress: "0x3Fe3828e742bA90Cb8fd002Ae05C501c495F484B",
  };

  /**
   * @dev Deploy contract
   */
  const SwapContract = await ethers.getContractFactory("HamsterSwap");
  try {
    await upgrades.forceImport(Addresses.HamsterSwapAddress, SwapContract);
  } catch {
    console.log("skipped warning");
  }
  const Swap = (await upgrades.upgradeProxy(
    Addresses.HamsterSwapAddress,
    SwapContract,
    { unsafeAllow: ["delegatecall"] }
  )) as unknown as HamsterSwap;
  console.log("HamsterSwap upgraded at:", Swap.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
