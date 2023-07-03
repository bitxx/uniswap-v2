pragma solidity =0.5.16;

//合约地址：0x92A3f1B80118e4627FaeeA874259332a84fa7372
import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';

contract UniswapV2Factory is IUniswapV2Factory {
    address public feeTo;
    address public feeToSetter;

    // creationCode 创建合约的字节码
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(UniswapV2Pair).creationCode));
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    //获取所有交易对的长度
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    //创建交易对，可以理解成是创建池子，只调用一次
    // tokenA和tokenB是两个不同的合约地址
    //为什么不使用 new 的方式，而是调用 create2 操作码来新建合约呢？使用 create2 最大的好处其实在于：可以在部署智能合约前预先计算出合约的部署地址。
    // 因为能计算出地址，简化了两个合约之间的处理
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        //必须是两个不一样的ERC20合约地址
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        //让tokenA和tokenB的地址从小到大排列
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        //token地址不能是0
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        //必须是uniswap中未创建过的pair
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        //获取模板合约UniswapV2Pair的creationCode
        bytes memory bytecode = type(UniswapV2Pair).creationCode; //bytecode 这个创建字节码其实会在 periphery 项目中的 UniswapV2Library 库中用到，是被硬编码设置的值。
        //以两个token的地址作为种子生产salt
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        //直接调用汇编创建合约
        assembly {
            //交易对的合约地址
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        //初始化刚刚创建的合约
        //为什么还要另外定义一个初始化函数，而不直接将 _token0 和 _token1 在构造函数中作为入参进行初始化呢？这是因为用 create2 创建合约的方式限制了构造函数不能有参数。
        IUniswapV2Pair(pair).initialize(token0, token1);  //初始化交易对地址
        //记录刚刚创建的合约对应的pair
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    //协议费用相关，uniswap到现在也没有使用到该功能
    // 设置手续费地址
    // 用于设置feeTo地址，只有feeToSetter才可以设置。
    // uniswap中每次交易代币会收取0.3%的手续费，目前全部分给了LQ，若此地址不为0时，将会分出手续费中的1/6给这个地址
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    // 设置手续费的管理员账户
    // 用于设置feeToSetter地址，必须是现任feeToSetter才可以设置。
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
