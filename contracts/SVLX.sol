// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.7.0;

import "./libs/Initializable.sol";
import "./libs/SafeERC20.sol";
import "./libs/Math.sol";
import "./libs/ReentrancyGuard.sol";
import "./libs/EnumerableSet.sol";

import "./interfaces/IStakingAuRa.sol";

contract SVLX is Initializable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    using Math for uint256;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string public name;
    string public symbol;
    uint8 public decimals;

    /// @notice VELAS staking contract
    IStakingAuRa public stakingAuRa;

    /// @notice contract admin address
    address public admin;

    /// @notice Proposed new admin address
    address public proposedAdmin;

    /// @dev Staking pool addresses
    EnumerableSet.AddressSet private stakingPools;

    /// @notice Next pool index
    uint256 public poolIndex;

    /// @dev SVLX token total supply
    uint256 private _totalSupply;

    uint256 public rewardIndex = 0;
    uint256 public rewardDebt = 0;
    mapping(address => uint256) public userRewardClaimable;
    mapping(address => uint256) public userRewardIndex;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad, uint256 old);
    event Withdrawal(address indexed src, uint256 wad);

    /// @notice Event: claim previously ordered tokens
    /// @param poolAddress pool address
    /// @param amount ordered amount
    event ClaimOrderedWithdraw(address indexed poolAddress, uint256 amount);

    /// @notice Event: withdraw from the pool
    /// @param poolAddress pool address
    /// @param amount amount withdrew
    event PoolWithdraw(address indexed poolAddress, uint256 amount);

    /// @notice Event: withdraw from the ordered tokens
    /// @param poolAddress pool address
    /// @param amount amount withdrew
    event OrderWithdraw(address indexed poolAddress, int256 amount);

    /// @notice Event: Set the staking contract address
    /// @param oldStakingAuRa old address
    /// @param newStakingAuRa new address
    event SetStakingAuRa(address oldStakingAuRa, address newStakingAuRa);

    /// @notice Event: Set proposed admin
    /// @param proposedAdmin proposed admin address
    event SetProposedAdmin(address proposedAdmin);

    /// @notice Event: Claim admin
    /// @param oldAdmin old address
    /// @param newAdmin new address
    event ClaimAdmin(address oldAdmin, address newAdmin);

    /// @notice Event: Add a new staking pool
    /// @param newPool new pool address
    event AddPool(address newPool);

    /// @notice Event: Remove a existing staking pool
    /// @param pool pool address
    event RemovePool(address pool);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    modifier onlyAdmin {
        require(msg.sender == admin, "Admin required");
        _;
    }

    function initialize() public initializer {
        admin = msg.sender;
        name = "Staking Velas";
        symbol = "SVLX";
        decimals = 18;
        poolIndex = 0;
        stakingAuRa = IStakingAuRa(0x1100000000000000000000000000000000000001);
    }

    /// @notice Deposit VLX into VELAS pools and mint SVLX tokens
    function deposit() external payable nonReentrant {
        require(msg.value > 0, "Amount cannot be zero");

        address currentPool = stakingPools.at(poolIndex);
        require(currentPool != address(0), "Pool is zero address");

        // NOTE: Need to mint the SVLX tokens here first to get the correct balance and reward amount
        _mint(msg.sender, msg.value);

        // update the reward
        uint256 reward = getTotalRewards();
        uint256 redeemable = address(this).balance.sub(reward);

        // Rotating the staking pool for the next action
        poolIndex = (poolIndex + 1) % stakingPools.length();

        // Stake to the pool when we already staking in the pool (stake amount in the pool is greater than zero),
        // Or our current balance is more than minStake.
        if (
            stakingAuRa.areStakeAndWithdrawAllowed() &&
            (stakingAuRa.stakeAmount(currentPool, address(this)) > 0 ||
                redeemable >= stakingAuRa.delegatorMinStake())
        ) {
            stakingAuRa.stake{ value: redeemable }(currentPool, redeemable);
        }
        // else we just leave the deposited tokens in the contract

        emit Deposit(msg.sender, msg.value, redeemable);
    }

    /// @notice Redeem VLX from the stake pools
    function withdraw(uint256 wad) external nonReentrant returns (uint256) {
        require(balanceOf[msg.sender] >= wad, "Insufficient balance");
        bool hasAction;
        uint256 reward = getTotalRewards();
        uint256 redeemable = address(this).balance.sub(reward);

        if (redeemable < wad && stakingAuRa.areStakeAndWithdrawAllowed()) {
            // Redeemable balance is not enought and the staking service is working
            IStakingAuRa auRa = stakingAuRa;
            address currPool;
            // claim previously ordered VLX from the pool
            for (uint256 i = 0; i < stakingPools.length(); ++i) {
                currPool = stakingPools.at(i);
                uint256 claimAmount = _getClaimableOrderedAmount(currPool);
                if (claimAmount > 0) {
                    auRa.claimOrderedWithdraw(currPool);
                    hasAction = true;
                    emit ClaimOrderedWithdraw(currPool, claimAmount);
                }
            }

            // Get the latest redeemable amount
            redeemable = address(this).balance.sub(reward);
            uint256 needToWithdraw = 0;
            if (redeemable < wad) {
                uint256 minStake = auRa.delegatorMinStake();
                uint256 canWithdraw = 0;
                uint256 maxAllowed = 0;
                for (uint256 i = 0; i < stakingPools.length(); ++i) {
                    needToWithdraw = wad > redeemable ? wad.sub(redeemable) : 0;
                    if (needToWithdraw == 0) {
                        // Stop the loop if it's enough for user to withdraw
                        break;
                    }
                    currPool = stakingPools.at(i);
                    maxAllowed = auRa.maxWithdrawAllowed(currPool, address(this));
                    if (maxAllowed > 0) {
                        if (
                            maxAllowed >= needToWithdraw &&
                            maxAllowed.sub(needToWithdraw) >= minStake
                        ) {
                            canWithdraw = needToWithdraw;
                        } else {
                            canWithdraw = maxAllowed;
                        }
                        auRa.withdraw(currPool, canWithdraw);
                        hasAction = true;
                        emit PoolWithdraw(currPool, canWithdraw);

                        // Update the redeemable amount all the time
                        redeemable = address(this).balance.sub(reward);
                    }
                }
            }

            // Update the redeemable amount all the time
            redeemable = address(this).balance.sub(reward);

            if (redeemable < wad) {
                uint256 length = stakingPools.length();
                uint256 totalOrderedAmount;
                for (uint256 i = 0; i < length; ++i) {
                    uint256 claimAmount =
                        auRa.orderedWithdrawAmount(stakingPools.at(i), address(this));
                    totalOrderedAmount = totalOrderedAmount.add(claimAmount);
                }
                if (totalOrderedAmount < wad) {
                    uint256 minStake = auRa.delegatorMinStake();
                    uint256 canOrderWithdraw = 0;
                    uint256 maxOrderWithdrawal = 0;
                    for (uint256 i = 0; i < stakingPools.length(); ++i) {
                        needToWithdraw = wad > redeemable ? wad.sub(redeemable) : 0;
                        if (needToWithdraw == 0) {
                            // Stop the loop if it's enough for user to withdraw
                            break;
                        }
                        currPool = stakingPools.at(i);
                        // uint256 remainingWad = wad.sub(redeemable);
                        maxOrderWithdrawal = auRa.maxWithdrawOrderAllowed(currPool, address(this));
                        if (maxOrderWithdrawal > 0) {
                            if (
                                maxOrderWithdrawal >= needToWithdraw &&
                                maxOrderWithdrawal.sub(needToWithdraw) >= minStake
                            ) {
                                canOrderWithdraw = needToWithdraw;
                            } else {
                                canOrderWithdraw = maxOrderWithdrawal;
                            }

                            auRa.orderWithdraw(currPool, int256(canOrderWithdraw));
                            hasAction = true;
                            emit OrderWithdraw(currPool, int256(canOrderWithdraw));

                            // Update the redeemable amount all the time
                            redeemable = address(this).balance.sub(reward);
                        }
                    }
                }
            }
        }

        // Update the redeemable amount all the time
        redeemable = address(this).balance.sub(reward);

        uint256 withdrawAmount = wad.min(redeemable);

        if (withdrawAmount > 0) {
            _burn(msg.sender, withdrawAmount);
            hasAction = true;
            _sendWithdrawnStakeAmount(msg.sender, withdrawAmount);
        }

        require(hasAction, "no action executed");

        emit Withdrawal(msg.sender, withdrawAmount);

        return withdrawAmount;
    }

    /// @notice Get the total amount of VLX in the staking pools,
    /// including the staked and ordered amount
    function getPoolTotalBalance() public view returns (uint256 res) {
        IStakingAuRa auRa = stakingAuRa;
        for (uint256 i = 0; i < stakingPools.length(); ++i) {
            //number of order
            res = res.add(auRa.orderedWithdrawAmount(stakingPools.at(i), address(this)));
            //The amount of all stakes, including locked and unlocked amounts
            res = res.add(auRa.stakeAmount(stakingPools.at(i), address(this)));
        }
    }

    /// @notice Get the amount of total staked VLX
    function getTotalStaked() external view returns (uint256 res) {
        for (uint256 i = 0; i < stakingPools.length(); ++i) {
            res = res.add(stakingAuRa.stakeAmount(stakingPools.at(i), address(this)));
        }
    }

    function orderedAmount()
        external
        view
        returns (
            address[] memory _pools,
            uint256[] memory _amount,
            uint256[] memory _claimableBlock
        )
    {
        IStakingAuRa auRa = stakingAuRa;
        uint256 stakingEpoch = auRa.stakingEpoch();

        uint256 length = stakingPools.length();

        _pools = new address[](length);
        _amount = new uint256[](length);
        _claimableBlock = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            uint256 claimAmount = auRa.orderedWithdrawAmount(stakingPools.at(i), address(this));
            _pools[i] = stakingPools.at(i);
            _amount[i] = claimAmount;

            if (
                stakingEpoch == auRa.orderWithdrawEpoch(stakingPools.at(i), address(this)) &&
                claimAmount > 0
            ) {
                _claimableBlock[i] = auRa.stakingEpochEndBlock() + 1;
            }
        }
    }

    /// @notice Get all the staking pools
    function getPoolsStaked()
        external
        view
        returns (address[] memory pool, uint256[] memory stake)
    {
        IStakingAuRa auRa = stakingAuRa;
        uint256 length = stakingPools.length();
        pool = new address[](length);
        stake = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            pool[i] = stakingPools.at(i);
            stake[i] = auRa.stakeAmount(stakingPools.at(i), address(this));
        }
    }

    /// @notice Get the pools where the stake amount is greater than 0
    function getStakedPools() external view returns (address[] memory pool) {
        uint256 stakePoolsCount = 0;
        IStakingAuRa auRa = stakingAuRa;
        for (uint256 i = 0; i < stakingPools.length(); ++i) {
            if (auRa.stakeAmount(stakingPools.at(i), address(this)) > 0) {
                stakePoolsCount++;
            }
        }

        pool = new address[](stakePoolsCount);
        uint256 j = 0;
        for (uint256 i = 0; i < stakingPools.length(); ++i) {
            if (auRa.stakeAmount(stakingPools.at(i), address(this)) > 0) {
                pool[j] = stakingPools.at(i);
            }
        }
    }

    /// @notice Set the staking contract address
    /// @param _stakingAuRa staking contract address
    function setStakingAuRa(address _stakingAuRa) external onlyAdmin {
        address oldStaking = address(stakingAuRa);
        stakingAuRa = IStakingAuRa(_stakingAuRa);

        emit SetStakingAuRa(oldStaking, _stakingAuRa);
    }

    function setProposedAdmin(address _proposedAdmin) external onlyAdmin {
        proposedAdmin = _proposedAdmin;

        emit SetProposedAdmin(proposedAdmin);
    }

    /// @notice Add a new staking pool
    /// @param _pool pool address
    function addPool(address _pool) external onlyAdmin {
        address newPool = address(0);
        address[] memory _pools = stakingAuRa.getPools();
        for (uint256 i = 0; i < _pools.length; ++i) {
            if (_pools[i] == _pool) {
                newPool = _pools[i];
                break;
            }
        }
        require(newPool != address(0), "Invalid new pool");
        stakingPools.add(newPool);
        emit AddPool(newPool);
    }

    /// @notice Remove a staking pool
    /// @param _pool pool address
    function remove(address _pool) external onlyAdmin {
        stakingPools.remove(_pool);
        emit RemovePool(_pool);
    }

    /// @notice Claim the admin
    function claimAdmin() external {
        require(msg.sender == proposedAdmin, "ProposedAdmin required");
        address oldAdmin = admin;
        admin = proposedAdmin;
        proposedAdmin = address(0);

        emit ClaimAdmin(oldAdmin, admin);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function approve(address guy, uint256 wad) external returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) external returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(
        address src,
        address dst,
        uint256 wad
    ) public returns (bool) {
        require(balanceOf[src] >= wad);
        updateFor(src);
        updateFor(dst);

        if (src != msg.sender && allowance[src][msg.sender] != uint256(-1)) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }

    function getUserRewards(address account) external returns (uint256) {
        updateFor(account);
        return userRewardClaimable[account];
    }

    /// @notice Return the total staking rewards collected
    function getTotalRewards() public view returns (uint256) {
        uint256 currentBalance = address(this).balance;
        uint256 poolBalance = getPoolTotalBalance();
        if (poolBalance.add(currentBalance) <= _totalSupply) {
            return 0;
        } else {
            return poolBalance.add(currentBalance).sub(_totalSupply);
        }
    }

    /// @notice Returnt the total amount that can be redeemed by the SVLX holders
    function getLocalRedeemable() public view returns (uint256) {
        uint256 currentBalance = address(this).balance;
        uint256 reward = getTotalRewards();
        if (currentBalance > reward) {
            return currentBalance.sub(reward);
        } else {
            return 0;
        }
    }

    /// @notice Get the total withdrawable amount, including the redeemable balance of the contract,
    /// and ordered and unlocked amount in the staking pools.
    function getTotalWithdrawable() external view returns (uint256 res) {
        res = getLocalRedeemable();
        uint256 claimableAmount = 0;
        address currPool;
        for (uint256 i = 0; i < stakingPools.length(); ++i) {
            currPool = stakingPools.at(i);
            res = res.add(stakingAuRa.maxWithdrawAllowed(currPool, address(this)));
            claimableAmount = _getClaimableOrderedAmount(currPool);
            if (claimableAmount > 0) res = res.add(claimableAmount);
        }
    }

    function claimRewards() external returns (uint256) {
        updateFor(msg.sender);
        _sendWithdrawnStakeAmount(msg.sender, userRewardClaimable[msg.sender]);
        userRewardClaimable[msg.sender] = 0;
        rewardDebt = getTotalRewards();
    }

    function updateFor(address recipient) public {
        _update();
        uint256 _supplied = balanceOf[recipient];
        if (_supplied > 0) {
            uint256 _supplyIndex = userRewardIndex[recipient];
            userRewardIndex[recipient] = rewardIndex;
            uint256 _delta = rewardIndex.sub(_supplyIndex, "rewardIndex delta");
            if (_delta > 0) {
                uint256 _share = _supplied.mul(_delta).div(1e18);
                userRewardClaimable[recipient] = userRewardClaimable[recipient].add(_share);
            }
        } else {
            userRewardIndex[recipient] = rewardIndex;
        }
    }

    function update() external {
        _update();
    }

    function _update() internal {
        if (_totalSupply > 0) {
            uint256 _bal = getTotalRewards();
            if (_bal > rewardDebt) {
                uint256 _diff = _bal.sub(rewardDebt, "rewardDebt _diff");
                if (_diff > 0) {
                    uint256 _ratio = _diff.mul(1e18).div(_totalSupply);
                    if (_ratio > 0) {
                        rewardIndex = rewardIndex.add(_ratio);
                        rewardDebt = _bal;
                    }
                }
            }
        }
    }

    function _mint(address dst, uint256 amount) internal {
        // mint the amount
        _totalSupply = _totalSupply.add(amount);
        // transfer the amount to the recipient
        balanceOf[dst] = balanceOf[dst].add(amount);
        updateFor(dst);
        emit Transfer(address(0), dst, amount);
    }

    function _burn(address dst, uint256 amount) internal {
        updateFor(dst);
        // mint the amount
        _totalSupply = _totalSupply.sub(amount);
        // transfer the amount to the recipient
        balanceOf[dst] = balanceOf[dst].sub(amount);
        emit Transfer(dst, address(0), amount);
    }

    /// @notice Return the current claimable amount from orderedWithdraw in previous epochs
    function _getClaimableOrderedAmount(address poolAddress) internal view returns (uint256) {
        IStakingAuRa auRa = stakingAuRa;
        uint256 currEpoch = auRa.stakingEpoch();
        if (currEpoch > auRa.orderWithdrawEpoch(poolAddress, address(this)))
            return auRa.orderedWithdrawAmount(poolAddress, address(this));
        return 0;
    }

    /// @dev Sends coins from this contract to the specified address.
    /// @param _to The target address to send amount to.
    /// @param _amount The amount to send.
    function _sendWithdrawnStakeAmount(address payable _to, uint256 _amount) internal {
        if (!_to.send(_amount)) {
            // We use the `Sacrifice` trick to be sure the coins can be 100% sent to the receiver.
            // Otherwise, if the receiver is a contract which has a revert in its fallback function,
            // the sending will fail.
            (new Sacrifice){ value: _amount }(_to);
        }
    }

    function airdrop() external payable {}

    fallback() external payable {}

    receive() external payable {}

    function getStakingPool(uint256 index) external view returns (address) {
        return stakingPools.at(index);
    }
}

contract Sacrifice {
    constructor(address payable _recipient) public payable {
        selfdestruct(_recipient);
    }
}
