pragma solidity =0.5.16;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';

// 此合约继承了IUniswapV2Pair和UniswapV2ERC20，因此也是ERC20代币。
contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;  //1000
    //获取transfer方法的bytecode前四个字节
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    //一个锁，使用该modifier的函数在unlocked==1时才可以进入，
    //第一个调用者进入后，会将unlocked置为0，此使第二个调用者无法再进入
    //执行完_部分的代码后，才会再将unlocked置1，重新将锁打开
    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    //用于获取两个代币在池子中的数量和最后更新的时间
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        //调用transfer方法，把合约账户的value个代币转账给to
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        //检查返回值，必须成功否则报错
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    //部署此合约时将msg.sender设置为factory，后续初始化时会用到这个值
    //在UniswapV2Factory.sol的createPair中调用过
    // msg.sender 为factory合约地址
    constructor() public {
        factory = msg.sender;
    }

    //这个函数是用来初始化两个合约地址
    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        //防止溢出
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        // 当前块时间与池子最后更新时间的时间差
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // 计算时间加权的累计价格，256位中，前112位用来存整数，后112位用来存小数，多的32位用来存溢出的值
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        //更新reserve值
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    // 如果有设置手续费分账人，则可分走1/6的手续费
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo();  //查看有没有设置手续费账户
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // 铸造LP，新增流动性
    // this low-level function should be called from a contract which performs important safety checks
    // 假设初始化时，_reserve0=0  _reserve1=0  balance0=1000（账户转入）  balance1=4000（账户转入）amount0=1000  amount1=4000
    // 初始化最终LP生成1000个，reserve0=1000 reserve1=4000 totalSupply=2000
    //
    // 第二次mint：_reserve0=1000  _reserve1=4000 balance0=2000  balance1=8000 _totalSupply=2000 amount0=1000 amount1=4000
    // 最终：reserve0=2000 reserve1=8000 totalSupply=4000
    function mint(address to) external lock returns (uint liquidity) {
        //获取上次池子中缓存的余额
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        //用来获取当前合约注入的两种资产数量，即在两种合约里token的当前的balance
        //balance0和balance1是外部token账户转入的（erc20标准），转入到池子合约地址
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        //获得当前balance和上一次缓存的余额的差值
        uint amount0 = balance0.sub(_reserve0);   //1000
        uint amount1 = balance1.sub(_reserve1);   //4000

        //计算手续费
        //首次铸币时，为了解决攻击漏洞，牺牲了首次铸币者的利益，有1000lp被永久锁定
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            //第一次铸币，也就是第一次注入流动性，值为根号k减去MINIMUM_LIQUIDITY，也就是说Math.sqrt(amount0.mul(amount1))一定要大于1000
            //这里 uint 使用 SafeMath，所以 sub() 操作会有溢出检查，也就是说首次铸币时总流动性大于 MINIMUM_LIQUIDITY (1000)，否则会 REVERT
            // min是为了首次提高创建流行性的成本，也相当于收税，值为可以忽略不计的1000；
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);   //sub成负数的话，会报错   //1000
            //把MINIMUM_LIQUIDITY赋给地址0，永久锁住
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            //计算增量的token占总池子的比例，作为新铸币的数量
            //如果不是首次创建流动性，而是后续陆续的添加，则按照token的新增数据占目前余额的比值，计算对应的新增流动性。注意这里是取最小值，所以LP 提供者一定要按照比例添加流动性，不然就亏了。
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        // 需要注意，liquidity中已经包含了奖励的手续费
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        //铸币，修改to的token数量及totalsupply
        _mint(to, liquidity);

        //更新时间加权平均价格
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // 销毁，即销毁合约中拥有的所有流动性LP，对应的token0和token1转移至to账户
    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        //分别获取本合约地址中token0、token1和本合约代币的数量
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        //此时用户的LP token已经被转移至合约地址，因此这里取合约地址中的LP Token余额就是等下要burn掉的量
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        //根据liquidity占比获取两个代币的实际数量
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        //销毁LP Token
        _burn(address(this), liquidity);
        //将token0和token1转给地址to
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        //更新时间加权平均价格
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }




    // swap
    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        //一对大括号,为了限制 _token{0,1} 这两个临时变量的作用域，防止堆栈太深导致错误。
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0; //两种token合约地址
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens 有最后一个条件限制x*y=k，不可能让你随意转出。balance0Adjusted
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);  //to地址实现了uniswapV2Call才能用，如闪电贷
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }
        //amount0In和amount1In表示uniswap合约地址中，两种token余额。也就是说，如果balance大于_reserve0(可能是外部转入给合约的)，则也会被囊入到流动性中，
        //正常情况下，balance始终等于reserve，除非有人给合约账户通过直接转账追加了流动性
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));  //减去手续费的数额，手续费是池子剩余余额的0.3%
        uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K'); //x*y=k，交易后的k要不小于交易前的k
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
