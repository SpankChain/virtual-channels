pragma solidity ^0.4.23;

import "./HumanStandardToken.sol";

import "../../LedgerChannel.sol";

contract ReentrancyToken is HumanStandardToken {
    LedgerChannel ledgerChannel;
    uint256 constant MAX_REENTRIES = 5;
    uint256 numReentries = 0;

    event FakeTransfer(uint256 numReentries);

    constructor(
        uint256 _initialAmount,
        string _tokenName,
        uint8 _decimalUnits,
        string _tokenSymbol,
        address ledgerChannelAddress
    ) HumanStandardToken(
        _initialAmount, 
        _tokenName, 
        _decimalUnits, 
        _tokenSymbol
    ) public {
        ledgerChannel = LedgerChannel(ledgerChannelAddress);
    }

    function createChannel() public {
        ledgerChannel.createChannel.value(1 ether)(
            bytes32(0x1000000000000000000000000000000000000000000000000000000000000000),
            address(0x627306090abaB3A6e1400e9345bC60c78a8BEf57),
            0,
            this,
            [uint256(1000000000000000000), 1] // [eth, token]
        );
    }

    function transfer(address _to, uint256 _value) public returns (bool success) {
        if (numReentries >= MAX_REENTRIES) {
            return true;
        }
        numReentries++;
        ledgerChannel.LCOpenTimeout(bytes32(0x1000000000000000000000000000000000000000000000000000000000000000));
        FakeTransfer(numReentries);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        return true;
    }

    function () external payable {
    }
}