# uniswap-v2
基于hardhat框架管理和发布uniswap v2

## 信息整理
使用本项目，goerli测试网自行发布信息如下：
1. [WETH9地址](https://goerli.etherscan.io/address/0xFe33eC9960E430608030e92860264B486Ae99Ef2) ：0xFe33eC9960E430608030e92860264B486Ae99Ef2
2. [UniswapV2Factory合约地址](https://goerli.etherscan.io/address/0x08b99e6b892da793b3da07db14d83c86337d5b1c) ：0x08b99e6b892da793b3da07db14d83c86337d5b1c
3. [UniswapV2Router02合约地址](https://goerli.etherscan.io/address/0x4A566ba09a8628d2a3BC7132f6F9F1D3Fe8Aca61) ：0x4A566ba09a8628d2a3BC7132f6F9F1D3Fe8Aca61
4. UniswapV2Factory的`INIT_CODE_PAIR_HASH` = 0x6ea2252a145d03633feebbade3509ebd120dbe9d50dbf6bd343c366dc155dc67
5. [AAA Token](https://goerli.etherscan.io/token/0x41466d52a90dFa935463c38B7D477059D5B04093) ：0x41466d52a90dFa935463c38B7D477059D5B04093
6. [BBB Token](https://goerli.etherscan.io/token/0xC180BA5FD897781f5764c1B079e21Be2a77855Ee) ：0xC180BA5FD897781f5764c1B079e21Be2a77855Ee
7. [MyTokenList](https://gist.githubusercontent.com/jason-wj/53780a04750e640b6e5171090b7707ac/raw/d77990cd7a69f7bf559dda874d9e401b747fa6a8/token.json)


## 发布
```shell
npm install
npx hardhat --network goerli run scripts/deploy.js
```
