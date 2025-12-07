// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/*\
Created by SolidityX for Decision Game
Telegram: @solidityX
\*/


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";



contract Staking is AutomationCompatible {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint;

    IERC20 private depToken; // deposit token (LP)
    IERC20 private rewToken; // reward token
    EnumerableSet.AddressSet private stakeholders; // list of depositor addresses

    /*\
    struct that contains information about the deposit
    \*/
    struct Stake {
        uint staked;
        uint shares;
        uint unlock;
    }

    address public owner; // owner of the contract
    address public registry; // chainlink automation registry
    uint private totalStakes; // total amount of tokens deposited
    uint private totalShares; // total amount of shares issued
    uint constant private minForExecution = 3; // minimum amount of available withdrawls for chainlink to trigger
    uint constant private maxForExecution = 9; // maximum amount of available withdrawls for chainlink to trigger in one transaction
    bool private initialized; // if contract is initialized

    mapping(address => Stake) private stakeholderToStake; // mapping from the depositor address to his information (tokens deposited etc.)
    mapping(uint => uint) private timePeriods; // mapping from index to time periods in seconds (mapping are cheaper than arrays)

    /*\
    function with this modifier can only be called by the owner
    \*/
    modifier onlyOwner() {
        require(msg.sender == owner, "caller not owner");
        _;
    }

    /*\
    sets important variables at deployment
    \*/
    constructor(address _depToken, address _rewToken, address _registry, uint[] memory _timePeriods) {
        depToken = IERC20(_depToken);
        rewToken = IERC20(_rewToken);
        registry = _registry;
        owner = msg.sender;
        for(uint i; i < _timePeriods.length; i++) {
            timePeriods[i] = _timePeriods[i];
        }
    }

    event StakeAdded(address indexed stakeholder, uint amount, uint shares, uint timestamp); // this event emits on every deposit
    event StakeRemoved(address indexed stakeholder, uint amount, uint shares, uint reward, uint timestamp); // this event emits on every withdraw


/*//////////////////////////////////////////////‾‾‾‾‾‾‾‾‾‾\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\*\
///////////////////////////////////////////////executeables\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
\*\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\____________/////////////////////////////////////////////*/

    /*\
    initialize all values
    amount will be locked forever
    \*/
    function initialize(uint _amount, uint _p) external onlyOwner {
        require(!initialized, "already initialized!");
        require(depToken.transferFrom(msg.sender, address(this), _amount), "transfer failed!");
        require(timePeriods[_p] > 0, "invalid time period!");

        stakeholderToStake[address(0x0)] = Stake({
            staked: _amount,
            shares: _amount,
            unlock: 0
        });
        totalStakes = _amount;
        totalShares = _amount;
        initialized = true;
        owner = address(0x0);
        emit StakeAdded(address(0x0), _amount, _amount, block.timestamp);
    }

    /*\
    stake tokens
    \*/
    function deposit(uint _amount, uint _p) external returns(bool) {
        require(initialized, "not initialized!");
        require(stakeholderToStake[msg.sender].staked == 0, "already deposited!");
        require(timePeriods[_p] > 0, "invalid time period!");
        require(_amount > 0, "amount too small!");

        uint tbal = depToken.balanceOf(address(this)).add(rewToken.balanceOf(address(this)));
        uint shares = _amount.mul(totalShares).div(tbal);
        require(depToken.transferFrom(msg.sender, address(this), _amount), "transfer failed!");

        stakeholders.add(msg.sender);
        stakeholderToStake[msg.sender] = Stake({
            staked: _amount,
            shares: shares,
            unlock: block.timestamp.add(timePeriods[_p])
        });
        totalStakes = totalStakes.add(_amount);
        totalShares += shares;
        emit StakeAdded(msg.sender, _amount, shares, block.timestamp);
        return true;
    }

    /*\
    withdraw function if in emergency state (no rewards)
    \*/
    function emergencyWithdraw() external returns(bool) {
        uint stake = stakeholderToStake[msg.sender].staked;
        uint shares = stakeholderToStake[msg.sender].shares;

        stakeholderToStake[msg.sender] = Stake({
            staked: 0,
            shares: 0,
            unlock: 0
        });
        totalShares = totalShares.sub(shares);
        totalStakes = totalStakes.sub(stake);

        require(depToken.transfer(msg.sender, stake), "initial transfer failed!");

        stakeholders.remove(msg.sender);
        return true;
    }

    /*\
    remove staked tokens
    \*/
    function withdraw() external returns(bool){
        _withdraw(msg.sender);
        return true;
    }

    function _withdraw(address _account) internal {
        require(block.timestamp >= stakeholderToStake[_account].unlock, "stake still locked!");
        require(stakeholderToStake[_account].staked > 0, "not staked!");
        uint rewards = rewardOf(_account);
        uint stake = stakeholderToStake[_account].staked;
        uint shares = stakeholderToStake[_account].shares;

        stakeholderToStake[_account] = Stake({
            staked: 0,
            shares: 0,
            unlock: 0
        });
        totalShares = totalShares.sub(shares);
        totalStakes = totalStakes.sub(stake);

        require(depToken.transfer(_account, stake), "initial transfer failed!");
        require(rewToken.transfer(_account, rewards), "reward transfer failed!");

        stakeholders.remove(_account);

        emit StakeRemoved(_account, stake, shares, rewards, block.timestamp);
    }

    /*\
    executed by chainlink automation
    withdraws all withdrawable stakes in performData
    \*/
    function performUpkeep(bytes calldata performData) external override {
        require(msg.sender == registry, "not registry!");
        (address[] memory withdrawable) = abi.decode(performData, (address[]));
        for(uint i; i < withdrawable.length; i++) {
            _withdraw(withdrawable[i]);
        }
    }

    /*\
    called by chainlink automation
    returns all withdrawable stakes
    \*/
    function checkUpkeep(bytes calldata /* checkData */) external view override returns (bool upkeepNeeded, bytes memory performData) {
        address[] memory withdrawableFULL = new address[](getTotalStakeholders());
        uint count;
        for(uint i; i < withdrawableFULL.length; i++) {
            if(block.timestamp >= stakeholderToStake[stakeholders.at(i)].unlock) {
                withdrawableFULL[count] = stakeholders.at(i);
                count++;
            }
            if(count >= maxForExecution)
                break;
        }
        address[] memory withdrawable = new address[](count);
        for(uint i; i < withdrawable.length; i++) {
            withdrawable[i] = withdrawableFULL[i];
        }
        performData = abi.encode(withdrawable);
        if(count >= minForExecution)
            upkeepNeeded = true;
    }


/*//////////////////////////////////////////////‾‾‾‾‾‾‾‾‾‾‾\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\*\
///////////////////////////////////////////////viewable/misc\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
\*\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\_____________/////////////////////////////////////////////*/


    /*\
    ratio of token/share
    \*/
    function getRatio() public view returns(uint) {
        uint tbal = depToken.balanceOf(address(this)).add(rewToken.balanceOf(address(this)));
        return tbal.mul(1e18).div(totalShares);
    }

    /*\
    get token stake of user
    \*/
    function stakeOf(address stakeholder) public view returns (uint) {
        return stakeholderToStake[stakeholder].staked;
    }

    /*\
    get shares of user
    \*/
    function sharesOf(address stakeholder) public view returns (uint) {
        return stakeholderToStake[stakeholder].shares;
    }

    /*\
    get total amount of tokens staked
    \*/
    function getTotalStakes() external view returns (uint) {
        return totalStakes;
    }

    /*\
    get total amount of shares
    \*/ 
    function getTotalShares() external view returns (uint) {
        return totalShares;
    }

    /*\
    get total current rewards
    \*/
    function getCurrentRewards() external view returns (uint) {
        return rewToken.balanceOf(address(this));
    }

    /*\
    get list of all stakers
    \*/
    function getTotalStakeholders() public view returns (uint) {
        return stakeholders.length();
    }

    /*\
    get the unix timestamp when the stake of staker unlocks
    \*/
    function getUnlockOf(address staker) external view returns(uint) {
        return stakeholderToStake[staker].unlock;
    }

    /*\
    get rewards that user received
    \*/
    function rewardOf(address stakeholder) public view returns (uint) {
        uint stakeholderStake = stakeOf(stakeholder);
        uint stakeholderShares = sharesOf(stakeholder);

        if (stakeholderShares == 0) {
            return 0;
        }

        uint stakedRatio = stakeholderStake.mul(1e18).div(stakeholderShares);
        uint currentRatio = getRatio();

        if (currentRatio <= stakedRatio) {
            return 0;
        }

        uint rewards = stakeholderShares.mul(currentRatio.sub(stakedRatio)).div(1e18);
        return rewards;
    }
}
