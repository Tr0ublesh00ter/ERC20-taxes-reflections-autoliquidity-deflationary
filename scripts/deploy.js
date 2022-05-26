// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
//const routerV2Address = "0x10ED43C718714eb63d5aA57B78B54704E256024E"; pcs
const UniswapV2Router02 = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
const UniswapV2Router01 = "0xf164fC0Ec4E93095b804a4795bBe1e041497b92a";

async function main() {
    // Hardhat always runs the compile task when running scripts with its command
    // line interface.
    //
    // If this script is run directly using `node` you may want to call compile
    // manually to make sure everything is compiled
    // await hre.run('compile');

    // We get the contract to deploy
    const TokenContract = await hre.ethers.getContractFactory("AutoStakeERC20");
    const tokenContract = await TokenContract.deploy();

    await tokenContract.deployed();

    console.log("Token contract deployed to:", tokenContract.address);

    const StakingContract = await hre.ethers.getContractFactory("Distributor");
    const stakingContract = await StakingContract.deploy(UniswapV2Router02);

    await stakingContract.deployed();

    console.log("Staking contract deployed to:", stakingContract.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});