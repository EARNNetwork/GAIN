// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./lib/InterFaces.sol";

contract LiquidityAndStakingV1 is OwnableUpgradeable {
    // uniswapRouter address
    address public uniswapRouterAddress;

    // gain token address
    address public GainTokenAddress;

    // gain amount to be swapped and added to liquidity
    uint256 public GainAmount;

    // reward rate for staking
    uint256 public rewardRate;

    // time interval for reward
    uint256 public timePeriod;

    // temporary values
    uint256 public amountA;
    uint256 public amountB;
    uint256 public liquidityAB;

    // temporary array of address
    address[] public PAIR1_GAIN;
    address[] public PAIR2_GAIN;

    // stake structure
    struct StakeInfo {
        uint256 stakeId;
        address User;
        address LPAddress;
        uint256 LPTokens;
        uint256 ClaimedReward;
        uint256 LastClaimedTimestamp;
    }

    // mapping stake id with its stake information
    mapping(uint256 => StakeInfo) public StakeInformation;

    // mapping of address w.r.t their owned take ids
    mapping(address => uint256[]) public stakeOwner;

    // stake counter
    uint256 public stakeCounter;

    struct History {
        uint256 stakeId;
        uint256 createdAt;
    }
    mapping(address => History[]) private StakeHistory;

    struct UserHistory {
        uint256 stakeId;
        uint256 amount;
        uint256 createdAt;
    }
    mapping(address => UserHistory[]) private UserStakeHistory;
    /**
     * @dev Emitted when gain amount is swapped and added into liquidity
     */

    event TokenDetails(
        uint256 GainAmount,
        uint256 Pair1Amount,
        uint256 Pair2Amount
    );

    mapping(address => bool) public allowedLpAddress;

    /**
     * @dev Emitted when user stakes amount of LP tokens.
     */
    event Stake(
        uint256 stakeId,
        address User,
        address LPAddress,
        uint256 Amount
    );

    /**
     * @dev Emitted when user unstakes LP tokens.
     */
    event Unstake(
        uint256 stakeId,
        address User,
        address LPAddress,
        uint256 Amount
    );

    /**
     * @dev Emitted when user claims the reward for lp tokens.
     */
    event Claimed(address User, address[] LPAddress, uint256 Amount);

    // initilization part
    function initialize() public initializer {
        __Ownable_init();
        uniswapRouterAddress = 0x8954AfA98594b838bda56FE4C12a09D7739D179b;
        GainTokenAddress = 0xAeE80423b73188745462282E2fCFd915b9B2585C;
        GainAmount = 10 * (10**18);

        rewardRate = 100000000000000000;
        timePeriod = 300;
    }

     /**
     * @dev updates the allowed lp address for staking.
     *
     * @param _addresses array of lp addresses
     * @param _status status for allowed address
     *
     * Requirements:
     * - only owner can update value.
     */

    function updateAllowedLpAddresses(address[] calldata _addresses, bool _status)
        external
        onlyOwner
    {
        for(uint256 i = 0; i < _addresses.length; i++){
            allowedLpAddress[_addresses[i]] = _status;
        }
    }

    /**
     * @dev updates gain token address.
     *
     * @param _gain_token_address gain token address
     *
     * Requirements:
     * - only owner can update value.
     */

    function updateGainTokenAddress(address _gain_token_address)
        external
        onlyOwner
    {
        GainTokenAddress = _gain_token_address;
    }

    /**
     * @dev withdraw any ERC20 tokens from contract.
     *
     * Requirements:
     * - only owner can update value.
     */

    function withdrawErc20Token(address _tokenAddress)
        external
        virtual
        onlyOwner
    {
        IGain(_tokenAddress).transfer(
            owner(),
            IGain(_tokenAddress).balanceOf(address(this))
        );
    }

    /**
     * @dev withdraw ETH/MATIC tokens from contract.
     *
     * Requirements:
     * - only owner can update value.
     */

    function withdraw() external virtual onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev updates gain total amount to be swapped and add to liquidity,
     * reward rate and time intervals.
     *
     * @param _amount amount of tokens.
     * @param _rewardRate reward rate.
     * @param _timeInterval time interval for rewards.
     *
     * Requirements:
     * - only owner can update value.
     */

    function changeTotalGainAmount(
        uint256 _amount,
        uint256 _rewardRate,
        uint256 _timeInterval
    ) external onlyOwner {
        GainAmount = _amount;
        rewardRate = _rewardRate;
        timePeriod = _timeInterval;
    }

    /**
     * @dev this method swaps the 25%-25% with two pair addresses
     * and 25%-25% add into liquidity with two pair address.
     *
     * @param pair1 first pair token address.
     * @param pair2 second pair token address.
     *
     * Requirements:
     * - msg.sender must be owner of contract.
     *
     * Returns
     * - boolean.
     *
     * Emits a {TokenDetails} event.
     */

    function tokenSwap(address pair1, address pair2)
        external
        onlyOwner
        returns (bool)
    {
        uint256 deadline = block.timestamp + 30000 days;

        IGain tokenAddress = IGain(GainTokenAddress);
        uint256 balance = tokenAddress.balanceOf(
            IGain(GainTokenAddress).GLWallet()
        );

        require(balance >= GainAmount, "$LIQ&STAK: GL-wallet has less balance");

        tokenAddress.safeTransfer(
            IGain(GainTokenAddress).GLWallet(),
            address(this),
            GainAmount
        );
        uint256 amount = GainAmount / 4;

        PAIR1_GAIN = [GainTokenAddress, pair1];
        PAIR2_GAIN = [GainTokenAddress, pair2];

        tokenAddress.approve(
            uniswapRouterAddress,
            IGain(tokenAddress).balanceOf(address(this))
        );

        swapFromContract(pair1, amount, PAIR1_GAIN, address(this), deadline);
        uint256 pair1Amt = IGain(pair1).balanceOf(address(this));

        addLiquidityFromContract(
            pair1,
            amount,
            pair1Amt,
            1,
            1,
            IGain(GainTokenAddress).GLWallet(),
            deadline
        );

        swapFromContract(pair2, amount, PAIR2_GAIN, address(this), deadline);
        uint256 pair2Amt = IGain(pair2).balanceOf(address(this));

        addLiquidityFromContract(
            pair2,
            amount,
            pair2Amt,
            1,
            1,
            IGain(GainTokenAddress).GLWallet(),
            deadline
        );

        emit TokenDetails(amount, pair1Amt, pair2Amt);
        return true;
    }

    /**
     * @dev user stakes LP tokens and gain rewards on it.
     *
     * @param _amount amount of LP tokens.
     * @param _lp_address second pair token address.
     *
     * Requirements:
     * - msg.sender must be have LP tokens of GAIN token address(ex. DAI/GAIN, USDC/GAIN, etc)
     *
     * Returns
     * - boolean.
     *
     * Emits a {Stake} event.
     */

    function stake(uint256 _amount, address _lp_address) external virtual {
        require(
            isLpTokenValid(_lp_address) && allowedLpAddress[_lp_address],
            "$LIQ&STAK: Invalid LP tokens"
        );
        require(
            IUniswapV2Pair(_lp_address).allowance(msg.sender, address(this)) >=
                _amount,
            "$LIQ&STAK: Not enough allowance"
        );
        stakeCounter += 1;

        IUniswapV2Pair(_lp_address).transferFrom(
            msg.sender,
            address(this),
            _amount
        );

        StakeInfo memory _data = StakeInfo(
            stakeCounter,
            msg.sender,
            _lp_address,
            _amount,
            0,
            block.timestamp
        );
        StakeInformation[stakeCounter] = _data;
        stakeOwner[msg.sender].push(stakeCounter);

        UserHistory memory _hist_data = UserHistory(
            stakeCounter,
            _amount,
            block.timestamp
        );
        UserStakeHistory[msg.sender].push(_hist_data);

        emit Stake(stakeCounter, msg.sender, _lp_address, _amount);
    }

    /**
     * @dev user can unstake the LP tokens w.r.t to their stake Id.
     * User stops getting reward and LP tokens ar return to the user.
     *
     * @param stakeId stake Id to be unstaked.
     *
     * Requirements:
     * - msg.sender must be owner of stake Id.
     *
     * Emits a {Unstake} event.
     */

    function unstake(uint256 stakeId) external virtual {
        require(
            (StakeInformation[stakeId]).LPTokens > 0 && (StakeInformation[stakeId]).User == msg.sender,
            "$LIQ&STAK: Invalid stake Id or owner"
        );

        IUniswapV2Pair(StakeInformation[stakeId].LPAddress).transfer(
            msg.sender,
            StakeInformation[stakeId].LPTokens
        );
        (StakeInformation[stakeId]).LPTokens = 0;

        emit Unstake(
            stakeId,
            msg.sender,
            StakeInformation[stakeId].LPAddress,
            StakeInformation[stakeId].LPTokens
        );
    }

    /**
     * @dev user can view his/her stake details.
     *
     * @param _user user wallet address.
     *
     * Returns
     *  - TotalIds,
     *  - StakedTokens,
     *  - LpAddresses,
     *  - TotalRewards,
     *  - ClaimedRewards,
     *  - RemainingRewards
     *
     */

    function viewRewards(address _user)
        public
        view
        returns (
            uint256[] memory TotalIds,
            uint256[] memory StakedTokens,
            address[] memory LpAddresses,
            uint256[] memory TotalRewards,
            uint256[] memory ClaimedRewards,
            uint256[] memory RemainingRewards
        )
    {
        uint256 number = stakeOwner[_user].length;
        TotalIds = new uint256[](number);
        LpAddresses = new address[](number);
        ClaimedRewards = new uint256[](number);
        RemainingRewards = new uint256[](number);
        TotalRewards = new uint256[](number);
        StakedTokens = new uint256[](number);

        for (uint256 i = 0; i < stakeOwner[_user].length; i++) {
            TotalIds[i] = stakeOwner[_user][i];
            LpAddresses[i] = StakeInformation[stakeOwner[_user][i]].LPAddress;
            ClaimedRewards[i] = StakeInformation[stakeOwner[_user][i]]
                .ClaimedReward;
            StakedTokens[i] = StakeInformation[stakeOwner[_user][i]].LPTokens;

            if (StakeInformation[stakeOwner[_user][i]].LPTokens > 0) {
                uint256 rate = (StakeInformation[stakeOwner[_user][i]]
                    .LPTokens * rewardRate) / (10**18);

                uint256 num = (block.timestamp -
                    StakeInformation[stakeOwner[_user][i]]
                        .LastClaimedTimestamp) / timePeriod;

                RemainingRewards[i] = num * rate;
            }
            TotalRewards[i] = RemainingRewards[i] + ClaimedRewards[i];
        }
    }

    /**
     * @dev user can claim total rewards.
     *
     * Requirements:
     * - msg.sender must be owner of stake Id.
     *
     * Returns
     * - boolean.
     *
     * Emits a {Claimed} event.
     */

    function Claim() external virtual {
        (
            uint256[] memory TotalIds,
            ,
            address[] memory LpAddresses,
            ,
            ,
            uint256[] memory RemainingRewards
        ) = viewRewards(msg.sender);
        uint256 _amount;
        address[] memory LpAddress = new address[](TotalIds.length);
        uint256 j = 0;

        for (uint256 i = 0; i < TotalIds.length; i++) {
            if (RemainingRewards[i] > 0) {
                _amount += RemainingRewards[i];
                LpAddress[j] = LpAddresses[i];
                j++;

                StakeInformation[TotalIds[i]].ClaimedReward += RemainingRewards[
                    i
                ];
                StakeInformation[TotalIds[i]].LastClaimedTimestamp = block
                    .timestamp;
            }
        }
        require(_amount > 0, "$LIQ&STAK: No rewards generated for user");
        IGain(GainTokenAddress).transfer(msg.sender, _amount);

        emit Claimed(msg.sender, LpAddresses, _amount);
    }

    /**
     * @dev user can view LP tokens are valid or not.
     *
     * @param _lp_address Lp token address.
     *
     * Returns
     *  - boolean
     *
     */

    function isLpTokenValid(address _lp_address) public view returns (bool) {
        return (IUniswapV2Pair(_lp_address).token0() == GainTokenAddress ||
            IUniswapV2Pair(_lp_address).token1() == GainTokenAddress);
    }

    /**
     * @dev adds the liquidity from the contract and transfers the LP tokens to the GL wallet.
     */

    function addLiquidityFromContract(
        address tokenAddress,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) internal returns (bool) {
        IGain tokenAddressB = IGain(tokenAddress);

        tokenAddressB.approve(
            uniswapRouterAddress,
            IGain(tokenAddress).balanceOf(address(this))
        );

        IUniswapV2Router01 addLiq = IUniswapV2Router01(uniswapRouterAddress);
        (amountA, amountB, liquidityAB) = addLiq.addLiquidity(
            GainTokenAddress,
            tokenAddress,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            to,
            deadline
        );

        return true;
    }

    /**
     * @dev swaps gain token with pair address and
     * returns the pair tokens into this contract for adding liquidity.
     */

    function swapFromContract(
        address tokenAddress,
        uint256 amountIn,
        address[] memory path,
        address to,
        uint256 deadline
    ) internal {
        IGain tokenAddress_ = IGain(tokenAddress);

        tokenAddress_.approve(
            uniswapRouterAddress,
            IGain(tokenAddress).balanceOf(address(this))
        );

        IUniswapV2Router01 swapLiq = IUniswapV2Router01(uniswapRouterAddress);

        swapLiq.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            1,
            path,
            to,
            deadline
        );
    }

    /**
     * @dev shows the history of user staking
     *
     * @param _user user address.
     */

    function showHistory(address _user)
        external
        view
        returns (address User, UserHistory[] memory StakeUserHistory)
    {
        User = _user;
        uint256 number = UserStakeHistory[_user].length;
        StakeUserHistory = new UserHistory[](number);
        for (uint256 i = 0; i < UserStakeHistory[_user].length; i++) {
            StakeUserHistory[i] = UserStakeHistory[_user][i];
        }
    }
}
