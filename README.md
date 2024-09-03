## ContinuPay Smart Contract

ContinuPay is a Solidity smart contract that enables the creation and management of token streams. It supports both ETH and ERC20 token streams, allowing for continuous, time-based payments to recipients.

## Features

- Create ETH and ERC20 token streams
- Withdraw from active streams
- Recurring stream support
- Pausable functionality
- Owner-controlled contract

## Contract Overview

The ContinuPay contract is built using OpenZeppelin's libraries and includes the following main functionalities:

1. Stream Creation: Users can create streams for both ETH and ERC20 tokens.
2. Stream Withdrawal: Recipients can withdraw funds from active streams.
3. Stream Renewal: Automatic renewal of recurring streams.
4. Contract Management: Pause/unpause functionality and owner-controlled operations.

## Important Note

The contract includes `withdrawEth` and `withdrawToken` functions. These functions are implemented for testing purposes only and are not recommended for production use due to potential security risks. In a production environment, it's advisable to implement more secure fund management strategies.

## Usage

To use this contract:

1. Deploy the contract to your chosen Ethereum network.
2. Use the `createEthStream` or `createErc20Stream` functions to start a new stream.
3. Recipients can use `withdrawFromEthStream` or `withdrawFromErc20Stream` to claim their funds.
4. The contract owner can pause/unpause the contract using the `pause` and `unpause` functions.

## Security Considerations

- Ensure proper access control for owner-only functions.
- Thoroughly test the contract before deploying to mainnet.
- Consider removing or securing the withdrawal functions before production use.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## License

This project is licensed under the MIT License.
