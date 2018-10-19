// TODO
// - watchtowers
// - if time, add convenience method to allow recipient to close all threads in 1 tx
// - document assumptions around threads / persisted txCounts

pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;

import "./lib/ECTools.sol";
import "./lib/ERC20.sol";
import "./lib/SafeMath.sol";

contract ChannelManager {
    using SafeMath for uint256;

    string public constant NAME = "Channel Manager";
    string public constant VERSION = "0.0.1";

    enum Status {
       Open,
       ChannelDispute,
       ThreadDispute
    }

    struct Channel {
        uint256[3] weiBalances; // [hub, user, total]
        uint256[3] tokenBalances // [hub, user, total]
        uint256[2] txCount; // persisted onchain even when empty [global, onchain]
        bytes32 threadRoot;
        uint256 threadCount;
        address exitInitiator;
        uint256 channelClosingTime;
        uint256 threadClosingTime;
        Status status;
        mapping(address => mapping(address => Thread)) threads; // [sender, receiver]
    }

    struct Thread {
        uint256[2] weiBalances; // [hub, user]
        uint256[2] tokenBalances // [hub, user]
        uint256 txCount; // persisted onchain even when empty
        bool inDispute; // needed so we don't close threads twice
    }

    mapping(address => Channel) public channels;

    ERC20 public approvedToken;
    address public hub;

    uint256 public totalChannelWei;
    uint256 public totalChannelToken;

    bool locked;

    modifier onlyHub() {
        require(msg.sender == hub);
        _;
    }

    modifier noReentrancy() {
        require(!locked, "Reentrant call.");
        locked = true;
        _;
        locked = false;
    }

    constructor(address _hub, uint256 _challengePeriod, address _tokenAddress) public {
        hub = _hub;
        challengePeriod = _challengePeriod;
        approvedToken = ERC20(_tokenAddress);
    }

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

    function getHubReserveWei() public view returns (uint256) {
        return address(this).balance.sub(totalChannelWei);
    }

    function getHubReserveTokens() public view returns (uint256) {
        return approvedToken.balanceOf(address(this)).sub(totalChannelTokens);
    }

    // assume 1 BOOTY = 1 ETH

    // state1 {
    //                   hub / user
    //      weiBalances: [0, 0],
    //      tokenBalances: [10, 200],
    // }

    // state2 {
    //      weiBalances: [0, 0],
    //      tokenBalances: [10, 0],
    //      pendingWeiDeposits: [0, 200], <- hub deposits ETH on behalf of the user
    //      pendingTokenDeposits: [0, 0],
    //      pendingWeiWithdrawals: [0, 200],
    //      pendingTokenWithdrawals: [200, 0]
    //      proposer: hub (special flag)
    // }

    // This might allow the user to exit, but only if the deposit/exchange succeeds...
    // state3 {
    //      weiBalances: [0, 0],
    //      tokenBalances: [5, 5], <- performer earns 5 more BOOTY
    //      pendingWeiDeposits: [0, 200], <- hub deposits ETH on behalf of the user
    //      pendingTokenDeposits: [0, 0],
    //      pendingWeiWithdrawals: [0, 200],
    //      pendingTokenWithdrawals: [200, 0],
    // }

    // state3 {
    //      weiBalances: [0, 0],
    //      tokenBalances: [5, 5], <- performer earns 5 more BOOTY
    //      pendingWeiDeposits: [200, 0], <- hub deposits ETH on behalf of the user
    //      pendingTokenDeposits: [0, 0],
    //      pendingWeiExchange: [0, 200], <- wei to be credited
    //      pendingTokenExchange: [200, 0], <- tokens to be credited
    //      pendingWeiWithdrawals: [0, 200],
    //      pendingTokenWithdrawals: [200, 0],
    // }

    // balances = balances + withdrawal - deposit - exchange credit + exchange debit
    // hub wei = balances [0] + withdrawal [0] - deposit [200] - exchange credit [0] + exchange debit [200]
    channel.weiBalances[0] = weiBalances[0].add(pendingWeiWithdrawals[0]).sub(pendingWeiDeposits[0]).sub(pendingWeiExchange[0]).add(pendingWeiExchange[1]);
    // ? = 0 + 0 - 200 + 0 + 200 = 0 check!

    // New user deposits eth, hub deposits booty (into their own balances)
    // state0 {
    //      weiBalances: [0, 0],
    //      tokenBalances: [0, 0],
    //      pendingWeiDeposits: [0, 100],
    //      pendingTokenDeposits: [69, 0],
    //      pendingWeiExchange: [0, 0], <- alternatively, could do exchange onchain...
    //      pendingTokenExchange: [0, 0], <- alternatively, could do exchange onchain...
    //      pendingWeiWithdrawals: [0, 0],
    //      pendingTokenWithdrawals: [0, 0],
    // }

    // mutually acknowledge channel deposit
    // state1 {
    //      weiBalances: [0, 100],
    //      tokenBalances: [69, 0],
    // }

    // offchain exchange - hub sells user 69 token for 69 wei
    // state2 {
    //      weiBalances: [69, 31],
    //      tokenBalances: [0, 69],
    // }

    // balances = balances + withdrawal - deposit - exchange credit + exchange debit
    // hub wei = balances [0] + withdrawal [0] - deposit [200] - exchange credit [0] + exchange debit [200]
    channel.weiBalances[0] = weiBalances[0].add(pendingWeiWithdrawals[0]).sub(pendingWeiDeposits[0]).sub(pendingWeiExchange[0]).add(pendingWeiExchange[1]);
    // ? = 0 + 0 - 200 + 0 + 200 = 0 check!

    // Question:
    // - Can the user take this state and submit it themselves?
    // - I think there needs to be a flag that differentiates between states for users to submit and state the hub will submit

    // assume 1 BOOTY = 1 ETH
    // state1 { hubETH: 0, hubBOOTY: 10, userETH: 0, userBOOTY: 200 }

    // hub prepares to deposit BOOTY
    // state2 { hubETH: 0, hubBOOTY: 10, userETH: 0, userBOOTY: 200, pendingHubBOOTYDeposit: 200 }

    // user acknowledges deposit
    // state3 { hubETH: 0, hubBOOTY: 210, userETH: 0, userBOOTY: 200 }

    // USER DEPOSIT FLOW
    // assume 1 BOOTY = 1 ETH
    // state1 { hubETH: 0, hubBOOTY: 10, userETH: 0, userBOOTY: 200 }
    // state1.1 { hubETH: 0, hubBOOTY: 20, userETH: 0, userBOOTY: 190 }

    // user prepares to deposit ETH
    // state2 { hubETH: 0, hubBOOTY: 10, userETH: 0, userBOOTY: 200, pendingUserETHDeposit: 200 }
    // state2.1 { hubETH: 0, hubBOOTY: 20, userETH: 0, userBOOTY: 190, pendingUserETHDeposit: 200 }
    // Scenario: deposit success, then hub startsExit with 1.1
    // - well channel.weiBalance[1] should have increased by pendingUserETHDeposit
    // - if exit function returns all extra balance to the owner then it's fine...

    // user acknowledges deposit
    // state3 { hubETH: 0, hubBOOTY: 210, userETH: 0, userBOOTY: 200 }


    // state2 { hubETH: 0, hubBOOTY: 10, userETH: 0, userBOOTY: 0, pendingHubETHDeposit: 200, pendingUserETHWithdrawal: 200, pendingHubBOOTYWithdrawal: 200, txCount: 5 }
    // state3 { hubETH: 0, hubBOOTY: 5, userETH: 0, userBOOTY: 5, pendingHubETHDeposit: 200, pendingUserETHWithdrawal: 200, pendingHubBOOTYWithdrawal: 200, txCount: 6 }
    // ^ user needs to be able to settle with just that state

    // All funds come from the hub
    // - is it critical to have the hub be able to deposit into the user's balance in the channel?
    //   - it would be probably easier for the hub to simply send money in a state update afterwards
    // TODO add withdrawal address for the user
    // - not every state update can be used as an *authorized update*
    // - the ideally behind mutually signed states is to allow *unilateral exit* with just that state

    // BUT WAIT
    // - you can't add additional states on top of a state that has a timeout
    // - if the timeout expires, then all the other states will be invalid
    // - FAILS the user story of hub depositing into open performer channel while performer has a popping show, because timeout

    // What needs a timeout?
    // - exchange
    // - hub liability (hub agrees to deposit)


    // 1. user deposit into open channel without stopping tips
    //  - Two options:
    //    1. user calls userAuthorizedUpdate with timeout
    //    - hub deposits BOOTY at the same time
    //    - user can't tip more than total in current thread
    //    - users can't merge threads / open new threads until tx completes
    //    2. user calls deposit (no timeout)
    //    - hub separately later deposits more BOOTY
    //    - user can keep tipping / opening new threads
    //    - sometime later, they see their BOOTY limit increase
    //    3. during the timeout, fork the state, sign both
    //    - user wants to close a thread while the timeout for their deposit is pending
    //    - user signs 2 state updates with the same txCount
    //      1. includes pendingDeposit (and timeout) as part of the state
    //      2. does not include pendingDeposit as part of the state
    //    - Possible outcomes:
    //      1. Deposit succeeds
    //         1. hub can exit with the latest state from non-deposit branch
    //          - can't prevent it by making sure all balances add up
    //          - could try using two different versions
    //      2. Deposit expires
    // 2. performer withdraw out of open channel + exchange
    //  - performer has BOOTY, wants to cash out ETH
    //  - hub also wants to claim BOOTY
    // 3. hub deposit BOOTY as collateral into performer channel during show
    // 4. allow hub to reclaim ETH / BOOTY more easily when users / performers deposit/withdraw

    // Pattern:
    // - For all exchange operations or liability introducing operations, the hub will set / expect a timeout.
    //   - The user / hub will not sign any further updates until the tx succeeds or expires
    // - Anytime both parties agree, and there are no withdrawals / exchanges, can update onchain without challenge
    // - Dispute are required for unauthorized withdrawals
    function hubAuthorizedUpdate(
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
        string sigHub, // TODO - do we need this, if hub sends (they can sign it at the time)
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
        totalChannelWei = totalChannelWei.add(pendingWeiDeposits[1]);
        user.transfer(pendingWeiWithdrawals[1]);

        // update hub token channel balance, account for deposit/withdrawal in reserves
        channel.tokenBalances[0] = tokenBalances[0].add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);
        totalChannelToken = totalChannelToken.add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);

        // update user token channel balance, account for deposit/withdrawal in reserves
        channel.tokenBalances[1] = tokenBalances[1].add(pendingTokenDeposits[1]).sub(pendingTokenWithdrawals[1]);
        totalChannelToken = totalChannelToken.add(pendingTokenDeposits[1]);
        require(approvedToken.transfer(user, pendingTokenWithdrawals[1]), "user token withdrawal transfer failed");

        // update channel total balances
        channel.weiBalances[2] = channel.weiBalances[2].add(pendingWeiDeposit[0]).add(pendingWeiDeposit[1]).sub(pendingWeiWithdrawals[0]).sub(pendingWeiWithdrawals[1]);
        channel.tokenBalances[2] = channel.tokenBalances[2].add(pendingTokenDeposit[0]).add(pendingTokenDeposit[1]).sub(pendingTokenWithdrawals[0]).sub(pendingTokenWithdrawals[1]);

        // update state variables
        channel.txCount = txCount;
        channel.threadRoot = threadRoot;
        channel.threadCount = threadCount;
    }

    function userAuthorizedUpdate(
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
        // 2. protect hub against infinite liability for deposits
        require(timeout == 0 || now < timeout, "the timeout must be zero or not have passed");

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
        user.transfer(pendingWeiWithdrawals[1]);

        // update hub token channel balance, account for deposit/withdrawal in reserves
        channel.tokenBalances[0] = tokenBalances[0].add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);
        totalChannelToken = totalChannelToken.add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);

        // update user token channel balance, account for deposit/withdrawal in reserves
        channel.tokenBalances[1] = tokenBalances[1].add(pendingTokenDeposits[1]).sub(pendingTokenWithdrawals[1]);
        totalChannelToken = totalChannelToken.add(pendingTokenDeposits[1]);
        require(approvedToken.transfer(user, pendingTokenWithdrawals[1]), "user token withdrawal transfer failed");

        // update channel total balances
        channel.weiBalances[2] = channel.weiBalances[2].add(pendingWeiDeposit[0]).add(pendingWeiDeposit[1]).sub(pendingWeiWithdrawals[0]).sub(pendingWeiWithdrawals[1]);
        channel.tokenBalances[2] = channel.tokenBalances[2].add(pendingTokenDeposit[0]).add(pendingTokenDeposit[1]).sub(pendingTokenWithdrawals[0]).sub(pendingTokenWithdrawals[1]);

        // update state variables
        channel.txCount = txCount;
        channel.threadRoot = threadRoot;
        channel.threadCount = threadCount;
    }

    /**********************
     * Unilateral Functions
     *********************/

    // start exit with onchain state
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

    // TODO - is it possible to get out of a trade / timeout state?
    // - yes, because I can exit with a previous state before the exchange operation is committed to chain
    // - hub / client need to deal with this edge case

    // TODO - what if the most recent state has pending deposits / withdrawals that did or did not get finalized?
    // - how do we know they never got finalized?
    // - scenario1:
    //   1. user initiates deposit via userAuthorizedDeposit w/ no timeout
    //   2. user continues making payments / opening threads while it is being confirmed
    //   3. the deposit tx confirms, but the current offchain txCount is higher than the deposit tx
    //   4. if the hub doesn't acknlowedge the deposit, the user initiates a startExitWithUpdate
    //   5. the update still includes the pendingDeposit which finalized but wasn't acknowledged
    //
    //   1 - Chain { weiBalances: [100, 100, 200], txCount: [1, 1] }
    //   1 - Channel { weiBalances: [100, 100, 200], txCount: [1, 1] }

    //   2 - Chain { weiBalances: [100, 100, 200], txCount: [1, 1] }
    //   2 - Channel { weiBalances: [100, 100, 200], pendingDeposits: [0, 100], txCount: [2, 2] }
    //
    //   Deposit success
    //   3 - Chain { weiBalances: [100, 200, 300], txCount: [2, 2] }
    //   3 - Channel { weiBalances: [100, 100, 200], pendingDeposits: [0, 100], txCount: [2, 2] }

    //   Other offchain payment
    //   4 - Chain { weiBalances: [100, 200, 300], [2, 2] }
    //   4 - Channel { weiBalances: [110, 90, 200], pendingDeposits: [0, 100], txCount: [3, 2] }

    // - scenario2:
    //   1. user initiates deposit via userAuthorizedDeposit w/ no timeout
    //   2. user continues making payments / opening threads while it is being confirmed
    //   3. ***before*** the deposit tx confirms, the user initiates a startExitWithUpdate
    //   4. the update still includes the pendingDeposit which was never finalized

    // - in s1, the user's weiBalance[1] will include the pendingDeposit (and weiBalance[2] - the total will reflect it too)
    // - in s2, the user's weiBalance[1] will **not** include the pendingDeposit
    // - this function needs to handle both cases (and generally all non time-sensitive deposit / withdrawal)

    //   1 - Chain { weiBalances: [100, 100, 200]  txCount: [1, 1]}
    //   1 - Channel { weiBalances: [100, 100, 200], txCount: [1, 1] }

    //   2 - Chain { weiBalances: [100, 100, 200]  txCount: [1, 1]}
    //   2 - Channel { weiBalances: [100, 100, 200], pendingDeposits: [0, 100], txCount: [2, 2] }

    //   Other offchain payment
    //   3 - Chain { weiBalances: [100, 100, 200]  txCount: [1, 1]}
    //   3 - Channel { weiBalances: [110, 90, 200], pendingDeposits: [0, 100], txCount: [3, 2] }

    // WILDCARD: what if the user never follows through with their pendingDeposit, and then the hub wants to withdraw?
    // 1. hub closes their channel (byzantine) - this will work
    // 2. friendly?
    // - after this offchain state is committed to, what if the user *finally* submits the previous one?

    //   2 - Chain { weiBalances: [100, 400, 200]  txCount: [1, 1]}
    //   2 - Channel { weiBalances: [100, 350, 200], pendingWithdrawal: [0, 50], txCount: [2, 2], prevHash: 0 }

    //   3 - Chain { weiBalances: [100, 400, 200]  txCount: [1, 1], hash: lkqjfkljalsdjf }
    //  pay hub 10
    //   3 - Channel { weiBalances: [110, 340, 200], pendingWithdrawal: [0, 50], txCount: [3, 2] }

    //  withdraw more
    //   3 - Channel { weiBalances: [110, 310, 200], pendingWithdrawal: [0, 80], txCount: [4, 3] , prevHash: 0 }

    //   4.1 - user submits previous authorized onchain operation
    //   - Chain { weiBalances: [100, 350, 50], txCount: [2, 2] }
    //   - Channel { weiBalances: [110, 310, 200], pendingWithdrawal: [0, 80], txCount: [4, 3] }

    // - Scenario3: deposit + withdrawal: SUCCESS
    //   2 - Chain { weiBalances: [100, 100, 200] , [1, 1]}
    //   2 - Channel { weiBalances: [100, 100, 200], pendingDeposits: [0, 100], pendingWithdrawals: [100, 0], txCount: [2, 2] }
    //
    //   Deposit success
    //   3 - Chain { weiBalances: [0, 200, 200], [2, 2] }
    //   2 - Channel { weiBalances: [100, 100, 200], pendingDeposits: [0, 100], pendingWithdrawals: [100, 0], txCount: [2, 2] }

    //   Other offchain payment
    //   4 - Chain { weiBalances: [0, 200, 200] }
    //   4 - Channel { weiBalances: [110, 90, 200], pendingDeposits: [0, 100], pendingWithdrawals: [100, 0], txCount: [3, 2] }
    //   CORRECT
    //   4 - Channel { weiBalances: [10, 190, 200], pendingDeposits: [0, 100], pendingWithdrawals: [100, 0], txCount: 3 }

    // - Scenario4: deposit + withdrawal: FAIL
    //   2 - Chain { weiBalances: [100, 100, 200] }
    //   2 - Channel { weiBalances: [100, 100, 200], pendingDeposits: [0, 100], pendingWithdrawals: [100, 0], txCount: 2 }
    //
    //   Deposit success
    //   3 - Chain { weiBalances: [100, 100, 200] }
    //   2 - Channel { weiBalances: [100, 100, 200], pendingDeposits: [0, 100], pendingWithdrawals: [100, 0], txCount: 2 }

    //   Other offchain payment
    //   4 - Chain { weiBalances: [100, 100, 200] }
    //   4 - Channel { weiBalances: [110, 90, 200], pendingDeposits: [0, 100], pendingWithdrawals: [100, 0], txCount: 3 }

    // User has open channel
    // weiBalances: [0, 100], txCount: [1, 1]
    // weiBalances: [0, 100], pendingDeposits: [0, 100], txCount: [2, 2]
    // 1. attempt 100 ETH deposit, fails (user doesn't have enough ETH)
    // 2. user wallet says your 100 ETH deposit failed - try again? (YES) (NO)
    //    YES - tries again...
    //    NO - let's forget about it...
    // weiBalances: [0, 100], txCount: [3, 1]
    //
    // Paths:
    // 1. re-submit the old tx
    // 2. try to deposit a different amount
    // - weiBalances: [0, 100], pendingDeposits: [0, 1], txCount: [4, 2]
    //   1. submit new tx success
    //   2. old tx is submitted after new one is signed
    //    - weiBalances: [0, 100], pendingDeposits: [0, 100], txCount: [2, 2]
    //
    // 3. make payments
    // - problem, if other payments / state updates are made
    // - weiBalances: [10, 90], txCount: [10, 1]
    // 4. close out account

    // 3 operations without a timer
    // 1. hub withdraw
    // 3. user withdraw - hub can inititate, no timer needed
    // 4. hub deposit? - but what about depositing into open channels with performers?
    // - didn't want to timeout for that...
    // - hub can set timeout to 0, then it's fine...
    // - if performer can submit this state, hub is liable, needs timer
    // - In practice, this shouldn't matter, because the hub can just send the deposit themselves...
    // - UPDATED RULE - timeouts only for liabilities OUTSIDE of the hub's control (and exchange)
    // - we can add to liabilities anyways

    // with timer
    // 1. hub deposit into user balance (exchange)
    // 2. hub deposit along with user deposit
    // 3. user deposit

    // Problem - can't really rely on the offchain weiBalances values because some $$ could be in threads.
    // If we had offchain total value, that would probably be sufficient
    // - no, because deposits/withdrawals can cancel each other out...
    //
    // Idea: use a different nonce/counter to track pending txs separate from txCount
    // - pendingCounter?
    // - batchNumber
    // - chainCount, chainUpdates
    // - chainTxCount

    // Is it possible to invalidate a *onchain* txCount / pendingTx?
    // - How does this work with timeout functions?
    // - What if each onchain tx refers to each previous tx uniquely?

    // For txCount[1] -> onChain ops -> the rule is to never ever add another pending op if the current one has not been confirmed onchain
    // - it makes no difference if the pending state persists until the hub is ready / forced to exit the channel
    // - when the hub exits the channel, they can send the state which will have the pending op still attached, but it will be ignored by the startExitWithUpdate fn
    // - realistically, this only matter for user deposits, because that's the only time when the user HAS TO initiate.
    //   - UX is tricky - users want to deposit ETH / tokens
    //   - the client side can validate before this state update is actually signed
    //     - user has enough ETH / tokens to execute
    //     - enough tokens are approved
    //     - what if tx fails or user never executes?
    //     - as the user, now I try to deposit more money into the channel, I can't
    //   - at what point will the hub exit your channel for you?

    // FUCK IT
    // use a timeout for user deposits
    // hub will reject user state updates with pendingDeposit unless there is a timer

    // start exit with offchain state
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

    // party that didn't start exit can challenge and empty
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
        require(channel.status == Status.ChannelDispute, "channel must be open");
        require(channel.channelClosingTime < now, "channel closing time must have passed");

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
        channel.threadClosingTime = now.add(challengePeriod);
        channel.status == Status.ThreadDispute;
    }

    // after timer expires - anyone can call
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

    // states
    // open
    // - hubAuthorizedUpdate -> open
    // - userAuthorizedUpdate -> open
    // - startExit -> channelDispute
    // - startExitWithUpdate -> channelDispute
    // channelDispute + before channelClosingTime
    // - emptyChannelWithChallenge -> threadDispute
    // channelDispute + after channelClosingTime
    // - emptyChannel -> threadDispute
    // threadDisptue + before threadClosingTime
    // - startExitThreads -> threadDispute, thread.inDispute == true
    // - startExitThreadsWithUpdates -> threadDispute, thread.inDispute == true
    // threadDispute + before threadClosingTime, after startExitThreads/Update (thread.inDispute == true)
    // - recipientEmptyThreads -> open
    // threadDispute + after threadClosingTime
    // - emptyThreads -> open
    // threadDispute + (now > threadClosingTime + challengePeriod * 10)
    // - nukeThreads -> open

    // Question: what happens if both parties lost all thread updates and can't call startExitThreads?
    // - how can we return the channel to a useable state?
    // - should we have a different timeout
    //   - nukeThreads

    // either party starts exit with initial state
    function startExitThreads() {}

    // either party starts exit with offchain state
    function startExitThreadsWithUpdates() {}

    // after timer expires, empty with onchain state
    function emptyThreads() {}

    // recipient can empty anytime after initialization
    function recipientEmptyThreads() {}

    // anyone can call to re-open an accont stuck in threadDispute after 10x challengePeriods
    function nukeThreads() {}
