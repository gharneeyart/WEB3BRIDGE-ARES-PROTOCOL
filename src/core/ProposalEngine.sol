// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../interfaces/IProposalEngine.sol";
import "../modules/GovernanceGuard.sol";
import "../modules/SignatureAuth.sol";
import "../modules/MerkleDistributor.sol";

contract ProposalEngine is IProposalEngine, GovernanceGuard, SignatureAuth, MerkleDistributor {
    error NOT_GOVERNOR();
    error ALREADY_CONFIRMED();
    error ALREADY_EXECUTED();
    error TIMELOCK_NOT_ELAPSED();
    error TIMELOCK_NOT_STARTED();
    error WRONG_STATE();
    error NOT_PROPOSER();
    error WRONG_DEPOSIT();
    error UPGRADE_VALUE_FORBIDDEN();
    error UPGRADE_DATA_REQUIRED();

    struct Proposal {
        address target;
        uint256 value;
        bytes data;
        address proposer;
        uint256 confirmations;
        ProposalState state;
        uint256 submittedAt;
        uint256 executeAfter;
        uint256 deposit;
        ActionType actionType;
    }

    address[] public governors;
    uint256 public threshold;
    uint256 public proposalCount;

    mapping(address => bool) public isGovernor;
    mapping(uint256 => mapping(address => bool)) public confirmed;
    mapping(uint256 => Proposal) public proposals;

    uint256 public constant TIMELOCK_DURATION = 1 hours;

    constructor(address[] memory _governors, uint256 _threshold) payable SignatureAuth() {
        require(_governors.length > 0, "no governors");
        require(_threshold > 0 && _threshold <= _governors.length, "invalid threshold");
        threshold = _threshold;

        for (uint256 i = 0; i < _governors.length; i++) {
            address g = _governors[i];
            require(g != address(0), "zero address governor");
            require(!isGovernor[g], "duplicate governor");
            isGovernor[g] = true;
            governors.push(g);
        }

        _setMerkleAdmin(address(this));
    }

    modifier onlyGovernor() {
        if (!isGovernor[msg.sender]) revert NOT_GOVERNOR();
        _;
    }

    function submitProposal(address _target, uint256 _value, bytes calldata _data, ActionType _actionType)
        public
        payable
        onlyGovernor
        returns (uint256 id)
    {
        if (msg.value != PROPOSAL_DEPOSIT) revert WRONG_DEPOSIT();

        if (_actionType == ActionType.Upgrade) {
            if (_value != 0) revert UPGRADE_VALUE_FORBIDDEN();
            if (_data.length < 4) revert UPGRADE_DATA_REQUIRED();
        }

        id = proposalCount++;
        _lockDeposit(id, msg.sender);
        proposals[id] = Proposal({
            target: _target,
            value: _value,
            data: _data,
            proposer: msg.sender,
            confirmations: 0,
            state: ProposalState.Pending,
            submittedAt: block.timestamp,
            executeAfter: 0,
            deposit: msg.value,
            actionType: _actionType
        });

        confirmed[id][msg.sender] = true;
        proposals[id].confirmations = 1;

        if (threshold == 1) {
            proposals[id].state = ProposalState.Queued;
            proposals[id].executeAfter = block.timestamp + TIMELOCK_DURATION;
            emit ProposalQueued(id, proposals[id].executeAfter);
        }

        emit ProposalSubmitted(id, msg.sender);
        return id;
    }

    function confirmProposal(uint256 proposalId) public onlyGovernor {
        Proposal storage prop = proposals[proposalId];

        if (prop.state != ProposalState.Pending) revert WRONG_STATE();
        if (confirmed[proposalId][msg.sender]) revert ALREADY_CONFIRMED();

        confirmed[proposalId][msg.sender] = true;
        prop.confirmations++;

        if (prop.confirmations >= threshold) {
            prop.state = ProposalState.Queued;
            prop.executeAfter = block.timestamp + TIMELOCK_DURATION;
            emit ProposalQueued(proposalId, prop.executeAfter);
        }

        emit ProposalConfirmed(proposalId, msg.sender);
    }

    function executeProposal(uint256 proposalId) external virtual onlyGovernor {
        _executeProposal(proposalId);
    }

    function executeProposalWithSignature(uint256 proposalId, address signer, bytes calldata signature)
        external
        virtual
    {
        if (!isGovernor[signer]) revert NOT_GOVERNOR();
        bytes32 action = keccak256(abi.encodePacked("execute", proposalId));
        _verifyAndConsume(signer, action, signature);
        _executeProposal(proposalId);
    }

    function _executeProposal(uint256 proposalId) internal {
        Proposal storage prop = proposals[proposalId];
        if (prop.state != ProposalState.Queued) revert WRONG_STATE();
        if (prop.executeAfter == 0) revert TIMELOCK_NOT_STARTED();
        if (block.timestamp < prop.executeAfter) revert TIMELOCK_NOT_ELAPSED();

        recordSpend(prop.value);

        prop.state = ProposalState.Executed;

        (bool success,) = prop.target.call{value: prop.value}(prop.data);
        require(success, "execution failed");

        _returnDeposit(proposalId);

        emit ProposalExecuted(proposalId);
    }

    function cancelProposal(uint256 proposalId) public onlyGovernor {
        Proposal storage prop = proposals[proposalId];
        if (prop.state == ProposalState.Executed) revert ALREADY_EXECUTED();
        if (prop.state == ProposalState.Cancelled) revert WRONG_STATE();
        if (msg.sender != prop.proposer) revert NOT_PROPOSER();

        prop.state = ProposalState.Cancelled;

        _returnDeposit(proposalId);

        emit ProposalCancelled(proposalId);
    }

    function setMerkleRoot(bytes32 root) external override onlyGovernor {
        _setMerkleRoot(root);
    }

    function getState(uint256 proposalId) public view returns (ProposalState) {
        return proposals[proposalId].state;
    }

    receive() external payable virtual {}
}
