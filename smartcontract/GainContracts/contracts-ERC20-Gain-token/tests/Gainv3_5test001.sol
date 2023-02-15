// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.16;

import "./lib/ERC20Upgradeable.sol";
import "./lib/IUniswapV2Factory.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// @author MrKawdy & Swati Malode
contract Gainv3_5test001 is ERC20Upgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeMathInt for int256;
    
    // Rebase last time stamp
    uint256 public lastRebaseTimestampSec;

    // number of rebase
    uint256 public epoch;

    // rebase on and off status
    bool public rebaseLockStatus;

    // rebase interval time
    uint256 public intervalRebasePeriod;
 
    // Gain Dai pair address 
    IUniswapV2Pair public Gain_Dai;

    // Gain Staking Wallet address
    address public GECOWallet;

    // Gain Stability Wallet address
    address public GSWallet;

    // Gain Liquidity Wallet address
    address public GLWallet;

    // Gain Voucher Wallet address
    address public GVWallet;

    // Gain stability tax fee
    uint256 GsFee;

    // Gain staking tax fee
    uint256 GecoFee;

    // Gain liquidity tax fee
    uint256 GlFee;

    // Tax enable disable status
    bool public sellStatus;

    // liquity staking contract address
    address public LiqStakingContract;

    /** 
    * Contributed by MrKawdy:
    * 
    * Gainv3_5
    *
    * Removed the Stretch from negative rebases to guarantee (unless - a protocol hack or automation failure) that GAIN maintains >=100% backing every day.    
    * Changed the feeCalculation function to use a divisor of 10000 instead of 1000 for the ability to set fees in 0.01% increments. 
    *
    * Gainv3_1
    * 
    * DEXFees: address for DEX Fees that can drastically overcharge GAIN and other Rebase tokens fees when a DEX has activated Uniswap V2 protocol fees.
    * This address is not allowed to transfer GAIN tokens due to the error.
    * @notice - DEX protocols are sent the correct fees on a monthly basis from END's treasury. Fees = total monthly trading volume * protocol fee. 
    *
    * Gainv3
    *
    * Cleaned up rebase calculation to use powers of 10 instead of large numbers and round down total supply for viewing purposes. 
    * Gain_Dai: renamed from Gain_Usd to Gain_Dai for clarification purposes
    * GRMultisig: address for Multisig containing GAIN's reserves including the DAI GAIN LP tokens + DAI Reserves.
    * daiReserves(): function for retrieving the DAI Reserves in the GAIN Reserves Multisig.
    * daiLiquidityReserves(): function for retrieving the DAI Liquidity Reserves paired with GAIN in the DEX liquidity pool.
    * totalReserves(): function for retrieving the sum of DAI Liquidity Reserves + DAI Reserves in the GAIN Reserves Multisig.
    *
    * @notice - The Current Ratio, Target, and Stretch are scaled up by a factor of 1000 for both viewing and calculation purposes.
    * Example - If the Current Ratio is publicly displayed as 2000, Target as 1100, and Stretch as 1000, this means that  
    * Current Ratio = 2.000, Target = 1.100, and Stretch = 1.000. 
    *
    * CurrentRatio(): function for retrieving the Total Reserves:Total Supply ratio. 
    * Target: allows for GAIN to have the rebase target a backing of greater than 100%. This value always has to be >= 1000 in which 1000 = 100% backing.
    * Stretch: allows for softening of each rebase. For example, a stretch of 10000 = total supply +/- 1/10th the amount it would with a stretch = 1000. 
    * DaiAddress: contract address of DAI.
    * RebaseWhitelist/Whitelisted: allows for whitelisting of addresses or contracts to execute the rebase for automation purposes. 
    *
    * @notice - these additions allow GAIN to both transparently and automatically maintain a backing >= 100% as well as optionally soften rebases for stability. 
    * 
    */

    // GAIN Reserves Multisig
    address public GRMultisig;

    // GAIN DAI Reserves 
    function daiReserves() public virtual view returns (uint256) {
    return IERC20Upgradeable(DaiAddress).balanceOf(GRMultisig);
    }

    // GAIN DAI Liquidity Reserves
    function daiLiquidityReserves() public virtual view returns (uint256) {
    uint112 _reserve0;
    uint112 _reserve1;
    uint112 _temp;

    (_reserve0, _reserve1, ) = Gain_Dai
        .getReserves();
    
    // interchange the token reserve according to token position.
    if(Gain_Dai.token1() == address(this)){
        _temp = _reserve0;
        _reserve0 = _reserve1;
        _reserve1 = _temp;
    } 

    return uint256(_reserve1);
    }

    // GAIN Total Reserves 
    function totalReserves () public virtual view returns (uint256) {
        return daiLiquidityReserves().add(daiReserves());
    }   
    
    // GAIN Current Ratio 
    function CurrentRatio () public virtual view returns (uint256) {
        return totalReserves().mul(1000).div(_totalSupply);
    }

    // GAIN Target 
    uint256 public Target;

    // GAIN Stretch 
    uint256 public Stretch;

    // DAI Address  
    address public DaiAddress;

    // DEX Router
    IUniswapV2Router01 public RouterAddress;

    // DEX Converter
    address public DEXFees;

    // Whitelisting For Rebasing Purposes
    bool public enableRebaseWhitelist = true;
    mapping (address => bool) public whitelisted;
    
    // Events
    event Whitelisted(address indexed _address);
    event WhitelistRemoved(address indexed _address);
    event Rebase(uint256 indexed epoch, uint256 totalSupply, int256 supply);

    // Modifiers
    modifier onlyAuthorised() {
        require(msg.sender == LiqStakingContract || msg.sender == owner() , "GainTokenv3_5: not allowed to use this method");
        _;
    }

    modifier onlyWhitelisted {
    require(whitelisted[msg.sender], "Only whitelisted can call this function");
    _;
    }


    // Initialisation part.
    function initialize() public initializer {
        __ERC20_init("Gainv3_5test001","GAINv3_5t1");
        __Ownable_init();

        _mint(msg.sender, 6000000000000000000000);

        GECOWallet = 0xb7E5362E387FC5c9A2CDf4e819b35CFCB27728AE;
        GSWallet = 0x0112649DB507Dd6A33b0e566942eD936A909F46B;
        GLWallet = 0x4DB85C64DBAD3B8Ed350FD592A18eD17690873F7;
        GVWallet = 0xee7a7Ab6d11AeBdcd54B243cE476f1f548e60194;
        GRMultisig = 0x0ec07dB540539145380f660581c1D2a17F5e8467;
        DaiAddress = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;

        RouterAddress = IUniswapV2Router01(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
        
        GsFee = 2;
        GecoFee = 2;
        GlFee = 2;
        sellStatus = true;

        rebaseLockStatus = true;
        intervalRebasePeriod = 1;

        Target = 1000;
        Stretch = 1000;
        

    }

    /**
     * @dev updates rebase details and liquidity staking contract.
     *
     * @param _status rebase enable status
     * @param _period rebase period time
     * @param _gain_dai gain dai pair address
     * @param _liq_staking_address liquidity staking contract address
     * @param _router_address router contract address
     *
     * Requirements:
     * - only owner can update value.
     */

    function updateRebaseDetails(
        bool _status,
        uint256 _period,
        IUniswapV2Pair _gain_dai,
        address _liq_staking_address,
        address _router_address
    ) external onlyOwner {
        rebaseLockStatus = _status;
        intervalRebasePeriod = _period;
        Gain_Dai = _gain_dai;
        LiqStakingContract = _liq_staking_address;
        RouterAddress = IUniswapV2Router01(_router_address);
    }

    /**
     * @dev updates tax details.
     *
     * @param _GsFee gain stability tax fee
     * @param _GecoFee gain staking tax fee
     * @param _GlFee gain liquidity tax fee
     * @param _status tax enable disable status
     *
     * Requirements:
     * - only owner can update value.
     */

    function updateTaxDetails(
        uint256 _GsFee,
        uint256 _GecoFee,
        uint256 _GlFee,
        bool _status
    ) external onlyOwner {
        GsFee = _GsFee;
        GecoFee = _GecoFee;
        GlFee = _GlFee;

        sellStatus = _status;
    }

    /**
     * @dev updates wallets.
     *
     * @param _geco_wallet gain staking wallet address
     * @param _gs_wallet gain stability wallet address
     * @param _gl_wallet gain liquidity wallet address
     * @param _gv_wallet gain voucher wallet address
     *
     * Requirements:
     * - only owner can update value.
     */

    function updateWallets(
        address _geco_wallet,
        address _gs_wallet,
        address _gl_wallet,
        address _gv_wallet     
    ) external onlyOwner {
        GECOWallet = _geco_wallet;
        GSWallet = _gs_wallet;
        GLWallet = _gl_wallet;
        GVWallet = _gv_wallet;
    }

    /**
     * @dev GAIN tokens are rebased w.r.t Dai tokens.
     *
     * Requirements:
     * - only owner can rebase.
     *
     * Emits a {Rebase} event.
     */

    function rebase() external virtual {
    // Check if enableRebaseWhitelist is true
    require(enableRebaseWhitelist, "GainTokenv3_5: Whitelist is not enabled.");
    // Check if msg.sender is the owner or is whitelisted
    require(msg.sender == owner() || whitelisted[msg.sender], "GainTokenv3_5: You are not authorized to execute this function.");
    require(
        rebaseLockStatus &&
            (lastRebaseTimestampSec + intervalRebasePeriod) <=
            block.timestamp,
        "GainTokenv3_5: You can not rebase"
    );
         
        epoch += 1;  // increasing rebase count
        int256 _supplyDelta = 0;
        lastRebaseTimestampSec = block.timestamp;  // last rebase timestamp

        uint112 _reserve0;
        uint112 _reserve1;
        uint112 _temp;

        (_reserve0, _reserve1, ) = Gain_Dai
            .getReserves();
        
        // interchange the token reserve according to token position.
        if(Gain_Dai.token1() == address(this)){
            _temp = _reserve0;
            _reserve0 = _reserve1;
            _reserve1 = _temp;
        }
          
       if (CurrentRatio() > Target) {
            uint256 reservePercentage = uint256((totalReserves() * 10**3) - (_totalSupply * Target));
            uint256 percentage = (reservePercentage * 10**20) /
                uint256(_totalSupply * Target);

            uint256 totalSupply = uint256(
                IERC20Upgradeable(address(this)).totalSupply()
            );
            uint256 _data = percentage * totalSupply;

            _supplyDelta = int256(((_data * 10**3) / Stretch) / 10**20);
            if (_supplyDelta != 0) {
                _totalSupply = _totalSupply.add(uint256(_supplyDelta));
            }
        }
        if (CurrentRatio() < Target) {
            uint256 reservePercentage = uint256((_totalSupply * Target) - (totalReserves() * 10**3));
            uint256 percentage = (reservePercentage * 10**20) / 
                uint256(_totalSupply * Target);

            uint256 totalSupply = uint256(
                IERC20Upgradeable(address(this)).totalSupply()
            );
            uint256 _data = percentage * totalSupply;

            _supplyDelta = -int256(_data  / 10**20);
            if (_supplyDelta != 0) {
                _totalSupply = _totalSupply.sub(uint256(_supplyDelta.abs()));
            }
        }

        // Round down _totalSupply to the nearest readable integer
        _totalSupply = (_totalSupply / 10**18) * 10**18;

        // check if _totalSupply should be less than Max supply
        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
        Gain_Dai.sync(); // syncs the gain tokens in uniswap pair address

        emit Rebase(epoch, _totalSupply, _supplyDelta);
    }
    
    /**
     * @dev get a gain price in Dai.
     *
     */

    function gainPriceInDai()
        external
        virtual
        view
        returns(uint256 Price)
    {   
        uint112 _reserve0;
        uint112 _reserve1;
        uint112 _temp;

        (_reserve0, _reserve1, ) = Gain_Dai
            .getReserves();
        
        // interchange the token reserve according to token position.
        if(Gain_Dai.token1() == address(this)){
            _temp = _reserve0;
            _reserve0 = _reserve1;
            _reserve1 = _temp;
        }
        Price = RouterAddress.getAmountOut(10**18, _reserve0, _reserve1);
    }

    /**
     * @dev withdraw any ERC20 tokens from contract which are already deposited.
     *
     * Requirements:
     * - only owner can call this method.
     *
     */

    function withdrawErc20Token(address _tokenAddress)
        external
        virtual
        onlyOwner
    {
        IERC20Upgradeable(_tokenAddress).transfer(
            owner(),
            IERC20Upgradeable(_tokenAddress).balanceOf(address(this))
        );
    }

    /**
     * @dev withdraw ETH/MATIC tokens from contract which are already deposited.
     *
     * Requirements:
     * - only owner can call this method.
     *
     */

    function withdraw() external virtual onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev Transfer the gain tokens without tax.
     *
     * Requirements:
     * - only owner can call this method.
     *
     */

    function safeTransfer(address from, address to, uint256 amount) external virtual onlyAuthorised {
        require(_allowances[from][to] >= amount, "GainTokenv3_5: transfer amount exceeds allowance");
        require (to != DEXFees, "GainTokenv3_5: DEX has overcharged fees");
        unchecked {
            _approve(from, to, _allowances[from][to] - amount);
        }
        _transfer(from, to, amount);
    }

    /**
     * @dev Overrides the transfer function by applying taxes on it.
     *
     */

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        if (recipient != DEXFees) { 
            if (sellStatus) {
                uint256 GSWalletFees = feeCalculation(GsFee, amount);
                _transfer(msg.sender, GSWallet, GSWalletFees);

                uint256 GECOWalletFees = feeCalculation(GecoFee, amount);
                _transfer(msg.sender, GECOWallet, GECOWalletFees);

                uint256 GLWalletFees = feeCalculation(GlFee, amount);
                _transfer(msg.sender, GLWallet, GLWalletFees);

                uint256 _recipient_amt = amount -
                    (GECOWalletFees + GSWalletFees + GLWalletFees);
                _transfer(msg.sender, recipient, _recipient_amt);

            } else {
                _transfer(msg.sender, recipient, amount);
            }
            return true;
        } else { 
            return false;
        }
    }

    /**
     * @dev Overrides the transferFrom function by applying taxes on it.
     *
     */

     function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        require (recipient != DEXFees, "GainTokenv3_5: DEX has overcharged fees"); 
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, recipient, currentAllowance - amount);
        }
        if (sellStatus) {
            uint256 GSWalletFees = feeCalculation(GsFee, amount);
            _transfer(sender, GSWallet, GSWalletFees);

            uint256 GECOWalletFees = feeCalculation(GecoFee, amount);
            _transfer(sender, GECOWallet, GECOWalletFees);

            uint256 GLWalletFees = feeCalculation(GlFee, amount);
            _transfer(sender, GLWallet, GLWalletFees);

            uint256 _recipient_amt = amount -
                (GECOWalletFees + GSWalletFees + GLWalletFees);
            _transfer(sender, recipient, _recipient_amt);

        } else {
            _transfer(sender, recipient, amount);
        }
        return true;
    }

    /**
     * @dev Calculates tax fee with total amount.
     *
     */

    function feeCalculation(uint256 _feeMargin, uint256 _totalPrice)
        internal
        pure
        returns (uint256)
    {
        uint256 fee = _feeMargin * _totalPrice;
        uint256 fees = fee / 10000;
        return fees;
    }

    // @dev sets the Dai Address
    function setDaiAddress(address _DaiAddress) external onlyOwner {
        DaiAddress = _DaiAddress;
    }

    // @dev sets the GAIN Reserves Multisig
    function setGRMultisig(address _GRMultisig) external onlyOwner {
        GRMultisig = _GRMultisig;
    }

    // @dev sets the DEX Fees Address
     function setDEXFees(address _DEXFees) external onlyOwner {
        DEXFees = _DEXFees;
    }

    // @dev sets the Target
    function setTarget(uint256 _Target) external onlyOwner {
        require(_Target >= 1000);
        Target = _Target;
    }

    // @dev sets the Stretch
    function setStretch(uint256 _stretch) external onlyOwner {
        require(_stretch >= 1000);
        Stretch = _stretch;
    }
    
    // @dev enables/disables the rebase whitelist
    function setEnableRebaseWhitelist(bool _enableRebaseWhitelist) external onlyOwner {
        enableRebaseWhitelist = _enableRebaseWhitelist;
    }

    // @dev adds address/contract to rebase whitelist
    function RebaseWhitelist(address _address) external onlyOwner {
        require(_address != address(0), "Address cannot be 0x0");
        whitelisted[_address] = true;
        emit Whitelisted(_address);
    }

    // @dev removes address/contract from rebase whitelist
    function removeFromRebaseWhitelist(address _address) external onlyOwner {
        require(_address != address(0), "Address cannot be 0x0");
        require(whitelisted[_address] == true, "Address is not whitelisted");
        whitelisted[_address] = false;
        emit WhitelistRemoved(_address);
    }
}