pragma solidity ^0.4.23;

import "./lib/ECTools.sol";

/// @title Set Virtual Channels - A layer2 hub and spoke payment network 
/// @author Nathan Ginnever

contract LedgerChannel {

    string public constant NAME = "Ledger Channel";
    string public constant VERSION = "0.0.1";

    // timeout storage
    uint256 public confirmTime = 0 minutes;

    uint256 public numChannels = 0;

    event DidLCOpen (
        bytes32 indexed channelId,
        address indexed partyA,
        address indexed partyI,
        uint256 balanceA
    );

    event DidLCJoin (
        bytes32 indexed channelId,
        uint256 balanceI
    );

    event DidLCDeposit (
        bytes32 indexed channelId,
        address indexed recipient,
        uint256 deposit
    );

    event DidLCUpdateState (
        bytes32 indexed channelId, 
        uint256 sequence, 
        uint256 numOpenVc, 
        uint256 balanceA, 
        uint256 balanceI, 
        bytes32 vcRoot
    );

    event DidLCClose (
        bytes32 indexed channelId,
        uint256 balanceA,
        uint256 balanceI
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
        address partyA, 
        address partyB, 
        uint256 updateBalA, 
        uint256 updateBalB,
        address challenger
    );

    event DidVCClose(
        bytes32 indexed lcId, 
        bytes32 indexed vcId, 
        uint256 balanceA, 
        uint256 balanceB
    );

    struct Channel {
        address partyA;
        address partyI;
        uint256 balanceA;
        uint256 balanceI;
        uint256 sequence;
        bytes32 stateHash;
        bytes32 VCrootHash;
        uint256 LCopenTimeout;
        uint256 updateLCtimeout; // when update LC times out
        bool isOpen; // true when both parties have joined
        bool isUpdateLCSettling;
        uint256 numOpenVC;
        //address closingParty;
    }

    // virtual-channel state
    struct VirtualChannel {
        bool isClose;
        bool isInSettlementState;
        uint256 sequence;
        address challenger; // Initiator of challenge
        uint256 updateVCtimeout; // when update VC times out
        // channel state
        address partyA; // VC participant A
        address partyB; // VC participant B
        address partyI; // LC hub
        uint256 balanceA;
        uint256 balanceB;
        uint256 bond;
        //uint256 balanceI;
    }

    mapping(bytes32 => VirtualChannel) public virtualChannels;
    mapping(bytes32 => Channel) public Channels;

    function createChannel(bytes32 _lcID, address _partyI) public payable {
        require(Channels[_lcID].partyA == address(0), "Channel has already been created.");
        require(_partyI != 0x0, "No partyI address provided to LC creation");
        require(Channels[_lcID].isOpen == false, "Channel already open");
        require(Channels[_lcID].sequence == 0, "Channel has already been used");
        // Set initial ledger channel state
        // Alice must execute this and we assume the initial state 
        // to be signed from this requirement
        // Alternative is to check a sig as in joinChannel
        Channels[_lcID].partyA = msg.sender;
        Channels[_lcID].partyI = _partyI;
        Channels[_lcID].balanceA = msg.value;
        Channels[_lcID].sequence = 0;
        // is close flag, lc state sequence, number open vc, vc root hash, partyA... 
        //Channels[_lcID].stateHash = keccak256(uint256(0), uint256(0), uint256(0), bytes32(0x0), bytes32(msg.sender), bytes32(_partyI), balanceA, balanceI);
        Channels[_lcID].LCopenTimeout = now + confirmTime;

        emit DidLCOpen(_lcID, msg.sender, _partyI, msg.value);
    }

    function LCOpenTimeout(bytes32 _lcID) public {
        require(msg.sender == Channels[_lcID].partyA && Channels[_lcID].isOpen == false);
        if (now > Channels[_lcID].LCopenTimeout) {
            Channels[_lcID].partyA.transfer(Channels[_lcID].balanceA);
            // only safe to delete since no action was taken on this channel
            delete Channels[_lcID];

            emit DidLCClose(_lcID, Channels[_lcID].balanceA, 0);
        }
    }

    function joinChannel(bytes32 _lcID) public payable {
        // require the channel is not open yet
        require(Channels[_lcID].isOpen == false);
        require(msg.sender == Channels[_lcID].partyI);
        // Initial state
        //address recover = ECTools.recoverSigner(Channels[_lcID].stateHash, _sigI);
        Channels[_lcID].balanceI = msg.value;

        // no longer allow joining functions to be called
        Channels[_lcID].isOpen = true;
        numChannels++;

        emit DidLCJoin(_lcID, msg.value);
    }


    // additive updates of monetary state
    function deposit(bytes32 _lcID, address recipient) public payable {
        require(Channels[_lcID].isOpen == true, "Tried adding funds to a closed channel");
        require(recipient == Channels[_lcID].partyA || recipient == Channels[_lcID].partyI);

        if (Channels[_lcID].partyA == recipient) { Channels[_lcID].balanceA += msg.value; }
        if (Channels[_lcID].partyI == recipient) { Channels[_lcID].balanceI += msg.value; }
        
        emit DidLCDeposit(_lcID, recipient, msg.value);
    }

    // TODO: Check there are no open virtual channels, the client should have cought this before signing a close LC state update
    function consensusCloseChannel(
        bytes32 _lcID, 
        uint256 _sequence, 
        uint256 _balanceA, 
        uint256 _balanceI, 
        string _sigA, 
        string _sigI
    ) 
        public 
    {
        // assume num open vc is 0 and root hash is 0x0
        require(Channels[_lcID].sequence < _sequence);
        bytes32 _state = keccak256(
            abi.encodePacked(
                true,
                _sequence,
                uint256(0),
                bytes32(0x0),
                Channels[_lcID].partyA, 
                Channels[_lcID].partyI, 
                _balanceA, 
                _balanceI
            )
        );

        require(Channels[_lcID].partyA == ECTools.recoverSigner(_state, _sigA));
        require(Channels[_lcID].partyI == ECTools.recoverSigner(_state, _sigI));

        Channels[_lcID].partyA.transfer(_balanceA);
        Channels[_lcID].partyI.transfer(_balanceI);

        Channels[_lcID].isOpen = false;
        numChannels--;

        emit DidLCClose(_lcID, _balanceA, _balanceI);
    }

    // Byzantine functions

    function updateLCstate(
        bytes32 _lcID, 
        uint256 _sequence, 
        uint256 _numOpenVc, 
        uint256 _balanceA, 
        uint256 _balanceI, 
        bytes32 _VCroot, 
        string _sigA, 
        string _sigI
    ) 
        public 
    {
        require(Channels[_lcID].sequence < _sequence); // do same as vc sequence check

        bytes32 _state = keccak256(
            abi.encodePacked(
                false, 
                _sequence, 
                _numOpenVc, 
                _VCroot, 
                Channels[_lcID].partyA, 
                Channels[_lcID].partyI, 
                _balanceA, 
                _balanceI
            )
        );

        require(Channels[_lcID].partyA == ECTools.recoverSigner(_state, _sigA));
        require(Channels[_lcID].partyI == ECTools.recoverSigner(_state, _sigI));

        // update LC state
        Channels[_lcID].sequence = _sequence;
        Channels[_lcID].numOpenVC = _numOpenVc;
        Channels[_lcID].balanceA = _balanceA;
        Channels[_lcID].balanceI = _balanceI;
        Channels[_lcID].VCrootHash = _VCroot;

        Channels[_lcID].isUpdateLCSettling = true;
        Channels[_lcID].updateLCtimeout = now + confirmTime;

        // make settlement flag

        emit DidLCUpdateState (
            _lcID, 
            _sequence, 
            _numOpenVc, 
            _balanceA, 
            _balanceI, 
            _VCroot
        );
    }

    //TODO: verify state transition since the hub did not agree to this state
    // make sure the A/B balances are not beyond ingrids bonds    
    function initVCstate(
        bytes32 _lcID, 
        bytes32 _vcID, 
        bytes _proof, 
        uint256 _sequence, 
        address _partyA, 
        address _partyB, 
        uint256 _bond,
        uint256 _balanceA,
        uint256 _balanceB,
        string sigA
    ) 
        public 
    {
        // sub-channel must be open
        require(!virtualChannels[_vcID].isClose, "VC is closed.");
        require(virtualChannels[_vcID].sequence == 0, "VC sequence is not 0");
        // Check time has passed on updateLCtimeout and has not passed the time to store a vc state
        require(Channels[_lcID].updateLCtimeout < now, "LC timeout over.");
        // partyB is now Ingrid
        bytes32 _initState = keccak256(
            abi.encodePacked(_vcID, _sequence, _partyA, _partyB, _bond, _balanceA, _balanceB)
        );

        // Make sure Alice has signed initial vc state (A/B in oldState)
        require(_partyA == ECTools.recoverSigner(_initState, sigA));

        // Check the oldState is in the root hash
        //require(_isContained(_initState, _proof, Channels[_lcID].VCrootHash));

        virtualChannels[_vcID].partyA = _partyA; // VC participant A
        virtualChannels[_vcID].partyB = _partyB; // VC participant B
        virtualChannels[_vcID].sequence = _sequence;
        virtualChannels[_vcID].balanceA = _balanceA;
        virtualChannels[_vcID].balanceB = _balanceB;
        virtualChannels[_vcID].bond = _bond;
        virtualChannels[_vcID].updateVCtimeout = now + confirmTime;

        emit DidVCInit(_lcID, _vcID, _proof, _sequence, _partyA, _partyB, _balanceA, _balanceB);
    }

    // Params: vc init state, vc final balance, vcID
    function settleVC(
        bytes32 _lcID, 
        bytes32 _vcID, 
        uint256 updateSeq, 
        address _partyA, 
        address _partyB,
        uint256 updateBalA, 
        uint256 updateBalB, 
        string sigA
    ) 
        public 
    {
        // sub-channel must be open
        require(!virtualChannels[_vcID].isClose, "VC is closed.");
        require(virtualChannels[_vcID].sequence < updateSeq, "VC sequence is higher than update sequence.");
        require(virtualChannels[_vcID].balanceB < updateBalB, "State updates may only increase recipient balance.");
        require(virtualChannels[_vcID].bond == updateBalA + updateBalB, "Incorrect balances for bonded amount");
        // Check time has passed on updateLCtimeout and has not passed the time to store a vc state
        //require(Channels[_lcID].updateLCtimeout < now && now < virtualChannels[_vcID].updateVCtimeout);
        require(Channels[_lcID].updateLCtimeout < now); // for testing!

        bytes32 _updateState = keccak256(
            abi.encodePacked(_vcID, updateSeq, _partyA, _partyB, virtualChannels[_vcID].bond, updateBalA, updateBalB)
        );

        // Make sure Alice has signed a higher sequence new state
        require(virtualChannels[_vcID].partyA == ECTools.recoverSigner(_updateState, sigA));

        // store VC data
        // we may want to record who is initiating on-chain settles
        virtualChannels[_vcID].challenger = msg.sender;
        virtualChannels[_vcID].sequence = updateSeq;

        // channel state
        virtualChannels[_vcID].balanceA = updateBalA;
        virtualChannels[_vcID].balanceB = updateBalB;

        virtualChannels[_vcID].updateVCtimeout = now + confirmTime;
        virtualChannels[_vcID].isInSettlementState = true;

        emit DidVCSettle(_lcID, _vcID, updateSeq, _partyA, _partyB, updateBalA, updateBalB, msg.sender);
    }

    function closeVirtualChannel(bytes32 _lcID, bytes32 _vcID) public {
        // require(updateLCtimeout > now)
        require(virtualChannels[_vcID].isInSettlementState, "VC is not in settlement state.");
        require(virtualChannels[_vcID].updateVCtimeout < now, "Update vc timeout has not elapsed.");
        // reduce the number of open virtual channels stored on LC
        Channels[_lcID].numOpenVC--;
        // re-introduce the balances back into the LC state from the settled VC
        // decide if this lc is alice or bob in the vc
        if(virtualChannels[_vcID].partyA == Channels[_lcID].partyA) {
            Channels[_lcID].balanceA += virtualChannels[_vcID].balanceA;
            Channels[_lcID].balanceI += virtualChannels[_vcID].balanceB;
        } else if (virtualChannels[_vcID].partyB == Channels[_lcID].partyA) {
            Channels[_lcID].balanceA += virtualChannels[_vcID].balanceB;
            Channels[_lcID].balanceI += virtualChannels[_vcID].balanceA;
        }
        // close vc flags
        virtualChannels[_vcID].isClose = true;

        emit DidVCClose(_lcID, _vcID, virtualChannels[_vcID].balanceA, virtualChannels[_vcID].balanceB);
    }


    function byzantineCloseChannel(bytes32 _lcID) public{
        // check settlement flag
        require(Channels[_lcID].isUpdateLCSettling == true);
        require(Channels[_lcID].numOpenVC == 0);

        // reentrancy
        uint256 balanceA = Channels[_lcID].balanceA;
        uint256 balanceI = Channels[_lcID].balanceI;
        Channels[_lcID].balanceA = 0;
        Channels[_lcID].balanceI = 0;

        Channels[_lcID].partyA.transfer(balanceA);
        Channels[_lcID].partyI.transfer(balanceI);
        Channels[_lcID].isOpen = false;
        numChannels--;

        emit DidLCClose(_lcID, balanceA, balanceI);
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
