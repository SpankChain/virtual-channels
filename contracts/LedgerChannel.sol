pragma solidity ^0.4.23;

/// @title SpankChain Virtual-Channel - A multisignature "wallet" for general state
/// @author Nathan Ginnever (Finality Labs)

contract LedgerChannel {

    string public constant NAME = "Ledger Channel";
    string public constant VERSION = "0.0.1";


    address public partyA;
    address public partyB;
    uint256 public balanceA;
    uint256 public balanceB;
    uint256 public sequence;
    uint256 public confirmTime = 100 minutes;

    bytes32 public stateHash;

    bool public isOpen = false; // true when both parties have joined
    bool public isPending = false; // true when waiting for counterparty to join agreement
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
        address partyA;
        address partyB;
        address partyI;
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
    }

    function joinChannel(uint8 _v, bytes32 _r, bytes32 _s) public payable {
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
    function closeChannel(uint256 isClose, uint256 sequence, uint256 _balanceA, uint256 _balanceB, uint8[2] sigV, bytes32[2] sigR, bytes32[2] sigS) public {
        require(isClose == 1, 'State did not have a signed close sentinel');

        bytes32 _state = keccak256(isClose, sequence, 0x0, partyA, partyB, _balanceA, _balanceB);

        require(partyA == _getSig(_state, sigV[0], sigR[0], sigS[0]));
        require(partyB == _getSig(_state, sigV[1], sigR[1], sigS[1]));

        require(_hasAllSigs(_partyA, _partyB));

        _finalizeAll(_balanceA, _balanceB);
        isOpen = false;
    }


    function closeVirtualChannel(uint _vcID) public {

        uint isSettle;
        bytes memory _state;
        (,isSettle,,,,,,,,,_state) = deployedMetaChannel.getSubChannel(_subchannelID);
        //require(isSettle == 1);

        address _ext = _getInterpreter(_state);

        _finalizeSubchannel(_state, _ext);
    }

    function closeWithMetachannel() public {
        // TODO send all remaining msig funds to challenger to punish counterparty from dropping off
        // this prevents the counterparty knowing that it would cost more to go on chain than the
        // value that has been exchanged in a subchannel. Use the msig balance as a bond of trust
        MetaChannel deployedMetaChannel = MetaChannel(registry.resolveAddress(metachannel));

        uint isClosed;
        bytes memory _state;
        isClosed = deployedMetaChannel.isClosed();
        require(isClosed == 1);
        _state = deployedMetaChannel.state();

        _finalizeAll(_state);
    }

    // Internal

    function _finalizeAll(uint256 _balanceA, uint256 _balanceB,) internal {
        partyA.transfer(_balanceA);
        partyB.transfer(_balanceB);
    }

    // send all funds to metachannel if a channel is in dispute
    function _finalizeSubchannel(bytes _s, address _ext) internal {
        uint _length = _s.length;
        require(address(_ext).delegatecall(bytes4(keccak256("finalizeByzantine(bytes)")), bytes32(32), bytes32(_length), _s));
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
