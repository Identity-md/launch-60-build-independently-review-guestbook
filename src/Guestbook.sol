// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IGuest {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Append-only messages paid for in the immutable launch token.
contract Guestbook {
    struct Entry {
        address author;
        uint256 timestamp;
        string message;
    }

    uint256 public constant POST_COST = 1 ether;
    uint256 public constant MAX_MESSAGE_BYTES = 140;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    IGuest public immutable token;
    Entry[] public entries;
    bool private entered;

    error InvalidToken();
    error MessageTooLong();
    error ReentrantCall();
    error PaymentFailed();

    event MessagePosted(uint256 indexed id, address indexed author, uint256 timestamp, string message);

    constructor(address token_) {
        if (token_ == address(0) || token_.code.length == 0) revert InvalidToken();
        token = IGuest(token_);
    }

    function entryCount() external view returns (uint256) {
        return entries.length;
    }

    /// @dev Effects and event precede the interaction; a failed payment rolls them all back.
    /// The guard also prevents a token callback from creating a nested entry.
    function post(string calldata message) external returns (uint256 id) {
        if (entered) revert ReentrantCall();
        if (bytes(message).length > MAX_MESSAGE_BYTES) revert MessageTooLong();
        entered = true;
        id = entries.length;
        entries.push(Entry(msg.sender, block.timestamp, message));
        emit MessagePosted(id, msg.sender, block.timestamp, message);
        if (!token.transferFrom(msg.sender, DEAD, POST_COST)) revert PaymentFailed();
        entered = false;
    }
}
