// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

 /**
 * @title A Smart Revenue Distribution System
 * @author Joseph Gimba
 * @notice This contract is for distributing revenue
 * @dev A contract that manages the distribution of revenue among stakeholders, community members, and operating costs.
 * Involves time-locked deposits and quarterly revenue distribution using Chainlink Keepers for automation.
 */

contract RevenueDistribution is Ownable, ReentrancyGuard {

    // Errors 
    error RevenueDistribution__CantDepositZero();
    error RevenueDistribution__InsufficientBalance();
    error RevenueDistribution__NotAuthorizedToWithdraw();
    error RevenueDistribution__WithdrawalTooSoon();
    error RevenueDistribution__DepositTooLow();
    error RevenueDistribution__NotQuarterly();
    error RevenueDistribution__NoFundsToDistribute();

    // State Variables
    address payable[] public communityAddresses;
    address payable[] public stakeHoldersAddresses;
    address payable public immutable i_operatingCostAddress;
 
    uint256 private constant COMMUNITY_SHARES = 60; // 60% of TotalRevenue generated
    uint256 private constant STAKEHOLDERS_SHARES = 30; // 30% of TotalRevenue generated
    uint256 private constant OPERATING_COST = 10; // 10% of TotalRevenue generated
    uint256 private constant LOCK_PERIOD = 30 days; // Lock investors funds deposited for 30 days
    uint256 private constant QUARTER_DURATION = 90 days; // Time range for distribution of revenue
    uint256 private constant MINIMUM_DEPOSIT = 1 ether; // Minimum deposit a user(stakeHolder) can invest
    uint256 private constant MINIMUM_REVENUE_FOR_DISTRIBUTION = 30 ether; 

    uint256 private lastDistributionTime;

    mapping(address => uint256) private s_balance; // balance of user that deposited or invested in the system
    mapping(address => uint256) private s_timeDeposited; // Timestamp of a user when they deposit
    mapping(address => bool) private s_hasDeposited; // Confirms if a user has deposited or invested
    mapping(address => uint256) private s_distributedStakeHolderBalance; // mapping to track distributed revenue balance
    mapping(address => uint256) private s_distributedCommunityBalance; 
    uint256 private s_distributedOperatingBalance; 


    // Events
    event DepositedRevenue(address indexed _stakeholder, uint256 amount);
    event WithdrawnRevenue(address indexed _stakeholder, uint256 amount);
    event RevenueDistributed(uint256 timestamp);

    modifier nonZero(uint256 amount) {
      if (amount <= 0) {
            revert RevenueDistribution__CantDepositZero();
           }
        _;
    }

    constructor(
        address payable[] memory _communityAddresses,
        address payable[] memory _stakeHoldersAddresses,
        address payable _operatingCostAddress
    ) Ownable(msg.sender) {
        communityAddresses = _communityAddresses;
        stakeHoldersAddresses = _stakeHoldersAddresses;
        i_operatingCostAddress = _operatingCostAddress;
        lastDistributionTime = block.timestamp; // Initialize to current time
    }

    receive() external payable {
        emit DepositedRevenue(msg.sender, msg.value);
    }

   function depositRevenue() external payable nonZero(msg.value) {
    if (msg.value < MINIMUM_DEPOSIT) { 
        revert RevenueDistribution__DepositTooLow();
    }

    if (!s_hasDeposited[msg.sender]) {
        s_hasDeposited[msg.sender] = true; // Mark the user as having deposited
        stakeHoldersAddresses.push(payable(msg.sender)); // Add the user's address to the list of depositors
    }

    s_balance[msg.sender] += msg.value; // Update balance with of the user with msg.value
    s_timeDeposited[msg.sender] = block.timestamp;  
    emit DepositedRevenue(msg.sender, msg.value); 
    }

    function distributeRevenue() public onlyOwner nonReentrant {
    uint256 currentTime = block.timestamp;

    if (currentTime < lastDistributionTime + QUARTER_DURATION) {
        revert RevenueDistribution__NotQuarterly();
    }

    uint256 totalRevenue = address(this).balance;
    if (totalRevenue < MINIMUM_REVENUE_FOR_DISTRIBUTION) {
        revert RevenueDistribution__NoFundsToDistribute();
    }

    if (totalRevenue == 0 ){
        revert RevenueDistribution__NoFundsToDistribute();
    }

    uint256 communitySharesAmount = (totalRevenue * COMMUNITY_SHARES) / 100;
    uint256 stakeHoldersSharesAmount = (totalRevenue * STAKEHOLDERS_SHARES) / 100;
    uint256 operatingCostSharesAmount = (totalRevenue * OPERATING_COST) / 100;

    // Distribute Stakeholders Shares
    _distributeStakeholderShares(stakeHoldersSharesAmount);

    // Distribute Community Members Shares
    _distributeCommunityShares(communitySharesAmount);

    // Distribute Operating Costs
    _distributeOperatingCost(operatingCostSharesAmount);

    lastDistributionTime = currentTime; // Update the last distribution time [RESET]
    emit RevenueDistributed(currentTime);
    }


    function withdrawRevenue(uint256 amount) public nonZero(amount) nonReentrant {
        if (s_balance[msg.sender] < amount) {
            revert RevenueDistribution__InsufficientBalance();
        }

        if (!s_hasDeposited[msg.sender]) {
            revert RevenueDistribution__NotAuthorizedToWithdraw();
        }

        if (block.timestamp < s_timeDeposited[msg.sender] + LOCK_PERIOD) {
            revert RevenueDistribution__WithdrawalTooSoon();
        }

        s_balance[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        
        emit WithdrawnRevenue(msg.sender, amount);
    }

    /**
    * @notice Chainlink Keeper function to check if the contract needs upkeep (revenue distribution).
    * @dev Upkeep is needed if the quarter duration has passed and sufficient revenue is available.
    * @return upkeepNeeded Whether the upkeep is required.
     */
    function checkUpkeep(bytes memory /*checkData*/) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
        upkeepNeeded = (block.timestamp >= lastDistributionTime + QUARTER_DURATION && address(this).balance > MINIMUM_REVENUE_FOR_DISTRIBUTION);
        return (upkeepNeeded, "");
    }

    /**
     * @notice Chainlink Keeper function to perform the upkeep (distribute revenue).
     * @dev If the upkeep conditions are met, this function calls distributeRevenue().
     */
    function performUpkeep(bytes calldata /*performData*/) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert RevenueDistribution__NotQuarterly();
        }
        distributeRevenue();
    }

    //////////////////////////////////////////////
    // Private & Internal View & Pure Functions //
    /////////////////////////////////////////////
     /**
     * @dev Distributes the revenue among the stakeholders equally.
     * @param stakeHoldersSharesAmount Total amount of revenue to be distributed to stakeholders(Investors).
     */
    function _distributeStakeholderShares(uint256 stakeHoldersSharesAmount) private {
         uint256 stakeHolderMemberCount = stakeHoldersAddresses.length;
         require(stakeHolderMemberCount > 0, "No stakeholders to distribute to");
         uint256 individualStakeHolderAmount = stakeHoldersSharesAmount / stakeHolderMemberCount;

    for (uint256 i = 0; i < stakeHolderMemberCount; i++) {
        stakeHoldersAddresses[i].transfer(individualStakeHolderAmount);
        s_distributedStakeHolderBalance[stakeHoldersAddresses[i]] += individualStakeHolderAmount;
        }
    }

    /**
     * @dev Distributes the revenue among the community members equally.
     * @param communitySharesAmount Total amount of revenue to be distributed to community members.
     */
    function _distributeCommunityShares(uint256 communitySharesAmount) private {
        uint256 communityMemberCount = communityAddresses.length;
        require(communityMemberCount > 0, "No community members to distribute to"); // Check for zero community members
        uint256 individualCommunityShare = communitySharesAmount / communityMemberCount;

    for (uint256 i = 0; i < communityMemberCount; i++) {
        communityAddresses[i].transfer(individualCommunityShare);
        s_distributedCommunityBalance[communityAddresses[i]] += individualCommunityShare; // Track distributed amount
        }
    }
    
    /**
     * @dev Transfers the operating cost share to the operating cost address.
     * @param operatingCostSharesAmount The amount of revenue allocated for operating costs.
     */
    function _distributeOperatingCost(uint256 operatingCostSharesAmount) private {
        i_operatingCostAddress.transfer(operatingCostSharesAmount);
        s_distributedOperatingBalance += operatingCostSharesAmount;
}

    //////////////////////
    // GETTER FUNCTIONS //
    /////////////////////
    function getStakeHoldersAddress() external view returns(address payable[] memory){
        return stakeHoldersAddresses;
    }

    function getBalance(address user) external view returns(uint256){
        return s_balance[user];
    }

   function getStakeHolderSharesValue() external view returns (uint256) {
        uint256 totalRevenue = address(this).balance;
        return (totalRevenue * STAKEHOLDERS_SHARES) / 100;
    }

    function getCommunityUsersAddress() external view returns(address payable[] memory){
        return communityAddresses;
    }

    function getCommunitySharesValue() external view returns (uint256) {
        uint256 totalRevenue = address(this).balance;
        return (totalRevenue * COMMUNITY_SHARES) / 100;
    }

    function getOperatingCostSharesValue() external view returns (uint256) {
        uint256 totalRevenue = address(this).balance;
        return (totalRevenue * OPERATING_COST) / 100;
    }

    function getDistributedStakeHolderBalance(address stakeholder) external view returns (uint256) {
        return s_distributedStakeHolderBalance[stakeholder];
    }

    function getDistributedCommunityBalance(address communityMember) external view returns (uint256) {
        return s_distributedCommunityBalance[communityMember];
    }

    function getDistributedOperatingBalance() external view returns (uint256) {
        return s_distributedOperatingBalance;
    }

}
