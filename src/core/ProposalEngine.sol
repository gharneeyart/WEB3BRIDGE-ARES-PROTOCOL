// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract ProposalEngine {
    error NOT_OWNER();
    error ALREADY_CONFIRMED();
    error ALREADY_EXECUTED();
    error NOT_ENOUGH_CONFIRMATIONS();
    error TIMELOCK_NOT_ELAPSED();
    error TIMELOCK_NOT_STARTED();

    enum ProposalState {
        Pending,
        Queued,
        Executed,
        Cancelled
    }

    struct Proposal {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
        ProposalState state;
        uint256 submissionTime;
        uint256 executionTime;
    }

    address[] public owners;
    uint256 public threshold;
    uint256 public txCount;

    mapping(address => bool) public isOwner;
    mapping(uint256 => mapping(address => bool)) public confirmed;
    mapping(uint256 => Proposal) public proposals;

    uint256 public constant TIMELOCK_DURATION = 1 hours;

    event Submission(uint256 indexed txId);
    event Confirmation(uint256 indexed txId, address indexed owner);
    event Execution(uint256 indexed txId);

    constructor(address[] memory _owners, uint256 _threshold) payable {
        require(_owners.length > 0, "no owners");
        require(_threshold > 0 && _threshold <= _owners.length, "invalid threshold");
        threshold = _threshold;

        for (uint256 i = 0; i < _owners.length; i++) {
            address o = _owners[i];
            require(o != address(0), "zero address owner");
            require(!isOwner[o], "duplicate owner");
            isOwner[o] = true;
            owners.push(o);
        }
    }

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NOT_OWNER();
        _;
    }

    function submitProposal(address to, uint256 value, bytes calldata data) external onlyOwner {
        uint256 id = txCount++;
        proposals[id] = Transaction({
            to: to,
            value: value,
            data: data,
            executed: false,
            confirmations: 0,
            submissionTime: block.timestamp,
            executionTime: 0,
            state: ProposalState.Pending
        });

        confirmed[id][msg.sender] = true;
        proposals[id].confirmations = 1;

        if (threshold == 1) {
            proposals[id].executionTime = block.timestamp + TIMELOCK_DURATION;
        }

        emit Submission(id);
    }

    function confirmProposal(uint256 txId) external onlyOwner {
        Proposal storage prop = proposals[txId];
        if (prop.executed) revert ALREADY_EXECUTED();
        if (confirmed[txId][msg.sender]) revert ALREADY_CONFIRMED();

        confirmed[txId][msg.sender] = true;
        prop.confirmations++;

        if (prop.confirmations == threshold) {
            prop.executionTime = block.timestamp + TIMELOCK_DURATION;
            prop.state = ProposalState.Queued;
        }

        emit Confirmation(txId, msg.sender);
    }

    function executeProposal(uint256 txId) external virtual onlyOwner {
        Proposal storage prop = proposals[txId];
        if (prop.confirmations < threshold) revert NOT_ENOUGH_CONFIRMATIONS();
        if (prop.executed) revert ALREADY_EXECUTED();
        if (prop.executionTime == 0) revert TIMELOCK_NOT_STARTED();
        if (block.timestamp < prop.executionTime) revert TIMELOCK_NOT_ELAPSED();

        prop.executed = true;
        prop.state = ProposalState.Executed;
        (bool success,) = prop.to.call{value: prop.value}(prop.data);
        require(success, "execution failed");

        emit Execution(txId);
    }

    function queueProposal(uint256 txId) external onlyOwner {
        Proposal storage prop = proposals[txId];
        if (prop.executed) revert ALREADY_EXECUTED();
        if (prop.confirmations < threshold) revert NOT_ENOUGH_CONFIRMATIONS();

        prop.executionTime = block.timestamp + TIMELOCK_DURATION;
        prop.state = ProposalState.Queued;
    }

    function cancelProposal(uint256 txId) external onlyOwner {
        Proposal storage prop = proposals[txId];
        if (prop.executed) revert ALREADY_EXECUTED();
        prop.executed = true;
        prop.state = ProposalState.Cancelled;
    }
}
