// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RevenueDistribution} from "../src/RevenueDistribution.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RevenueDistributionTest is Test {
    // Events
    event DepositedRevenue(address indexed _stakeholder, uint256 amount);
    event WithdrawnRevenue(address indexed _stakeholder, uint256 amount);
    event RevenueDistributed(uint256 timestamp);

    RevenueDistribution public revenue;

    // Stakeholders and Community Members
    address payable[] communityAddresses;
    address payable[] stakeHoldersAddresses;
    address payable operatingCostAddress = payable(address(100));
    address private owner;

    uint256 public minimumDeposit = 100 * 10 * 18; // 100   ETH
    uint256 public startingBalance = 50 ether;
    uint256 private constant LOCK_PERIOD = 30 days;
    uint256 private constant QUARTER_DURATION = 90 days;

    uint256 private constant COMMUNITY_SHARES = 60;    //60% of Total Revenue generated
    uint256 private constant STAKEHOLDER_SHARES = 30;  //30% of Total Revenue generated
    uint256 private constant OPERATING_SHARES = 10;    //10% of Total Revenue generated
    uint256 private constant REVENUE_FUNDS = 100 ether;

   // Users which are also the STAKEHOLDERS.
    address payable[] private USERS = [
        payable(makeAddr("USER")),
        payable(makeAddr("USER1")),
        payable(makeAddr("USER2")),
        payable(makeAddr("USER3"))
    ];

    function setUp() external {
        // Mocking some addresses for community members and stakeholders
        for (uint i = 0; i < 3; i++) {
            communityAddresses.push(payable(address(uint160(101 + i))));
        }

        // Deploy the RevenueDistribution contract
        revenue = new RevenueDistribution(
            communityAddresses,
            stakeHoldersAddresses,
            operatingCostAddress
        );

        // Funded the Revenue System with 100 ether.
        deal(address(revenue), REVENUE_FUNDS);
        owner = address(this);

        // Fund you USERS(StakeHolders)
        for(uint256 i = 0; i < USERS.length; i++){
            vm.deal(USERS[i], startingBalance);
        }
    }

    /////////////////////
    // depositRevenue////
    /////////////////////
    function testRevertIfDepositIsZero() public {
        vm.startPrank(USERS[0]);
        vm.expectRevert(
            RevenueDistribution.RevenueDistribution__CantDepositZero.selector
        );
        revenue.depositRevenue();
    }

    function testRevertIfDepositIsTooLow() public {
        uint256 amount = 0.5 ether;
        vm.startPrank(USERS[0]);
        vm.expectRevert(
            RevenueDistribution.RevenueDistribution__DepositTooLow.selector
        );
        revenue.depositRevenue{value: amount}();
    }

    function testUserBalanceBeforeAndAfterDeposit() public {
        vm.startPrank(USERS[0]);
        uint256 userBalanceBeforeDeposit = revenue.getBalance(USERS[0]);
        assertEq(0, userBalanceBeforeDeposit);
        revenue.depositRevenue{value: startingBalance}();
        uint256 userBalance = revenue.getBalance(USERS[0]);
        assertEq(startingBalance, userBalance);
    }

    function testDifferentUsersCanDeposit() public {
        uint256 amountOfUsers = USERS.length;

        for(uint256 i = 0; i < USERS.length; i++){
            vm.startPrank(USERS[i]);
            revenue.depositRevenue{value: startingBalance}();
        }
        
        assertEq(revenue.getStakeHoldersAddress().length, amountOfUsers);
    }

    function testUserFundingIsTracked() public {
        uint256 amount = 20 ether;

        vm.startPrank(USERS[0]);
        revenue.depositRevenue{value: amount}(); // Send Ether

        uint256 amountFunded = revenue.getBalance(USERS[0]);
        assertEq(amount, amountFunded);
    }

    function testDepositedRevenueIsAccurate() public {
        uint256 totalRevenue = startingBalance * USERS.length;
        uint256 totalBalance = 0;

        for(uint256 i = 0; i < USERS.length; i++){
            vm.startPrank(USERS[i]);
            revenue.depositRevenue{value: startingBalance}();
            totalBalance += revenue.getBalance(USERS[i]);
        }

        assertEq(totalRevenue, totalBalance);
    }

    function testEmitDeposit() public {
        vm.startPrank(USERS[0]);
        vm.expectEmit(true, true, false, false, address(revenue));
        emit DepositedRevenue(USERS[0], startingBalance);
        revenue.depositRevenue{value: startingBalance}(); // Send Ether
    }

    /////////////////////
    // withdrawRevenue////
    /////////////////////
    modifier userHasDeposited() {
        vm.startPrank(USERS[0]);
        revenue.depositRevenue{value: startingBalance}();
        _;
    }

    function testRevertIfWithdrawalIsZero() public {
        vm.startPrank(USERS[0]);
        vm.expectRevert(RevenueDistribution.RevenueDistribution__CantDepositZero.selector);
        revenue.withdrawRevenue(0);
    }

    function testUsersCannotWithdrawBeforeLockperiodEnds() public userHasDeposited {
        vm.startPrank(USERS[0]);
        vm.expectRevert(RevenueDistribution.RevenueDistribution__WithdrawalTooSoon.selector);
        revenue.withdrawRevenue(startingBalance);
    }

    function testUsersCanWithdrawAfterLockPeriod() public userHasDeposited {
        uint256 depositedAmount = 50 ether;

        vm.roll(block.timestamp + LOCK_PERIOD + 1 days);
        vm.warp(block.number + 1);
        
        revenue.withdrawRevenue(depositedAmount);

        // Verify the final balance after withdrawal
        assertEq(revenue.getBalance(USERS[0]), 0);
        console.log("RevenueContract balance after withdrawal:", address(revenue).balance);
    }

    function testEmitWithdrawal() public userHasDeposited {
        vm.roll(block.timestamp + LOCK_PERIOD + 1 days);
        vm.warp(block.number + 1);
        vm.expectEmit(true, true, false, false, address(revenue));
        emit WithdrawnRevenue(USERS[0], startingBalance);
        revenue.withdrawRevenue(startingBalance);
    }

    ///////////////////////
    // distributeRevenue //
    //////////////////////
    function testOnlyOwnerCanCallDistributeRevenue() public {
        vm.startPrank(USERS[0]);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(USERS[0])));
        revenue.distributeRevenue();
    }

    function testRevertsIfDurationIsOngoing() public {
        vm.startPrank(owner);
        vm.expectRevert(RevenueDistribution.RevenueDistribution__NotQuarterly.selector);
        revenue.distributeRevenue();
    }

     function testShareIsDistributedAccurately() public {
        uint256 amount = 50 ether;

        vm.startPrank(USERS[0]);
        revenue.depositRevenue{value: amount}(); 

        uint256 expectedCommunityShares = (address(revenue).balance * COMMUNITY_SHARES) / 100;
        uint256 expectedOperatingShares = (address(revenue).balance * OPERATING_SHARES) / 100;
        uint256 expectedStakeholdersShares = (address(revenue).balance * STAKEHOLDER_SHARES) / 100;

        console.log("community members:", communityAddresses.length);
        console.log("community shares:", expectedCommunityShares);
        console.log("stakeholder members:", stakeHoldersAddresses.length);
        console.log("StakeHolder shares:", expectedStakeholdersShares);

        assertEq(expectedCommunityShares, revenue.getCommunitySharesValue());
        assertEq(expectedOperatingShares, revenue.getOperatingCostSharesValue());
        assertEq(expectedStakeholdersShares, revenue.getStakeHolderSharesValue());
    }
    
    function testDistributeRevenueAfterDuration() public {
        uint256 totalRevenue = REVENUE_FUNDS + startingBalance;

        // Arrange
        vm.startPrank(USERS[0]);
        revenue.depositRevenue{value: startingBalance}();
        vm.stopPrank();

        // Simulate passage of time
        vm.warp(block.timestamp + QUARTER_DURATION + 1);
        vm.startPrank(owner);

        // Act
        revenue.distributeRevenue();

        // Assert
        assertEq(address(revenue).balance, 0);  // Contract's balance should be 0 after distribution
        assertEq(revenue.getDistributedStakeHolderBalance(USERS[0]), totalRevenue * STAKEHOLDER_SHARES / 100);  // Stakeholder's share

        // Distributing community shares among contributors
        uint256 communitySharesPerUser = (totalRevenue * COMMUNITY_SHARES) / 100 / communityAddresses.length; // equally distribute among community members
        for (uint i = 0; i < communityAddresses.length; i++) {
            assertEq(revenue.getDistributedCommunityBalance(communityAddresses[i]), communitySharesPerUser);
        }

        // Check operating cost's share
        assertEq(revenue.getDistributedOperatingBalance(), (totalRevenue * OPERATING_SHARES) / 100);

        uint256 totalShares = revenue.getDistributedStakeHolderBalance(USERS[0]) + ((totalRevenue * COMMUNITY_SHARES) / 100) + revenue.getDistributedOperatingBalance();
        assertEq(totalRevenue, totalShares);
    }

    function testEmitAfterDistribution() public {
        vm.startPrank(USERS[0]);
        revenue.depositRevenue{value: startingBalance}();
        vm.stopPrank();

        // Simulate passage of time
        vm.warp(block.timestamp + QUARTER_DURATION + 1);
        vm.startPrank(owner);

        vm.expectEmit(true, false, false, false, address(revenue));
        emit RevenueDistributed(block.timestamp);
        revenue.distributeRevenue();
    }


    ///////////////////////
    ///// checkUpKeep ////
    //////////////////////
    function testCheckUpkeepRevertsIfTimeHasNotPassed() public {
        // Arrange/Act
        (bool upKeepNeeded, ) = revenue.checkUpkeep("");

        //Assert
        assert(!upKeepNeeded);
    }

    function testCheckUpkeepIsTrueIfTimeHasPassed() public {
        //Arrange
        vm.warp(block.timestamp + QUARTER_DURATION + 1);
        vm.roll(block.number + 1);

        //Act
        (bool upKeepNeeded, ) = revenue.checkUpkeep("");

        //Assert
        assert(upKeepNeeded);
    }

    ///////////////////////
    /// performUpKeep ////
    //////////////////////
    function testPerfromUpkeepRunsOnlyIfCheckUpkeepIsTrue() public userHasDeposited{
        //Arrange
        vm.startPrank(owner);
        vm.warp(block.timestamp + QUARTER_DURATION + 1);
        vm.roll(block.number + 1);

        // Act/Assert
        revenue.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfTimeHasNotPassed() public {
        vm.expectRevert(RevenueDistribution.RevenueDistribution__NotQuarterly.selector);
        revenue.performUpkeep("");
    }
}
