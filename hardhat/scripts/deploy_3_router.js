// This is a script for deploying your contracts. You can adapt it to deploy
// yours, or create new ones.

async function main() {
    // This is just a convenience check
    if (network.name === "hardhat") {
        console.warn(
            "You are trying to deploy a contract to the Hardhat Network, which" +
            "gets automatically created and destroyed every time. Use the Hardhat" +
            " option '--network localhost'"
        );
    }

    // ethers is available in the global scope
    const [deployer] = await ethers.getSigners();
    console.log(
        "Deploying the contracts with the account:",
        await deployer.getAddress()
    );

    console.log("Account balance:", (await deployer.getBalance()).toString());

    //solidity version：0.6.6
    await uniswapV2Router02();
}

//solidity version：0.6.6
async function uniswapV2Router02(){
    const UniswapV2Router02 = await ethers.getContractFactory("UniswapV2Router02");
    const uniswapV2Router02 = await UniswapV2Router02.deploy('0x08b99E6B892da793b3dA07db14D83c86337d5B1c','0xFe33eC9960E430608030e92860264B486Ae99Ef2');
    await uniswapV2Router02.deployed();

    console.log("UniswapV2Router02 address:", uniswapV2Router02.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
