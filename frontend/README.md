# Uniswap 前端

## 部署

```bash
# 下载依赖
yarn

# 启动
yarn start

# 备注：如果node verson>=17，需要加入如下环境变量
export NODE_OPTIONS=--openssl-legacy-provider
```

### Configuring the environment (optional)

To have the interface default to a different network when a wallet is not connected:

1. Make a copy of `.env` named `.env.local`
2. Change `REACT_APP_NETWORK_ID` to `"{YOUR_NETWORK_ID}"`
3. Change `REACT_APP_NETWORK_URL` to e.g. `"https://{YOUR_NETWORK_ID}.infura.io/v3/{YOUR_INFURA_KEY}"`