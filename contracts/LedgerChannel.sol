pragma solidity ^0.4.23;

/// @title SpankChain Virtual-Channels - A layer2 hub and spoke payment network 
/// @author Nathan Ginnever

contract LedgerChannel {

    string public constant NAME = "Ledger Channel";
    string public constant VERSION = "0.0.1";


    address public partyA; // VC participant
    address public partyB; // Hub
    uint256 public balanceA;
    uint256 public balanceB;
    uint256 public sequence;
    uint256 public confirmTime = 100 minutes;
    uint256 public LCopenTimeout = 0;
    uint256 public LCcloseTimeout = 0;
    bytes32 public stateHash;
    bytes32 public VCrootHash;

    // timeout storage
    uint256 public updateLCtimeout; // when update LC times out

    bool public isOpen = false; // true when both parties have joined
    bool public isUpdateLCSettling = false;
    bool public isFinal = false;

    address public closingParty = address(0x0);

    // virtual-channel state
    struct VirtualChannel {
        uint isClose;
        uint isInSettlementState;
        uint sequence;
        address challenger; // Initiator of challenge
        uint settlementPeriodLength; // timeout length for challenges
        uint settlementPeriodEnd; // Validity
        uint settledAt;
        uint subchan1; // ID of LC AI
        uint subchan2; // ID of LC BI
        // channel state
        address partyA; // VC participant A
        address partyB; // VC participant B
        address partyI; // LC party B hub
        uint256 balanceA;
        uint256 balanceB;
        uint256 balanceI;
    }

    mapping(uint => VirtualChannel) VirtualChannels;

    constructor(address _partyA, address _partyB, uint256 _balanceA, uint256 _balanceB) public payable {
        require(_partyA != 0x0, 'No partyA address provided to LC constructor');
        require(_partyB != 0x0, 'No partyB address provided to LC constructor');
        require(msg.value == _balanceA);
        require(msg.sender == _partyA);
        // Set initial ledger channel state
        // Alice must execute this and we assume the initial state 
        // to be signed from this requirement
        // Alternative is to check a sig as in joinChannel
        partyA = _partyA;
        partyB = _partyB;
        balanceA = _balanceA;
        balanceB = _balanceB;
        sequeunce = 0;
        stateHash = keccak256(0, 0, 0x0, partyA, partyB, balanceA, balanceB);
        LCopenTimeout = now + confirmTime;
    }

    function LCOpenTimeout() public {
        require(msg.sender == partyA && isOpen == false);
        if (now > LCopenTimeout) {
            selfdestruct(partyA);
        }
    }

    function openChannel(uint8 _v, bytes32 _r, bytes32 _s) public payable {
        // only allow pre-deployed extension contracts
        //require(_assertExtension(_ext));
        // require the channel is not open yet
        require(isOpen == false);
        // Initial state
        bytes32 _state = keccak256(0, 0, partyA, partyB, balanceA, balanceB);
        address recover = _getSig(_state, _v, _r, _s);
        require(keccak256(0, partyA, recover, balanceA, msg.value) == stateHash);

        // no longer allow joining functions to be called
        isOpen = true;

        // check that the state is signed by the sender and sender is in the state
        require(partyB == _getSig(_state, _v, _r, _s));
    }


    // additive updates of monetary state
    function deposit(address recipient) public payable {
        require(isOpen == true, 'Tried adding funds to a closed channel');
        require(recipient == partyA || recipient == partyB);

        if(partyA == recipient) { balanceA += msg.value; }
        if(partyB == recipient) { balanceB += msg.value; }
    }

    // TODO: Check there are no open virtual channels, the client should have cought this before signing a close LC state update
    function consensusCloseChannel(uint256 isClose, uint256 sequence, uint256 _balanceA, uint256 _balanceB, uint8[2] sigV, bytes32[2] sigR, bytes32[2] sigS) public {
        require(isClose == 1, 'State did not have a signed close sentinel');

        bytes32 _state = keccak256(isClose, sequence, 0x0, partyA, partyB, _balanceA, _balanceB);

        require(partyA == _getSig(_state, sigV[0], sigR[0], sigS[0]));
        require(partyB == _getSig(_state, sigV[1], sigR[1], sigS[1]));

        require(_hasAllSigs(_partyA, _partyB));

        _finalizeAll(_balanceA, _balanceB);
        isOpen = false;
    }

    // Byzantine functions

    function initUpdateLCstate(uint256 isClose, uint256 _sequence, uint256 _balanceA, uint256 _balanceB, bytes32 VCroot, uint8[2] sigV, bytes32[2] sigR, bytes32[2] sigS) public {
        require(isClose == 0, 'State should not have a signed close sentinel');
        require(sequence < _sequence);

        bytes32 _state = keccak256(isClose, sequence, VCroot, partyA, partyB, _balanceA, _balanceB);

        require(partyA == _getSig(_state, sigV[0], sigR[0], sigS[0]));
        require(partyB == _getSig(_state, sigV[1], sigR[1], sigS[1]));

        // update LC state
        sequence = _sequence;
        balanceA = _balanceA;
        balanceB = _balanceB;
        VCrootHash = VCroot;

        isUpdateLCSettling = true;
        updateLCtimeout = now + confirmTime;
    }

    function challengeUpdateLCstate(uint256 isClose, uint256 sequence, uint256 _balanceA, uint256 _balanceB, bytes32 VCroot, uint8[2] sigV, bytes32[2] sigR, bytes32[2] sigS) public {
        
    }

    // Check time has passed on updateLCtimeout
    function setUpdateFinalized() public {
        // updateFinal = true;
        // updateLCtimeout = 0;
    }

    // TODO: Check the update finalized flag
    // Currently you have to settle all channels if you are to settle one
    // change this to accept a sig not check the sender
    function startSettleVC(bytes _forceState, uint _vcID) public payable{
        // Make sure one of the parties has signed this subchannel update
        require(_hasOneSig(msg.sender));

        // sub-channel must be open
        require(subChannels[_channelID].isSubClose == 0);

        // Check forcestate against current state
        uint _length = _forceState.length;
        require(address(subChannels[_channelID].CTFaddress).delegatecall(bytes4(keccak256("validateState(bytes)")), bytes32(32), bytes32(_length), _forceState));

        subChannels[_channelID].challenger = msg.sender;
        subChannels[_channelID].subSequence = _getSequence(_forceState);
        subChannels[_channelID].subState = _forceState;
        subChannels[_channelID].subSettlementPeriodEnd = now + _getChallengePeriod(subChannels[_channelID].subState);
    }

    // challenger can agree to latest state proposed by initiator, or present a higher VC state
    function challengeSettleVC(bytes _forceState, uint _vcID) public payable{
        // check forceState VC sequence, challenge state must have higher or equal sequence

    }

    function closeVirtualChannel(uint _vcID) public {
        // TODO: Check the vcID is past teh VC settlement time
        // Rebalance LC ledger
        // Rebalance open channel merkle root
        // set
    }

    function startSettleLC() public {
        // again channel root must be 0x0
        // Same logic as update but close flag and different timeout storage location `LCcloseTimeout`
        // call initUpdateLCState()
    }

    function challengeSettleLC() public {
        // Same logic as update but close flag and different timeout storage location `LCcloseTimeout`
        // call initUpdateLCState()
    }

    function byzantineCloseChannel() public{
        // require(LCcloseTimeout < now)
        // isFinal == true;
    }

    // Internal

    function _finalizeAll(uint256 _balanceA, uint256 _balanceB,) internal {
        partyA.transfer(_balanceA);
        partyB.transfer(_balanceB);
    }

    function _CheckVC(uint vid, address p1, uint bal1, uint subchan1, address Ingrid,
                               address p2, uint bal2, uint subchan2, uint validity, bytes sig) private view {
        require(id == subchan1 || id == subchan2);
        require(Ingrid == alice.id || Ingrid == bob.id);
        require(Other(Ingrid, alice.id, bob.id) == p1 || Other(Ingrid, alice.id, bob.id) == p2);
        require(CheckSignature(Other(msg.sender, alice.id, bob.id), vid, p1, cash1, subchan1, Ingrid, p2, cash2, subchan2, validity, 0, sig));

        // check the vc state provided by either alice or ingrid to force close a VC
        // check the state is signed by Alice and Bob
        // check the balance settling against the LC balance does not go beyond partyA or B's bond in the VC
    }


    function _getSig(bytes _d, uint8 _v, bytes32 _r, bytes32 _s) internal pure returns(address) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 h = keccak256(_d);

        bytes32 prefixedHash = keccak256(prefix, h);

        address a = ecrecover(prefixedHash, _v, _r, _s);

        //address a = ECRecovery.recover(prefixedHash, _s);

        return(a);
    }
}
