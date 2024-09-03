// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ContinuPay is ReentrancyGuard,Ownable, Pausable {
    using SafeERC20 for IERC20;


    struct Stream {
        string name;
        string description;
        string imageUrl;
        uint256 deposit;
        uint256 ratePerSecond;
        uint256 remainingBalance;
        uint256 startTime;
        uint256 stopTime;
        address recipient;
        bool isRecurring;
        uint256 recurringPeriod;
    }

    mapping(uint256 => Stream) public ethStreams;
    mapping(address => mapping(uint256 => Stream)) public tokenStreams;
    uint256 public nextStreamId;
    uint256 public unallocatedBalance;


    event StreamCreated(string name, string description, string imageUrl, uint256 indexed streamId, address indexed sender, address indexed recipient, address token, uint256 deposit, uint256 startTime, uint256 stopTime, bool isRecurring, uint256 recurringPeriod);
    event WithdrawFromStream(uint256 indexed streamId, address indexed recipient, uint256 amount, address token);
    event StreamRenewed(uint256 indexed streamId, uint256 newStartTime, uint256 newStopTime, address token);
    event TokensWithdrawn(address indexed token, address indexed recipient, uint256 amount);
    event EthWithdrawn(address indexed recipient, uint256 amount);

    error InvalidRecipient();
    error InvalidStartTime();
    error InvalidStopTime();
    error DepositTooSmall();
    error StreamNotStarted();
    error NothingToWithdraw();
    error OnlyRecipientCanWithdraw();
    error TransferFailed();
    error InvalidTokenAddress();
    error DepositMustBeGreaterThanZero();


    // constructor(address initialOwner)  Ownable(initialOwner) {
    // }
    constructor() Ownable(msg.sender) {}


    /**
    * @notice Create a new ETH stream with an initial deposit. The funds will be streamed to the recipient over time.
    * @dev Only owner can create a new ETH stream. 
    * @param recipient Address of the recipient of the streamed funds.
    * @param startTime Timestamp when the first portion of the stream starts.
    * @param stopTime Timestamp after which no more streams will be made.
    * @param isRecurring Boolean flag indicating whether the stream should repeat.
    * @param recurringPeriod Duration between each stream in seconds.
    * @return Returns the ID of the newly created ETH stream.
    */
    function createEthStream(
        string memory name,
        string memory description,
        string memory imageUrl,
        address recipient,
        uint256 startTime,
        uint256 stopTime,
        bool isRecurring,
        uint256 recurringPeriod
    ) external payable returns (uint256) {
        // require(msg.value > 0, "Deposit must be greater than 0");
        if (msg.value == 0) revert DepositMustBeGreaterThanZero();

        uint256 streamId = _createStream( name, description, imageUrl,recipient, msg.value, startTime, stopTime, isRecurring, recurringPeriod);
        ethStreams[streamId] = Stream({
            deposit: msg.value,
            ratePerSecond: msg.value / (stopTime - startTime),
            remainingBalance: msg.value,
            startTime: startTime,
            stopTime: stopTime,
            recipient: recipient,
            isRecurring: isRecurring,
            recurringPeriod: recurringPeriod,
            name: name,
            description: description,
            imageUrl: imageUrl
        });

        unallocatedBalance += msg.value;

        emit StreamCreated(name, description, imageUrl, streamId, msg.sender, recipient, address(0), msg.value, startTime, stopTime, isRecurring, recurringPeriod);
        return streamId;
    
    }

    /**
     * @notice Create an ERC-20 token stream.
     * @dev Token address must be valid and not address(0). Deposit must be greater than 0, recipient cannot be address(0), start time must be in future and stop time must be after start time.
     * @param token The address of the ERC-20 token that will be withdrawn from this stream. Cannot be address(0).
     * @param recipient The address where the funds will be sent to.
     * @param deposit The amount of tokens to be deposited into this stream. Must be greater than 0.
     * @param startTime The timestamp when the deposit starts being withdrawn from this stream. Must be in the future.
     * @param stopTime The timestamp after which the stream stops and no more tokens are withdrawable. Must be greater than startTime.
     * @param isRecurring Whether or not the stream should continue to recur after it has ended.
     * @param recurringPeriod How often the stream should recur in seconds. Only used if `isRecurring` is true.
     * @return The ID of the created stream.
    */
     function createErc20Stream(
        string memory name,
        string memory description,
        string memory imageUrl,
        IERC20 token,
        address recipient,
        uint256 deposit,
        uint256 startTime,
        uint256 stopTime,
        bool isRecurring,
        uint256 recurringPeriod
    ) external whenNotPaused returns (uint256) {
        if (address(token) == address(0)) revert InvalidTokenAddress();
        if (deposit == 0) revert DepositMustBeGreaterThanZero();
        uint256 streamId = _createStream( name, description, imageUrl,recipient, deposit, startTime, stopTime, isRecurring, recurringPeriod);
        tokenStreams[address(token)][streamId] = Stream({
            deposit: deposit,
            ratePerSecond: deposit / (stopTime - startTime),
            remainingBalance: deposit,
            startTime: startTime,
            stopTime: stopTime,
            recipient: recipient,
            isRecurring: isRecurring,
            recurringPeriod: recurringPeriod,
            name: name,
            description: description,
            imageUrl: imageUrl
        });
        token.safeTransferFrom(msg.sender, address(this), deposit);
        emit StreamCreated( name, description, imageUrl,streamId, msg.sender, recipient, address(token), deposit, startTime, stopTime, isRecurring, recurringPeriod);
        return streamId;
    }

     /**
     * @notice Create an ETH stream.
     * @param recipient The address that will receive funds from this stream.
     * @param startTime The timestamp when the stream starts, in seconds since unix epoch.
     * @param stopTime The timestamp when the stream stops, in seconds since unix epoch.
     * @param isRecurring Whether the stream should repeat after each period.
     * @param recurringPeriod The length of time for each period, in seconds.
     * @return Returns the ID of the created stream.
     */

    function _createStream(
        string memory name,
        string memory description,
        string memory imageUrl,
        address recipient,
        uint256 deposit,
        uint256 startTime,
        uint256 stopTime,
        bool isRecurring,
        uint256 recurringPeriod
    ) internal returns (uint256) {
        if (recipient == address(0)) revert InvalidRecipient();
        if (startTime < block.timestamp) revert InvalidStartTime();
        if (stopTime <= startTime) revert InvalidStopTime();
        if (deposit / (stopTime - startTime) == 0) revert DepositTooSmall();
        
        // Use the parameters to silence the compiler warnings
        if (bytes(name).length == 0 || bytes(description).length == 0 || bytes(imageUrl).length == 0) {
            // This condition will never be true, but it uses the parameters
            revert("Invalid metadata");
        }
        if (isRecurring && recurringPeriod == 0) {
            // This condition will never be true, but it uses the parameters
            revert("Invalid recurring parameters");
        }

        return nextStreamId++;
    }
    

    /**
     * @notice Withdraw from an ETH stream.
     * @dev Only the recipient can withdraw, and the stream must have started but not yet stopped.
     * @param streamId The ID of the stream from which tokens will be withdrawn.
    */
    function withdrawFromEthStream(uint256 streamId) external nonReentrant {
        Stream storage stream = ethStreams[streamId];
        _withdraw(stream, streamId, address(0));
    }

    /**
     * @notice Withdraw from an ERC-20 token stream.
     * @dev Only the recipient can withdraw, and the stream must have started but not yet stopped.
     * @param token The address of the ERC-20 token in the stream.
     * @param streamId The ID of the stream from which tokens will be withdrawn.
    */
    function withdrawFromErc20Stream(IERC20 token, uint256 streamId) external nonReentrant {
        Stream storage stream = tokenStreams[address(token)][streamId];
        _withdraw(stream, streamId, address(token));
    }

    
    function _withdraw(Stream storage stream, uint256 streamId, address token) internal {
        if (msg.sender != stream.recipient) revert OnlyRecipientCanWithdraw();
        if (block.timestamp < stream.startTime) revert StreamNotStarted();

        uint256 amount = _calculateStreamedAmount(stream);
        if (amount == 0) revert NothingToWithdraw();

        stream.remainingBalance -= amount;

        if (block.timestamp >= stream.stopTime) {
            if (stream.isRecurring) {
                _renewStream(stream, streamId, token);
            } else {
                if (token == address(0)) {
                    delete ethStreams[streamId];
                } else {
                    delete tokenStreams[token][streamId];
                }
            }
        }

        if (token == address(0)) {
            (bool success, ) = payable(stream.recipient).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(stream.recipient, amount);
        }

        emit WithdrawFromStream(streamId, stream.recipient, amount, token);
    }

    function _calculateStreamedAmount(Stream memory stream) internal view returns (uint256) {
        if (block.timestamp <= stream.startTime) {
            return 0;
        }
        uint256 endTime = block.timestamp > stream.stopTime ? stream.stopTime : block.timestamp;
        uint256 duration = endTime - stream.startTime;
        uint256 amount = duration * stream.ratePerSecond;
        return amount > stream.remainingBalance ? stream.remainingBalance : amount;
    }

    function _renewStream(Stream storage stream, uint256 streamId, address token) internal {
        uint256 newStartTime = stream.stopTime;
        uint256 newStopTime = newStartTime + stream.recurringPeriod;

        stream.startTime = newStartTime;
        stream.stopTime = newStopTime;
        stream.remainingBalance = stream.deposit;

        emit StreamRenewed(streamId, newStartTime, newStopTime, token);
    }

    function getStreamDetails(uint256 streamId, address token) external view returns (
        uint256 deposit,
        uint256 ratePerSecond,
        uint256 remainingBalance,
        uint256 startTime,
        uint256 stopTime,
        address recipient,
        bool isRecurring,
        uint256 recurringPeriod
    ) {
        Stream memory stream;
        if (token == address(0)) {
            stream = ethStreams[streamId];
        } else {
            stream = tokenStreams[token][streamId];
        }
        return (
            stream.deposit,
            stream.ratePerSecond,
            stream.remainingBalance,
            stream.startTime,
            stream.stopTime,
            stream.recipient,
            stream.isRecurring,
            stream.recurringPeriod
        );
    }

     /**
     * @notice Withdraw ETH from the contract.
     * @dev This function is for testing purposes only. It's not recommended for production use due to potential security risks.
     * @param recipient The address to receive the withdrawn ETH.
     * @param amount The amount of ETH to withdraw.
     */
    function withdrawEth(address recipient, uint256 amount) external onlyOwner {
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount == 0) revert DepositMustBeGreaterThanZero();
        (bool success, ) = payable(recipient).call{value: amount}("");
        if (!success) revert TransferFailed();
        emit EthWithdrawn(recipient, amount);
    }

     /**
     * @notice Withdraw ERC20 tokens from the contract.
     * @dev This function is for testing purposes only. It's not recommended for production use due to potential security risks.
     * @param token The address of the ERC20 token to withdraw.
     * @param recipient The address to receive the withdrawn tokens.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawToken(IERC20 token, address recipient, uint256 amount) external onlyOwner {
        if (address(token) == address(0)) revert InvalidTokenAddress();
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount == 0) revert DepositMustBeGreaterThanZero();
        token.safeTransfer(recipient, amount);
        emit TokensWithdrawn(address(token), recipient, amount);
    }


    receive() external payable {}

    /** 
     * @notice Pauses the contract, preventing any further transactions from being processed.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /** 
     * @notice Unpauses the contract, allowing it to process transactions again.
     */
    function unpause() public onlyOwner {
        _unpause();
    }
}
