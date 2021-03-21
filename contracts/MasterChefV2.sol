// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./BlzdToken.sol";

// MasterChef is the master of BLZD. He can make BLZD and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once BLZD is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of BLZDs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accBLZDPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accBLZDPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. BLZD to distribute per block.
        uint256 lastRewardBlock;  // Last block number that BLZD distribution occurs.
        uint256 accBlzdPerShare;   // Accumulated BLZD per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The BLZD TOKEN!
    BlzdToken public blzd;
    // Dev address.
    address public devaddr;
    // BLZD tokens created per block.
    uint256 public blzdPerBlock;
    // Bonus muliplier for early BLZD makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddBb = 0x4b3aF8f787efa5B5B319bDC244da8368E2d3D454;
    address public feeAddSt = 0x27D6cd0640C8fEE5eAa781604fb259dD430ADe00;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when BLZD mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddressBb(address indexed user, address indexed newAddress);
    event SetFeeAddressSt(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 blzdPerBlock);

    constructor(
        BlzdToken _blzd,
        address _devaddr,
        uint256 _blzdPerBlock,
        uint256 _startBlock
    ) public {
        blzd = _blzd;
        devaddr = _devaddr;
        blzdPerBlock = _blzdPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    modifier poolExists(uint256 pid) {
        require(pid < poolInfo.length, "pool inexistent");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= 400, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accBlzdPerShare : 0,
        depositFeeBP : _depositFeeBP
        }));
    }

    // Update the given pool's BLZD allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner poolExists(_pid) {
        require(_depositFeeBP <= 400, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending BLZDs on frontend.
    function pendingBlzd(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBlzdPerShare = pool.accBlzdPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 blzdReward = multiplier.mul(blzdPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accBlzdPerShare = accBlzdPerShare.add(blzdReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accBlzdPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 blzdReward = multiplier.mul(blzdPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        blzd.mint(devaddr, blzdReward.mul(888).div(10000));
        blzd.mint(address(this), blzdReward);
        pool.accBlzdPerShare = pool.accBlzdPerShare.add(blzdReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for BLZD allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant  poolExists(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accBlzdPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeBlzdTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                uint256 depositeFeeHalf = depositFee.div(2);
                pool.lpToken.safeTransfer(feeAddBb, depositeFeeHalf);
                pool.lpToken.safeTransfer(feeAddSt, depositeFeeHalf);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accBlzdPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant poolExists(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accBlzdPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeBlzdTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBlzdPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant poolExists(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe BLZD transfer function, just in case if rounding error causes pool to not have enough BLZDs.
    function safeBlzdTransfer(address _to, uint256 _amount) internal {
        uint256 blzdBal = blzd.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > blzdBal) {
            transferSuccess = blzd.transfer(_to, blzdBal);
        } else {
            transferSuccess = blzd.transfer(_to, _amount);
        }
        require(transferSuccess, "safeBlzdTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    function setFeeAddressBb(address _feeAddress) public {
        require(msg.sender == feeAddBb, "setFeeAddress: FORBIDDEN");
        feeAddBb = _feeAddress;
        emit SetFeeAddressBb(msg.sender, _feeAddress);
    }

    function setFeeAddressSt(address _feeAddress) public {
        require(msg.sender == feeAddSt, "setFeeAddress: FORBIDDEN");
        feeAddSt = _feeAddress;
        emit SetFeeAddressSt(msg.sender, _feeAddress);
    }

}
