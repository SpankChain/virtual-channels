pragma solidity ^0.4.23;

import "./lib/ECTools.sol";
import "./lib/token/HumanStandardToken.sol";
import "./lib/SafeMath.sol";

/// @title Set Virtual Channels - A layer2 hub and spoke payment network 

contract LedgerChannel {
    using SafeMath for uint256;

    string public constant NAME = "Ledger Channel";
    string public constant VERSION = "0.0.1";

    uint256 public numChannels = 0;

    event DidLCOpen (
        bytes32 indexed channelId,
        address indexed partyA,
        address indexed partyI,
        uint256 ethBalanceA,
        address token,
        uint256 tokenBalanceA,
        uint256 LCopenTimeout
    );

    event DidLCJoin (
        bytes32 indexed channelId,
        uint256 ethBalanceI,
        uint256 tokenBalanceI
    );

    event DidLCDeposit (
        bytes32 indexed channelId,
        address indexed recipient,
        uint256 ethDeposit,
        uint256 tokenDeposit
    );

    event DidLCUpdateState (
        bytes32 indexed channelId, 
        uint256 sequence, 
        uint256 numOpenVc, 
        uint256 ethBalanceA,
        uint256 tokenBalanceA,
        uint256 ethBalanceI,
        uint256 tokenBalanceI,
        bytes32 vcRoot,
        uint256 updateLCtimeout
    );

    event DidLCClose (
        bytes32 indexed channelId,
        uint256 sequence,
        uint256 ethBalanceA,
        uint256 tokenBalanceA,
        uint256 ethBalanceI,
        uint256 tokenBalanceI
    );

    event DidVCInit (
        bytes32 indexed lcId, 
        bytes32 indexed vcId, 
        bytes proof, 
        uint256 sequence, 
        address partyA, 
        address partyB, 
        uint256 balanceA, 
        uint256 balanceB 
    );

    event DidVCSettle (
        bytes32 indexed lcId, 
        bytes32 indexed vcId,
        uint256 updateSeq, 
        uint256 updateBalA, 
        uint256 updateBalB,
        address challenger,
        uint256 updateVCtimeout
    );

    event DidVCClose(
        bytes32 indexed lcId, 
        bytes32 indexed vcId, 
        uint256 balanceA, 
        uint256 balanceB
    );

    event WhitelistModified(
        address indexed token,
        bool added
    );

    enum ChannelStatus {
        Nonexistent,
        Opened,
        Joined,
        Settling,
        Settled
    }

    struct Channel {
        address[2] partyAddresses; // 0: partyA 1: partyI
        uint256[4] ethBalances; // 0: balanceA 1:balanceI 2:depositedA 3:depositedI
        uint256[4] erc20Balances; // 0: balanceA 1:balanceI 2:depositedA 3:depositedI
        uint256[2] initialDeposit; // 0: eth 1: tokens
        uint256 sequence;
        uint256 confirmTime;
        bytes32 VCrootHash;
        uint256 LCopenTimeout;
        uint256 updateLCtimeout; // when update LC times out
        ChannelStatus status;
        bool isOpen; // true when both parties have joined
        bool isUpdateLCSettling;
        uint256 numOpenVC;
        HumanStandardToken token; // TODO add onlyowner method for whitelisting tokens
    }

    // TODO new enum for VC states
    // virtual-channel state
    struct VirtualChannel {
        ChannelStatus status;
        uint256 sequence;
        address challenger; // Initiator of challenge
        uint256 updateVCtimeout; // when update VC times out
        // channel state
        address partyA; // VC participant A
        address partyB; // VC participant B
        uint256[2] ethBalances;
        uint256[2] erc20Balances;
        uint256[2] bond;
        HumanStandardToken token;
    }

    mapping(bytes32 => VirtualChannel) public virtualChannels;
    mapping(bytes32 => Channel) public Channels;

    address public approvedToken;
    address public hubAddress;

    constructor(address _token, address _hubAddress) public {
        approvedToken = _token;
        hubAddress = _hubAddress;
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
        Channels[_lcID].erc20Balances[0] = 0;
        Channels[_lcID].erc20Balances[1] = 0;

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

        //if(Channels[_lcID].token)

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
        require(virtualChannels[_vcID].status != ChannelStatus.Settled, "VC is closed");
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

        virtualChannels[_vcID].status = ChannelStatus.Settling;
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
        require(virtualChannels[_vcID].status == ChannelStatus.Settling, "Virtual channel status must be Settling");

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
        require(virtualChannels[_vcID].status == ChannelStatus.Settling, "Virtual channel status must be Settling");
        require(virtualChannels[_vcID].updateVCtimeout < now, "Update VC timeout has not expired.");

        // reduce the number of open virtual channels stored on LC
        Channels[_lcID].numOpenVC = Channels[_lcID].numOpenVC.sub(1);
        // close vc 
        virtualChannels[_vcID].status = ChannelStatus.Settled;

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
        address,
        uint256,
        address,
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
            virtualChannel.challenger,
            virtualChannel.updateVCtimeout,
            virtualChannel.partyA,
            virtualChannel.partyB,
            virtualChannel.partyI,
            virtualChannel.ethBalances,
            virtualChannel.erc20Balances,
            virtualChannel.bond
        );
    }
}
