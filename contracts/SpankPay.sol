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
        uint256 tokenBalances[3] // [hub, user, total
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
    // state1 { hubETH: 0, hubBOOTY: 10, userETH: 0, userBOOTY: 200 }
    // state1 {
    //      weiBalances: [0, 0],
    //      tokenBalances: [10, 200],
    //      pendingWeiDeposits: [0, 200], <- hub deposits ETH on behalf of the user
    //      pendingTokenDeposits: [0, 0],
    //      pendingWeiWithdrawals: [0, 200],
    //      pendingTokenWithdrawals: [200, 0],
    // }

    // Question:
    // - Can the user take this state and submit it themselves?
    // - I think there needs to be a flag that differentiates between states for users to submit and state the hub will submit

    // assume 1 BOOTY = 1 ETH
    // state1 { hubETH: 0, hubBOOTY: 10, userETH: 0, userBOOTY: 200 }
    // state2 { hubETH: 0, hubBOOTY: 10, userETH: 0, userBOOTY: 0, pendingHubETHDeposit: 200, pendingUserETHWithdrawal: 200, pendingHubBOOTYWithdrawal: 200, txCount: 5 }
    // state3 { hubETH: 0, hubBOOTY: 10, userETH: 0, userBOOTY: 0 }
    // state4 { hubETH: 0, hubBOOTY: 5, userETH: 0, userBOOTY: 5, txCount: 6 }

    // All funds come from the hub
    // - is it critical to have the hub be able to deposit into the user's balance in the channel?
    //   - it would be probably easier for the hub to simply send money in a state update afterwards
    // TODO add withdrawal address for the user
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
        string sigHub,
        string sigUser
    ) public noReentrancy onlyHub {

        Channel storage channel = channels[user];
        require(!channel.inDispute, "account must not be in dispute");

        require(now < timeout, "the timeout must not have passed");

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
                timeout,
                true // this bit is 1 if the hub proposed this state update (0 if user proposed)
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
        totalChannelWei = totalChannelWei.sub(pendingWeiDeposits[0]).add(pendingWeiWithdrawals[0]);

        // update user wei channel balance, account for deposit/withdrawal in reserves
        channel.weiBalances[1] = weiBalances[1].add(pendingWeiDeposits[1]).sub(pendingWeiWithdrawals[1]);
        totalChannelWei = totalChannelWei.sub(pendingWeiDeposits[1]).add(pendingWeiWithdrawals[1]);

        // update hub token channel balance, account for deposit/withdrawal in reserves
        channel.tokenBalances[0] = tokenBalances[0].add(pendingTokenDeposits[0]).sub(pendingTokenWithdrawals[0]);
        totalChannelToken = totalChannelToken.sub(pendingTokenDeposits[0]).add(pendingTokenWithdrawals[0]);

        // update user token channel balance, account for deposit/withdrawal in reserves
        channel.tokenBalances[1] = tokenBalances[1].add(pendingTokenDeposits[1]).sub(pendingTokenWithdrawals[1]);
        totalChannelToken = totalChannelToken.sub(pendingTokenDeposits[1]).add(pendingTokenWithdrawals[1]);

        // transfer wei/tokens to user
        user.transfer(pendingWeiWithdrawals[1]);
        require(approvedToken.transfer(user, pendingTokenWithdrawals[1]), "user token withdrawal transfer failed");

        // update channel total balances
        channel.weiBalances[2] = channel.weiBalances[0].add(channel.weiBalances[1]);
        channel.tokenBalances[2] = channel.tokenBalances[0].add(channel.tokenBalances[1]);

        // update state variables
        channel.txCount = txCount;
        channel.threadRoot = threadRoot;
        channel.threadCount = threadCount;
    }

    function userAuthorizedUpdate(

    ) public payable noReentrancy {

    }

    /*
     * Unilateral Functions
     */

    // start exit with onchain state
    function startExit() {}

    // start exit with offchain state
    function startExitWithUpdate() {}

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

