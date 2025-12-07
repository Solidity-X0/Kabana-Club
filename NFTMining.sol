// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/*\
Created by SolidityX for Decision Game
Telegram: @solidityX
\*/

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/*\
IERC165 interface
\*/
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/*\
nft interface
\*/
interface IERC721 is IERC165 {
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

/*\
reward token interface
\*/
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}


contract Staking {
    using EnumerableSet for EnumerableSet.UintSet;

    IERC20 private token; // reward token
    IERC721 private NFT; // deposit token (nft)
    
    uint private constant day = 24*60*60; // seconds in a day
    uint private constant rewardsPD = 444e18; // rewards per day

    mapping(address => Staker) private NFTM; // maps an address to a staker struct

    /*\
    saves information about the deposit
    \*/
    struct Staker {
        uint256 lastClaim;
        EnumerableSet.UintSet tokenIds;
    }

    /*\
    sets tokenAddress and NftAddress at deployment
    \*/
    constructor(address tokenAddress, address NFTAddress) {
        token = IERC20(tokenAddress);
        NFT = IERC721(NFTAddress);
    }


/*//////////////////////////////////////////////‾‾‾‾‾‾‾‾‾‾\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\*\
///////////////////////////////////////////////executeables\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
\*\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\____________/////////////////////////////////////////////*/

    
    /*\
    allows user to deposit any amount of nfts he likes to deposit
    will claim rewards
    \*/
    function stake(uint256[] memory tokenId) external returns(bool, uint){
        _claim(msg.sender);
        for(uint256 i = 0; i < tokenId.length; i++) {
            NFT.transferFrom(msg.sender, address(this), tokenId[i]);
            NFTM[msg.sender].tokenIds.add(tokenId[i]);
        }
        return (true, nftsDepositedOf(msg.sender));
    }

    /*\
    unstake deposited nfts
    rewards will be claimed
    \*/
    function unstake(uint256[] memory tokenId) external returns(bool, uint, uint){
        require(nftsDepositedOf(msg.sender) >= tokenId.length, "you don't have that many nfts deposited!");
        uint rewards = _claim(msg.sender);
        for(uint256 i; i < tokenId.length; i++) {
            require(NFTM[msg.sender].tokenIds.contains(tokenId[i]), "nft not deposited!");
            _unstake(tokenId[i]);
        }
        return (true, rewards, nftsDepositedOf(msg.sender));
    }

    /*\
    function to unstake all nfts that user has deposited
    rewards will be claimed
    \*/
    function unstakeAll() external returns(bool, uint){
        uint rewards = _claim(msg.sender);
        uint nfts = nftsDepositedOf(msg.sender);
        for(uint i; i < nfts; i++) {
            _unstake(NFTM[msg.sender].tokenIds.at(0));
        }
        return(true, rewards);
    }

    /*\
    allows user to claim rewards
    \*/
    function claim() external returns(bool, uint){
        return (true, _claim(msg.sender));
    }


/*//////////////////////////////////////////////‾‾‾‾‾‾‾‾‾‾‾\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\*\
///////////////////////////////////////////////viewable/misc\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
\*\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\_____________/////////////////////////////////////////////*/


    /*\
    internal function to unstake nft
    \*/
    function _unstake(uint256 id) private {
        NFTM[msg.sender].tokenIds.remove(id);
        NFT.transferFrom(address(this), msg.sender, id);
    }

    /*\
    internal function for claiming rewards
    \*/
    function _claim(address user) private returns(uint) {
        uint256 rewards = rewardsOf(user);
        NFTM[user].lastClaim = block.timestamp;
        if (rewards > 0) {
            rewards = rewards > token.balanceOf(address(this)) ? token.balanceOf(address(this)) : rewards;
            require(token.transfer(user, rewards), "transfer failed, reward!");
        }
        return rewards;
    }

    /*\
    returns the rewards of user since the last claim
    \*/
    function rewardsOf(address user) public view returns(uint) {
        if (nftsDepositedOf(user) == 0)
            return 0;
        uint256 amountInSeconds = block.timestamp - NFTM[user].lastClaim;
        uint256 rewardMult = (100e18 / day) * amountInSeconds;
        uint256 rewards = (rewardsPD * rewardMult / 100e18) * nftsDepositedOf(user);
        return rewards;
    }

    /*\
    returns deposited nfts of address
    \*/    
    function nftsDepositedOf(address user) public view returns(uint) {
        return NFTM[user].tokenIds.length();
    }
    
    /*\
    returns the latest unix timestamp that user has claimed rewards
    \*/
    function lastClaimOf(address user) external view returns(uint) {
        return NFTM[user].lastClaim;
    }

    /*\
    returns the address of the deposit nft
    \*/
    function depositNft() external view returns(address) {
        return address(NFT);
    }

    /*\
    returns the address of the reward token
    \*/
    function rewardToken() external view returns(address) {
        return address(token);
    }

    /*\
    returns the rewards per day per nft deposited
    \*/
    function getRewardsPerDay() external pure returns(uint) {
        return rewardsPD;
    }
}
