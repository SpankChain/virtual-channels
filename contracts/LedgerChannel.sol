// Refucktor!
//
// Questions:
// 1. The VC root hash only reflects the initial states of each VC - why?
//  - we could make it so the VC root hash updates every time, right?
//  - wrong, because in order to settle a VC into the LC the counterparty needs to sign
// 2.
//
// Notes:
// 1.
//

pragma solidity ^0.4.23;

import "./lib/ECTools.sol";
import "./lib/token/HumanStandardToken.sol";
import "./lib/SafeMath.sol";

/// @title Set Virtual Channels - A layer2 hub and spoke payment network

contract LedgerChannel {
    using SafeMath for uint256;

    string public constant NAME = "Ledger Channel Manager";
    string public constant VERSION = "0.0.1";

    uint256 public numChannels = 0; // TODO why does this exist

    // Let's use a single hub address per contract
    // - if we want to change the hub, then we can deploy a new contract
    // - this saves us from needing to deal with contract complexity around storing hub addresses
    // - need to think through how this affects the DB architecture
    //   - store contract address on the table to know which contract version / hub address we're using.

    // Let's move to allow multi-token channels / deposits.
    // - token whitelist enforced by the hub
    // - only affects new channels

    // I can upgrade BOOTY to have more features
    // - approveAndCall to allow single calls (per token) to the contract
    // - what about tx batching contracts? -> bulk send proxy contracts

    // Reverse the assumption that user - hub need to send eachother an init signed message
    // - the contract will store deposits separate from balances until confirmed by offchain signature
    // - deposits can be added to as many times as desired

    // two types of state updates:
    // 1. offchain, mutual
    // - consensus join
    //   -> annoying bit is about approves on tokens
    //   -> only one user can transfer at a time...
    //      - unless the hub has it's funds in a contract
    //      - but then it's the USER that needs their funds in a contract
    //      - the hub will be the one sending the tx anyway, so ETH can come from hot wallet
    //
    // - consensus close
    // - consensus update (timer -> 2 mins) + challenge
    //   - payment
    //   - exchange -> state update introduces free-option, need timer
    // 2. onchain, unilateral
    // - openChannel
    // - joinChannel
    // - startSettle
    // - challenge
    // - settle

    // SKIP - multisigs don't exist yet, fuck it.
    // Multisig interop
    // - TODO read sergey's report
    // - msg.sender can open channel on behalf of a set of delegate signers
    // - access controls (approve / revoke / bulk update)

    // SKIP - only helps avoid gas / pay in tokens for gas
    // - and requires user contract...
    // Meta Txns
    // https://github.com/austintgriffith/bouncer-proxy/blob/master/BouncerProxy/BouncerProxy.sol
    // - Need to have a separate contract w/ permissions that holds the BOOTY
    // - alternatively, we can use the payment channel as a BOOTY bank as well?
    // - booty is immediately deposited into the contract by the hub on the user's behalf
    //   - this is wont happen on the site unless we give out gift cards or allow fiat buy-in
    //   - otherwise the user will always have ETH or BOOTY to deposit themselves...
    // - what txs does a user execute, anyways?
    //   - open channel
    //   - join channel
    //   - start settle
    //   - challenge
    //   - settle
    //   - send ETH
    //   - send BOOTY / SPANK / whitelisted ERC20
    // - can't use MetaTxns without contract:
    //   - funds comes from user (open channel, join channel, send ETH, send BOOTY)
    //   - adversiaral vs. hub (start settle, challenge, settle)
    //  - so basically, the only way to avoid gas costs is to use a contract
    //  - this doesn't matter too much for users since they all should have ETH anyways
    //    - this will only change once we have a fiat onramp / gift cards

    // What if the hub is the only one allowed to create channels?
    // - assumption is that the hub is always online anyways, so why not?
    // - can I recreate a legit ETH xfer tx and broadcast it?

    // What if hub can store money on the contract to make deposits into and out of channels easier?
    // - can keep ETH / BOOTY on the contract, and then move it over.
    // - what flows does this optimize?
    //   - viewers join with ETH from their SpankPay
    //     1. User sends ETH to SpankPay
    //     1.5. WAIT
    //     2. User calls createChannel onchain
    //     3. Wait.
    //     4. Hub sees createChannel via chainsaw and calls joinChannel with ETH / BOOTY
    //     5. Wait.
    //     6. User sees joinChannel finalize, proposed a state update to exchange ETH->BOOTY
    //     7. Hub countersigns and responds.
    //     8. User can now open VCs with BOOTY and tip
    //   - instead, it would look like this:
    //     1. User sends ETH to SpankPay
    //     1.5. WAIT
    //     2. User requests signature from hub to authorize opening the channel, with timeout
    //     3. Before timeout expires, user calls openChannel w/ hub signature (will include the amount hub wants to deposit)
    //        3.1. this could fail either because timeout expires or because hub doesn't have enough funds
    //        3.2. if it fails for timeout, the wallet should request new sig and try again with more gas x2
    //              - if it fails x3 (network bogged down), then stop wasting gas on a loop... how to restart?
    //              - the wallet enters a pending state where it stops trying to open for 5 mins (displays: network slow, trying again in 5 mins)
    //              - if the user sticks around, it will start trying again in 5 mins
    //              - if the user leaves and comes back (before 5 mins), the pending state should persist
    //              - if the user leaves and comes back (after 5 mins), the pending state should go away
    //        3.3  if it fails for lack of funds, the wallet error should say so, and wait for more funds to be deposited before trying again
    //              - enter into a pending state, start a watcher process that polls the hub (or chain)
    //              - waits for hub / chain to report the hub ETH / BOOTY balance is enough to cover the channel
    //              - then requests new sig from hub and submits again
    //     4. Wait.
    //     5. User sees openChannel finalize (poll hub), proposed a state update to exchange ETH->BOOTY
    //     6. Hub countersigns and responds.
    //     7. User can now open VCs with BOOTY and tip
    //   - this is one less onchain TX for the hub, and less waiting for the user.
    // - what about the performer opening channels?
    //   - right now we have to send them a small amount of ETH so they can join
    //   - but if their initial balance is zero, then we can call openChannel for them and use our deposits.
    //  - Does the timeout matter? Even if the hub signs first.
    //    - it's more anoying than anything else, because the hub would have to track those signed openChannel txs forever
    //    - users could DOS by hoarding lots of these, then submitting all at once
    //    - with the timer, the hub can forget about openChannel txs as they expire...
    //    - this is important because the hub should have enough funds on the contract to cover all pending signed openChannel txns

    // So we can have two open functions:
    // - hubOpenChannel -> authorize user sig, assume 0 user funds to start (for performers)
    //   - I need to be convinced the performer can also exit without paying gas
    //   - how would they withdraw?
    //     1. they would sign an exchange + consensusClose
    //     2. the hub would countersign and send
    //     3. the contract would send the performer ETH to their wallet
    //     4. the wallet would send the funds out
    //   - can this be optimized to save a tx?
    //     - The performer could *optionally* supply a destination address
    //     - if they do, funds would be sent there instead of their address
    // - userOpenChannel -> authorize hub sig, transfer ETH / BOOTY from contract -> channel

    // Need to think through partial withdrawals + consensusUpdate
    // - consensusUpdate could execute a partial withdrawal anyway
    // - performer should not accept any state updates until either:
    //   1. the consensusUpdate expires
    //   2. the consensusUpdate succeeds

    // Also need support for hub to deposit / withdraw ETH / ERC20
    // - deposit (address[] tokens, uint256[] values)
    // - withdraw (ethAmount, address[] tokens, uint256[] values)
    // - maybe rescue tokens stupidly sent
    //   - make fallback not payable
    //   - tokens? keep track of tokens deposited in channels as a "totalBalance"
    //   - allow for hub to call a withdrawStupidTokens fn - if token.balanceOf(this) > totalBalance[token], withdraw the extra

    // If we don't add support for watchtowers, the timeout is 1 hour, and performers tend to be offline... we can replay attack at will
    // Add support for watchtowers? How?
    // - users who open channels designate watchtower address
    // - watchtower can be changed in channel via mutual sign
    // - the watchtower can submit a challenge, where the state provided needs to point to them as the watchtower
    // - wallet needs to broadcast all signed state messages to watchtower as well
    //   - how to ensure that states are synchronized?
    //   - wallet waits for acks from watchtower on previous states before sending new ones
    //   - testing/debugging this will be a huge bitch
    // What happens if a watchtower is hacked? How does it get switched out?
    // - watchtower notifies hub out-of-band (connext picks up phone and calls ameen)
    //   - hub calls API method for closeAllChannelsByWatchtower(address watchtower)
    // - this may require user action to copy/pasta a new watchtower address in the wallet and sign a state update
    //   - this introduces a fishing attack -> but only to replace the watchtower, so no incentive to steal funds (unless hub)
    //   - hub could be malicious and push bad wallet updates anyways...
    // How could offline payments work?
    // - can I open a VC with the seller and pay in that?
    // - attack vector:
    //   1. when seller comes back online, hub only gives it 1/2 VC payments
    //   2. the performer signs and the hub keeps that sig
    //   3. when user comes back online, hub proposed LC update to settle VC with that sig
    //  - protocol (probably re-invented hashlocks, wtf):
    //   1. buyers send signed payment directly to seller's watchtower, receives ACK
    //   2. buyers send payment hash / id to the hub
    //   3. hub requests the signed payment from the seller's watchtower by id/hash
    //   4. watchtower responds to hub with the payment message
    //   5. hub responds to user with content
    //  - How does the watchtower discovery process work?
    //    - ideas:
    //      1. onchain registry of sellers -> watchtowers
    //       - mapping(address => Watchtower) watchtowersByUser;  Watchtower { string url, address addr }
    //       - prevents MITM attacks to alter URL (again, hub (or whoever hacked it) is only one incentivized to do so
    //       - the web3 provider to SpankPay is INFURA, which means they can lie about state
    //       - would need a built-in light client to be able to not trust any third parties
    //      2. site provides address of watchtower to the SpankPay wallet
    //       - three cases (1&2 are offline payments, 3 is replay protection):
    //         1. SpankChain operated site: SpankChain can change URL to be itself, and then withold payments
    //         2. Third party site: less risky, the site could be its own watchtower (is this really a watchtower then?)
    //         3. Live Performer: performer is responsible for sending txs to watchtower
    //           1. buyer sends payment privately, directly to performer
    //           2. performer sends payment to watchtower, receives ACK (adds delay, provides offline security)
    //           3. performer sends to the hub to broadcast
    //          - UX considerations:
    //            - user can optimistically update UI to reflect payment upon sending
    //              - if payment fails, either revert /
    //            - performer can optimistically update UI to reflect payment upon receiving
    //              - if watchtower ACK is not received... the performer shouldn't go offline
    //              - show error message banner at the top of the screen (or in wallet) saying (you have de-synchronized from your watchtower)
    //              - urges you to close your channel before you go offline
    //              - if hub doesn't sign consensusClose immediately, the hub know that your watchtower is offline, and try to take advantage
    //                - in this case, start the dispute process
    //                - this should be wallet default behavior if hub doesn't comply to consensusClose EVER
    //                - this forces the performer to stay online until the dispute period is complete... 1 hour?
    //                - transaction relay networks / schedulers would be hugely helpful for this
    //                  - this is *similar* to watchtowers, but not exactly because you are still signing the dispute txns
    // Regarding watchtower network privacy - if the state is a merkle tree, you can reveal nonce without anything else
    // Because of the liveness requirements for true non-custodial payments - it's likely that we still need to recreate the private messaging between buyer-seller
    // - this reduces advantage of VCs over hashlocks... BUT - the actual flow for performers is better than hashlocks
    // Security:
    // - If it isn't possible to send payments directly, privately from SpankPay to SpankPay, then the website can always fish and receive the payment itself
    // - Questions:
    //   1. can the site snoop on HTTP requests made from inside the iframe? Can it prevent these messages from sending? MITM.
    //   2. can iframes on websites set up direct p2p encrypted tcp/webrtc/socket connections with other iframes?
    // Futility:
    // - because we're already trusting the content server to provide the correct address for the performer, the watchtower registry doesn't matter...
    // - this is the case unless the wallet is verifying the content itself
    //   - this would require a P2P marketplace
    //   - a user's "store" is an array of content each with metadata (price, previewPic, tags, videoHash)
    //   - to purchase, money needs to be sent to an address, this address needs to hold encryption keys for content and share
    //   - if I'm online, this can be me, but if I'm not, then I'm always trusting someone to act on my behalf
    // - if the wallet holds payment history, you could offline reconciliate with the performer.
    //   - you tell the perfomer "I bought your vid" and they say "no you didn't" and then you both say "weird"

    // Security Model (solve liveness, not trustlessness):
    // 1. Hub is honestly serving the site (performer addresses, watchtower urls)
    // 2. Hub sends all states to watchtowers to protect against itself getting hacked
    // 3. For offline/online payments, users pay hub, hub sends to watchtower
    // 4. When offline users reconnect, request latest state from watchtower

    // Hacked Scenarios:
    // 1. Hot wallet
    //  - drain hot wallet
    //  - send in channel funds to all counterparties
    //  - withdraw contract reserves
    //  - Replay attack all channels onchain
    //    - protected by watchtowers
    // 2. Payment routing server
    //  - stop broadcasting new VC payments to performers and watchtowers
    //  - replay attack merge viewer VC into LC
    //  - consensus close viewer LC onchain
    // 3. Website - HTML
    //  - change address of recipients to attacker wallet with an open channel
    //  - hacked hub calls consensusClose with attacker wallet
    // 4. Payment storage server
    //  - performer comes online, hub lies about most recent state
    //    - consensusClose and send themselves the funds
    //  - performer queries watchtower, gets latest state up to hack
    //  - if hub does not agree to update to latest watchtower state, close channels


    // IF YOUR TRANSACTION LASTS FOR MORE THAN FOUR HOURS, PLEASE CONTACT US AT DR@SPANKCHAIN.COM

    enum Status {
        Empty,
        Open,
        Closing
    }

    struct Account {
        uint256 userETH;
        uint256 hubETH;
        mapping (address => uint256) userTokens;
        mapping (address => uint256) hubTokens;
        uint256 txCount; // persisted onchain even when empty
        uint256 accountClosingTime;
        uint256 tabClosingTime;
        bytes32 tabRoot;
        uint256 tabCount;
        Status status;
        mapping(address => Tab) tabs;
    }

    struct Tab {
        uint256 userETH;
        uint256 recipientETH;
        mapping (address => uint256) userTokens;
        mapping (address => uint256) recipientTokens;
        uint256 txCount;
    }

    mapping (address => Account) public accounts;

    mapping (address => bool) public approvedTokens;
    address public hub;
    uint256 public challengePeriod

    uint256 public reserveETH;
    mapping (address => uint256) public reserveTokens;

    constructor(address[] _approvedTokens, address _hub, uint256 _challengePeriod) public {
        approvedToken = _approvedTokens;
        hub = _hub;
        challengePeriod = _challengePeriod;
    }

    modifier onlyHub() {
        require(msg.sender == hub);
        _;
    }

    // TODO hub approve / revoke tokens

    // TODO think about if hub ever opens an account and deposits ETH on behalf of user
    // - airdrop on to users
    // - custodial deposit (user sends us BOOTY / ETH)

    // TODO bulkHubOpenAccounts (airdrop)
    // - allow hub to open multiple user accounts at once, saving lots of txns and simplifying airdrops
    // TODO consensusUpdateWithDeposit
    // - this ...

    // What is the protocol for depositing into an open channel?
    // Use case: Performer is blowing up, lots of people are joining their channel, hub needs to deposit extra BOOTY
    // Two options:
    // 1. Offchain ACK First
    //    1. Hub prepares a consensusUpdateWithDeposit which also deposits extra booty into the account
    //    2. The hub has to hold off on sending any more payments to the performer until this update
    // 2. Onchain deposit first
    //    1. hub initiates the deposit
    //    2. hub continues opening tabs with the user as needed and sending payments
    //    3. when the deposit is confirmed, the hub requests the user's sig on a state update acknowledging the deposit
    //       3.1. the hub will stop sending payments / opening tabs with the performer until the deposit is acknowledged
    //       3.2. if the performer doesn't ack the deposit, after a certain time limit (TODO), the hub will close the channel
    //    4. once the hub's deposit is acknowledged, the hub will continue to send payments / open tabs

    // The difference between a vanilla deposit and a consensusUpdate is:
    // - consensusUpdate locks in a tabRoot, which means no new tabs can be opened while we wait for the tx to get confirmed
    // - deposit would not affect the tabRoot, so new tabs could be opened while we wait for tx to get confirmed
    // - problem with a deposit is being able to withdraw from it if the user doesn't acknowledge it
    //   - this makes the case for a separate "deposits" data structure
    //   - alternatively, we make sure the onchain balances *are greater than* the signed balances, and the remainder is returned to the owner
    // - so we still want a hubDeposit function to allow the hub to add funds to a performer account async
    // - what about users depositing into their accounts?
    //   - they too could tip / open new tabs while their deposit is pending
    //   - once it has been confirmed, they would stop until the deposit is acknowledged

    // So then for partial withdrawals, we have a few use cases:
    // 1. hub wants to rebalance liquidity between performer channels
    //  - move funds out of a performer's account and into its reserves
    //  - OR move funds out of a performer's account and directly into another performer's account
    //    - partialWithdrawal + deposit
    //    - can this be done in a single tx?
    //  - OR claim funds out of a user's account and move to a performer account
    //    - for BOOTY, this doesn't make a whole lot of sense, because performer collat is in BOOTY but user spend is in ETH
    //    - for users who generate/buy their own BOOTY and use it to tip beyond the BOOTY LIMIT we could claim the extra though
    // 2. performer wants to withdraw *some* of the money
    // 3. user wants to withdraw *some* of the money

    // Partial withdrawal protocol
    // - should partial withdrawals be prevented by open tabs? can't withdraw if you have tabs open?
    //   - what if you can withdraw whatever is in your account, but not your tabs?

    // consensusUpdate can be used for partial withdrawals
    // - what if we have a function called partialWithdrawals that wraps consensusUpdate?

    // If the hub is opening the account, all the funds come from the hub's reserves.
    // - the edge case is if users want to open a channel with tokens *only*
    // - in that case, the user should still open the channel
    // - so if NONE of the funds are coming from the user, do they need to sign?
    // - does the hub need the user's signature in order to withdraw?
    // - if the only way to update state
    //   - possible exit scenarios:
    //     1. no state updates
    //     2. state updates + consensusClose
    //     3. state updates + byzantineClose
    // - It's easier to prevent footgun if hub requires signature from user on initial state
    //   - because then I know I can always exit
    // - I should be able to settle the onchain state without requiring a mutually signed update reflecting the onchain state...
    // - So I need a function which starts the closing process and *doesn't* take a mutually signed state
    //   - startExit -> start the exit process using the onchain state, no sigs required
    //   - startExitWithUpdate -> start the exit process using offchain state, 2x sigs required
    //   - challengeExit -> challenge the exit with a higher txCount, 2x sigs required -> if success, account is immediately closed
    //   - emptyAccount -> after the challenge period expires, close/empty the account
    function hubOpenAccount(
        address user,
        uint256 userETH,
        uint256 hubETH,
        address[] userTokenAddresses,
        address[] hubTokenAddresses,
        uint256[] userTokenValues,
        uint256[] hubTokenValues,
    ) public onlyHub {
        require(reserveETH == userETH.add(hubETH), "insufficient ETH");

        // the user account must be empty
        Account storage account = accounts[user];
        require(account.Status == Status.Empty, "account must be empty");
        require(account.tabCount == 0, "account may not have open tabs");

        account.user = user;
        account.userETH = userETH;
        account.hubETH = hubETH;

        // After an Account has been emptied, some of the Threads might still be in dispute onchain...
        // How to prevent an account from being re-opened until all the Threads are closed?
        // 1. startExit / startExitWithUpdate
        // 2. emptyAccount / challengeExit
        // 3. startExitTabs / startExitTabsWithUpdate
        // 4. emptyTabs / challengeExitTabs
        //  - emptyTabs could be called once at the end of the timeout for all open tabs (loop over array)
        //    - can I do this without an array? (send array of tab recipient addresses to empty?)
        //  - challengeExitTab is called (also with an array of tab recipients?)
        // Need to give the user/hub time to dispute threads

        // When I do startExit, where does the offchain state get saved?
        // If there were onchain deposits that are not reflected in the offchain state, they can't be overwritten...
        // - so I need to save the deposits / separate to the actual balances...

    }

    // If the user is opening the account, the user and hub fund their own balances.
    function userOpenAccount() public {
        uint256 hubETH,
        address[] userTokenAddresses,
        address[] hubTokenAddresses,
        uint256[] userTokenValues,
        uint256[] hubTokenValues,

    }


    function createChannel(
        bytes32 _lcID,
        address _partyI, // TODO can remove this, leaving in to preserve interface
        uint256 _confirmTime,
        address _token,
        uint256[2] _balances // [eth, token]
    )
        public
        payable
    {
        require(Channels[_lcID].status == ChannelStatus.Nonexistent, "Channel already exists");
        require(_token == approvedToken, "Token is not whitelisted");
        require(_partyI == hubAddress, "Channel must be created with hub");

        // Set initial ledger channel state
        // Alice must execute this and we assume the initial state
        // to be signed from this requirement
        // Alternative is to check a sig as in joinChannel
        Channels[_lcID].status = ChannelStatus.Opened;

        Channels[_lcID].partyAddresses[0] = msg.sender;
        Channels[_lcID].partyAddresses[1] = _partyI;

        Channels[_lcID].sequence = 0;
        Channels[_lcID].confirmTime = _confirmTime;
        // is close flag, lc state sequence, number open vc, vc root hash, partyA...
        //Channels[_lcID].stateHash = keccak256(uint256(0), uint256(0), uint256(0), bytes32(0x0), bytes32(msg.sender), bytes32(_partyI), balanceA, balanceI);
        Channels[_lcID].LCopenTimeout = now.add(_confirmTime);
        Channels[_lcID].initialDeposit = _balances;

        Channels[_lcID].token = HumanStandardToken(_token);

        require(msg.value == _balances[0], "Eth balance does not match sent value");
        Channels[_lcID].ethBalances[0] = msg.value;

        require(Channels[_lcID].token.transferFrom(msg.sender, this, _balances[1]),"CreateChannel: token transfer failure");
        Channels[_lcID].erc20Balances[0] = _balances[1];

        emit DidLCOpen(_lcID, msg.sender, _partyI, _balances[0], _token, _balances[1], Channels[_lcID].LCopenTimeout);
    }

    function LCOpenTimeout(bytes32 _lcID) public {
        require(msg.sender == Channels[_lcID].partyAddresses[0], "Request not sent by channel party A");
        require(Channels[_lcID].status == ChannelStatus.Opened, "Channel status must be Opened");
        require(now > Channels[_lcID].LCopenTimeout, "Channel timeout has not expired");

        // reentrancy protection
        Channels[_lcID].status = ChannelStatus.Settled;
        uint256 ethbalanceA = Channels[_lcID].ethBalances[0];
        uint256 tokenbalanceA = Channels[_lcID].erc20Balances[0];

        Channels[_lcID].ethBalances[0] = 0;
        Channels[_lcID].ethBalances[1] = 0;
        Channels[_lcID].ethBalances[2] = 0;
        Channels[_lcID].ethBalances[3] = 0;
        Channels[_lcID].erc20Balances[0] = 0;
        Channels[_lcID].erc20Balances[1] = 0;
        Channels[_lcID].erc20Balances[2] = 0;
        Channels[_lcID].erc20Balances[3] = 0;

        Channels[_lcID].partyAddresses[0].transfer(ethbalanceA);
        require(Channels[_lcID].token.transfer(Channels[_lcID].partyAddresses[0], tokenbalanceA), "CreateChannel: token transfer failure");

        emit DidLCClose(_lcID, 0, ethbalanceA, tokenbalanceA, 0, 0);
    }

    // TODO need settle 0 state function (leave joined channel that doesn't have updates)

    function joinChannel(bytes32 _lcID, uint256[2] _balances) public payable {
        // require the channel is not open yet
        require(Channels[_lcID].status == ChannelStatus.Opened, "Channel status must be Opened");
        require(msg.sender == Channels[_lcID].partyAddresses[1], "Channel can only be joined by counterparty");

        // no longer allow joining functions to be called
        Channels[_lcID].status = ChannelStatus.Joined;
        numChannels = numChannels.add(1);

        // TODO: can separate these by party
        Channels[_lcID].initialDeposit[0] = Channels[_lcID].initialDeposit[0].add(_balances[0]);
        Channels[_lcID].initialDeposit[1] = Channels[_lcID].initialDeposit[1].add(_balances[1]);

        require(msg.value == _balances[0], "State balance does not match sent value");
        Channels[_lcID].ethBalances[1] = msg.value;

        require(Channels[_lcID].token.transferFrom(msg.sender, this, _balances[1]), "joinChannel: token transfer failure");
        Channels[_lcID].erc20Balances[1] = _balances[1];

        emit DidLCJoin(_lcID, _balances[0], _balances[1]);
    }


    // additive updates of monetary state
    // TODO check to figure out if party can push counterparty to unrecoverable state with malicious deposit
    function deposit(
        bytes32 _lcID,
        address recipient,
        uint256[2] _balances // [eth, token]
    )
        public
        payable
    {
        require(Channels[_lcID].status == ChannelStatus.Joined, "Channel status must be Joined");
        require(
            recipient == Channels[_lcID].partyAddresses[0] || recipient == Channels[_lcID].partyAddresses[1],
            "Recipient must be channel member"
        );
        require(
            msg.sender == Channels[_lcID].partyAddresses[0] || msg.sender == Channels[_lcID].partyAddresses[1],
            "Sender must be channel member"
        );

        if (Channels[_lcID].partyAddresses[0] == recipient) {
            require(msg.value == _balances[0], "State balance does not match sent value");
            Channels[_lcID].ethBalances[2] = Channels[_lcID].ethBalances[2].add(msg.value);

            require(Channels[_lcID].token.transferFrom(msg.sender, this, _balances[1]), "deposit: token transfer failure");
            Channels[_lcID].erc20Balances[2] = Channels[_lcID].erc20Balances[2].add(_balances[1]);
        } else if (Channels[_lcID].partyAddresses[1] == recipient) {
            require(msg.value == _balances[0], "State balance does not match sent value");
            Channels[_lcID].ethBalances[3] = Channels[_lcID].ethBalances[3].add(msg.value);

            require(Channels[_lcID].token.transferFrom(msg.sender, this, _balances[1]), "deposit: token transfer failure");
            Channels[_lcID].erc20Balances[3] = Channels[_lcID].erc20Balances[3].add(_balances[1]);
        }

        emit DidLCDeposit(_lcID, recipient, _balances[0], _balances[1]);
    }

    // TODO: Check there are no open virtual channels, the client should have cought this before signing a close LC state update
    function consensusCloseChannel(
        bytes32 _lcID,
        uint256 _sequence,
        uint256[4] _balances, // 0: ethBalanceA 1:ethBalanceI 2:tokenBalanceA 3:tokenBalanceI
        string _sigA,
        string _sigI
    )
        public
    {
        // assume num open vc is 0 and root hash is 0x0
        //require(Channels[_lcID].sequence < _sequence);
        require(Channels[_lcID].status == ChannelStatus.Joined, "Channel status must be Joined");

        uint256 totalEthDeposit = Channels[_lcID].initialDeposit[0].add(Channels[_lcID].ethBalances[2]).add(Channels[_lcID].ethBalances[3]);
        uint256 totalTokenDeposit = Channels[_lcID].initialDeposit[1].add(Channels[_lcID].erc20Balances[2]).add(Channels[_lcID].erc20Balances[3]);
        require(totalEthDeposit == _balances[0].add(_balances[1]), "On-chain balances not equal to provided balances");
        require(totalTokenDeposit == _balances[2].add(_balances[3]), "On-chain balances not equal to provided balances");

        bytes32 _state = keccak256(
            abi.encodePacked(
                _lcID,
                true,
                _sequence,
                uint256(0),
                bytes32(0x0),
                Channels[_lcID].partyAddresses[0],
                Channels[_lcID].partyAddresses[1],
                _balances[0],
                _balances[1],
                _balances[2],
                _balances[3]
            )
        );

        require(Channels[_lcID].partyAddresses[0] == ECTools.recoverSigner(_state, _sigA), "Party A signature invalid");
        require(Channels[_lcID].partyAddresses[1] == ECTools.recoverSigner(_state, _sigI), "Party I signature invalid");

        // this will prevent reentrancy
        Channels[_lcID].status = ChannelStatus.Settled;
        numChannels = numChannels.sub(1);

        Channels[_lcID].ethBalances[0] = 0; // TODO add comments to array, extract into function
        Channels[_lcID].ethBalances[1] = 0;
        Channels[_lcID].ethBalances[2] = 0;
        Channels[_lcID].ethBalances[3] = 0;
        Channels[_lcID].erc20Balances[0] = 0;
        Channels[_lcID].erc20Balances[1] = 0;
        Channels[_lcID].erc20Balances[2] = 0;
        Channels[_lcID].erc20Balances[3] = 0;

        Channels[_lcID].partyAddresses[0].transfer(_balances[0]);
        Channels[_lcID].partyAddresses[1].transfer(_balances[1]);

        require(
            Channels[_lcID].token.transfer(Channels[_lcID].partyAddresses[0], _balances[2]),
            "consensusCloseChannel: token transfer failure"
        );
        require(
            Channels[_lcID].token.transfer(Channels[_lcID].partyAddresses[1], _balances[3]),
            "consensusCloseChannel: token transfer failure"
        );

        emit DidLCClose(_lcID, _sequence, _balances[0], _balances[1], _balances[2], _balances[3]);
    }

    // Byzantine functions
    // TODO only allowing one update. should not block launch.
    function updateLCstate(
        bytes32 _lcID,
        uint256[6] updateParams, // [sequence, numOpenVc, ethbalanceA, ethbalanceI, tokenbalanceA, tokenbalanceI]
        bytes32 _VCroot,
        string _sigA,
        string _sigI
    )
        public
    {
        Channel storage channel = Channels[_lcID];
        require(
            channel.status == ChannelStatus.Joined || channel.status == ChannelStatus.Settling,
            "Channel status must be Joined or Settling"
        );
        require(channel.sequence < updateParams[0], "Sequence must be higher"); // do same as vc sequence check

        // TODO: need to check deposits here, add them
        require(
            channel.ethBalances[0].add(channel.ethBalances[1]) >= updateParams[2].add(updateParams[3]),
            "On-chain eth balances must be higher than provided balances"
        ); // TODO should this be equal?
        require(
            channel.erc20Balances[0].add(channel.erc20Balances[1]) >= updateParams[4].add(updateParams[5]),
            "On-chain token balances must be higher than provided balances"
        );

        // Question: If the channel is settling, we have to wait until the timeout expires before updating it again?
        // - why is this the case?
        // - how is updateLCState used?
        //   1. The first time updateLCState is called, updateLCtimeout is set to now + confirmTime (which is set at opening)
        //   2. If the channel is already settling, updateLCState must be called again before the timeout expires
        //      2.1. The channel timeout will be reset
        //   3. After the channel timeout expires, we can add VC updates / close VC channels
        //      3.1. call initVC for each VC - this starts the VC timeout (for each VC) and sets it to now + confirmTime
        //      3.2. call settleVC for each VC - this resets the VC timeout
        //      3.3. after the VC timeout expires, call closeVC
        //   4. After the channel timeout expires & all VCs are closed, we can call byzantineClose
        // - what happens if there are no VCs?
        //   - If no VCs, then call updateLCState, wait for updateLCtimeout to expire, then call byzantineClose

        if (channel.status == ChannelStatus.Settling) {
            require(channel.updateLCtimeout > now, "Update timeout not expired");
        }

        bytes32 _state = keccak256(
            abi.encodePacked(
                _lcID,
                false,
                updateParams[0],
                updateParams[1],
                _VCroot,
                channel.partyAddresses[0],
                channel.partyAddresses[1],
                updateParams[2],
                updateParams[3],
                updateParams[4],
                updateParams[5]
            )
        );

        require(channel.partyAddresses[0] == ECTools.recoverSigner(_state, _sigA), "Party A signature invalid");
        require(channel.partyAddresses[1] == ECTools.recoverSigner(_state, _sigI), "Party I signature invalid");

        //TODO how do we check to make sure someone doesn't accidentally add a messed up vcRootHash?

        // update LC state
        channel.sequence = updateParams[0];
        channel.numOpenVC = updateParams[1];
        channel.ethBalances[0] = updateParams[2];
        channel.ethBalances[1] = updateParams[3];
        channel.erc20Balances[0] = updateParams[4];
        channel.erc20Balances[1] = updateParams[5];
        channel.VCrootHash = _VCroot;
        channel.status = ChannelStatus.Settling;
        channel.updateLCtimeout = now.add(channel.confirmTime);

        // make settlement flag

        emit DidLCUpdateState (
            _lcID,
            updateParams[0],
            updateParams[1],
            updateParams[2],
            updateParams[3],
            updateParams[4],
            updateParams[5],
            _VCroot,
            channel.updateLCtimeout
        );
    }

    // supply initial state of VC to "prime" the force push game
    // TODO: combine with settleVC
    function initVCstate(
        bytes32 _lcID,
        bytes32 _vcID,
        bytes _proof,
        address _partyA,
        address _partyB,
        uint256[2] _bond,
        uint256[4] _balances, // 0: ethBalanceA 1:ethBalanceB 2:tokenBalanceA 3:tokenBalanceB
        string sigA
    )
        public
    {
        // sub-channel must be open
        require(Channels[_lcID].status == ChannelStatus.Settling, "Channel status must be Settling");
        require(virtualChannels[_vcID].status != VirtualChannelStatus.Settled, "VC is closed");
        // Check time has passed on updateLCtimeout and has not passed the time to store a vc state
        require(Channels[_lcID].updateLCtimeout < now, "Update LC timeout not expired");
        // prevent rentry of initializing vc state
        require(virtualChannels[_vcID].updateVCtimeout == 0, "Update VC timeout not expired");
        // partyB is now Ingrid
        bytes32 _initState = keccak256(
            abi.encodePacked(_vcID, uint256(0), _partyA, _partyB, _bond[0], _bond[1], _balances[0], _balances[1], _balances[2], _balances[3])
        );

        // Make sure Alice has signed initial vc state (A/B in oldState)
        require(_partyA == ECTools.recoverSigner(_initState, sigA), "Party A signature invalid");

        // Check the oldState is in the root hash
        require(_isContained(_initState, _proof, Channels[_lcID].VCrootHash) == true, "Old state is not contained in root hash");

        virtualChannels[_vcID].status = VirtualChannelStatus.Settling;
        virtualChannels[_vcID].partyA = _partyA; // VC participant A
        virtualChannels[_vcID].partyB = _partyB; // VC participant B
        virtualChannels[_vcID].sequence = uint256(0);
        virtualChannels[_vcID].ethBalances[0] = _balances[0];
        virtualChannels[_vcID].ethBalances[1] = _balances[1];
        virtualChannels[_vcID].erc20Balances[0] = _balances[2];
        virtualChannels[_vcID].erc20Balances[1] = _balances[3];
        virtualChannels[_vcID].bond = _bond;
        virtualChannels[_vcID].updateVCtimeout = now.add(Channels[_lcID].confirmTime);

        emit DidVCInit(_lcID, _vcID, _proof, uint256(0), _partyA, _partyB, _balances[0], _balances[1]);
    }

    // TODO: verify state transition since the hub did not agree to this state
    // make sure the A/B balances are not beyond ingrids bonds
    // Params: vc init state, vc final balance, vcID
    function settleVC(
        bytes32 _lcID,
        bytes32 _vcID,
        uint256 updateSeq,
        address _partyA,
        address _partyB,
        uint256[4] updateBal, // [ethupdateBalA, ethupdateBalB, tokenupdateBalA, tokenupdateBalB]
        string sigA
    )
        public
    {
        // sub-channel must be open
        require(Channels[_lcID].status == ChannelStatus.Settling, "Channel status must be Settling");
        require(virtualChannels[_vcID].status == VirtualChannelStatus.Settling, "Virtual channel status must be Settling");

        // TODO: Can remove this once we implement logic to only allow one settle call
        require(virtualChannels[_vcID].sequence < updateSeq, "VC sequence is higher than update sequence.");

        require(
            virtualChannels[_vcID].ethBalances[1] < updateBal[1] && virtualChannels[_vcID].erc20Balances[1] < updateBal[3],
            "State updates may only increase recipient balance."
        );
        require(
            virtualChannels[_vcID].bond[0] == updateBal[0].add(updateBal[1]) &&
            virtualChannels[_vcID].bond[1] == updateBal[2].add(updateBal[3]),
            "Incorrect balances for bonded amount"
        );
        // Check time has passed on updateLCtimeout and has not passed the time to store a vc state
        // virtualChannels[_vcID].updateVCtimeout should be 0 on uninitialized vc state, and this should
        // fail if initVC() isn't called first
        require(now < virtualChannels[_vcID].updateVCtimeout, "Timeouts not expired");

        bytes32 _updateState = keccak256(
            abi.encodePacked(
                _vcID,
                updateSeq,
                _partyA,
                _partyB,
                virtualChannels[_vcID].bond[0],
                virtualChannels[_vcID].bond[1],
                updateBal[0],
                updateBal[1],
                updateBal[2],
                updateBal[3]
            )
        );

        // Make sure Alice has signed a higher sequence new state
        require(virtualChannels[_vcID].partyA == ECTools.recoverSigner(_updateState, sigA), "Party A signature invalid");

        // TODO remove challenger from vc struct and getter

        // TODO: remove this, only can call this function once
        virtualChannels[_vcID].sequence = updateSeq;

        // channel state
        virtualChannels[_vcID].ethBalances[0] = updateBal[0];
        virtualChannels[_vcID].ethBalances[1] = updateBal[1];
        virtualChannels[_vcID].erc20Balances[0] = updateBal[2];
        virtualChannels[_vcID].erc20Balances[1] = updateBal[3];

        // TODO: remove this, only can call this function once
        virtualChannels[_vcID].updateVCtimeout = now.add(Channels[_lcID].confirmTime);

        emit DidVCSettle(_lcID, _vcID, updateSeq, updateBal[0], updateBal[1], msg.sender, virtualChannels[_vcID].updateVCtimeout);
    }

    function closeVirtualChannel(bytes32 _lcID, bytes32 _vcID) public {
        require(Channels[_lcID].status == ChannelStatus.Settling, "Channel status must be Settling");
        require(virtualChannels[_vcID].status == VirtualChannelStatus.Settling, "Virtual channel status must be Settling");
        require(virtualChannels[_vcID].updateVCtimeout < now, "Update VC timeout has not expired.");

        // reduce the number of open virtual channels stored on LC
        Channels[_lcID].numOpenVC = Channels[_lcID].numOpenVC.sub(1);
        // close vc
        virtualChannels[_vcID].status = VirtualChannelStatus.Settled;

        // re-introduce the balances back into the LC state from the settled VC
        // decide if this lc is alice or bob in the vc
        // TODO: refactor into using the indices as variables
        if(virtualChannels[_vcID].partyA == Channels[_lcID].partyAddresses[0]) {
            Channels[_lcID].ethBalances[0] = Channels[_lcID].ethBalances[0].add(virtualChannels[_vcID].ethBalances[0]);
            Channels[_lcID].ethBalances[1] = Channels[_lcID].ethBalances[1].add(virtualChannels[_vcID].ethBalances[1]);

            Channels[_lcID].erc20Balances[0] = Channels[_lcID].erc20Balances[0].add(virtualChannels[_vcID].erc20Balances[0]);
            Channels[_lcID].erc20Balances[1] = Channels[_lcID].erc20Balances[1].add(virtualChannels[_vcID].erc20Balances[1]);
        } else if (virtualChannels[_vcID].partyB == Channels[_lcID].partyAddresses[0]) {
            Channels[_lcID].ethBalances[0] = Channels[_lcID].ethBalances[0].add(virtualChannels[_vcID].ethBalances[1]);
            Channels[_lcID].ethBalances[1] = Channels[_lcID].ethBalances[1].add(virtualChannels[_vcID].ethBalances[0]);

            Channels[_lcID].erc20Balances[0] = Channels[_lcID].erc20Balances[0].add(virtualChannels[_vcID].erc20Balances[1]);
            Channels[_lcID].erc20Balances[1] = Channels[_lcID].erc20Balances[1].add(virtualChannels[_vcID].erc20Balances[0]);
        }

        emit DidVCClose(_lcID, _vcID, virtualChannels[_vcID].erc20Balances[0], virtualChannels[_vcID].erc20Balances[1]);
    }

    // TODO: allow either LC end-user to nullify the settled LC state and return to off-chain
    function byzantineCloseChannel(bytes32 _lcID) public {
        Channel storage channel = Channels[_lcID];

        // check settlement flag
        require(channel.status == ChannelStatus.Settling, "Channel status must be Settling");
        require(channel.numOpenVC == 0, "Open VCs must be 0");
        require(channel.updateLCtimeout < now, "LC timeout not over.");

        // if off chain state update didnt reblance deposits, just return to deposit owner
        uint256 totalEthDeposit = channel.initialDeposit[0].add(channel.ethBalances[2]).add(channel.ethBalances[3]);
        uint256 totalTokenDeposit = channel.initialDeposit[1].add(channel.erc20Balances[2]).add(channel.erc20Balances[3]);

        uint256 possibleTotalEthBeforeDeposit = channel.ethBalances[0].add(channel.ethBalances[1]);
        uint256 possibleTotalTokenBeforeDeposit = channel.erc20Balances[0].add(channel.erc20Balances[1]);

        if (possibleTotalEthBeforeDeposit < totalEthDeposit) {
            channel.ethBalances[0] = channel.ethBalances[0].add(channel.ethBalances[2]);
            channel.ethBalances[1] = channel.ethBalances[1].add(channel.ethBalances[3]);
        } else {
            require(possibleTotalEthBeforeDeposit == totalEthDeposit, "Eth deposit must add up");
        }

        if (possibleTotalTokenBeforeDeposit < totalTokenDeposit) {
            channel.erc20Balances[0] = channel.erc20Balances[0].add(channel.erc20Balances[2]);
            channel.erc20Balances[1] = channel.erc20Balances[1].add(channel.erc20Balances[3]);
        } else {
            require(possibleTotalTokenBeforeDeposit == totalTokenDeposit, "Token deposit must add up");
        }

        // reentrancy
        channel.status = ChannelStatus.Settled;
        numChannels = numChannels.sub(1);

        uint256 ethbalanceA = channel.ethBalances[0];
        uint256 ethbalanceI = channel.ethBalances[1];
        uint256 tokenbalanceA = channel.erc20Balances[0];
        uint256 tokenbalanceI = channel.erc20Balances[1];

        channel.ethBalances[0] = 0;
        channel.ethBalances[1] = 0;
        channel.ethBalances[2] = 0;
        channel.ethBalances[3] = 0;
        channel.erc20Balances[0] = 0;
        channel.erc20Balances[1] = 0;
        channel.erc20Balances[2] = 0;
        channel.erc20Balances[3] = 0;

        if (ethbalanceA != 0 || ethbalanceI != 0) {
            channel.partyAddresses[0].transfer(ethbalanceA);
            channel.partyAddresses[1].transfer(ethbalanceI);
        }

        if (tokenbalanceA != 0 || tokenbalanceI != 0) {
            require(
                channel.token.transfer(channel.partyAddresses[0], tokenbalanceA),
                "byzantineCloseChannel: token transfer failure"
            );
            require(
                channel.token.transfer(channel.partyAddresses[1], tokenbalanceI),
                "byzantineCloseChannel: token transfer failure"
            );
        }

        emit DidLCClose(_lcID, channel.sequence, ethbalanceA, ethbalanceI, tokenbalanceA, tokenbalanceI);
    }

    function _isContained(bytes32 _hash, bytes _proof, bytes32 _root) internal pure returns (bool) {
        bytes32 cursor = _hash;
        bytes32 proofElem;

        for (uint256 i = 64; i <= _proof.length; i += 32) {
            assembly { proofElem := mload(add(_proof, i)) }

            if (cursor < proofElem) {
                cursor = keccak256(abi.encodePacked(cursor, proofElem));
            } else {
                cursor = keccak256(abi.encodePacked(proofElem, cursor));
            }
        }

        return cursor == _root;
    }

    // Struct Getters
    function getChannel(bytes32 id) public view returns (
        address[2],
        uint256[4],
        uint256[4],
        uint256[2],
        uint256,
        uint256,
        bytes32,
        uint256,
        uint256,
        uint256,
        uint256
    ) {
        Channel memory channel = Channels[id];
        return (
            channel.partyAddresses,
            channel.ethBalances, // 0: balanceA 1:balanceI 2:depositedA 3:depositedI
            channel.erc20Balances, // 0: balanceA 1:balanceI 2:depositedA 3:depositedI
            channel.initialDeposit,
            channel.sequence,
            channel.confirmTime,
            channel.VCrootHash,
            channel.LCopenTimeout,
            channel.updateLCtimeout,
            uint256(channel.status),
            channel.numOpenVC
        );
    }

    function getVirtualChannel(bytes32 id) public view returns(
        uint256,
        uint256,
        uint256,
        address,
        address,
        uint256[2],
        uint256[2],
        uint256[2]
    ) {
        VirtualChannel memory virtualChannel = virtualChannels[id];
        return(
            uint256(virtualChannel.status),
            virtualChannel.sequence,
            virtualChannel.updateVCtimeout,
            virtualChannel.partyA,
            virtualChannel.partyB,
            virtualChannel.ethBalances,
            virtualChannel.erc20Balances,
            virtualChannel.bond
        );
    }
}
