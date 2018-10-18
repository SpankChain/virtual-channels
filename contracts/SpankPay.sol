// Refucktor!
//
// Questions:
// 1.
//
// Notes:
// 1. DB primary key should be hub address + contract address
// 2. Future work
//  - Multisig integrations
//  - User identity contracts / Meta Txns (makes sense if user is sending funds / cooperative hub)
// 3. As a gas optimization, if we're only using a few tokens (ETH / SPANK / BOOTY) then we could store the array onchain
//  - this would allow us to avoid passing these in every time
//
// Design:
// 1. timeouts - only used when hub authorizes the user to transfer its reserve balances into their account
// 2. hub first, then user for all variable assignments / transfers / checks
// 3. to deposit into open channel, contract requires you to have mutually signed state acknowledging pending deposit upfront
//  - this allows you to exit if the deposit goes through but the counterparty refused to confirm offchain
//
// TODO:
// 3. Do I need numChannels?
// 4. msg.sender opens channel on behalf of a set of delegate addresses
//  - possibly skip for this version
//  - would need to implement access control
//  - do we need this for watchtowers anyways? Possibly easier to simply close/reopen
// 5. discussion about functions with timeouts
//  - authorizedOpen
//  - authorizedClose
//  - authorizedUpdate
// 6. bulkHubOpenAccounts (airdrop)
//  - allow hub to open multiple user accounts at once, saving lots of txns and simplifying airdrops



pragma solidity ^0.4.23;

import "./lib/ECTools.sol";
import "./lib/ERC20.sol";
import "./lib/SafeMath.sol";

contract SpankPay {
    using SafeMath for uint256;

    string public constant NAME = "SpankPay";
    string public constant VERSION = "0.0.1";

    uint256 public numChannels = 0; // TODO why does this exist

    // SPEC OUT ALL FUNCTIONS


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
    // 5. fishing the site to control the wallet iframe


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
        mapping (address => bool) activeTokens;
        uint256 numActiveTokens;
    }

    struct Tab {
        uint256 userETH;
        uint256 recipientETH;
        mapping (address => uint256) userTokens;
        mapping (address => uint256) recipientTokens;
        uint256 txCount;
        Status status;
        mapping (address => bool) activeTokens;
        uint256 numActiveTokens;
    }

    // Do I need to store challenges / proposed state updates separately?
    // - I would want to do this if I was allowed to deposit onchain without offchain ack
    //   - If I did this, then any startExitWithUpdate would overwrite my deposited funds
    // - If I can only consensusDeposit, do I still need to store challenges separately?
    // - What other params can't be overwritten safely?
    // - All params -> no need to store challenges separately
    // - If a double-signed state update is provided with a higher txCount and can overwrite onchain state
    // - This update will stay unless challenged, and if the challenge is successful it will overwrite again

    mapping (address => Account) public accounts;

    mapping (address => bool) public approvedTokens;
    address public hub;
    uint256 public challengePeriod

    uint256 public reserveETH;
    mapping (address => uint256) public reserveTokens;

    bool locked;

    constructor(address _hub, uint256 _challengePeriod) public {
        hub = _hub;
        challengePeriod = _challengePeriod;
    }

    modifier onlyHub() {
        require(msg.sender == hub);
        _;
    }

    modifier shielded() {
        require(!locked, "Reentrant call.");
        locked = true;
        _;
        locked = false;
    }

    function approveTokens(address[] tokenAddresses) public onlyHub shielded {
        for (uint256 i; i < _approvedTokens.length; i++) {
            approvedTokens[_approvedTokens[i]] = true;
        }
    }

    function unapproveTokens(address[] tokenAddresses) public onlyHub shielded {
        for (uint256 i; i < _approvedTokens.length; i++) {
            approvedTokens[_approvedTokens[i]] = false;
        }
    }

    function hubDepositETH() public payable onlyHub shielded {
        reserveETH = reserveETH.add(msg.value);
    }

    function hubDepositTokens(address[] tokenAddresses, uint256[] tokenValues) public onlyHub shielded {
        require(tokenAddresses.length == tokenValues.length);

        for (uint256 i; i < tokenAddresses.length; i++) {
            ERC20 token = ERC20(tokenAddresses[i]);
            require(approvedTokens[token]);
            reserveTokens[token] = reserveTokens[token].add(tokenValues[i]);
            require(token.transferFrom(hub, address(this), tokenValues[i]));
        }
    }

    function hubWithdrawETH(uint256 value) public onlyHub shielded {
        reserveETH = reserveETH.sub(value);
        hub.transfer(value);
    }

    function hubWithdrawTokens(address[] tokenAddresses, uint256[] tokenValues) public onlyHub shielded {
        require(tokenAddresses.length == tokenValues.length);

        for (uint256 i; i < tokenAddresses.length; i++) {
            ERC20 token = ERC20(tokenAddresses[i]);
            require(approvedTokens[token]);
            reserveTokens[token] = reserveTokens[token].sub(tokenValues[i]);
            require(token.transfer(hub, tokenValues[i]));
        }
    }

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


    // TODO add watchtower support
    function hubOpenAccount(
        address user,
        uint256 hubETH,
        uint256 userETH,
        address[] tokenAddresses,
        uint256[] hubTokenValues,
        uint256[] userTokenValues,
    ) public onlyHub shielded {
        // TODO not sure if this is needed, because should throw when we try to subtract from reserve balance
        require(reserveETH >= hubETH.add(userETH), "insufficient ETH");

        // the user account must be empty
        Account storage account = accounts[user];
        require(account.Status == Status.Empty, "account must be empty");
        require(account.tabCount == 0, "account may not have open tabs");

        // transfer ETH into this account
        uint256 totalETH = userETH.add(hubETH);
        reserveETH = reserveETH.sub(totalETH);
        account.hubETH = hubETH;
        account.userETH = userETH;

        // update channel status
        account.txCount = account.txCount.add(1);
        account.status = Status.Open;

        // confirm token arrays match
        require(tokenAddresses.length == hubTokenValues.length);
        require(tokenAddresses.length == userTokenValues.length);

        // transfer all tokens into this account
        for (uint256 i; i < tokenAddresses.length; i++) {
            ERC20 token = ERC20(tokenAddresses[i]);
            require(approvedTokens[token]);
            require(!account.activeTokens[token]); // token can't already be active
            account.activeTokens[token] = true;
            account.numActiveTokens = account.numActiveTokens.add(1);
            uint256 totalTokenValue = userTokenValues[i].add(hubTokenValues[i]);
            reserveTokens[token] = reserveTokens[token].sub(totalTokenValue);
            account.hubTokens[token] = hubTokenValues[i];
            account.userTokens[token] = userTokenValues[i];
        }

        // reset state variables
        account.tabRoot = bytes32(0x0);
        account.accountClosingTime = 0;
        account.tabClosingTime = 0;
    }



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

        // offchain -> onchain deposits
        // - use case: hub deposit into performer account during show
        //   - without interrupting payments
        //   - new tabs can still be opened (with original balance, not pending deposit balance)
        // - goal: to reduce contract complexity to avoid requiring separate variables for deposit + balance onchain
        //   - strategy is to have "pendingDeposits" for ETH/ERC20 that acknowledge a deposit offchain *in advance*
        //   - once the onchain transaction succeeds, the counterparty would move offchain pending deposits -> balances
        //   - depositer should be able to withdraw if the receiver doesn't acknowledge the deposit
        //     - just needs the state with the pendingDeposits to do so
        //   - either party should be able to exit even if the deposit never happens
        //     - pending deposits should not affect update/closing/dispute if the onchain balances cover offchain balance (exclusing pending deposit)
        // Protocol:
        // 1. hub sends single-signed update to performer which includes pendingDeposit for ETH/ERC20
        // 2. performer countersigns and responds
        //    - no interruption on payments
        //    - performer will still countersign new tabs up to the balances onchain (not including pending deposits)
        // 3. hub uses doublesigned update to execute onchain deposit calling consensusDeposit
        //    - this checkpoints the channel onchain
        // 4.1. Deposit success but not acknowledged
        //      1. hub starts the exit process
        // 4.2. Deposit failure - no additional state updates
        //      1. hub/performer calls startExitWithUpdate (use the previous state right before the deposit) it's as if nothing happened
        //      2. hub/performer calls startExitWithUpdate (using deposit state) -> succeeds
        //         - should recognize that onchain balances >= offchain balances
        //         - when emptyAccount / challengeExit are called, then the extra deposited funds are sent back to the owner
        // 4.3. Deposit failure - further state updates (that didn't affect pending deposits)
        //      1. hub/performer calls startExitWithUpdate (using latest state) -> succeeds
        //         - should recognize that onchain balances >= offchain balances
        //         - when emptyAccount / challengeExit are called, then the extra deposited funds are sent back to the owner

        // Where do we store the challenge?
        // - Need a separate place to store offchain state submitted as part of startExitWithUpdate
        // - separate mapping?
        // - or just as a pending state on the Account
        // NOPE - can overwrite.

        // Updated Connext
        // 1. hub sends single-signed update to performer which includes the deposit as part of the balance
        //    - also contains a *deposit* flag
        // 2. performer countersigns and responds
        // 3. hub uses doublesigned update to execute onchain deposit
        //    - this checkpoints the channel onchain
        // Ameen's notes:
        // - I think this forces the perfomer to stop accepting new tabs / VCs until the deposit is executed

    // If the user is opening the account, the user and hub fund their own balances.
    // TODO watchtower support
    function userOpenAccount(
        uint256 hubETH,
        address[] tokenAddresses,
        uint256[] hubTokenValues,
        uint256[] userTokenValues,
        uint256 timeout,
        string sig
    ) public payable shielded {
        address user = msg.sender;
        uint256 userETH = msg.value;

        require(reserveETH >= hubETH.add(userETH), "insufficient ETH");

        // the user account must be empty
        Account storage account = accounts[user];
        require(account.Status == Status.Empty, "account must be empty");
        require(account.tabCount == 0, "account may not have open tabs");

        // the timeout must not have passed
        require(now < timeout);

        // prepare state hash to check hub sig
        bytes32 state = keccak256(
            abi.encodePacked(
                address(this),
                user,
                account.txCount.add(1),
                timeout,
                hubETH,
                userETH,
                tokenAddresses,
                hubTokenValues
                userTokenValues
            )
        );

        // check hub sig against state hash
        require(hub == ECTools.recoverSigner(state, sig));

        // transfer ETH into this account
        reserveETH = reserveETH.sub(hubETH);
        account.hubETH = hubETH;
        account.userETH = userETH;

        // update channel status
        account.txCount = account.txCount.add(1);
        account.status = Status.Open;

        // confirm token arrays match
        require(tokenAddresses.length == hubTokenValues.length);
        require(tokenAddresses.length == userTokenValues.length);

        // transfer all tokens into this account
        for (uint256 i; i < tokenAddresses.length; i++) {
            ERC20 token = ERC20(tokenAddresses[i]);
            require(approvedTokens[token]);
            require(!account.activeTokens[token]); // token can't already be active
            account.activeTokens[token] = true;
            account.numActiveTokens = account.numActiveTokens.add(1);
            reserveTokens[token] = reserveTokens[token].sub(hubTokenValues[i]);
            account.hubTokens[token] = hubTokenValues[i];
            account.userTokens[token] = userTokenValues[i];
            require(token.transferFrom(user, address(this), userTokenValues[i]));
        }

        // reset dispute variables
        account.tabRoot = bytes32(0x0);
        account.accountClosingTime = 0;
        account.tabClosingTime = 0;
    }

    // Usage:
    // 1. Hub deposits extra BOOTY into performer account as collateral during a popping show
    // 2. Hub deposits extra ETH / ERC20 into a SpankPay account to facilitate exchange

    // will this come with an exchange message by the user?
    // - will the offchain exchange have a timeout?
    // - is that even possible?
    // - user signs an exchange update - $100 ETH for $100 SPANK ... hub does... nothing.
    //   - then later the exchange rate goes up and the hub countersigns...
    //   - there is no way to prove that the hub signed earlier or later
    // - we can make the default behavior of the wallet to exit the channel if the hub takes too long to respond to exchange requests
    // - the hub can also say "no"...
    // - what if an exchange update is proposed but never used?
    //   - the user makes another exchange update later, can this point to the previous one to invalidate it?
    //   - what if the hub signs the second one, then later signs the first one and invalidates the second one?
    //   - the second one would need to be signed with a higher txCount in order to invalidate the first
    //   - this means that we're occasionally going to skip txs
    //   - the client must be programmed to treat exchange updates differently than normal
    //     1. proposeExchange
    //      - save to local storage
    //      - starts timer
    //      - if hub doesn't respond within 1 min -> startExitWithUpdate
    //      - if hub rejects exchange, it needs to provide a signed update with original state but higher txCount
    //      - if hub doesn't provide higher txCount state update -> startExitWithUpdate
    //      - NOTE - have to be careful of user not exiting if *they* are offline and not the hub
    //        - exit would fail bc tx may not broadcast?

    // Only allows hub to deposit into their own balance
    // - if the goal is to transfer to the user's balance, then we can xfer offchain
    function hubDepositIntoAccount(
        address user,
        uint256 hubETH,
        uint256 userETH
        uint256 pendingHubETH,
        address[] tokenAddresses,
        uint256[] hubTokenValues,
        uint256[] userTokenValues,
        uint256[] pendingHubTokenValues,
        uint256 txCount,
        bytes32 tabRoot,
        uint256 tabCount,
        string[] sigs
    ) public onlyHub shielded {
        // TODO not sure if this is needed, because should throw when we try to subtract from reserve balance
        require(reserveETH >= pendingHubETH, "insufficient ETH");

        // the user account must be open
        Account storage account = accounts[user];
        require(account.Status == Status.Open, "account must be open");

        // prepare state hash to check hub sig
        bytes32 state = keccak256(
            abi.encodePacked(
                address(this),
                user,
                hubETH,
                userETH,
                pendingHubETH,
                tokenAddresses,
                hubTokenValues,
                userTokenValues,
                pendingHubTokenValues,
                txCount,
                tabRoot,
                tabCount
            )
        );

        // check hub and user sigs against state hash
        require(hub == ECTools.recoverSigner(state, sigs[0]));
        require(user == ECTools.recoverSigner(state, sigs[1]));

        // txCount must be higher than the current txCount
        require(txCount > account.txCount);

        // eth balances must be conserved
        require(hubETH.add(userETH) == account.hubETH.add(account.userETH));

        // transfer ETH into this account
        reserveETH = reserveETH.sub(pendingHubETH);
        account.hubETH = hubETH.add(pendingHubETH);
        account.userETH = userETH;

        // confirm token arrays match
        require(tokenAddresses.length == hubTokenValues.length);
        require(tokenAddresses.length == userTokenValues.length);
        require(tokenAddresses.length == pendingHubTokenValues.length);

        // transfer all tokens into this account
        for (uint256 i; i < tokenAddresses.length; i++) {
            ERC20 token = ERC20(tokenAddresses[i]);
            require(approvedTokens[token]);

            // token values must be conserved
            require(hubTokenValues[i].add(userTokenValues[i]) == account.hubTokens[token].add(account.userTokens[token]);

            // activate token if not already active
            if (!account.activeTokens[token]) {
                account.activeTokens[token] = true;
                account.numActiveTokens = account.numActiveTokens.add(1);
            }

            reserveTokens[token] = reserveTokens[token].sub(pendingHubTokenValues[i]);
            account.hubTokens[token] = hubTokenValues[i].add(pendingHubTokenValues[i]);
            account.userTokens[token] = userTokenValues[i];
        }

        // set state variables
        account.txCount = txCount;
        account.tabRoot = tabRoot;
        account.tabCount = tabCount;
    }

    // Usage:
    // 1. User depositing BOOTY into the account to tip
    // 2. User depositing ETH into the account to be exchanged for BOOTY to tip
    //  - accompanied by offchain exchange update
    // 3. User depositing ETH / ERC20 tokens to trade
    function userDepositIntoAccount(
        uint256 hubETH,
        uint256 userETH,
        address[] tokenAddresses,
        uint256[] hubTokenValues,
        uint256[] userTokenValues,
        uint256[] pendingUserTokenValues,
        uint256 txCount,
        bytes32 tabRoot,
        uint256 tabCount,
        string[] sigs
    ) public payable shielded {
        address user = msg.sender;
        uint256 pendingUserETH = msg.value;

        // the user account must be open
        Account storage account = accounts[user];
        require(account.Status == Status.Open, "account must be open");

        // prepare state hash to check hub sig
        bytes32 state = keccak256(
            abi.encodePacked(
                address(this),
                user,
                hubETH,
                userETH,
                pendingUserETH,
                tokenAddresses,
                hubTokenValues,
                userTokenValues,
                pendingUserTokenValues,
                txCount,
                tabRoot,
                tabCount
            )
        );

        // check hub and user sigs against state hash
        require(hub == ECTools.recoverSigner(state, sigs[0]));
        require(user == ECTools.recoverSigner(state, sigs[1]));

        // txCount must be higher than the current txCount
        require(txCount > account.txCount);

        // eth balances must be conserved
        require(hubETH.add(userETH) == account.hubETH.add(account.userETH));

        // transfer ETH into this account
        account.hubETH = hubETH;
        account.userETH = userETH.add(pendingUserETH);

        // confirm token arrays match
        require(tokenAddresses.length == hubTokenValues.length);
        require(tokenAddresses.length == userTokenValues.length);
        require(tokenAddresses.length == pendingHubTokenValues.length);

        // transfer all tokens from user to this contract
        for (uint256 i; i < tokenAddresses.length; i++) {
            ERC20 token = ERC20(tokenAddresses[i]);
            require(approvedTokens[token]);

            // token values must be conserved
            require(hubTokenValues[i].add(userTokenValues[i]) == account.hubTokens[token].add(account.userTokens[token]);

            // activate token if not already active
            if (!account.activeTokens[token]) {
                account.activeTokens[token] = true;
                account.numActiveTokens = account.numActiveTokens.add(1);
            }

            account.hubTokens[token] = hubTokenValues[i];
            account.userTokens[token] = userTokenValues[i].add(pendingUserTokenValues[i]);
            require(token.transferFrom(user, address(this), pendingUserTokenValues[i]));
        }

        // set state variables
        account.txCount = txCount;
        account.tabRoot = tabRoot;
        account.tabCount = tabCount;
    }

    // requires all tabs to be closed
    // usage:
    // 1. user wants to empty the account
    // 2. hub wants to empty the account
    function hubAuthorizedEmptyAccount(
        address user,
        uint256 hubETH,
        uint256 userETH
        address[] tokenAddresses,
        uint256[] hubTokenValues,
        uint256[] userTokenValues,
        uint256 txCount,
        string[] sigs
    ) public onlyHub shielded {
        // the user account must be open
        Account storage account = accounts[user];
        require(account.Status == Status.Open, "account must be open");

        // prepare state hash to check hub sig
        bytes32 state = keccak256(
            abi.encodePacked(
                address(this),
                user,
                hubETH,
                userETH,
                tokenAddresses,
                hubTokenValues,
                userTokenValues,
                txCount,
                true, // extra bit for authorized closing
            )
        );

        // check hub and user sigs against state hash
        require(hub == ECTools.recoverSigner(state, sigs[0]));
        require(user == ECTools.recoverSigner(state, sigs[1]));

        // txCount must be higher than the current txCount
        require(txCount > account.txCount);

        // eth balances must be conserved
        require(hubETH.add(userETH) == account.hubETH.add(account.userETH));

        // reset ETH balances
        account.hubETH = 0;
        account.userETH = 0;

        // transfer ETH to reserves and user
        reserveETH = reserveETH.add(hubETH);
        user.transfer(userETH);

        // confirm token arrays match
        require(tokenAddresses.length == hubTokenValues.length);
        require(tokenAddresses.length == userTokenValues.length);

        // empty all tokens
        for (uint256 i; i < tokenAddresses.length; i++) {
            ERC20 token = ERC20(tokenAddresses[i]);

            // token values must be conserved
            require(hubTokenValues[i].add(userTokenValues[i]) == account.hubTokens[token].add(account.userTokens[token]);

            // token must be active
            require(account.activeTokens[token]);

            // deactivate token
            account.activeTokens[token] = false;
            account.numActiveTokens = account.numActiveTokens.sub(1);

            // reset token balances
            account.userTokens[token] = 0;
            account.hubTokens[token] = 0;

            // transfer tokens to reserve and user
            reserveTokens[token] = reserveTokens[token].add(hubTokenValues[i]);
            require(token.transfer(user, userTokenValues[i]));
        }

        // check that all tokens have been deactivated
        require(account.numActiveTokens == 0);

        // reset state variables
        account.txCount = txCount;
        account.tabRoot = bytes32(0x0);
        account.tabCount = 0;
        account.status = Status.Empty;
    }



    // Why do I need this function? When do I want to checkpoint to chain?
    // I already checkpoint every time I need to deposit / withdraw
    // I think I only need this if I want to withdraw
    // function consensusUpdate()

    // So then for partial withdrawals, we have a few use cases:
    // 1. hub wants to rebalance liquidity between performer channels
    //  - move BOOTY out of a performer's account and into its reserves
    //  - OR move BOOTY out of a performer's account and directly into another performer's account
    //    - partialWithdrawal + deposit
    //    - can this be done in a single tx?
    //  - OR claim ETH / BOOTY out of a user's account and move to a performer account
    //    - for BOOTY, this doesn't make a whole lot of sense, because performer collat is in BOOTY but user spend is in ETH
    //    - for users who generate/buy their own BOOTY and use it to tip beyond the BOOTY LIMIT we could claim the extra though
    // 2. performer wants to withdraw *some* of the money
    //  - they have BOOTY in their side of the channel, but want ETH
    //  - need to do a authorizedExchangeAndWithdrawal (timeout)
    // 3. user wants to withdraw *some* of the money
    //  - authorizedExchangeAndWithdrawal

    // all partial withdrawals require a timer
    // - why? to make sure it happens now
    // - it isn't to make sure it happens now
    // - it's to allow both parties to agree to invalidate that state if it fails.
    // - 1. no timeout, tx submitted immediately
    //   - fine
    // - 2. no timeout, tx delayed / rejected
    //   - neither party can ever submit a state update again
    //   - does this matter?
    //   - do we NEED to wait?
    //   - what if we continue to allow payments that draw from the remaining balance?
    //   - performer cashes out during a show
    //     - hub starts an authorized withdrawal on their behalf
    //     - they can still receive tips from hubs collat
    //   - user withdraws some money
    //     - hub starts an authorized withdrawal on their behalf
    //     - they can tip from remaining balance
    //   - can do the same thing we did for deposits, move money into a "pendingWithdrawals" variable offchain

    // What do I really want?
    // - to update onchain with any more recent mutually signed state update at any time
    // - only unilateral withdrawals trigger challenge periods
    // - to execute one or more transactions onchain as part of an update
    //   - hubDeposit (ETH / tokens)
    //   - userDeposit (ETH / tokens) -> more difficult, requires token approval
    //   - hubWithdrawal
    //   - userWithdrawal
    //   - exchange

    // I could pass in a byteArray of signed txs to execute
    // - bytes -> encode txs [num of transactions, length of 1st tx, type, value, length of 2nd tx, type, value, ... ]
    // - or pass in hella variables
    //   - pendingHubETHDeposit
    //   - pendingHubTokenDeposits
    //   - pendingUserETHDeposit
    //   - pendingUserTokenDeposits
    //   - pendingHubETHWithdrawal
    //   - pendingHubTokenWithdrawals
    //   - pendingUserETHWithdrawal
    //   - pendingUserTokenWithdrawals

    // this would cover the exchange withdrawal case too, actually
    // - update + pendingUserETHWithdrawals + pendingHubETHDeposits
    // - what happens if hub doesn't have the ETH?
    //   - tx fails
    //   - then what?
    //
    // if we think in terms of txns, its:
    // 1. hub deposit ETH in channel
    // 2. hub / user exchange ETH / BOOTY
    // 3. user withdraw ETH
    // 4. hub withdraw BOOTY (optionally)

    // what would a retarded person do?
    // 1. deposit ETH into performer channel
    // 2. WAIT
    // 3. in channel exchange
    // 4. hubAuthorizedWithdrawal - performer gets ETH (to user address, not recipient)
    // 5. WAIT
    // 6. performer wallet transfers funds out to desired address
    // 7. WAIT
    // 8. some time later, hub calls withdrawal, starts a challenge period
    // 9. WAIT A LONG TIME
    // 10. hub gets BOOTY back.
    // Confirmed, this is retarded.

    // Less retarded - hubAuthorizedWithdrawalWithExchange
    // 4. hubAuthorizedWithdrawalWithExchange - performer gets ETH (to user address, not recipient)
    //  - hub deposits ETH and receives BOOTY as part of the withdrawal
    // 5. WAIT
    // 6. performer wallet transfers funds out to desired address
    // 7. WAIT
    // 8. some time later, hub calls withdrawal, starts a challenge period
    // 9. WAIT A LONG TIME
    // 10. hub gets BOOTY back.

    // Even Less retarded - hubAuthorizedWithdrawalWithExchange(recipient)
    // 4. hubAuthorizedWithdrawalWithExchange(recipient) - performer gets ETH to recipient address
    //  - hub deposits ETH and receives BOOTY as part of the withdrawal
    // 5. WAIT
    // 8. some time later, hub calls withdrawal, starts a challenge period
    // 9. WAIT A LONG TIME
    // 10. hub gets BOOTY back.

    function executeTxns()

    // I could pass in a byteArray of signed txs to execute
    // - bytes -> encode txs [num of transactions, length of 1st tx, type, value, length of 2nd tx, type, value, ... ]
    // - or pass in hella variables
    //   - pendingHubETHDeposit
    //     - type = hub ETH deposit
    //     - amount = 1000
    //   - pendingHubTokenDeposits
    //     - type = hub token deposit
    //     - token = BOOTY
    //     - amount = 1000
    //   - pendingUserETHDeposit
    //   - pendingUserTokenDeposits
    //   - pendingHubETHWithdrawal
    //     - type = hub ETH withdrawal
    //     - address = hub (can omit for hub)
    //     - amount = 1000
    //   - pendingHubTokenWithdrawals
    //   - pendingUserETHWithdrawal
    //   - pendingUserTokenWithdrawals
    //     - type = user token withdrawal
    //     - token = BOOTY
    //     - amount = 1000
    //     - recipient = 0xSomeAddress
    //   - exchange
    //     - type = exchange
    //     - hub currency = BOOTY
    //     - user currency = ETH
    //     - hub amount = 1000
    //     - user amount = 5000
    //     - timeout?

    // What are the actual user stories that we're optimizing?
    // - for user / performer withdrawals, we could ask the user to keep the window open (this is not great UX)
    //   - then again, it isn't *that bad* either, because the user could simply open another tab or something
    // - for user deposits (2 txns, doesn't get much better than this)
    //   1. user send ETH to wallet
    //   2. WAIT
    //   3. userOpenChannel
    //   4. WAIT
    //   5. offchain exchange
    //   6. user can start tipping

    // Priorities:
    // - so far, I've been trying to combine ComeSwap and SpankPay
    // - my priority is to get BOOTY on the camsite and the SpankPay SDK out ASAP
    // - that means this contract is fine with 1 token (BOOTY) and ETH.
    // - it also means the exchange functionality can be limited to just SpankPay BOOTY/ETH xfers
    // - I haven't thought through the UX of ComeSwap enough (thinking it through today made that clear)
    // - We'll probably need to do more thinking around it before adding that all to the contract
    // - if it does end up using something like Lineup.sol, then it'll take a lot more work.

    function hubAuthorizedWithdrawal(
        address user,
        uint256 hubETH,
        uint256 userETH
        address[] tokenAddresses,
        uint256[] hubTokenValues,
        uint256[] userTokenValues,
        uint256 txCount,
        string[] sigs
    ) public onlyHub shielded {
        // the user account must be open
        Account storage account = accounts[user];
        require(account.Status == Status.Open, "account must be open");

        // prepare state hash to check hub sig
        bytes32 state = keccak256(
            abi.encodePacked(
                address(this),
                user,
                hubETH,
                userETH,
                tokenAddresses,
                hubTokenValues,
                userTokenValues,
                txCount,
                true, // extra bit for authorized closing
            )
        );

        // check hub and user sigs against state hash
        require(hub == ECTools.recoverSigner(state, sigs[0]));
        require(user == ECTools.recoverSigner(state, sigs[1]));

        // txCount must be higher than the current txCount
        require(txCount > account.txCount);

        // eth balances must be conserved
        require(hubETH.add(userETH) == account.hubETH.add(account.userETH));

        // reset ETH balances
        account.hubETH = 0;
        account.userETH = 0;

        // transfer ETH to reserves and user
        reserveETH = reserveETH.add(hubETH);
        user.transfer(userETH);

        // confirm token arrays match
        require(tokenAddresses.length == hubTokenValues.length);
        require(tokenAddresses.length == userTokenValues.length);

        // empty all tokens
        for (uint256 i; i < tokenAddresses.length; i++) {
            ERC20 token = ERC20(tokenAddresses[i]);

            // token values must be conserved
            require(hubTokenValues[i].add(userTokenValues[i]) == account.hubTokens[token].add(account.userTokens[token]);

            // token must be active
            require(account.activeTokens[token]);

            // deactivate token
            account.activeTokens[token] = false;
            account.numActiveTokens = account.numActiveTokens.sub(1);

            // reset token balances
            account.userTokens[token] = 0;
            account.hubTokens[token] = 0;

            // transfer tokens to reserve and user
            reserveTokens[token] = reserveTokens[token].add(hubTokenValues[i]);
            require(token.transfer(user, userTokenValues[i]));
        }

        // check that all tokens have been deactivated
        require(account.numActiveTokens == 0);

        // reset state variables
        account.txCount = txCount;
        account.tabRoot = bytes32(0x0);
        account.tabCount = 0;
        account.status = Status.Empty;
    }

    // Do I need separate functions for user/hub authorized withdrawals?
    // - both parties need to sign
    // - do we want to do withdrawals at the same time?
    //   - user partial withdrawals 90% of ETH in their channel, if they drop below BOOTY limit, hub can withdraw extra BOOTY
    //   - performer wants to withdraw their earned BOOTY -> ETH, hub can withdraw their BOOTY collateral
    //   - sometimes, we do want to allow the hub to piggyback on the withdrawal
    // - what if the hub always sent the transaction?
    // - users are never sending funds, so the tx doesn't have to come from them
    // - I think hub initiating all of them is fine.
    //   - saves user gas
    //   - assumption is hub is always online anyways
    //   - if hub is offline, then the tx should be unilateral anyways

    // For *withExchange functions we need to add timeouts
    // If the hub is the only one that can call, it gives the hub a free option...
    // If the timeout is 5 mins, that's not so bad.

    function authorizedWithdrawal()

    // Does this serve the comeswap exchange use case?
    // - userOpenAccount (user -> ETH, hub -> SPANK)
    // - user requests sig from hub on openAccount
    //   - user needs to know how much the hub is willing to deposit
    //     - this can be done as part of the first request or a round-trip
    //   - user provides signed update on in-channel exchange (needs to know how much hub will deposit)
    //   - once hub sees the signed exchange it will sign the userOpenAccount msg and the exchange message
    // - do these need separate values?

    // What about users that just want to exchange?
    // - how would we represent their balance in the UX?
    // - should we even allow this?

    // I come in to trade SPANK for ETH
    // 1. User has an open account with all the SPANK
    //     1. User wants to transfer it to a separate address
    //     - authorizedWithdrawalWithExchange(address destination)
    //     2. User wants to exchange but keep the funds in the same address, onchain
    //     - authorizedWithdrawalWithExchange
    //     3. User wants to exchange and keep the funds offchain
    //     - hubDepositIntoAccount -> offchain exchange
    // 2. User has an open account, but not with the SPANK
    //     1. User wants to transfer it to a separate address
    //     - userDepositIntoAccount -> authorizedWithdrawalWithExchange(address destination)
    //     2. User wants to exchange but keep the funds in the same address, onchain
    //     - userDepositIntoAccount -> authorizedWithdrawalWithExchange
    //     3. User wants to exchange and keep the funds offchain
    //     - userDepositIntoAccount -> offchain exchange
    // 3. User does not have an account
    //     1. User wants to transfer it to a separate address
    //     - userOpenAccount -> authorizedWithdrawalWithExchange(address destination)
    //     2. User wants to exchange but keep the funds in the same address, onchain
    //     - userOpenAccount -> authorizedWithdrawalWithExchange
    //     3. User wants to exchange and keep the funds offchain
    //     - userOpenAccount -> offchain exchange

    // Does the user want to keep the money in their account?
    // 1. User wants to transfer it to a separate address
    // 2. User wants to exchange but keep the funds in the same address, onchain
    // 3. User wants to exchange and keep the funds offchain

    // This is silly. If the user *just* wants to exchange, then we can just exchange
    // - we don't need to create account and save all their data...

    // takes ETH / tokens from user, and authorizes xfer of ETH / tokens from hub
    // - skips account?
    // - UX? What happens when a user arrives at ComeSwap?
    // - If it uses SpankPay natively, will the tokens automatically get deposited into the account?
    //   - does the user need to authorize which tokens get deposited?
    //   - could open up a loading screen "tokens detected -> depositing into your account"
    // - Probably two use cases - instant vs. slow
    //   - instant -> request hub deposit funds in channel
    //   - slow -> exchange with hub's onchain reserves
    // - Then exiting can be a separate tx
    //   - this is a worse UX, because now I have 3-4 (counting initial approve) on chain txs instead of just 1-2

    // What if I had two contracts - SpankPay and ComeSwap
    // - ComeSwap deals with all exchange functions
    // - SpankPay deals with all payment / tabs functions
    // - Both could use the same liquidity pool
    // - Both use the same sig auth scheme for the hub
    // - Best way to figure it out?
    //   - make all functions first, then refactor?
    //   - idk...

    // What if the user wants to use metamask directly?
    // UX - select wallet - SpankPay (default) / MetaMask / ...
    // If SpankPay selected, exchanges go through your SpankPay account...
    // Otherwise can exchange directly.
    function authorizedExchange() {

    }

    // Possible to create convenience wrappers do combine calls into atomic functions
    // - need to be careful with how shielded works then
    // - I think it would work, because each function is independently shielded

    // Usage:
    // 1. User (viewer / performer) has BOOTY in SpankPay, wants to withdraw to ETH
    //  - hub may also simultaneously want to withdraw some of their BOOTY / ETH collateral
    // 2. Hub wants to withdraw ETH / BOOTY accumulated in a viewer channel
    // 3. Hub wants to withdraw BOOTY collateral from a performer's channel
    function authorizedWithdrawalWithExchange()

    function authorizedExit()

    function authorizedExitWithExchange()

    // Unilateral functions

    function startExit

    function startExitWithUpdate

    function emptyAccount

    function emptyAccountWithChallenge

    function startExitTabs

    function startExitTabsWithUpdate

    function emptyTabs

    function emptyTabsWithChallenge

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
