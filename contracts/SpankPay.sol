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

    // TODO figure out isDispute vs. status
    struct Channel {
        uint256 weiBalances[3]; // [hub, user, total]
        uint256 tokenBalances[3] // [hub, user, total]
        uint256 txCount; // persisted onchain even when empty
        bytes32 threadRoot;
        uint256 threadCount;
        address exitInitiator;
        uint256 channelClosingTime;
        uint256 threadClosingTime;
        bool isDisputed;
        mapping(address => mapping(address => Thread)) threads; // [sender, receiver]
    }

    struct Thread {
        uint256[2] weiBalances; // [hub, user]
        uint256[2] tokenBalances // [hub, user]
        uint256 txCount; // should this txCount persist to chain even when empty?
        bool isDisputed;
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
        uint256 txCount, // persisted onchain even when empty
        bytes32 threadRoot,
        uint256 threadCount,
        uint256 timeout,
        string sigHub, // TODO - do we need this, if hub sends (they can sign it at the time)
        string sigUser
    ) public noReentrancy onlyHub {
        Channel storage channel = channels[user];
        require(!channel.inDispute, "account must not be in dispute");

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

        require(txCount > channel.txCount, "txCount must be higher than the current txCount");

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
        uint256 txCount, // persisted onchain even when empty
        bytes32 threadRoot,
        uint256 threadCount,
        uint256 timeout,
        string sigHub,
        string sigUser // TODO - do we need this, if hub sends (they can sign it at the time)
    ) public payable noReentrancy {
        address user = msg.sender;
        require(msg.value == pendingWeiDeposits[1], "msg.value is not equal to pending user deposit");

        Channel storage channel = channels[user];
        require(!channel.inDispute, "account must not be in dispute");

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

        require(txCount > channel.txCount, "txCount must be higher than the current txCount");

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
        require(!channel.inDispute, "account must not be in dispute");

        require(msg.sender == hub || msg.sender == user, "exit initiator must be user or hub");

        channel.exitInitiator = msg.sender;
        channel.channelClosingTime = now.add(challengePeriod);
        channel.isDisputed = true;
    }

    // TODO - is it possible to get out of a trade / timeout state?
    // - yes, because I can exit with a previous state before the exchange operation is committed to chain
    // - hub / client need to deal with this edge case

    // TODO - what if the most recent state has pending deposits / withdrawals that never got finalized?
    // - how do we know they never got finalized?
    // - scenario1:
    //   1. user initiates deposit via userAuthorizedDeposit w/ no timeout
    //   2. user continues making payments / opening threads while it is being confirmed
    //   3. the deposit tx confirms, but the current offchain txCount is higher than the deposit tx
    //   4. if the hub doesn't acknlowedge the deposit, the user initiates a startExitWithUpdate
    //   5. the update still includes the pendingDeposit which finalized but wasn't acknowledged
    //
    //   1 - Chain { weiBalances: [100, 100, 200] }
    //   1 - Channel { weiBalances: [100, 100] }

    //   2 - Chain { weiBalances: [100, 100, 200] }
    //   2 - Channel { weiBalances: [100, 100], pendingDeposits: [0, 100] }
    //
    //   Deposit success
    //   3 - Chain { weiBalances: [100, 200, 300] }
    //   3 - Channel { weiBalances: [100, 100], pendingDeposits: [0, 100], txCount: 2 }

    //   Other offchain payment
    //   4 - Chain { weiBalances: [100, 200, 300] }
    //   4 - Channel { weiBalances: [110, 90], pendingDeposits: [0, 100], txCount: 3 }

    // - scenario2:
    //   1. user initiates deposit via userAuthorizedDeposit w/ no timeout
    //   2. user continues making payments / opening threads while it is being confirmed
    //   3. ***before*** the deposit tx confirms, the user initiates a startExitWithUpdate
    //   4. the update still includes the pendingDeposit which was never finalized
    // - in s1, the user's weiBalance[1] will include the pendingDeposit
    // - in s2, the user's weiBalance[1] will **not** include the pendingDeposit
    // - this function needs to handle both cases (and generally all non time-sensitive deposit / withdrawal)

    //   1 - Chain { weiBalances: [100, 100, 200] }
    //   1 - Channel { weiBalances: [100, 100] }

    //   2 - Chain { weiBalances: [100, 100, 200] }
    //   2 - Channel { weiBalances: [100, 100], pendingDeposits: [0, 100], txCount: 2 }

    //   Other offchain payment
    //   3 - Chain { weiBalances: [100, 100, 200] }
    //   3 - Channel { weiBalances: [110, 90], pendingDeposits: [0, 100], txCount: 3 }

    // Problem - can't really rely on the offchain weiBalances values because some $$ could be in threads.
    // If we had offchain total value, that would probably be sufficient

    // start exit with offchain state
    function startExitWithUpdate(
        address user,
        uint256[2] weiBalances, // [hub, user]
        uint256[2] tokenBalances, // [hub, user]
        uint256[2] pendingWeiDeposits, // [hub, user]
        uint256[2] pendingTokenDeposits, // [hub, user]
        uint256[2] pendingWeiWithdrawals, // [hub, user]
        uint256[2] pendingTokenWithdrawals, // [hub, user]
        uint256 txCount, // persisted onchain even when empty
        bytes32 threadRoot,
        uint256 threadCount,
        uint256 timeout,
        string sigHub,
        string sigUser
    ) public noReentrancy {
        Channel storage channel = channels[user];
        require(!channel.inDispute, "account must not be in dispute");

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

        require(txCount > channel.txCount, "txCount must be higher than the current txCount");

        // offchain wei/token balances do not exceed onchain total wei/token
        require(weiBalances[0].add(weiBalances[1]) <= channel.weiBalances[2], "wei must be conserved");
        require(tokenBalances[0].add(tokenBalances[1]) <= channel.tokenBalances[2], "tokens must be conserved");

        // normally, replace onchain w/ offchain + pending

        // add pending withdrawals back in (only if they didn't work)


        // update hub wei channel balance, account for deposit/withdrawal in reserves
        channel.weiBalances[0] = weiBalances[0].add(pendingWeiDeposits[0]).sub(pendingWeiWithdrawals[0]);

        // update user wei channel balance, account for deposit/withdrawal in reserves
        channel.weiBalances[1] = weiBalances[1].add(pendingWeiDeposits[1]).sub(pendingWeiWithdrawals[1]);

        // update hub token channel balance, account for deposit/withdrawal in reserves
        channel.tokenBalances[0] = tokenBalances[0].add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);

        // update user token channel balance, account for deposit/withdrawal in reserves
        channel.tokenBalances[1] = tokenBalances[1].add(pendingTokenDeposits[1]).sub(pendingTokenWithdrawals[1]);

        // update state variables
        channel.txCount = txCount;
        channel.threadRoot = threadRoot;
        channel.threadCount = threadCount;

        channel.exitInitiator = msg.sender;
        channel.channelClosingTime = now.add(challengePeriod);
        channel.isDisputed = true;
    }

    // after timer expires
    function emptyChannel() {}

    // party that didn't start exit can challenge and empty
    function emptyChannelWithChallenge() {}

    // either party starts exit with initial state
    function startExitThreads() {}

    // either party starts exit with offchain state
    function startExitThreadsWithUpdates() {}

    // after timer expires, empty with onchain state
    function emptyThreads() {}

    // recipient can empty anytime after initialization
    function recipientEmptyThreads() {}

