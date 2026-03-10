// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {AresTreasury} from "../src/core/AresTreasury.sol";
import {IProposalEngine} from "../src/interfaces/IProposalEngine.sol";

contract ReentrancyAttacker {
    AresTreasury public treasury;
    uint256 public targetId;
    uint256 public callCount;

    constructor(address payable t) {
        treasury = AresTreasury(t);
    }

    function setTarget(uint256 id) external {
        targetId = id;
    }

    receive() external payable {
        callCount++;
        if (callCount < 3) {
            try treasury.execute(targetId) {} catch {}
        }
    }
}

contract GriefingReceiver {
    receive() external payable {
        revert("no ETH");
    }
}

contract AresTreasuryTest is Test {
    AresTreasury treasury;
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

        // Deploy treasury — pass address(this) as guard so it deploys a real guard
        // We pass alice as merkleAdmin (only alice can setMerkleRoot)
        treasury = new AresTreasury(govs, 2, alice);

        vm.deal(address(treasury), 10 ether); // fund treasury for claims + proposals
        vm.deal(alice, 5 ether);
        vm.deal(bob, 5 ether);
        vm.deal(carol, 5 ether);
        vm.deal(eve, 5 ether);
    }


    function testProposalLifecycle() public {
        address recipient = makeAddr("Recipient");
        // Fund treasury so it can send 1 ether
        vm.deal(address(treasury), 5 ether);

        vm.prank(alice);
        uint256 id = treasury.submit{value: DEPOSIT}(recipient, 1 ether, "", IProposalEngine.ActionType.Transfer);

        assertEq(uint256(treasury.stateOf(id)), uint256(0)); // Pending

        vm.prank(bob);
        treasury.confirm(id);

        assertEq(uint256(treasury.stateOf(id)), uint256(1)); // Queued

        // Should revert before timelock elapses
        vm.expectRevert();
        vm.prank(alice);
        treasury.execute(id);

        vm.warp(block.timestamp + 1 hours + 1);

        uint256 before = recipient.balance;
        vm.prank(alice);
        treasury.execute(id);

        assertEq(uint256(treasury.stateOf(id)), uint256(2)); // Executed
        assertEq(recipient.balance, before + 1 ether);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MERKLE CLAIMS
    // ─────────────────────────────────────────────────────────────────────────

    function testMerkleClaim() public {
        uint256 amount = 0.5 ether;
        bytes32 leaf = keccak256(abi.encodePacked(alice, amount));

        // Only merkleAdmin (alice) can set root
        vm.prank(alice);
        treasury.setMerkleRoot(leaf);

        uint256 before = alice.balance;
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        treasury.claim(proof, amount);

        assertGt(alice.balance, before);
        assertTrue(treasury.hasClaimed(treasury.currentRound(), alice));
    }

    function testRoundBasedClaims() public {
        uint256 amount = 0.1 ether;
        bytes32 leaf = keccak256(abi.encodePacked(bob, amount));

        vm.prank(alice);
        treasury.setMerkleRoot(leaf);
        uint256 round1 = treasury.currentRound();

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(bob);
        treasury.claim(proof, amount);
        assertTrue(treasury.hasClaimed(round1, bob));

        bytes32 leaf2 = keccak256(abi.encodePacked(carol, amount));
        vm.prank(alice);
        treasury.setMerkleRoot(leaf2);
        uint256 round2 = treasury.currentRound();

        assertEq(round2, round1 + 1);
        assertFalse(treasury.hasClaimed(round2, carol));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CANCEL
    // ─────────────────────────────────────────────────────────────────────────

    function testCancelProposal() public {
        vm.prank(alice);
        uint256 id = treasury.submit{value: DEPOSIT}(bob, 0, "", IProposalEngine.ActionType.Transfer);

        vm.prank(alice);
        treasury.cancelAndRefund(id);

        assertEq(uint256(treasury.stateOf(id)), uint256(3)); // Cancelled
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DEPOSIT RETURNED ON EXECUTE
    // ─────────────────────────────────────────────────────────────────────────

    function testDepositReturnedOnExecute() public {
        uint256 aliceBefore = alice.balance;

        vm.prank(alice);
        uint256 id = treasury.submit{value: DEPOSIT}(address(treasury), 0, "", IProposalEngine.ActionType.Call);

        vm.prank(bob);
        treasury.confirm(id);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        treasury.execute(id);

        // Alice spent DEPOSIT to submit, got it back on execute → net zero
        assertEq(alice.balance, aliceBefore);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXPLOIT: REENTRANCY
    // ─────────────────────────────────────────────────────────────────────────

    function testExploit_Reentrancy() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(payable(address(treasury)));
        vm.deal(address(attacker), 1 ether);
        vm.deal(address(treasury), 5 ether);

        vm.prank(alice);
        uint256 id =
            treasury.submit{value: DEPOSIT}(address(attacker), 0.1 ether, "", IProposalEngine.ActionType.Transfer);

        vm.prank(bob);
        treasury.confirm(id);

        attacker.setTarget(id);
        vm.warp(block.timestamp + 1 hours + 1);

        vm.prank(alice);
        treasury.execute(id);

        // State set to Executed before external call — reentrant execute must revert
        assertEq(attacker.callCount(), 1, "reentrant call must be blocked");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXPLOIT: DOUBLE CLAIM
    // ─────────────────────────────────────────────────────────────────────────

    function testExploit_DoubleClaim() public {
        uint256 amount = 0.1 ether;
        bytes32 leaf = keccak256(abi.encodePacked(alice, amount));
        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        treasury.setMerkleRoot(leaf);

        vm.prank(alice);
        treasury.claim(proof, amount);

        vm.prank(alice);
        vm.expectRevert();
        treasury.claim(proof, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXPLOIT: FAKE PROOF
    // ─────────────────────────────────────────────────────────────────────────

    function testExploit_FakeProof() public {
        bytes32 realLeaf = keccak256(abi.encodePacked(alice, uint256(1 ether)));
        vm.prank(alice);
        treasury.setMerkleRoot(realLeaf);

        bytes32[] memory fakeProof = new bytes32[](1);
        fakeProof[0] = keccak256("noise");

        vm.prank(eve);
        vm.expectRevert();
        treasury.claim(fakeProof, 1 ether);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXPLOIT: PREMATURE EXECUTION
    // ─────────────────────────────────────────────────────────────────────────

    function testExploit_PrematureExecution() public {
        vm.prank(alice);
        uint256 id = treasury.submit{value: DEPOSIT}(bob, 0, "", IProposalEngine.ActionType.Transfer);

        vm.prank(bob);
        treasury.confirm(id);

        vm.warp(block.timestamp + 30 minutes);
        vm.prank(alice);
        vm.expectRevert();
        treasury.execute(id);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXPLOIT: REPLAY EXECUTION
    // ─────────────────────────────────────────────────────────────────────────

    function testExploit_ReplayExecution() public {
        vm.prank(alice);
        uint256 id = treasury.submit{value: DEPOSIT}(address(treasury), 0, "", IProposalEngine.ActionType.Call);

        vm.prank(bob);
        treasury.confirm(id);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        treasury.execute(id);

        vm.prank(alice);
        vm.expectRevert();
        treasury.execute(id); // already Executed → WRONG_STATE
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXPLOIT: NON-GOVERNOR SUBMIT
    // ─────────────────────────────────────────────────────────────────────────

    function testExploit_NonGovernorSubmit() public {
        vm.prank(eve);
        vm.expectRevert();
        treasury.submit{value: DEPOSIT}(alice, 0, "", IProposalEngine.ActionType.Transfer);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXPLOIT: EXECUTE CANCELLED PROPOSAL
    // ─────────────────────────────────────────────────────────────────────────

    function testExploit_ExecuteCancelledProposal() public {
        vm.prank(alice);
        uint256 id = treasury.submit{value: DEPOSIT}(bob, 0, "", IProposalEngine.ActionType.Transfer);

        vm.prank(alice);
        treasury.cancelAndRefund(id);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        vm.expectRevert();
        treasury.execute(id); // Cancelled → WRONG_STATE
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXPLOIT: DRAIN LIMIT BLOCKED
    // ─────────────────────────────────────────────────────────────────────────

    function testExploit_DrainLimitBlocked() public {
        // Treasury has 10 ether, maxDailyBps = 1000 (10%) → max 1 ether/day
        // Attempting to drain 5 ether should revert
        vm.prank(alice);
        uint256 id = treasury.submit{value: DEPOSIT}(eve, 5 ether, "", IProposalEngine.ActionType.Transfer);

        vm.prank(bob);
        treasury.confirm(id);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        vm.expectRevert();
        treasury.execute(id);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXPLOIT: DOUBLE CONFIRM
    // ─────────────────────────────────────────────────────────────────────────

    function testExploit_DoubleConfirm() public {
        vm.prank(alice);
        uint256 id = treasury.submit{value: DEPOSIT}(bob, 0, "", IProposalEngine.ActionType.Transfer);

        vm.prank(bob);
        treasury.confirm(id);

        vm.prank(bob);
        vm.expectRevert();
        treasury.confirm(id); // ALREADY_CONFIRMED
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EXPLOIT: SUBMIT WITHOUT DEPOSIT
    // ─────────────────────────────────────────────────────────────────────────

    function testExploit_SubmitWithoutDeposit() public {
        vm.prank(alice);
        vm.expectRevert();
        treasury.submit{value: 0}(bob, 0, "", IProposalEngine.ActionType.Transfer);
    }

    receive() external payable {}
}
