// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console2} from "forge-std/Test.sol";
import {ProposalEngine} from "../src/core/ProposalEngine.sol";
import {IProposalEngine} from "../src/interfaces/IProposalEngine.sol";

contract ReentrancyAttacker {
    ProposalEngine public engine;
    uint256 public targetId;
    uint256 public callCount;

    constructor(address payable t) {
        engine = ProposalEngine(t);
    }

    function setTarget(uint256 id) external {
        targetId = id;
    }

    receive() external payable {
        callCount++;
        if (callCount < 3) {
            try engine.executeProposal(targetId) {} catch {}
        }
    }
}

contract GriefingReceiver {
    receive() external payable {
        revert("no ETH");
    }
}

contract ProposalEngineTest is Test {
    ProposalEngine engine;
    uint256 constant DEPOSIT = 0.01 ether;

    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");
    address carol = makeAddr("Carol");
    address eve = makeAddr("Eve");

    function setUp() public {
        address[] memory govs = new address[](3);
        govs[0] = alice;
        govs[1] = bob;
        govs[2] = carol;

        engine = new ProposalEngine(govs, 2);

        vm.deal(address(engine), 10 ether);
        vm.deal(alice, 5 ether);
        vm.deal(bob, 5 ether);
        vm.deal(carol, 5 ether);
        vm.deal(eve, 5 ether);
    }

    function testProposalLifecycle() public {
        address recipient = makeAddr("Recipient");

        vm.prank(alice);
        uint256 id = engine.submitProposal{value: DEPOSIT}(recipient, 1 ether, "", IProposalEngine.ActionType.Transfer);
        assertEq(uint256(engine.getState(id)), uint256(0)); 

        vm.prank(bob);
        engine.confirmProposal(id);
        assertEq(uint256(engine.getState(id)), uint256(1)); 

        vm.prank(alice);
        vm.expectRevert();
        engine.executeProposal(id);

        vm.warp(block.timestamp + 1 hours + 1);

        uint256 before = recipient.balance;
        vm.prank(alice);
        engine.executeProposal(id);

        assertEq(uint256(engine.getState(id)), uint256(2)); 
        assertEq(recipient.balance, before + 1 ether);
    }

    

    function testCancelProposal() public {
        vm.prank(alice);
        uint256 id = engine.submitProposal{value: DEPOSIT}(bob, 0, "", IProposalEngine.ActionType.Transfer);

        vm.prank(alice);
        engine.cancelProposal(id);

        assertEq(uint256(engine.getState(id)), uint256(3)); 
    }

    function testDepositReturnedOnExecute() public {
        uint256 aliceBefore = alice.balance;

        vm.prank(alice);
        uint256 id = engine.submitProposal{value: DEPOSIT}(address(engine), 0, "", IProposalEngine.ActionType.Call);

        vm.prank(bob);
        engine.confirmProposal(id);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        engine.executeProposal(id);

        assertEq(alice.balance, aliceBefore);
    }

    function testExploit_Reentrancy() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(payable(address(engine)));

        vm.prank(alice);
        uint256 id = engine.submitProposal{value: DEPOSIT}(
            address(attacker), 0.1 ether, "", IProposalEngine.ActionType.Transfer
        );

        vm.prank(bob);
        engine.confirmProposal(id);

        attacker.setTarget(id);
        vm.warp(block.timestamp + 1 hours + 1);

        vm.prank(alice);
        engine.executeProposal(id);

        assertEq(attacker.callCount(), 1, "reentrant call must be blocked");
    }


    function testExploit_PrematureExecution() public {
        vm.prank(alice);
        uint256 id = engine.submitProposal{value: DEPOSIT}(bob, 0, "", IProposalEngine.ActionType.Transfer);

        vm.prank(bob);
        engine.confirmProposal(id);

        vm.warp(block.timestamp + 30 minutes);
        vm.prank(alice);
        vm.expectRevert();
        engine.executeProposal(id);
    }

    function testExploit_ReplayExecution() public {
        vm.prank(alice);
        uint256 id = engine.submitProposal{value: DEPOSIT}(address(engine), 0, "", IProposalEngine.ActionType.Call);

        vm.prank(bob);
        engine.confirmProposal(id);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        engine.executeProposal(id);

        vm.prank(alice);
        vm.expectRevert(); 
        engine.executeProposal(id);
    }

    function testExploit_NonGovernorSubmit() public {
        vm.prank(eve);
        vm.expectRevert();
        engine.submitProposal{value: DEPOSIT}(alice, 0, "", IProposalEngine.ActionType.Transfer);
    }

    function testExploit_ExecuteCancelledProposal() public {
        vm.prank(alice);
        uint256 id = engine.submitProposal{value: DEPOSIT}(bob, 0, "", IProposalEngine.ActionType.Transfer);

        vm.prank(alice);
        engine.cancelProposal(id);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        vm.expectRevert(); 
        engine.executeProposal(id);
    }

    function testExploit_DoubleConfirm() public {
        vm.prank(alice);
        uint256 id = engine.submitProposal{value: DEPOSIT}(bob, 0, "", IProposalEngine.ActionType.Transfer);

        vm.prank(bob);
        engine.confirmProposal(id);

        vm.prank(bob);
        vm.expectRevert(); 
        engine.confirmProposal(id);
    }

    function testExploit_SubmitWithoutDeposit() public {
        vm.prank(alice);
        vm.expectRevert(); 
        engine.submitProposal{value: 0}(bob, 0, "", IProposalEngine.ActionType.Transfer);
    }

    receive() external payable {}
}
