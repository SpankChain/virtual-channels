# Channel Manager v1

The ChannelManager.sol contract manages bidirectional ETH/ERC20 channels between
a single payment channel hub and its users. It also allows users who have channels with the hub to open P2P unidirectional ETH/ERC20 subchannels that we call *threads* to pay each other directly, without the hub ever having custody of the transferred funds. The ChannelManager can also be used to secure ETH/ERC20 exchange.

The contract is designed to secure *offchain* updates - that is, it offers the hub and users the ability to, at any time, decide to exit their channels and withdraw all their funds. At minimum, the contract must be able to handle these unilaterally initiated exits. 

# Overview

## Single Token Contract Per Channel Manager

To increase security, ChannelManager.sol can only support one ERC20 token. The address of the ERC20 token is set at contract construction time and cannot be modified later. This prevents malicious ERC20 smart contracts from exploiting the Channel Manager, and drastically simplifies its implementation.

## Stateful Channels

Instead of storing channels onchain by a random ID generated at the time the channel is opened, we have moved to storing channels onchain by the user's address. This means that users can only ever have **one** channel open on this contract. This has several implications:

1. Users no longer need to **open** channels, because channels are assumed to be open for all users as soon as the contract is deployed. 
2. When users want to fully withdraw their balances from the contract, the `txCount` (nonce) of the channel will be saved onchain, even as the balances are zeroed out.
3. When users want to deposit additional funds into the contract *after* they have fully withdrawn, they will need to increment the `txCount` that was previously saved onchain, picking up from where they left off.

## Authorized Updates

There are many cases, however, when the hub or a user may want to deposit into, withdraw from, checkpoint, or close a channel where the counterparty provides their consent in advance. We realized that all of these cases could be combined into two contract functions:

1. `hubAuthorizedUpdate`
2. `userAuthorizedUpdate`

These functions can be used by either party to update the onchain channel state to reflect the latest mutually signed (authorized) state update, as well as execute any authorized deposits or withdrawals.

## Pending Deposits and Withdrawals

Updates to channel balances (ie, deposits and withdrawals) are performed via a 'two-phase commit.'

In the first phase, parties sign an offchain update adding the amount to be deposited and/or withdrawn to the `pending` state fields:

1. `pendingWeiDeposits`
2. `pendingWeiWithdrawals`
3. `pendingTokenDeposits`
4. `pendingTokenWithdrawals`

In the second phase, this signed state is broadcast onchain (the  `hubAuthorizedUpdate` or `userAuthorizedUpdate` smart contract methods), and the pending transactions are executed (ie, ETH and tokens are transferred). Note that this allows a single onchain transaction to perform deposits, withdrawals, and transfers, facilitating single-transaction ETH/Token swaps.

Finally, when one party or the other notices the onchain transaction, they propose an offchain update removing the `pending` fields, and transferring any pending deposits into the useable balances:

1. `weiBalances`
2. `tokenBalances`

For more, see:

- The deposit and withdrawal examples, below **TODO: WRITE**.
- The implementation of `hubAuthorizedUpdate` and `userAuthorizedUpdate` for an example of how pending states are executed.

## Transaction Counts

Nonces have been replaced with a `txCount` tuple. `txCount[0]` represents the global nonce, and `txCount[1]` represents the onchain nonce. Whenever a state update is applied offchain, `txCount[0]` is incremented. Whenever a state update is broadcast onchain, `txCount[1]` is incremented. In normal channel operation, `txCount[1]` will only change on deposits and withdrawals. The goal of tracking offchain and onchain updates separately is to facilitate the two-phase commit described above, and allow a withdrawal from a channel without completely zeroing it out. For example, a previously-disputed channel may be re-used as long as `txCount[1]` continually increases from the point of dispute.

## Time-Sensitive Updates and Timeouts

There are two kinds of timeouts to be considered: onchain timeouts and offchain timeouts.

**Onchain Timeouts**

Any state update including a `timeout` must be submitted to chain before the timeout expires, otherwise they are considered invalid and will be rejected.

Onchain timeouts are used for two operations:

1. User deposits.

    A timeout is included with user deposits to simplify situations where the user's transaction could never succeed (ex, the deposit is for 1 ETH, but the user only has 0.5 ETH in their wallet), or situations where a transaction gets stuck in the mempool.

    Consider, for example, a situation where a user deposit is submitted onchain, but it gets stuck in the mempool. It would be possible to invent a protocol wherein the user asks the hub to sign a new state removing the pending deposit. However, if the onchain deposit eventually succeeds, the hub and user will need to reconcile this new balance, which could be especially difficult if a subsequent deposit has been submitted.

    Because a timeout is included, however, no edge cases need to be considered: either the onchain transaction is confirmed within the timeout, or it is discarded.

2. Onchain exchanges.

    A timeout is included any time a Token <> ETH exchange is made (see below) to protect both parties against market fluctuations. If a Hub-initiated onchain transaction includes an exchange (for example, a user withdrawal), a `timeout` will be included.

**Offchain Timeouts**

**TODO**

## Hub Reserve

The hub collateralizes channels via a 'reserve balance' that exists within the Channel Manager contract. The purpose of the reserve balance is to reduce the number of onchain transactions required to collateralize user channels. Previously, recollateralization blocked usage of a particular channel until the hub deposited funds via a smart contract call. Now, recollateralization can happen as part of any other channel balance update since the act of depositing funds is decoupled from the act of collateralization.

## Dispute State Machine

Unlike the previous smart contract, ChannelManager.sol only supports a single round of disputes - that is, after a dispute is initiated then the other party has only one opportunity to present a challenge rather than each challenge resetting the challenge timer. This dramatically simplifies the dispute process. Notably, however, `msg.sender` is checked in each dispute method to ensure that only the non-disputing party can enter a challenge. This temporarily prevents the use of watchtowers. Future iterations of the contract will modify this behavior to allow watchtowers.

## Example Transactions

**User Deposit**

Note: the flow is the same regardless of whether or not there is a balance in the channel.

1. User decides how much they want to deposit
2. User requests the hub to send a state update with the deposit amount included as a `pendingDeposit`
    - The Hub may also chose to include ETH or tokens as part of the deposit, which could later be exchanged offchain. For example, if the user is depositing 1 ETH, the hub may chose to deposit 69 BOOTY.

        pendingDepositWei: [0, 1 eth]
        pendingDepositToken: [69 booty, 0]
        weiBalances: [0, 0]
        tokenBalances: [0, 0]
        txCount: [1, 1]
        timeout: 5 minutes

    - Note that a timeout is included in all user deposits - regardless of whether or not the hub is making a deposit - to ensure that the channel isn't left in limbo if the onchain transaction can't succeed. For more details, see the "Time-Sensitive Operations and Timeouts" heading.

- User counter-signs the state update from the hub, then publishes to chain (along with requisite payment)
- After the deposit succeeds, either party may either:
    - Propose a state update moving the pending deposits into balances:
        - before update: pendingDepositWei: [0, 1 eth], pendingDepositToken: [69 booty, 0]
        - after update: balanceWei: [0, 1 eth], balanceToken: [69 booty, 0]
        - txCount: [2, 1]
        - **verification:**
            - Did I see this tx confirm onchain?
            - Does the onchain deposit count match?
    - Propose an exchange for BOOTY:
        - User requests an exchange (either ETH for BOOTY or BOOTY for ETH)
        - Hub sends back an  state update that represents the exchange

            unsigned

        - The wallet validates that update (making sure the exchange rate is reasonable)
        - The wallet signs that update and returns it to the hub
        - The hub countersigns and returns the update
- If the user has ETH in their balance and is under the BOOTY limit, offer to trade ETH with the hub for BOOTY
    - after deposit: weiBalances: [0, 100], tokenBalances: [69, 0]
    - propose exchange: weiBalances: [69, 31], tokenBalances: [0, 69]
- **verification:**
    - do I like this exchange price?
    - do I have enough liquidity?
    - is the user allowed to swap this much booty?
- In practice: the client will notice when the onchain deposit succeeds, then send two state updates to the hub: one confirming the deposit, and one making the exchange:

**Hub Deposit**

**Offchain Token <> ETH Swap**

**Withdrawal with Token <> ETH Swap**

# Data Structures

## Global Constants

    `address public hub; 
    uint256 public challengePeriod;
    ERC20 public approvedToken;`

There is a single privileged `hub` address set at contract deployment which can store ETH/ERC20 reserves on the contract, deposit those reserves into channels, and withdraw any unallocated reserves.

There is a single `challengePeriod` set at contract deployment and is used for all channel and thread disputes. 

There is a single `approvedToken` ERC20 token set at contract deployment which is the only token that can be used in channels for the contract. This prevents [reentrancy attacks from user-provided malicious token contracts](https://www.reddit.com/r/ethdev/comments/9mp33i/we_got_spanked_what_we_know_so_far/). 

## Constructor

    constructor(
    	address _hub, 
    	uint256 _challengePeriod, 
    	address _tokenAddress
    ) public {
      hub = _hub;
      challengePeriod = _challengePeriod;
      approvedToken = ERC20(_tokenAddress);
    }

These global constants are all set by the contract constructor at deployment. 

## Internal Accounting

    uint256 public totalChannelWei;
    uint256 public totalChannelToken;

The `totalChannelWei` and `totalChannelToken` track the total wei and tokens that has been deposited in channels by the hub and all users. 

## Modifiers

## onlyHub

Prevents the modified method from being called except by the hub registered during contract construction.

    modifier onlyHub() {
            require(msg.sender == hub);
            _;
    }

## noReentrancy

Creates a mutex around modified methods such that any reentrant calls to modified methods will fail. The mutex is released after the modified method returns.

    modifier noReentrancy() {
            require(!locked, "Reentrant call.");
            locked = true;
            _;
            locked = false;
    }

# Functions

## hubContractWithdraw

Called by the hub to release deposited ETH or ERC20s. Checks to ensure that the hub cannot withdraw more funds than are currently un-allocated to channels.

    function hubContractWithdraw(uint256 weiAmount, uint256 tokenAmount) public noReentrancy onlyHub {
            require(
                getHubReserveWei() >= weiAmount,
                "hubContractWithdraw: Contract wei funds not sufficient to withdraw"
            );
            require(
                getHubReserveTokens() >= tokenAmount,
                "hubContractWithdraw: Contract token funds not sufficient to withdraw"
            );
    
            hub.transfer(weiAmount);
            require(
                approvedToken.transfer(hub, tokenAmount),
                "hubContractWithdraw: Token transfer failure"
            );
    }

## getHubReserveWei

Returns the amount of ETH that the hub can withdraw.

    function getHubReserveWei() public view returns (uint256) {
            return address(this).balance.sub(totalChannelWei);
    }

## getHubReserveTokens

Returns the amount of ERC20 tokens that the hub can withdraw.

    function getHubReserveTokens() public view returns (uint256) {
            return approvedToken.balanceOf(address(this)).sub(totalChannelTokens);
    }

## hubAuthorizedUpdate

`hubAuthorizedUpdate` is called by the hub to update the onchain channel state to reflect the latest mutually signed state update and execute any authorized deposits or withdrawals. It works as follows:

1. First, it checks to make sure that the requested channel is both open and the state update being applied is not past its timeout.
2. It verifies the provided `sigUser`. Since the method is modified by `onlyHub`, a valid hub signature can be provided as part of the signature of the transaction itself.
3. It verifies that the incoming `txCount` variables conform to the following rules:
    1. The provided global `txCount` must always be strictly higher than the stored global `txCount`. This is because the global `txCount` is expected to increment for every state update.
    2. The provided onchain `txCount` must be greater than or equal to the stored onchain `txCount`. This is because the onchain count only increases in the event of an onchain transaction, and the vast majority of updates will be handled offchain.
4. It verifies that the offchain balances do not exceed the onchain balances.
5. It verifies that the contract holds enough Ether or tokens to collateralize the state update.
6. It updates the hub's Wei channel balances, accounting for deposits or withdrawals.
7. It updates the user's Wei channel balances, accounting for deposits or withdrawals.
8. It updates the hub's token channel balances, accounting for deposits or withdrawals.
9. It updates the user's token channel balances, accounting for deposits or withdrawals.
10. It updates the channel's total balance.
11. It stores the new `txCount`, `threadRoot`, and `threadCount`.

    function hubAuthorizedUpdate(
            address user,
            address recipient,
            uint256[2] weiBalances, // [hub, user]
            uint256[2] tokenBalances, // [hub, user]
            uint256[2] pendingWeiDeposits, // [hub, user]
            uint256[2] pendingTokenDeposits, // [hub, user]
            uint256[2] pendingWeiWithdrawals, // [hub, user]
            uint256[2] pendingTokenWithdrawals, // [hub, user]
            uint256[2] txCount, // [global, onchain] persisted onchain even when empty
            bytes32 threadRoot,
            uint256 threadCount,
            uint256 timeout,
            string sigUser
        ) public noReentrancy onlyHub {
            Channel storage channel = channels[user];
            require(channel.status == Status.Open, "channel must be open");
    
            // Usage: exchange operations to protect user from exchange rate fluctuations
            require(timeout == 0 || now < timeout, "the timeout must be zero or not have passed");
    
            // prepare state hash to check hub sig
            bytes32 state = keccak256(
                abi.encodePacked(
                    address(this),
                    user,
                    recipient,
                    weiBalances, // [hub, user]
                    tokenBalances, // [hub, user]
                    pendingWeiDeposits, // [hub, user]
                    pendingTokenDeposits, // [hub, user]
                    pendingWeiWithdrawals, // [hub, user]
                    pendingTokenWithdrawals, // [hub, user]
                    txCount, // persisted onchain even when empty
                    threadRoot,
                    threadCount,
                    timeout
                )
            );
    
            // check user sig against state hash
            require(user == ECTools.recoverSigner(state, sigUser));
    
            require(txCount[0] > channel.txCount[0], "global txCount must be higher than the current global txCount");
            require(txCount[1] >= channel.txCount[1], "onchain txCount must be higher or equal to the current onchain txCount");
    
            // offchain wei/token balances do not exceed onchain total wei/token
            require(weiBalances[0].add(weiBalances[1]) <= channel.weiBalances[2], "wei must be conserved");
            require(tokenBalances[0].add(tokenBalances[1]) <= channel.tokenBalances[2], "tokens must be conserved");
    
            // hub has enough reserves for wei/token deposits
            require(pendingWeiDeposits[0].add(pendingWeiDeposits[1]) <= getHubReserveWei(), "insufficient reserve wei for deposits");
            require(pendingTokenDeposits[0].add(pendingTokenDeposits[1]) <= getHubReserveTokens(), "insufficient reserve tokens for deposits");
    
            // check that channel balances and pending deposits cover wei/token withdrawals
            require(channel.weiBalances[0].add(pendingWeiDeposits[0]) >= weiBalances[0].add(pendingWeiWithdrawals[0]), "insufficient wei for hub withdrawal");
            require(channel.weiBalances[1].add(pendingWeiDeposits[1]) >= weiBalances[1].add(pendingWeiWithdrawals[1]), "insufficient wei for user withdrawal");
            require(channel.tokenBalances[0].add(pendingTokenDeposits[0]) >= tokenBalances[0].add(pendingTokenWithdrawals[0]), "insufficient tokens for hub withdrawal");
            require(channel.tokenBalances[1].add(pendingTokenDeposits[1]) >= tokenBalances[1].add(pendingTokenWithdrawals[1]), "insufficient tokens for user withdrawal");
    
            // update hub wei channel balance, account for deposit/withdrawal in reserves
            channel.weiBalances[0] = weiBalances[0].add(pendingWeiDeposits[0]).sub(pendingWeiWithdrawals[0]);
            totalChannelWei = totalChannelWei.add(pendingWeiDeposits[0]).sub(pendingWeiWithdrawals[0]);
    
            // update user wei channel balance, account for deposit/withdrawal in reserves
            channel.weiBalances[1] = weiBalances[1].add(pendingWeiDeposits[1]).sub(pendingWeiWithdrawals[1]);
            totalChannelWei = totalChannelWei.add(pendingWeiDeposits[1]).sub(pendingWeiWithdrawals[1]);
            recipient.transfer(pendingWeiWithdrawals[1]);
    
            // update hub token channel balance, account for deposit/withdrawal in reserves
            channel.tokenBalances[0] = tokenBalances[0].add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);
            totalChannelToken = totalChannelToken.add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);
    
            // update user token channel balance, account for deposit/withdrawal in reserves
            channel.tokenBalances[1] = tokenBalances[1].add(pendingTokenDeposits[1]).sub(pendingTokenWithdrawals[1]);
            totalChannelToken = totalChannelToken.add(pendingTokenDeposits[1]).sub(pendingTokenWithdrawals[1]);
            require(approvedToken.transfer(recipient, pendingTokenWithdrawals[1]), "user token withdrawal transfer failed");
    
            // update channel total balances
            channel.weiBalances[2] = channel.weiBalances[2].add(pendingWeiDeposit[0]).add(pendingWeiDeposit[1]).sub(pendingWeiWithdrawals[0]).sub(pendingWeiWithdrawals[1]);
            channel.tokenBalances[2] = channel.tokenBalances[2].add(pendingTokenDeposit[0]).add(pendingTokenDeposit[1]).sub(pendingTokenWithdrawals[0]).sub(pendingTokenWithdrawals[1]);
    
            // update state variables
            channel.txCount = txCount;
            channel.threadRoot = threadRoot;
            channel.threadCount = threadCount;
    }

## userAuthorizedUpdate

Similar to `hubAuthorizedUpdate`, `userAuthorizedUpdate` is called by the user to update the onchain channel state to reflect the latest mutually signed state update and execute any authorized deposits or withdrawals. The mechanism is the same as `hubAuthorizedUpdate`, however since `hubAuthorizedUpdate` checks the hub's signature by comparing `msg.sender` to the hub's address a second method that allows passing in both the hub and the user's signature directly must be provided.

    function userAuthorizedUpdate(
            address recipient,
            uint256[2] weiBalances, // [hub, user]
            uint256[2] tokenBalances, // [hub, user]
            uint256[2] pendingWeiDeposits, // [hub, user]
            uint256[2] pendingTokenDeposits, // [hub, user]
            uint256[2] pendingWeiWithdrawals, // [hub, user]
            uint256[2] pendingTokenWithdrawals, // [hub, user]
            uint256[2] txCount, // persisted onchain even when empty
            bytes32 threadRoot,
            uint256 threadCount,
            uint256 timeout,
            string sigHub,
            string sigUser // TODO - do we need this, if hub sends (they can sign it at the time)
        ) public payable noReentrancy {
            address user = msg.sender;
            require(msg.value == pendingWeiDeposits[1], "msg.value is not equal to pending user deposit");
    
            Channel storage channel = channels[user];
            require(channel.status == Status.Open, "channel must be open");
    
            // Usage:
            // 1. exchange operations to protect hub from exchange rate fluctuations
            // 2. protect hub against user failing to send the transaction in a timely manner
            require(timeout || now < timeout, "the timeout must be zero or not have passed");
    
            // prepare state hash to check hub sig
            bytes32 state = keccak256(
                abi.encodePacked(
                    address(this),
                    user,
                    recipient,
                    weiBalances, // [hub, user]
                    tokenBalances, // [hub, user]
                    pendingWeiDeposits, // [hub, user]
                    pendingTokenDeposits, // [hub, user]
                    pendingWeiWithdrawals, // [hub, user]
                    pendingTokenWithdrawals, // [hub, user]
                    txCount, // persisted onchain even when empty
                    threadRoot,
                    threadCount,
                    timeout
                )
            );
    
            // check hub and user sigs against state hash
            require(hub == ECTools.recoverSigner(state, sigHub));
            require(user == ECTools.recoverSigner(state, sigUser));
    
            require(txCount[0] > channel.txCount[0], "global txCount must be higher than the current global txCount");
            require(txCount[1] >= channel.txCount[1], "onchain txCount must be higher or equal to the current onchain txCount");
    
            // offchain wei/token balances do not exceed onchain total wei/token
            require(weiBalances[0].add(weiBalances[1]) <= channel.weiBalances[2], "wei must be conserved");
            require(tokenBalances[0].add(tokenBalances[1]) <= channel.tokenBalances[2], "tokens must be conserved");
    
            // hub has enough reserves for wei/token deposits
            require(pendingWeiDeposits[0] <= getHubReserveWei(), "insufficient reserve wei for deposits");
            require(pendingTokenDeposits[0]) <= getHubReserveTokens(), "insufficient reserve tokens for deposits");
    
            // transfer user token deposit to this contract
            require(approvedToken.transferFrom(msg.sender, address(this), pendingTokenDeposits[1]), "user token deposit failed");
    
            // check that channel balances and pending deposits cover wei/token withdrawals
            require(channel.weiBalances[0].add(pendingWeiDeposits[0]) >= weiBalances[0].add(pendingWeiWithdrawals[0]), "insufficient wei for hub withdrawal");
            require(channel.weiBalances[1].add(pendingWeiDeposits[1]) >= weiBalances[1].add(pendingWeiWithdrawals[1]), "insufficient wei for user withdrawal");
            require(channel.tokenBalances[0].add(pendingTokenDeposits[0]) >= tokenBalances[0].add(pendingTokenWithdrawals[0]), "insufficient tokens for hub withdrawal");
            require(channel.tokenBalances[1].add(pendingTokenDeposits[1]) >= tokenBalances[1].add(pendingTokenWithdrawals[1]), "insufficient tokens for user withdrawal");
    
            // update hub wei channel balance, account for deposit/withdrawal in reserves
            channel.weiBalances[0] = weiBalances[0].add(pendingWeiDeposits[0]).sub(pendingWeiWithdrawals[0]);
            totalChannelWei = totalChannelWei.add(pendingWeiDeposits[0]).sub(pendingWeiWithdrawals[0]);
    
            // update user wei channel balance, account for deposit/withdrawal in reserves
            channel.weiBalances[1] = weiBalances[1].add(pendingWeiDeposits[1]).sub(pendingWeiWithdrawals[1]);
            totalChannelWei = totalChannelWei.add(pendingWeiDeposits[1]);
            recipient.transfer(pendingWeiWithdrawals[1]);
    by
            // update hub token channel balance, account for deposit/withdrawal in reserves
            channel.tokenBalances[0] = tokenBalances[0].add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);
            totalChannelToken = totalChannelToken.add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);
    
            // update user token channel balance, account for deposit/withdrawal in reserves
            channel.tokenBalances[1] = tokenBalances[1].add(pendingTokenDeposits[1]).sub(pendingTokenWithdrawals[1]);
            totalChannelToken = totalChannelToken.add(pendingTokenDeposits[1]);
            require(approvedToken.transfer(recipient, pendingTokenWithdrawals[1]), "user token withdrawal transfer failed");
    
            // update channel total balances
            channel.weiBalances[2] = channel.weiBalances[2].add(pendingWeiDeposit[0]).add(pendingWeiDeposit[1]).sub(pendingWeiWithdrawals[0]).sub(pendingWeiWithdrawals[1]);
            channel.tokenBalances[2] = channel.tokenBalances[2].add(pendingTokenDeposit[0]).add(pendingTokenDeposit[1]).sub(pendingTokenWithdrawals[0]).sub(pendingTokenWithdrawals[1]);
    
            // update state variables
            channel.txCount = txCount;
            channel.threadRoot = threadRoot;
            channel.threadCount = threadCount;
    }

## startExit

Begins the unilateral channel withdrawal process for the currently-stored onchain state. The process starts as follows:

1. The channel's state is verified to be `Status.Open`.
2. `msg.sender` is verified to be either the hub or the user.
3. The `exitInitiator` field is set to `msg.sender`.
4. The `channelClosingTime` field is set to `now` + `challengePeriod`.
5. The status is set to `Status.ChannelDispute`.

    function startExit(
            address user
        ) public noReentrancy {
            Channel storage channel = channels[user];
            require(channel.status == Status.Open, "channel must be open");
    
            require(msg.sender == hub || msg.sender == user, "exit initiator must be user or hub");
    
            channel.exitInitiator = msg.sender;
            channel.channelClosingTime = now.add(challengePeriod);
            channel.status = Status.ChannelDispute;
    }

## startExitWithUpdate

Begins the unilateral channel withdrawal process with the provided offchain state. The process works as follows:

1. The channel's state is verified to be `Status.Open`.
2. `msg.sender` is verified to be either the hub or the user
3. The provided state's `timeout` is verified to be zero. Note that no time-sensitive states can be disputed.
4. Hub and user signatures are verified.
5. The `txCount` field is verified as per the rules described in `hubAuthorizedUpdate`.
6. The balances are verified to not exceed the channel's total balances
7. In the case where the onchain `txCount` equals the provided onchain `txCount`, the provided offchain state is force-updated by executing the provided pending deposits and withdrawals. Otherwise, pending withdrawals are rolled back into the offchain balances.
8. The onchain balance is set to the offchain balance.
9. The `exitInitiator` field is set to `msg.sender`.
10. The `channelClosingTime` field is set to `now` + `challengePeriod`.
11. The status is set to `Status.ChannelDispute`.

    function startExitWithUpdate(
            address user,
            uint256[2] weiBalances, // [hub, user]
            uint256[2] tokenBalances, // [hub, user]
            uint256[2] pendingWeiDeposits, // [hub, user]
            uint256[2] pendingTokenDeposits, // [hub, user]
            uint256[2] pendingWeiWithdrawals, // [hub, user]
            uint256[2] pendingTokenWithdrawals, // [hub, user]
            uint256[2] txCount, // [global, onchain] persisted onchain even when empty
            bytes32 threadRoot,
            uint256 threadCount,
            uint256 timeout,
            string sigHub,
            string sigUser
        ) public noReentrancy {
            Channel storage channel = channels[user];
            require(channel.status == Status.Open, "channel must be open");
    
            require(msg.sender == hub || msg.sender == user, "exit initiator must be user or hub");
    
            require(timeout == 0, "can't start exit with time-sensitive states");
    
            // prepare state hash to check hub sig
            bytes32 state = keccak256(
                abi.encodePacked(
                    address(this),
                    user,
                    weiBalances, // [hub, user]
                    tokenBalances, // [hub, user]
                    pendingWeiDeposits, // [hub, user]
                    pendingTokenDeposits, // [hub, user]
                    pendingWeiWithdrawals, // [hub, user]
                    pendingTokenWithdrawals, // [hub, user]
                    txCount, // persisted onchain even when empty
                    threadRoot,
                    threadCount,
                    timeout
                )
            );
    
            // check hub and user sigs against state hash
            require(hub == ECTools.recoverSigner(state, sigHub));
            require(user == ECTools.recoverSigner(state, sigUser));
    
            require(txCount[0] > channel.txCount[0], "global txCount must be higher than the current global txCount");
            require(txCount[1] >= channel.txCount[1], "onchain txCount must be higher or equal to the current onchain txCount");
    
            // offchain wei/token balances do not exceed onchain total wei/token
            require(weiBalances[0].add(weiBalances[1]) <= channel.weiBalances[2], "wei must be conserved");
            require(tokenBalances[0].add(tokenBalances[1]) <= channel.tokenBalances[2], "tokens must be conserved");
    
            // pending onchain txs have been executed - force update offchain state to reflect this
            if (txCount[1] == channel.txCount[1]) {
                weiBalances[0] = weiBalances[0].add(pendingWeiDeposits[0]).sub(pendingWeiWithdrawals[0]);
                weiBalances[1] = weiBalances[1].add(pendingWeiDeposits[1]).sub(pendingWeiWithdrawals[1]);
                tokenBalances[0] = tokenBalances[0].add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);
                tokenBalances[1] = tokenBalances[1].add(pendingTokenDeposits[1]).sub(pendingTokenWithdrawals[1]);
    
            // pending onchain txs have *not* been executed - revert pending withdrawals back into offchain balances
            } else {
                weiBalances[0] = weiBalances[0].add(pendingWeiWithdrawals[0]);
                weiBalances[1] = weiBalances[1].add(pendingWeiWithdrawals[1]);
                tokenBalances[0] = tokenBalances[0].add(pendingTokenWithdrawals[0]);
                tokenBalances[1] = tokenBalances[1].add(pendingTokenWithdrawals[1]);
            }
    
            // set the channel wei/token balances
            channel.weiBalances[0] = weiBalances[0];
            channel.weiBalances[1] = weiBalances[1];
            channel.tokenBalances[0] = tokenBalances[0];
            channel.tokenBalances[1] = tokenBalances[1];
    
            // update state variables
            channel.txCount = txCount;
            channel.threadRoot = threadRoot;
            channel.threadCount = threadCount;
    
            channel.exitInitiator = msg.sender;
            channel.channelClosingTime = now.add(challengePeriod);
            channel.status == Status.ChannelDispute;
    }

# emptyChannelWithChallenge

`emptyChannelWithChallenge` performs the second round in the the unilateral withdrawal game. In this case, the challenging user presents a later authorized state than was presented in `startExitWithUpdate`. Only the user who did not start the exit may call this method.

    function emptyChannelWithChallenge(
            address user,
            uint256[2] weiBalances, // [hub, user]
            uint256[2] tokenBalances, // [hub, user]
            uint256[2] pendingWeiDeposits, // [hub, user]
            uint256[2] pendingTokenDeposits, // [hub, user]
            uint256[2] pendingWeiWithdrawals, // [hub, user]
            uint256[2] pendingTokenWithdrawals, // [hub, user]
            uint256[2] txCount, // persisted onchain even when empty
            bytes32 threadRoot,
            uint256 threadCount,
            uint256 timeout,
            string sigHub,
            string sigUser
        ) public noReentrancy {
            Channel storage channel = channels[user];
            require(channel.status == Status.ChannelDispute, "channel must be in dispute");
            require(now < channel.channelClosingTime, "channel closing time must not have passed");
    
            require(msg.sender != channel.exitInitiator, "challenger can not be exit initiator");
            require(msg.sender == hub || msg.sender == user, "challenger must be either user or hub");
    
            require(timeout == 0, "can't start exit with time-sensitive states");
    
            // prepare state hash to check hub sig
            bytes32 state = keccak256(
                abi.encodePacked(
                    address(this),
                    user,
                    weiBalances, // [hub, user]
                    tokenBalances, // [hub, user]
                    pendingWeiDeposits, // [hub, user]
                    pendingTokenDeposits, // [hub, user]
                    pendingWeiWithdrawals, // [hub, user]
                    pendingTokenWithdrawals, // [hub, user]
                    txCount, // persisted onchain even when empty
                    threadRoot,
                    threadCount,
                    timeout
                )
            );
    
            // check hub and user sigs against state hash
            require(hub == ECTools.recoverSigner(state, sigHub));
            require(user == ECTools.recoverSigner(state, sigUser));
    
            require(txCount[0] > channel.txCount[0], "global txCount must be higher than the current global txCount");
            require(txCount[1] >= channel.txCount[1], "onchain txCount must be higher or equal to the current onchain txCount");
    
            // offchain wei/token balances do not exceed onchain total wei/token
            require(weiBalances[0].add(weiBalances[1]) <= channel.weiBalances[2], "wei must be conserved");
            require(tokenBalances[0].add(tokenBalances[1]) <= channel.tokenBalances[2], "tokens must be conserved");
    
            // pending onchain txs have been executed - force update offchain state to reflect this
            if (txCount[1] == channel.txCount[1]) {
                weiBalances[0] = weiBalances[0].add(pendingWeiDeposits[0]).sub(pendingWeiWithdrawals[0]);
                weiBalances[1] = weiBalances[1].add(pendingWeiDeposits[1]).sub(pendingWeiWithdrawals[1]);
                tokenBalances[0] = tokenBalances[0].add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);
                tokenBalances[1] = tokenBalances[1].add(pendingTokenDeposits[1]).sub(pendingTokenWithdrawals[1]);
            }
    
            // set the channel wei/token balances
            channel.weiBalances[0] = weiBalances[0];
            channel.weiBalances[1] = weiBalances[1];
            channel.tokenBalances[0] = tokenBalances[0];
            channel.tokenBalances[1] = tokenBalances[1];
    
            // update state variables
            channel.txCount = txCount;
            channel.threadRoot = threadRoot;
            channel.threadCount = threadCount;
    
            channel.exitInitiator = address(0x0);
            channel.channelClosingTime = 0;
            channel.threadClosingTime = now.add(challengePeriod);
            channel.status == Status.ThreadDispute;
    }

## emptyChannel

    function emptyChannel(
            address user
        ) public noReentrancy {
            Channel storage channel = channels[user];
            require(channel.status == Status.ChannelDispute, "channel must be in dispute");
    
            require(channel.channelClosingTime < now, "channel closing time must have passed");
    
            // deduct hub/user wei/tokens from total channel balances
            channel.weiBalances[2] = channel.weiBalances[2].sub(channel.weiBalances[0]).sub(channel.weiBalances[1]);
            channel.tokenBalances[2] = channel.tokenBalances[2].sub(channel.tokenBalances[0]).sub(channel.tokenBalances[1]);
    
            // transfer hub wei balance from channel to reserves
            totalChannelWei = totalChannelWei.sub(channel.weiBalances[0]);
            channel.weiBalances[0] = 0;
    
            // transfer user wei balance to user
            totalChannelWei = totalChannelWei.sub(channel.weiBalances[1]);
            user.transfer(channel.weiBalances[1]);
            channel.weiBalances[1] = 0;
    
            // transfer hub token balance from channel to reserves
            totalChannelTokens = totalChannelToken.sub(channel.tokenBalances[0]);
            channel.tokenBalances[0] = 0;
    
            // transfer user token balance to user
            totalChannelTokens = totalChannelToken.sub(channel.tokenBalances[1]);
            require(approvedToken.transfer(user, channel.tokenBalances[1]), "user token withdrawal transfer failed");
            channel.tokenBalances[1] = 0;
    
            channel.exitInitiator = address(0x0);
            channel.channelClosingTime = 0;
            channel.threadClosingTime = now.add(challengePeriod):
            channel.status = Status.ThreadDispute;
    }

## startExitThreads (TODO)

## startExitThreadsWithUpdates (TODO)

## emptyThreads (TODO)

## recipientEmptyThreads (TODO)

## nukeThreads (TODO)
