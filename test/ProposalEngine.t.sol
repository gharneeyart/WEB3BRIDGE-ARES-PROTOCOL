// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
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

    address ganiyat = makeAddr("Ganiyat");
    address nursca = makeAddr("Nursca");
    address haneefah = makeAddr("Haneefah");
    address feyi = makeAddr("Feyi");

    function setUp() public {
        address[] memory govs = new address[](3);
        govs[0] = ganiyat;
        govs[1] = nursca;
        govs[2] = haneefah;

        engine = new ProposalEngine(govs, 2);

        vm.deal(address(engine), 10 ether);
        vm.deal(ganiyat, 5 ether);
        vm.deal(nursca, 5 ether);
        vm.deal(haneefah, 5 ether);
        vm.deal(feyi, 5 ether);
    }

    function testProposalLifecycle() public {
        address recipient = makeAddr("Recipient");

        vm.prank(ganiyat);
        uint256 id = engine.submitProposal{value: DEPOSIT}(recipient, 1 ether, "", IProposalEngine.ActionType.Transfer);
        assertEq(uint256(engine.getState(id)), uint256(IProposalEngine.ProposalState.Pending));

        vm.prank(nursca);
        engine.confirmProposal(id);
        assertEq(uint256(engine.getState(id)), uint256(IProposalEngine.ProposalState.Queued));

        vm.prank(ganiyat);
        vm.expectRevert();
        engine.executeProposal(id);

        vm.warp(block.timestamp + 1 hours + 1);
        uint256 before = recipient.balance;
        vm.prank(ganiyat);
        engine.executeProposal(id);

        assertEq(uint256(engine.getState(id)), uint256(IProposalEngine.ProposalState.Executed));
        assertEq(recipient.balance, before + 1 ether);
    }

    function testExploit_Reentrancy() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(payable(address(engine)));

        vm.prank(ganiyat);
        uint256 id = engine.submitProposal{value: DEPOSIT}(
            address(attacker), 0.1 ether, "", IProposalEngine.ActionType.Transfer
        );

        vm.prank(nursca);
        engine.confirmProposal(id);

        attacker.setTarget(id);
        vm.warp(block.timestamp + 1 hours + 1);

        vm.prank(ganiyat);
        engine.executeProposal(id);

        assertEq(attacker.callCount(), 1, "reentrant call must be blocked");
    }

    function testExploit_PrematureExecution() public {
        vm.prank(ganiyat);
        uint256 id = engine.submitProposal{value: DEPOSIT}(nursca, 0, "", IProposalEngine.ActionType.Transfer);

        vm.prank(nursca);
        engine.confirmProposal(id);

        vm.warp(block.timestamp + 30 minutes);
        vm.prank(ganiyat);
        vm.expectRevert();
        engine.executeProposal(id);
    }

    function testExploit_ReplayExecution() public {
        vm.prank(ganiyat);
        uint256 id = engine.submitProposal{value: DEPOSIT}(address(engine), 0, "", IProposalEngine.ActionType.Call);

        vm.prank(nursca);
        engine.confirmProposal(id);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(ganiyat);
        engine.executeProposal(id);

        vm.prank(ganiyat);
        vm.expectRevert();
        engine.executeProposal(id);
    }

    function testExploit_NonGovernorSubmit() public {
        vm.prank(feyi);
        vm.expectRevert();
        engine.submitProposal{value: DEPOSIT}(ganiyat, 0, "", IProposalEngine.ActionType.Transfer);
    }

    function testExploit_NonGovernorExecute() public {
        vm.prank(ganiyat);
        uint256 id = engine.submitProposal{value: DEPOSIT}(nursca, 0, "", IProposalEngine.ActionType.Transfer);
        vm.prank(nursca);
        engine.confirmProposal(id);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(feyi);
        vm.expectRevert(ProposalEngine.NOT_GOVERNOR.selector);
        engine.executeProposal(id);
    }

    function testExploit_ExecutePendingProposal() public {
        vm.prank(ganiyat);
        uint256 id = engine.submitProposal{value: DEPOSIT}(nursca, 0, "", IProposalEngine.ActionType.Transfer);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(ganiyat);
        vm.expectRevert(ProposalEngine.WRONG_STATE.selector);
        engine.executeProposal(id);
    }

    function testExploit_DoubleConfirm() public {
        vm.prank(ganiyat);
        uint256 id = engine.submitProposal{value: DEPOSIT}(nursca, 0, "", IProposalEngine.ActionType.Transfer);

        vm.prank(nursca);
        engine.confirmProposal(id);

        vm.prank(nursca);
        vm.expectRevert(ProposalEngine.WRONG_STATE.selector);
        engine.confirmProposal(id);
    }

    function testExploit_SubmitWithoutDeposit() public {
        vm.prank(ganiyat);
        vm.expectRevert(ProposalEngine.WRONG_DEPOSIT.selector);
        engine.submitProposal{value: 0}(nursca, 0, "", IProposalEngine.ActionType.Transfer);
    }

    function testExploit_CancelExecutedProposal() public {
        vm.prank(ganiyat);
        uint256 id = engine.submitProposal{value: DEPOSIT}(address(engine), 0, "", IProposalEngine.ActionType.Call);
        vm.prank(nursca);
        engine.confirmProposal(id);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(ganiyat);
        engine.executeProposal(id);
        vm.prank(ganiyat);
        vm.expectRevert(ProposalEngine.ALREADY_EXECUTED.selector);
        engine.cancelProposal(id);
    }

    receive() external payable {}
}
