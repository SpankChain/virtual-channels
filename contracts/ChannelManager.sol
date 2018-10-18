// Notes:
// 1. hub reserve ETH / token
// 2. deposit / withdrawal for hub reserves
// 3. topLevel -> shielded
// 4. create + join -> hubOpen / userOpen
// 5. Channel -> Account
// 6. channelId -> user address
// 7. remove checkpointing
// 8. Thread -> Tab
// 9. single token is cool
// 10. threadId -> tabs by recipient address
// 11. deposit -> user deposit + hub deposit
// 12. remove channelOpenTimeout
// 13. startChannelSettlement -> startExit / startExitWithUpdate
// 14. checkpointChannelDispute -> emptyAccountWithChallenge (immediately empties channel, but not tabs)
//   - no back and forth on settlement
// 15. byzantineCloseChannel -> emptyAccount (empties after confirmation time, but not tabs)
//   - prevent account from being re-opened without first closing tabs
//   - UX of closing disputes (please wait while your account is fully emptied)
// 16. signature scheme - do we always need to sign the same set of state vars?
// 17. initThread -> startExitTabs / startExitTabsWithUpdates
//   - multiple tabs at once
// 18. settleThread -> emptyTabs (empties after conf time)
//   - no back and forth settlement
// 19. closeThread -> recipientEmptyTabs (recipient or watchtower can immediately empty with an update)
// 20. confirmTime / openTimeout / updateTimeout -> global confirmationTime + account.closingTime + tab.closingTime
// 21. HumanStandardToken -> ERC20

// Explore:
// 1. consensusClose -> allow pending deposits / withdrawals
// 2. partialWithdraw -> allow pending deposits / withdrawals (exchange) -> requires timeouts to avoid later replay
// 3. deposit -> allow both parties to deposit when user deposits
//  - useful if user deposits ETH between BOOTY minimum and BOOTY limit, then adds more ETH
//  - hub will also deposit more BOOTY up to the BOOTY limit (now this function requires timeout)
// 4. how / when does the hub reclaim money in the channels?
//  - can the hub reclaim when user deposits?
//  - yes, if we use a timeout to prevent replay attacks
//  - timeouts will be required infra for ComeSwap anyways
// 5. withdraw -> user can provide recipient address
// 6. combine initVC and settleVC for recipient (startExitTabsWithUpdate + emptyTabs)
//  - best as a separate 5th function?
//  - probably overkill
// 7. batch close VCs
// 8. timeout -> hub needs to track *liabilities* on its reserves
//  - how much $$$ is hub currently liable for from txns that have yet to expire?
//  - update every few seconds -> SQL must keep track
// 9. watchtower support
//  - set when user opens channel
//  - can close channels on their behalf
// 10.

pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2;

import "./lib/ECTools.sol";
import "./lib/token/HumanStandardToken.sol";
import "./lib/SafeMath.sol";

/// @title Connext Channel Manager - A layer2 micropayment network

contract ChannelManager {
    using SafeMath for uint256;

    string public constant NAME = "Channel Manager";
    string public constant VERSION = "0.0.1";

    event DidChannelOpen (
        bytes32 indexed channelId,
        address indexed partyA,
        uint256 weiBalanceA,
        uint256 tokenBalanceA,
        uint256 openTimeout
    );

    event DidChannelJoin (
        bytes32 indexed channelId,
        uint256 weiBalanceI,
        uint256 tokenBalanceI
    );

    event DidChannelDeposit (
        bytes32 indexed channelId,
        address indexed recipient,
        uint256 weiDeposit,
        uint256 tokenDeposit
    );

    event DidChannelWithdraw(
        bytes32 indexed channelId,
        address indexed recipient,
        uint256 weiWithdrawal,
        uint256 tokenWithdrawal
    );

    event DidChannelCheckpoint (
        bytes32 indexed channelId,
        uint256 sequence,
        uint256 weiBalanceA,
        uint256 tokenBalanceA,
        uint256 weiBalanceI,
        uint256 tokenBalanceI,
        uint256 numOpenThread,
        bytes32 threadRoot
    );

    event DidChannelCheckpointDispute (
        bytes32 indexed channelId,
        uint256 sequence,
        uint256 weiBalanceA,
        uint256 tokenBalanceA,
        uint256 weiBalanceI,
        uint256 tokenBalanceI,
        uint256 numOpenThread,
        bytes32 threadRoot,
        uint256 updateTimeout
    );

    event DidChannelClose (
        bytes32 indexed channelId,
        uint256 sequence,
        uint256 weiBalanceA,
        uint256 tokenBalanceA,
        uint256 weiBalanceI,
        uint256 tokenBalanceI
    );

    event DidChannelStartSettlement (
        bytes32 indexed channelId,
        uint256 sequence,
        uint256 weiBalanceA,
        uint256 tokenBalanceA,
        uint256 weiBalanceI,
        uint256 tokenBalanceI,
        uint256 numOpenThread,
        bytes32 threadRoot,
        uint256 updateTimeout
    );

    event DidThreadInit (
        bytes32 indexed channelId,
        bytes32 indexed threadId,
        bytes proof,
        uint256 sequence,
        address partyA,
        address partyB,
        uint256 weiBalanceA,
        uint256 tokenBalanceA
    );

    event DidThreadSettle (
        bytes32 indexed channelId,
        bytes32 indexed threadId,
        uint256 sequence,
        uint256 weiBalanceA,
        uint256 tokenBalanceA,
        uint256 weiBalanceI,
        uint256 tokenBalanceI,
        uint256 updateTimeout
    );

    event DidThreadClose(
        bytes32 indexed channelId,
        bytes32 indexed threadId,
        uint256 weiBalanceA,
        uint256 tokenBalanceA,
        uint256 weiBalanceI,
        uint256 tokenBalanceI
    );

    enum ChannelStatus {
        Nonexistent,
        Opened,
        Joined,
        Settling,
        Settled
    }

    struct Channel {
        ChannelStatus status;
        address partyA;
        uint256[2] balancesA; // [wei, token]
        uint256[2] balancesI; // [wei, token]
        uint256 sequence;
        bytes32 threadRootHash;
        uint256 numOpenThread;
        uint256 confirmTime;
        uint256 openTimeout;
        uint256 updateTimeout;
    }

    enum ThreadStatus {
        Nonexistent,
        Settling,
        Settled
    }

    struct Thread {
        ThreadStatus status;
        uint256 sequence;
        address partyA;
        address partyB;
        uint256[2] balancesA; // [wei, token]
        uint256[2] balancesB; // [wei, token]
        uint256 updateTimeout;
    }

    enum CheckpointType {
        Checkpoint,
        Deposit,
        Withdraw,
        Close
    }

    mapping(bytes32 => Thread) public threads;
    mapping(bytes32 => Channel) public channels;

    bool topLevel = true;

    // globals
    HumanStandardToken public approvedToken;
    address public hubAddress;

    constructor(address _tokenAddress, address _hubAddress) public {
        approvedToken = HumanStandardToken(_tokenAddress);
        hubAddress = _hubAddress;
    }

    function createChannel(
        bytes32 channelId,
        uint256 confirmTime, // TODO can we hardcode this too?
        uint256 tokenBalance
    )
        public
        payable
    {
        require(topLevel, "createChannel: Top level function can only be called directly");
        require(channels[channelId].status == ChannelStatus.Nonexistent, "createChannel: Channel already exists");
        require(msg.sender != hubAddress, "createChannel: Cannot create channel with yourself");

        // Set initial ledger channel state
        // Alice must execute this and we assume the initial state
        // to be signed from this requirement
        Channel storage channel = channels[channelId];

        channel.status = ChannelStatus.Opened;
        channel.partyA = msg.sender; // partyA
        channel.sequence = 0;
        channel.confirmTime = confirmTime;
        channel.openTimeout = now.add(confirmTime);

        channel.balancesA[0] = msg.value; // wei deposit
        require(approvedToken.transferFrom(msg.sender, this, tokenBalance), "createChannel: Token transfer failure");
        channel.balancesA[1] = tokenBalance; // token deposit

        emit DidChannelOpen(
            channelId,
            channel.partyA, // partyA
            channel.balancesA[0], // weiBalanceA
            channel.balancesA[1], // tokenBalanceA
            channel.openTimeout
        );
    }

    function channelOpenTimeout(bytes32 channelId) public {
        require(topLevel, "channelOpenTimeout: Top level function can only be called directly");

        Channel storage channel = channels[channelId];

        require(msg.sender == channel.partyA, "channelOpenTimeout: Request not sent by partyA");
        require(channel.status == ChannelStatus.Opened, "channelOpenTimeout: Channel status must be Opened");
        require(now > channel.openTimeout, "channelOpenTimeout: Channel openTimeout has not expired");

        // reentrancy protection
        channel.status = ChannelStatus.Settled;
        uint256 weiBalanceA = channel.balancesA[0];
        uint256 tokenBalanceA = channel.balancesA[1];

        channel.balancesA[0] = 0; // wei
        channel.balancesA[1] = 0; // token
        channel.balancesI[0] = 0; // wei
        channel.balancesI[1] = 0; // token

        channel.partyA.transfer(weiBalanceA);
        require(
            approvedToken.transfer(channel.partyA, tokenBalanceA),
            "channelOpenTimeout: Token transfer failure"
        );

        emit DidChannelClose(
            channelId,
            0, // sequence
            weiBalanceA,
            tokenBalanceA,
            0, // weiBalanceI
            0 // tokenBalanceI
        );
    }

    function joinChannel(bytes32 channelId, uint256 tokenBalance) public payable {
        require(topLevel, "joinChannel: Top level function can only be called directly");

        Channel storage channel = channels[channelId];

        require(channel.status == ChannelStatus.Opened, "joinChannel: Channel status must be Opened");
        require(msg.sender == hubAddress, "joinChannel: Channel can only be joined by counterparty");

        channel.status = ChannelStatus.Joined;

        channel.balancesI[0] = msg.value; // wei
        require(
            approvedToken.transferFrom(msg.sender, this, tokenBalance),
            "joinChannel: token transfer failure"
        );
        channel.balancesI[1] = tokenBalance; // token

        emit DidChannelJoin(
            channelId,
            channel.balancesI[0], // wei
            channel.balancesI[1] // token
        );
    }

    function deposit(
        bytes32 channelId,
        uint256 tokenDeposit,
        uint256 sequence,
        uint256 numOpenThread,
        bytes32 threadRootHash,
        string sigA,
        string sigI
    )
        public
        payable
    {
        require(topLevel, "deposit: Top level function can only be called directly");

        Channel storage channel = channels[channelId];

        require(channel.status == ChannelStatus.Joined, "deposit: Channel status must be Joined");
        require(
            msg.sender == channel.partyA || msg.sender == hubAddress,
            "deposit: Sender must be channel member"
        );

        // store deposits by party who sent transaction
        uint256[2] memory depositA;
        uint256[2] memory depositI;
        if (msg.sender == channel.partyA) {
            depositA[0] = msg.value; // wei
            depositA[1] = tokenDeposit; // token
        } else if (msg.sender == hubAddress) {
            depositI[0] = msg.value; // wei
            depositI[1] = tokenDeposit; // token
        }

        // checkpoint on chain
        _verifyUpdateSig(
            channel,
            channelId,
            false, // isClose
            [
                sequence,
                numOpenThread,
                channel.balancesA[0], // wei
                channel.balancesI[0], // wei
                channel.balancesA[1], // token
                channel.balancesI[1], // token
                depositA[0], // pending wei
                depositI[0], // pending wei
                depositA[1], // pending token
                depositI[1], // pending token
                0, // pending withdrawal
                0, // pending withdrawal
                0, // pending withdrawal
                0 // pending withdrawal
            ],
            threadRootHash,
            sigA,
            sigI
        );

        // update chain state
        channel.sequence = sequence;
        channel.numOpenThread = numOpenThread;
        // add consensually signed pending deposits to on chain balances
        channel.balancesA[0] = channel.balancesA[0].add(depositA[0]); // weiBalanceA
        channel.balancesI[0] = channel.balancesI[0].add(depositI[0]); // weiBalanceI
        channel.balancesA[1] = channel.balancesA[1].add(depositA[1]); // tokenBalanceA
        channel.balancesI[1] = channel.balancesI[1].add(depositI[1]); // tokenBalanceI
        channel.threadRootHash = threadRootHash;

        require(approvedToken.transferFrom(msg.sender, this, tokenDeposit), "deposit: token transfer failure");

        emit DidChannelDeposit(
            channelId,
            msg.sender,
            msg.value, // weiDeposit
            tokenDeposit
        );
    }

    function withdraw(
        bytes32 channelId,
        uint256[2] withdrawals, // [wei, token]
        uint256 sequence,
        uint256 numOpenThread,
        bytes32 threadRootHash,
        string sigA,
        string sigI
    )
        public
        payable
    {
        require(topLevel, "withdraw: Top level function can only be called directly");

        Channel storage channel = channels[channelId];

        require(channel.status == ChannelStatus.Joined, "withdraw: Channel status must be Joined");
        require(
            msg.sender == channel.partyA || msg.sender == hubAddress,
            "withdraw: Sender must be channel member"
        );

        // store withdrawals by party who sent transaction
        // this causes sig verification to fail if the other party sends the transaction,
        // since the withdraw amounts will be different than what was signed for
        uint256[2] memory withdrawalA;
        uint256[2] memory withdrawalI;
        if (msg.sender == channel.partyA) {
            withdrawalA[0] = withdrawals[0]; // wei
            withdrawalA[1] = withdrawals[1]; // token
        } else if (msg.sender == hubAddress) {
            withdrawalI[0] = withdrawals[0]; // wei
            withdrawalI[1] = withdrawals[1]; // token
        }

        _verifyUpdateSig(
            channel,
            channelId,
            false, // isClose
            [
                sequence,
                numOpenThread,
                channel.balancesA[0], // wei
                channel.balancesI[0], // wei
                channel.balancesA[1], // token
                channel.balancesI[1], // token
                0, // pending deposit
                0, // pending deposit
                0, // pending deposit
                0, // pending deposit
                withdrawalA[0], // pending wei withdrawal
                withdrawalI[0], // pending wei withdrawal
                withdrawalA[1], // pending token withdrawal
                withdrawalI[1] // pending token withdrawal
            ],
            threadRootHash,
            sigA,
            sigI
        );

        // update chain state
        channel.sequence = sequence;
        channel.numOpenThread = numOpenThread;
        // subtract consensually signed pending withdrawals from on chain balances
        channel.balancesA[0] = channel.balancesA[0].sub(withdrawalA[0]); // weiBalanceA
        channel.balancesI[0] = channel.balancesI[0].sub(withdrawalI[0]); // weiBalanceI
        channel.balancesA[1] = channel.balancesA[1].sub(withdrawalA[1]); // tokenBalanceA
        channel.balancesI[1] = channel.balancesI[1].sub(withdrawalI[1]); // tokenBalanceI
        channel.threadRootHash = threadRootHash;

        // not possible to send to the wrong person because the sig will fail if the other party sends
        msg.sender.transfer(withdrawals[0]);
        require(approvedToken.transfer(msg.sender, withdrawals[1]), "withdraw: Token transfer failure");

        emit DidChannelWithdraw(
            channelId,
            msg.sender,
            withdrawals[0], // weiWithdrawal
            withdrawals[1] // tokenWithdrawal
        );
    }

    function consensusCloseChannel(
        bytes32 channelId,
        uint256 sequence,
        uint256[4] balances, // [weiBalanceA, weiBalanceI, tokenBalanceA, tokenBalanceI]
        string sigA,
        string sigI
    )
        public
    {
        require(topLevel, "consensusCloseChannel: Top level function can only be called directly");

        Channel storage channel = channels[channelId];

        require(channel.status == ChannelStatus.Joined, "consensusCloseChannel: Channel status must be Joined");
        // everything that is on chain must be accounted for in passed in balances
        require(
            balances[0].add(balances[1]) == channel.balancesA[0].add(channel.balancesI[0]),
            "consensusCloseChannel: On-chain wei balances not equal to provided balances"
        );
        require(
            balances[2].add(balances[3]) == channel.balancesA[1].add(channel.balancesI[1]),
            "consensusCloseChannel: On-chain token balances not equal to provided balances"
        );
        // don't need to check sequence here, don't sign anything else after you have signed this

        // verify sig and update chain
        _verifyUpdateSig(
            channel,
            channelId,
            true, // isClose
            [
                sequence,
                uint256(0), // numOpenThread must be 0
                channel.balancesA[0], // wei
                channel.balancesI[0], // wei
                channel.balancesA[1], // token
                channel.balancesI[1], // token
                0, // pending deposit
                0, // pending deposit
                0, // pending deposit
                0, // pending deposit
                0, // pending withdrawal
                0, // pending withdrawal
                0, // pending withdrawal
                0 // pending withdrawal
            ],
            bytes32(0x0), // threadRootHash
            sigA,
            sigI
        );

        // this will prevent reentrancy
        channel.status = ChannelStatus.Settled;

        channel.balancesA[0] = 0; // wei
        channel.balancesA[1] = 0; // token
        channel.balancesI[0] = 0; // wei
        channel.balancesI[1] = 0; // token

        channel.partyA.transfer(balances[0]); // weiBalanceA
        hubAddress.transfer(balances[1]); // weiBalanceI

        require(
            approvedToken.transfer(channel.partyA, balances[2]),
            "consensusCloseChannel: Token transfer failure"
        ); // tokenBalanceA
        require(
            approvedToken.transfer(hubAddress, balances[3]),
            "consensusCloseChannel: Token transfer failure"
        ); // tokenBalanceI

        emit DidChannelClose(
            channelId,
            sequence,
            balances[0], // weiBalanceA
            balances[1], // weiBalanceI
            balances[2], // tokenBalanceA
            balances[3] // tokenBalanceI
        );
    }

    function checkpointChannel(
        bytes32 channelId,
        // updateParams = [sequence, numOpenThread, weiBalanceA, weiBalanceI, tokenBalanceA, tokenBalanceI,
        // pendingDepositWeiA, pendingDepositWeiI, pendingDepositTokenA, pendingDepositTokenI,
        // pendingWithdrawalWeiA, pendingWithdrawalWeiI, pendingWithdrawalTokenA, pendingWithdrawalTokenI]
        uint256[14] updateParams,
        bytes32 threadRootHash,
        string sigA,
        string sigI
    )
        public
    {
        require(topLevel, "checkpointChannel: Top level function can only be called directly");

        Channel storage channel = channels[channelId];
        require(channel.status == ChannelStatus.Joined, "checkpointChannel: Channel status must be Joined or Settling");
        // require for all checkpoints
        require(
            updateParams[0] > channel.sequence,
            "checkpointChannel: Sequence must be higher or zero-state update"
        );
        // input balances can be less than on-chain balances because of balance bonded in threads
        require(
            updateParams[2].add(updateParams[3]) <= channel.balancesA[0].add(channel.balancesI[0]),
            "checkpointChannel: On-chain eth balances must be higher than provided balances"
        );
        require(
            updateParams[4].add(updateParams[5]) <= channel.balancesA[1].add(channel.balancesI[1]),
            "checkpointChannel: On-chain token balances must be higher than provided balances"
        );

        // verify sig and update chain
        _verifyUpdateSig(
            channel,
            channelId,
            false, // isClose
            updateParams,
            threadRootHash, // threadRootHash
            sigA,
            sigI
        );

        // update chain state, do not account for pending
        channel.sequence = updateParams[0];
        channel.numOpenThread = updateParams[1];
        channel.balancesA[0] = updateParams[2]; // weiBalanceA
        channel.balancesI[0] = updateParams[3]; // weiBalanceI
        channel.balancesA[1] = updateParams[4]; // tokenBalanceA
        channel.balancesI[1] = updateParams[5]; // tokenBalanceI
        channel.threadRootHash = threadRootHash;

        emit DidChannelCheckpoint(
            channelId,
            updateParams[0], // sequence
            updateParams[2], // weiBalanceA
            updateParams[3], // weiBalanceI
            updateParams[4], // tokenBalanceA
            updateParams[5], // tokenBalanceI
            updateParams[1], // numOpenThread
            threadRootHash
        );
    }

    // BYZANTINE FUNCTIONS
    function startChannelSettlement(bytes32 channelId) public {
        require(topLevel, "startChannelSettlement: Top level function can only be called directly");

        Channel storage channel = channels[channelId];

        require(msg.sender == channel.partyA || msg.sender == hubAddress, "startChannelSettlement: Sender must be part of channel");
        require(
            channel.status == ChannelStatus.Joined,
            "startChannelSettlement: Channel status must be Joined"
        );

        channel.status = ChannelStatus.Settling;
        channel.updateTimeout = now.add(channel.confirmTime);

        emit DidChannelStartSettlement(
            channelId,
            channel.sequence, // sequence
            channel.balancesA[0], // weiBalanceA
            channel.balancesI[0], // weiBalanceI
            channel.balancesA[1], // tokenBalanceA
            channel.balancesI[1], // tokenBalanceI
            channel.numOpenThread, // numOpenThread
            channel.threadRootHash,
            channel.updateTimeout
        );
    }

    function checkpointChannelDispute(
        bytes32 channelId,
        // updateParams = [sequence, numOpenThread, weiBalanceA, weiBalanceI, tokenBalanceA, tokenBalanceI,
        // pendingDepositWeiA, pendingDepositWeiI, pendingDepositTokenA, pendingDepositTokenI,
        // pendingWithdrawalWeiA, pendingWithdrawalWeiI, pendingWithdrawalTokenA, pendingWithdrawalTokenI]
        uint256[14] updateParams,
        bytes32 threadRootHash,
        string sigA,
        string sigI
    )
        public
    {
        require(topLevel, "checkpointChannelDispute: Top level function can only be called directly");

        Channel storage channel = channels[channelId];
        require(channel.status == ChannelStatus.Settling, "checkpointChannel: Channel status must be Settling");
        require(now < channel.updateTimeout);
        // input balances can be less than on-chain balances because of balance bonded in threads
        require(
            updateParams[2].add(updateParams[3]) <= channel.balancesA[0].add(channel.balancesI[0]),
            "checkpointChannel: On-chain eth balances must be higher than provided balances"
        );
        require(
            updateParams[4].add(updateParams[5]) <= channel.balancesA[1].add(channel.balancesI[1]),
            "checkpointChannel: On-chain token balances must be higher than provided balances"
        );

        // verify sig and update chain
        _verifyUpdateSig(
            channel,
            channelId,
            false, // isClose
            updateParams,
            threadRootHash, // threadRootHash
            sigA,
            sigI
        );

        // update chain state, do not account for pending
        channel.sequence = updateParams[0];
        channel.numOpenThread = updateParams[1];
        channel.balancesA[0] = updateParams[2]; // weiBalanceA
        channel.balancesI[0] = updateParams[3]; // weiBalanceI
        channel.balancesA[1] = updateParams[4]; // tokenBalanceA
        channel.balancesI[1] = updateParams[5]; // tokenBalanceI
        channel.threadRootHash = threadRootHash;
        channel.updateTimeout = now.add(channel.confirmTime);

        emit DidChannelCheckpointDispute(
            channelId,
            updateParams[0], // sequence
            updateParams[2], // weiBalanceA
            updateParams[3], // weiBalanceI
            updateParams[4], // tokenBalanceA
            updateParams[5], // tokenBalanceI
            updateParams[1], // numOpenThread
            threadRootHash,
            channel.updateTimeout
        );
    }

    // supply initial state of thread to "prime" the force push game
    function initThread(
        bytes32 channelId,
        bytes32 threadId,
        bytes proof,
        address partyA,
        address partyB,
        uint256[2] balances, // [weiBalanceA, tokenBalanceA]
        string sigA
    )
        public
    {
        require(topLevel, "initThread: Top level function can only be called directly");
        require(msg.sender == partyA || msg.sender == partyB || msg.sender == hubAddress, "initThread: Sender must be part of thread");
        require(channels[channelId].status == ChannelStatus.Settling, "initThread: Channel status must be Settling");
        require(threads[threadId].status == ThreadStatus.Nonexistent, "initThread: Thread exists");
        require(now > channels[channelId].updateTimeout, "initThread: Update channel timeout not expired");
        // dont need to check parties because root hash contains the initial state and was verified by hub

        bytes32 initState = keccak256(
            abi.encodePacked(
                threadId,
                uint256(0), // sequence
                partyA,
                partyB,
                balances[0], // weiBalanceA
                uint256(0), // weiBalanceI
                balances[1], // tokenBalanceA
                uint256(0) // tokenBalanceA
            )
        );

        // Make sure Alice has signed initial thread state (A/B in oldState)
        require(ECTools.recoverSigner(initState, sigA) == partyA, "initThread: Party A signature invalid");

        // Check the initState is in the root hash
        require(
            _isContained(initState, proof, channels[channelId].threadRootHash) == true,
            "initThread: Old state is not contained in root hash"
        );

        threads[threadId] = Thread({
            status: ThreadStatus.Settling,
            partyA: partyA,
            partyB: partyB,
            sequence: 0,
            balancesA: balances,
            balancesB: [uint256(0), uint256(0)],
            updateTimeout: now.add(channels[channelId].confirmTime)
        });

        emit DidThreadInit(
            channelId,
            threadId,
            proof,
            uint256(0), // sequence
            partyA,
            partyB,
            balances[0], // weiBalanceA
            balances[1] // tokenBalanceA
        );
    }

    function settleThread(
        bytes32 channelId,
        bytes32 threadId,
        uint256 sequence,
        address partyA,
        address partyB,
        uint256[4] balances, // [weiBalanceA, weiBalanceI, tokenBalanceA, tokenBalanceI]
        string sigA
    )
        public
    {
        require(topLevel, "settleThread: Top level function can only be called directly");

        Thread storage thread = threads[threadId];

        require(
            msg.sender == partyA || msg.sender == partyB || msg.sender == hubAddress,
            "settleThread: Sender must be part of thread"
        );
        require(channels[channelId].status == ChannelStatus.Settling, "settleThread: Channel status must be Settling");
        // init thread must have been called before this
        require(thread.status == ThreadStatus.Settling, "settleThread: Thread status must be Settling");

        // TODO: Can remove this once we implement logic to only allow one settle call
        require(sequence > thread.sequence, "settleThread: Sequence must be higher than on-chain");
        require(
            balances[0].add(balances[2]) == thread.balancesA[0].add(thread.balancesB[0]),
            "settleThread: Wei balances must equal initial state"
        );
        require(
            balances[1].add(balances[3]) == thread.balancesA[1].add(thread.balancesB[1]),
            "settleThread: Token balances must equal initial state"
        );
        require(
            balances[1] >= thread.balancesB[0] && // wei
            balances[3] >= thread.balancesB[1], // token
            "settleThread: State updates may only increase recipient balance."
        );
        require(now < thread.updateTimeout, "settleThread: Timeouts not expired");

        bytes32 fingerprint = keccak256(
            abi.encodePacked(
                threadId,
                sequence,
                partyA,
                partyB,
                balances[0], // weiBalanceA
                balances[1], // weiBalanceI
                balances[2], // tokenBalanceA
                balances[3] // tokenBalanceI
            )
        );

        require(thread.partyA == ECTools.recoverSigner(fingerprint, sigA), "settleThread: Party A signature invalid");

        // TODO: remove this, only can call this function once
        thread.sequence = sequence;

        thread.balancesA[0] = balances[0]; // wei
        thread.balancesB[0] = balances[1]; // wei
        thread.balancesA[1] = balances[2]; // token
        thread.balancesB[1] = balances[3]; // token

        // TODO: remove this, only can call this function once
        thread.updateTimeout = now.add(channels[channelId].confirmTime);

        emit DidThreadSettle(
            channelId,
            threadId,
            sequence,
            balances[0], // weiBalanceA
            balances[1], // weiBalanceB
            balances[2], // tokenBalanceA
            balances[3], // tokenBalanceB
            thread.updateTimeout
        );
    }

    function closeThread(bytes32 channelId, bytes32 threadId) public {
        require(topLevel, "closeThread: Top level function can only be called directly");

        Channel storage channel = channels[channelId];
        Thread storage thread = threads[threadId];

        require(channel.status == ChannelStatus.Settling, "closeThread: Channel status must be Settling");
        require(thread.status == ThreadStatus.Settling, "closeThread: Virtual channel status must be Settling");
        require(now > thread.updateTimeout, "closeThread: Update VC timeout has not expired.");

        // reduce the number of open virtual channels stored on LC
        channel.numOpenThread = channel.numOpenThread.sub(1);
        // close vc
        thread.status = ThreadStatus.Settled;

        // re-introduce the balances back into the LC state from the settled VC
        // decide if this lc is alice or bob in the vc
        if(thread.partyA == channel.partyA) {
            // channel A to I: partyA += threadBalanceA, partyI += threadBalanceB
            // wei
            channel.balancesA[0] = channel.balancesA[0].add(thread.balancesA[0]);
            channel.balancesI[0] = channel.balancesI[0].add(thread.balancesB[0]);

            // token
            channel.balancesA[1] = channel.balancesA[1].add(thread.balancesA[1]);
            channel.balancesI[1] = channel.balancesI[1].add(thread.balancesB[1]);
        } else if (thread.partyB == hubAddress) {
            // channel I to B: partyI += threadBalanceA, partyA += threadBalanceB
            // wei
            channel.balancesA[0] = channel.balancesA[0].add(thread.balancesB[0]);
            channel.balancesI[0] = channel.balancesI[0].add(thread.balancesA[0]);

            // token
            channel.balancesA[1] = channel.balancesA[1].add(thread.balancesB[1]);
            channel.balancesI[1] = channel.balancesI[1].add(thread.balancesA[1]);
        }

        emit DidThreadClose(
            channelId,
            threadId,
            thread.balancesA[0], // wei
            thread.balancesA[1], // token
            thread.balancesB[0], // wei
            thread.balancesB[1] // token
        );
    }

    // TODO: allow either LC end-user to nullify the settled LC state and return to off-chain
    function byzantineCloseChannel(bytes32 channelId) public {
        require(topLevel, "byzantineCloseChannel: Top level function can only be called directly");

        Channel storage channel = channels[channelId];

        // check settlement flag
        require(channel.status == ChannelStatus.Settling, "byzantineCloseChannel: Channel status must be Settling");
        require(channel.numOpenThread == 0, "byzantineCloseChannel: Open threads must be 0");
        require(now > channel.updateTimeout, "byzantineCloseChannel: Channel timeout not over.");

        // reentrancy
        channel.status = ChannelStatus.Settled;

        uint256 weibalanceA = channel.balancesA[0];
        uint256 weibalanceI = channel.balancesI[0];
        uint256 tokenbalanceA = channel.balancesA[0];
        uint256 tokenbalanceI = channel.balancesI[1];

        channel.balancesA[0] = 0;
        channel.balancesA[1] = 0;
        channel.balancesI[0] = 0;
        channel.balancesI[1] = 0;

        channel.partyA.transfer(weibalanceA);
        hubAddress.transfer(weibalanceI);

        require(
            approvedToken.transfer(channel.partyA, tokenbalanceA),
            "byzantineCloseChannel: token transfer failure"
        );
        require(
            approvedToken.transfer(hubAddress, tokenbalanceI),
            "byzantineCloseChannel: token transfer failure"
        );

        emit DidChannelClose(
            channelId,
            channel.sequence,
            weibalanceA,
            weibalanceI,
            tokenbalanceA,
            tokenbalanceI
        );
    }

    function _verifyUpdateSig(
        Channel storage channel,
        bytes32 channelId,
        bool isClose,
        // updateParams = [sequence, numOpenThread, weiBalanceA, weiBalanceI, tokenBalanceA, tokenBalanceI,
        // pendingDepositWeiA, pendingDepositWeiI, pendingDepositTokenA, pendingDepositTokenI,
        // pendingWithdrawalWeiA, pendingWithdrawalWeiI, pendingWithdrawalTokenA, pendingWithdrawalTokenI]
        uint256[14] updateParams,
        bytes32 threadRootHash,
        string sigA,
        string sigI
    )
        internal
        view
    {
        require(
            updateParams[0] > channel.sequence,
            "checkpointChannel: Sequence must be higher or zero-state update"
        );

        // need to encode double here because of weird stack issues
        // see: https://github.com/ethereum/solidity/issues/2931#issuecomment-422024109
        bytes32 fingerprint = keccak256(
            abi.encodePacked(
                abi.encodePacked(
                    channelId,
                    isClose,
                    updateParams[0], // sequence
                    updateParams[1], // numOpenThread
                    threadRootHash,
                    channel.partyA,
                    hubAddress, // partyI
                    updateParams[2], // weiBalanceA
                    updateParams[3], // weiBalanceI
                    updateParams[4], // tokenBalanceA
                    updateParams[5] // tokenBalanceI
                ),
                abi.encodePacked(
                    updateParams[6], // pendingDepositWeiA
                    updateParams[7], // pendingDepositWeiI
                    updateParams[8], // pendingDepositTokenA
                    updateParams[9], // pendingDepositTokenI
                    updateParams[10], // pendingWithdrawalWeiA
                    updateParams[11], // pendingWithdrawalWeiI
                    updateParams[12], // pendingWithdrawalTokenA
                    updateParams[13] // pendingWithdrawalTokenI
                )
            )
        );

        require(
            ECTools.recoverSigner(fingerprint, sigA) == channel.partyA,
            "checkpointChannel: Party A signature invalid"
        );
        require(
            ECTools.recoverSigner(fingerprint, sigI) == hubAddress,
            "checkpointChannel: Party I signature invalid"
        );
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
}
