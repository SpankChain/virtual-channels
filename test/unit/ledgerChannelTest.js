"use strict";

import MerkleTree from "../helpers/MerkleTree";
const Utils = require("../helpers/utils");
const Ledger = artifacts.require("./LedgerChannel.sol");
const EC = artifacts.require("./ECTools.sol");
const Token = artifacts.require("./token/HumanStandardToken.sol");

const Web3latest = require("web3");
const web3latest = new Web3latest(
  new Web3latest.providers.HttpProvider("http://localhost:8545")
); //ganache port
const BigNumber = web3.BigNumber;

const should = require("chai")
  .use(require("chai-as-promised"))
  .use(require("chai-bignumber")(BigNumber))
  .should();

/** NOTE: tests should be wrapped in try-catch (commented out) and this SolRevert should be used if testing with ganache-ui */
// const SolRevert = (txId) => {
// 	return `Transaction: ${txId} exited with an error (status 0).\nPlease check that the transaction:\n    - satisfies all conditions set by Solidity \`require\` statements.\n    - does not trigger a Solidity \`revert\` statement.\n`
// }

const SolRevert = "VM Exception while processing transaction: revert";

function wait(ms) {
  const start = Date.now();
  console.log(`Waiting for ${ms}ms...`);
  while (Date.now() < start + ms) {}
  return true;
}

const emptyRootHash =
  "0x0000000000000000000000000000000000000000000000000000000000000000";

let lc;
let ec;
let token;
let bond;

// state
let partyA;
let partyB;
let partyI;
let partyN;

let vcRootHash;
let initialVCstate;

let payload;
let sigA;
let sigI;
let sigB;
let fakeSig;

//is close flag, lc state sequence, number open vc, vc root hash, partyA/B, partyI, balA/B, balI

contract("LedgerChannel :: createChannel()", function(accounts) {
  before(async () => {
    partyA = accounts[0];
    partyB = accounts[1];
    partyI = accounts[2];
    partyN = accounts[3];

    ec = await EC.new();
    token = await Token.new(web3latest.utils.toWei("1000"), "Test", 1, "TST");
    Ledger.link("HumanStandardToken", token.address);
    Ledger.link("ECTools", ec.address);
    lc = await Ledger.new();

    await token.transfer(partyB, web3latest.utils.toWei("100"));
    await token.transfer(partyI, web3latest.utils.toWei("100"));
  });

  describe("Creating a channel has 6 possible cases:", () => {
    it("1. Fail: Channel with that ID has already been created", async () => {
      const lcId = web3latest.utils.sha3("fail", { encoding: "hex" });
      const sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("10")
      ];
      const challenge = 0;
      let approval = await token.approve(lc.address, sentBalance[1]);
      await lc.createChannel(
        lcId,
        partyI,
        challenge,
        token.address,
        sentBalance,
        {
          from: partyA,
          value: sentBalance[0]
        }
      );
      let channel = await lc.getChannel(lcId);
      expect(channel[0][0]).to.not.be.equal(
        "0x0000000000000000000000000000000000000000"
      ); // channel exists on chain

      // approve second transfer
      approval = await token.approve(lc.address, sentBalance[1]);
      await lc
        .createChannel(lcId, partyI, "0", token.address, sentBalance, {
          from: partyA,
          value: sentBalance[0]
        })
        .should.be.rejectedWith(SolRevert);
    });

    it("2. Fail: No Hub address was provided.", async () => {
      const lcId = web3latest.utils.sha3("1111", { encoding: "hex" });
      const sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("10")
      ];
      const approval = await token.approve(lc.address, sentBalance[1]);
      const challenge = 0;
      const nullAddress = "0x0000000000000000000000000000000000000000";

      await lc
        .createChannel(
          lcId,
          nullAddress,
          challenge,
          token.address,
          sentBalance,
          {
            from: partyA,
            value: sentBalance[0]
          }
        )
        .should.be.rejectedWith(SolRevert);
    });

    it("3. Fail: Token balance input is negative.", async () => {
      const lcId = web3latest.utils.sha3("1111", { encoding: "hex" });
      const sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("-10")
      ];
      const approval = await token.approve(lc.address, sentBalance[1]);
      const challenge = 0;

      await lc
        .createChannel(lcId, partyI, challenge, token.address, sentBalance, {
          from: partyA,
          value: sentBalance[0]
        })
        .should.be.rejectedWith(SolRevert);
    });

    it("4. Fail: Eth balance doesn't match paid value.", async () => {
      const lcId = web3latest.utils.sha3("1111", { encoding: "hex" });
      const sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("10")
      ];

      const approval = await token.approve(lc.address, sentBalance[1]);
      const challenge = 0;

      await lc
        .createChannel(lcId, partyI, challenge, token.address, sentBalance, {
          from: partyA,
          value: web3latest.utils.toWei("1")
        })
        .should.be.rejectedWith(SolRevert);
    });

    it("5. Fail: Token transferFrom failed.", async () => {
      const lcId = web3latest.utils.sha3("1111", { encoding: "hex" });
      const sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("100000")
      ];

      const challenge = 0;

      await lc
        .createChannel(lcId, partyI, challenge, token.address, sentBalance, {
          from: partyA,
          value: sentBalance[0]
        })
        .should.be.rejectedWith(SolRevert);
    });

    it("6. Success: Channel created!", async () => {
      const lcId = web3latest.utils.sha3("1111", { encoding: "hex" });
      const sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("10")
      ];

      const approval = await token.approve(lc.address, sentBalance[1]);
      const challenge = 0;

      const tx = await lc.createChannel(
        lcId,
        partyI,
        challenge,
        token.address,
        sentBalance,
        { from: partyA, value: sentBalance[0] }
      );

      expect(tx.logs[0].event).to.equal("DidLCOpen");
      // check the on chain information stored
      const channel = await lc.getChannel(lcId);
      expect(channel[0][0]).to.be.equal(partyA);
      expect(channel[0][1]).to.be.equal(partyI);
      expect(channel[1][0].toString()).to.be.equal(sentBalance[0]); // ethBalanceA
      expect(channel[1][1].toString()).to.be.equal("0"); // ethBalanceI
      expect(channel[1][2].toString()).to.be.equal("0"); // depositedEthA
      expect(channel[1][3].toString()).to.be.equal("0"); // depositedEthI
      expect(channel[2][0].toString()).to.be.equal(sentBalance[1]); // erc20A
      expect(channel[2][1].toString()).to.be.equal("0"); //erc20I
      expect(channel[2][2].toString()).to.be.equal("0"); // depositedERC20A
      expect(channel[2][3].toString()).to.be.equal("0"); // depositedERC20I
      expect(channel[3][0].toString()).to.be.equal(sentBalance[0]); // initialDepositEth
      expect(channel[3][1].toString()).to.be.equal(sentBalance[1]); // initialDepositErc20
      expect(channel[4].toString()).to.be.equal("0"); // sequence
      expect(channel[5].toString()).to.be.equal(String(challenge)); // confirmTime
      expect(channel[6].toString()).to.be.equal(emptyRootHash); // vcRootHash
      expect(channel[7].toString()).to.be.equal(
        String(Math.floor(Date.now() / 1000))
      ); // lcopen timeout
      expect(channel[8].toString()).to.be.equal("0"); // updateLC timeout
      expect(channel[9]).to.be.equal(false); // isOpen
      expect(channel[10]).to.be.equal(false); // isUpdateSettling
      expect(channel[11].toString()).to.be.equal("0"); // numOpenVC
    });
  });
});

contract("LedgerChannel :: LCOpenTimeout()", function(accounts) {
  const lcId = web3latest.utils.sha3("asdfe3", { encoding: "hex" });
  const sentBalance = [
    web3latest.utils.toWei("10"),
    web3latest.utils.toWei("10")
  ];
  const challenge = 0;
  before(async () => {
    partyA = accounts[0];
    partyB = accounts[1];
    partyI = accounts[2];
    partyN = accounts[3];

    ec = await EC.new();
    token = await Token.new(web3latest.utils.toWei("1000"), "Test", 1, "TST");
    Ledger.link("HumanStandardToken", token.address);
    Ledger.link("ECTools", ec.address);
    lc = await Ledger.new();

    await token.transfer(partyB, web3latest.utils.toWei("100"));
    await token.transfer(partyI, web3latest.utils.toWei("100"));

    const approval = await token.approve(lc.address, sentBalance[1]);

    await lc.createChannel(
      lcId,
      partyI,
      challenge,
      token.address,
      sentBalance,
      {
        from: partyA,
        value: sentBalance[0]
      }
    );
  });

  describe("LCopenTimeout() has 5 possible cases:", () => {
    it("1. Fail: Sender is not PartyA of channel", async () => {
      await lc
        .LCOpenTimeout(lcId, { from: partyB })
        .should.be.rejectedWith(SolRevert);
    });

    it("2. Fail: Channel does not exist", async () => {
      const fakeLcId = web3latest.utils.sha3("wrong", { encoding: "hex" });
      await lc
        .LCOpenTimeout(fakeLcId, { from: partyA })
        .should.be.rejectedWith(SolRevert);
    });

    it("3. Fail: Channel is already open", async () => {
      // approve transfer
      const approval = await token.approve(lc.address, sentBalance[1]);

      const joinedChannelId = web3latest.utils.sha3("joined", {
        encoding: "hex"
      });
      await lc.createChannel(
        joinedChannelId,
        partyI,
        challenge,
        token.address,
        sentBalance,
        {
          from: partyA,
          value: sentBalance[0]
        }
      );
      await lc.joinChannel(joinedChannelId, [0, 0], { from: partyI });

      await lc
        .LCOpenTimeout(joinedChannelId, { from: partyA })
        .should.be.rejectedWith(SolRevert);
    });

    it("4. Fail: LCopenTimeout has not expired", async () => {
      const longChallenge = web3latest.utils.sha3("longTimer", {
        encoding: "hex"
      });
      const challenge = 10000;
      await lc.createChannel(
        longChallenge,
        partyI,
        challenge,
        token.address,
        [0, 0],
        { from: partyA, value: 0 }
      );

      await lc
        .LCOpenTimeout(longChallenge, { from: partyA })
        .should.be.rejectedWith(SolRevert);
    });

    //******
    // NOTE: there's one more require in the contract for a failed token transfer. Unfortunately we can't recreate that here.
    //******

    it("5. Success!", async () => {
      let channel = await lc.getChannel(lcId);

      const oldBalanceEth = await web3latest.eth.getBalance(partyA);
      const oldBalanceToken = await token.balanceOf(partyA);

      const tokenDeposit = web3latest.utils.toBN(channel[1][0]);
      const ethDeposit = web3latest.utils.toBN(channel[2][0]);

      // explicitly wait 1s
      wait(1000);
      const tx = await lc.LCOpenTimeout(lcId, { from: partyA });

      const newBalanceEth = await web3latest.eth.getBalance(partyA);
      const newBalanceToken = await token.balanceOf(partyA);

      const returnedTokens = web3latest.utils
        .toBN(newBalanceToken)
        .sub(web3latest.utils.toBN(oldBalanceToken));

      // rounding for gas
      let returnedEth = web3latest.utils.fromWei(
        web3latest.utils
          .toBN(newBalanceEth)
          .sub(web3latest.utils.toBN(oldBalanceEth)),
        "ether"
      );
      returnedEth = web3latest.utils.toBN(
        web3latest.utils.toWei(String(Math.ceil(returnedEth)))
      );

      // ensure transfer
      expect(returnedEth.eq(ethDeposit)).to.be.equal(true);
      expect(returnedTokens.eq(tokenDeposit)).to.be.equal(true);
      // ensure event
      expect(tx.logs[0].event).to.equal("DidLCClose");
      // ensure deletion
      channel = await lc.getChannel(lcId);
      expect(channel[0][0]).to.not.equal(partyA);
      expect(channel[0][1]).to.not.equal(partyI);
    });
  });
});

contract("LedgerChannel :: joinChannel()", function(accounts) {
  const sentBalance = [
    web3latest.utils.toWei("10"),
    web3latest.utils.toWei("10")
  ];

  const lcId = web3latest.utils.sha3("fail", { encoding: "hex" });

  before(async () => {
    partyA = accounts[0];
    partyB = accounts[1];
    partyI = accounts[2];
    partyN = accounts[3];

    ec = await EC.new();
    token = await Token.new(web3latest.utils.toWei("1000"), "Test", 1, "TST");
    Ledger.link("HumanStandardToken", token.address);
    Ledger.link("ECTools", ec.address);
    lc = await Ledger.new();

    await token.transfer(partyA, web3latest.utils.toWei("100"));
    await token.transfer(partyB, web3latest.utils.toWei("100"));
    await token.transfer(partyI, web3latest.utils.toWei("100"));

    // approve req token transfers for
    const approvalA = await token.approve(lc.address, sentBalance[1], {
      from: partyA
    });
    const approvalI = await token.approve(lc.address, sentBalance[1], {
      from: partyI
    });

    // create unjoined channel on contract
    const challenge = 0;
    await lc.createChannel(
      lcId,
      partyI,
      challenge,
      token.address,
      sentBalance,
      {
        from: partyA,
        value: sentBalance[0]
      }
    );
  });

  describe("joinChannel() has 6 possible cases:", () => {
    it("1. Fail: Channel with that ID has already been opened", async () => {
      // create joined channel on contract
      const challenge = 0;
      const openedLcId = web3latest.utils.sha3("opened", { encoding: "hex" });
      // approve req token transfers for
      const approvalA = await token.approve(lc.address, sentBalance[1], {
        from: partyA
      });
      await lc.createChannel(
        openedLcId,
        partyI,
        challenge,
        token.address,
        sentBalance,
        {
          from: partyA,
          value: sentBalance[0]
        }
      );
      await lc.joinChannel(openedLcId, [0, 0], { from: partyI });

      await lc
        .joinChannel(openedLcId, sentBalance, {
          from: partyI,
          value: sentBalance[0]
        })
        .should.be.rejectedWith(SolRevert);
    });

    it("2. Fail: Msg.sender is not PartyI of this channel", async () => {
      // approve partyB transfer
      const approval = await token.approve(lc.address, sentBalance[1], {
        from: partyB
      });

      await lc
        .joinChannel(lcId, sentBalance, {
          from: partyB,
          value: sentBalance[0]
        })
        .should.be.rejectedWith(SolRevert);
    });

    it("3. Fail: Token balance is negative", async () => {
      const failedBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("-10")
      ];

      await lc
        .joinChannel(lcId, failedBalance, {
          from: partyI,
          value: failedBalance[0]
        })
        .should.be.rejectedWith(SolRevert);
    });

    it("4. Fail: Eth balance does not match paid value", async () => {
      await lc
        .joinChannel(lcId, sentBalance, {
          from: partyI,
          value: web3latest.utils.toWei("1")
        })
        .should.be.rejectedWith(SolRevert);
    });

    it("5. Fail: Token transferFrom failed", async () => {
      const failedBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("100")
      ];

      await lc
        .joinChannel(lcId, failedBalance, {
          from: partyI,
          value: sentBalance[0]
        })
        .should.be.rejectedWith(SolRevert);
    });

    it("6. Success: LC Joined!", async () => {
      const tx = await lc.joinChannel(lcId, sentBalance, {
        from: partyI,
        value: sentBalance[0]
      });

      expect(tx.logs[0].event).to.equal("DidLCJoin");
      // check the on chain information stored
      const channel = await lc.getChannel(lcId);
      expect(channel[0][0]).to.be.equal(partyA);
      expect(channel[0][1]).to.be.equal(partyI);
      expect(channel[1][0].toString()).to.be.equal(sentBalance[0]); // ethBalanceA
      expect(channel[1][1].toString()).to.be.equal(sentBalance[0]); // ethBalanceI
      expect(channel[1][2].toString()).to.be.equal("0"); // depositedEthA
      expect(channel[1][3].toString()).to.be.equal("0"); // depositedEthI
      expect(channel[2][0].toString()).to.be.equal(sentBalance[1]); // erc20A
      expect(channel[2][1].toString()).to.be.equal(sentBalance[1]); //erc20I
      expect(channel[2][2].toString()).to.be.equal("0"); // depositedERC20A
      expect(channel[2][3].toString()).to.be.equal("0"); // depositedERC20I
      expect(channel[3][0].toString()).to.be.equal(
        web3latest.utils
          .toBN(sentBalance[0])
          .mul(web3latest.utils.toBN("2"))
          .toString()
      ); // initialDepositEth
      expect(channel[3][1].toString()).to.be.equal(
        web3latest.utils
          .toBN(sentBalance[1])
          .mul(web3latest.utils.toBN("2"))
          .toString()
      ); // initialDepositErc20
      expect(channel[4].toString()).to.be.equal("0"); // sequence
      expect(channel[5].toString()).to.be.equal("0"); // confirmTime
      expect(channel[6].toString()).to.be.equal(emptyRootHash); // vcRootHash
      expect(channel[7].toString()).to.be.equal(
        String(Math.floor(Date.now() / 1000))
      ); // lcopen timeout
      expect(channel[8].toString()).to.be.equal("0"); // updateLC timeout
      expect(channel[9]).to.be.equal(true); // isOpen
      expect(channel[10]).to.be.equal(false); // isUpdateSettling
      expect(channel[11].toString()).to.be.equal("0"); // numOpenVC
    });
  });
});

// TODO deposit tests

contract("LedgerChannel :: consensusCloseChannel()", function(accounts) {
  const sentBalance = [
    web3latest.utils.toWei("10"),
    web3latest.utils.toWei("10")
  ];

  const finalBalances = [
    web3latest.utils.toWei("5"), // ethA
    web3latest.utils.toWei("15"), // ethI
    web3latest.utils.toWei("5"), // erc20A
    web3latest.utils.toWei("15") // erc20I
  ];

  const lcId = web3latest.utils.sha3("1111", { encoding: "hex" });
  const challenge = 0;
  const finalSequence = 1;
  const openVcs = 0;

  let sigA, sigI, fakeSig;
  let lcFinalHash, fakeHash;
  before(async () => {
    partyA = accounts[0];
    partyB = accounts[1];
    partyI = accounts[2];
    partyN = accounts[3];

    ec = await EC.new();
    token = await Token.new(web3latest.utils.toWei("1000"), "Test", 1, "TST");
    Ledger.link("HumanStandardToken", token.address);
    Ledger.link("ECTools", ec.address);
    lc = await Ledger.new();

    await token.transfer(partyA, web3latest.utils.toWei("100"));
    await token.transfer(partyB, web3latest.utils.toWei("100"));
    await token.transfer(partyI, web3latest.utils.toWei("100"));

    await token.approve(lc.address, sentBalance[1], { from: partyA });
    await token.approve(lc.address, sentBalance[1], { from: partyI });
    await lc.createChannel(
      lcId,
      partyI,
      challenge,
      token.address,
      sentBalance,
      {
        from: partyA,
        value: sentBalance[0]
      }
    );

    await lc.joinChannel(lcId, sentBalance, {
      from: partyI,
      value: sentBalance[0]
    });

    lcFinalHash = web3latest.utils.soliditySha3(
      { type: "bytes32", value: lcId },
      { type: "bool", value: true }, // isclose
      { type: "uint256", value: finalSequence }, // sequence
      { type: "uint256", value: openVcs }, // open VCs
      { type: "bytes32", value: emptyRootHash }, // VC root hash
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyI }, // hub
      { type: "uint256", value: finalBalances[0] }, // ethA
      { type: "uint256", value: finalBalances[1] }, // ethI
      { type: "uint256", value: finalBalances[2] }, // tokenA
      { type: "uint256", value: finalBalances[3] } // tokenI
    );

    fakeHash = web3latest.utils.soliditySha3(
      { type: "bytes32", value: lcId }, // ID
      { type: "bool", value: false }, // isclose
      { type: "uint256", value: finalSequence }, // sequence
      { type: "uint256", value: openVcs }, // open VCs
      { type: "string", value: emptyRootHash }, // VC root hash
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyI }, // hub
      { type: "uint256", value: finalBalances[0] }, // ethA
      { type: "uint256", value: finalBalances[1] }, // ethI
      { type: "uint256", value: finalBalances[2] }, // tokenA
      { type: "uint256", value: finalBalances[3] } // tokenI
    );

    sigA = await web3latest.eth.sign(lcFinalHash, partyA);
    sigI = await web3latest.eth.sign(lcFinalHash, partyI);
    fakeSig = await web3latest.eth.sign(fakeHash, partyA);
  });

  describe("consensusCloseChannel() has 7 possible cases:", () => {
    it("1. Fail: Channel with that ID does not exist", async () => {
      const failedId = web3latest.utils.sha3("fail", { encoding: "hex" });

      await lc
        .consensusCloseChannel(
          failedId,
          finalSequence,
          finalBalances,
          sigA,
          sigI
        )
        .should.be.rejectedWith(SolRevert);
    });

    it("2. Fail: Channel with that ID is not joined", async () => {
      const failedId = web3latest.utils.sha3("fail", { encoding: "hex" });
      await lc.createChannel(
        failedId,
        partyI,
        challenge,
        token.address,
        [0, 0],
        { from: partyA }
      );

      await lc
        .consensusCloseChannel(
          failedId, 
          finalSequence, 
          finalBalances, 
          sigA, 
          sigI
        ).should.be.rejectedWith(SolRevert);
    });

    it("3. Fail: Total Eth deposit is not equal to submitted Eth balances", async () => {
      const failedBalances = [
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15"),
        web3latest.utils.toWei("5")
      ];

      await lc
        .consensusCloseChannel(lcId, finalSequence, failedBalances, sigA, sigI)
        .should.be.rejectedWith(SolRevert);
    });

    it("4. Fail: Total token deposit is not equal to submitted token balances", async () => {
      const failedBalances = [
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15"),
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("5")
      ];

      await lc
        .consensusCloseChannel(lcId, finalSequence, failedBalances, sigA, sigI)
        .should.be.rejectedWith(SolRevert);
    });

    it("5. Fail: Incorrect sig for partyA", async () => {
      await lc
        .consensusCloseChannel(
          lcId,
          finalSequence,
          finalBalances,
          fakeSig,
          sigI
        )
        .should.be.rejectedWith(SolRevert);
    });

    it("6. Fail: Incorrect sig for partyI", async () => {
      await lc
        .consensusCloseChannel(
          lcId,
          finalSequence,
          finalBalances,
          sigA,
          fakeSig
        )
        .should.be.rejectedWith(SolRevert);
    });

    it("7. Success: Channel Closed", async () => {
      const openChansInit = await lc.numChannels();
      const tx = await lc.consensusCloseChannel(lcId, finalSequence, finalBalances, sigA, sigI);
      const openChansFinal = await lc.numChannels();
      expect(openChansInit - openChansFinal).to.be.equal(1);
    });
  });
});

// NOTE: in this case, only tested with empty root hash
// non-empty root hash is tested in initVCState fns
contract.only("LedgerChannel :: updateLCstate()", function(accounts) {
  const initialDeposit = [
    web3latest.utils.toWei("10"),
    web3latest.utils.toWei("10")
  ];

  // nonce = 2
  const finalBalances = [
    web3latest.utils.toWei("5"),
    web3latest.utils.toWei("15"),
    web3latest.utils.toWei("5"),
    web3latest.utils.toWei("15"),
  ];

  // nonce = 3
  const finalBalances2 = [
    web3latest.utils.toWei("0"),
    web3latest.utils.toWei("20"),
    web3latest.utils.toWei("0"),
    web3latest.utils.toWei("20"),
  ];

  const lcId = web3latest.utils.sha3("channel1", { encoding: "hex" });
  const challenge = 3; // 2s challenge
  const openVcs = 0;
  let sigA, sigI, fakeSig;
  let sigA2, sigI2;
  const sequence = 2; // initially disputed nonce
  before(async () => {
    partyA = accounts[0];
    partyB = accounts[1];
    partyI = accounts[2];
    partyN = accounts[3];

    ec = await EC.new();
    token = await Token.new(web3latest.utils.toWei("1000"), "Test", 1, "TST");
    Ledger.link("HumanStandardToken", token.address);
    Ledger.link("ECTools", ec.address);
    lc = await Ledger.new();
    // token disbursement
    await token.transfer(partyA, web3latest.utils.toWei("100"));
    await token.transfer(partyB, web3latest.utils.toWei("100"));
    await token.transfer(partyI, web3latest.utils.toWei("100"));
    // approve token transfers
    await token.approve(lc.address, initialDeposit[1], { from: partyA });
    await token.approve(lc.address, initialDeposit[1], { from: partyI });
    // create and join channel
    await lc.createChannel(lcId, partyI, challenge, token.address, initialDeposit, {
      from: partyA,
      value: initialDeposit[0]
    });
    await lc.joinChannel(lcId, initialDeposit, {
      from: partyI,
      value: initialDeposit[0]
    });

    const disputedStateHash = web3latest.utils.soliditySha3(
      { type: "bytes32", value: lcId },
      { type: "bool", value: false }, // isclose
      { type: "uint256", value: sequence }, // sequence
      { type: "uint256", value: openVcs }, // open VCs
      { type: "bytes32", value: emptyRootHash }, // VC root hash
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyI }, // hub
      { type: "uint256", value: finalBalances[0] }, // ethA
      { type: "uint256", value: finalBalances[1] }, // ethI
      { type: "uint256", value: finalBalances[2] }, // tokenA
      { type: "uint256", value: finalBalances[3] } // tokenI
    );

    const finalSequence = sequence + 1
    const finalStateHash = web3latest.utils.soliditySha3(
      { type: "bytes32", value: lcId },
      { type: "bool", value: false }, // isclose
      { type: "uint256", value: finalSequence }, // sequence
      { type: "uint256", value: openVcs }, // open VCs
      { type: "bytes32", value: emptyRootHash }, // VC root hash
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyI }, // hub
      { type: "uint256", value: finalBalances2[0] }, // ethA
      { type: "uint256", value: finalBalances2[1] }, // ethI
      { type: "uint256", value: finalBalances2[2] }, // tokenA
      { type: "uint256", value: finalBalances2[3] } // tokenI
    );

    sigA = await web3latest.eth.sign(disputedStateHash, partyA);
    sigI = await web3latest.eth.sign(disputedStateHash, partyI);
    fakeSig = await web3latest.eth.sign(disputedStateHash, partyB);

    sigA2 = await web3latest.eth.sign(finalStateHash, partyA);
    sigI2 = await web3latest.eth.sign(finalStateHash, partyI);
  });

  describe("updateLCstate() has 10 possible cases:", () => {
    it("1. Fail: Channel with that ID does not exist", async () => {
      const updateParams = [
        sequence,
        openVcs,
        finalBalances[0],
        finalBalances[1],
        finalBalances[2],
        finalBalances[3],
      ];
      const failedId = web3latest.utils.sha3("akjn", { encoding: "hex" });
      await lc
        .updateLCstate(failedId, updateParams, emptyRootHash, sigA, sigI)
        .should.be.rejectedWith(SolRevert);

    });

    it("2. Fail: Channel with that ID is not joined", async () => {
      // create unjoined channel
      const unjoinedId = web3latest.utils.sha3("fail", { encoding: "hex" });
      await lc.createChannel(
        unjoinedId,
        partyI,
        challenge,
        token.address,
        [0, 0],
        { from: partyA }
      );

      const updateParams = [
        sequence,
        openVcs,
        finalBalances[0],
        finalBalances[1],
        finalBalances[2],
        finalBalances[3],
      ];

      await lc
        .updateLCstate(
          unjoinedId, 
          updateParams, 
          emptyRootHash, 
          sigA, 
          sigI
        ).should.be.rejectedWith(SolRevert);
    });
    
    it("3. Fail: Total Eth deposit is not equal to submitted Eth balances", async () => {
      const updateParams = [
        sequence,
        openVcs,
        initialDeposit[0],
        finalBalances[1],
        finalBalances[2],
        finalBalances[3],
      ];
      const badStateHash = web3latest.utils.soliditySha3(
        { type: "bytes32", value: lcId }, // ID
        { type: "bool", value: false }, // isclose
        { type: "uint256", value: updateParams[0] }, // sequence
        { type: "uint256", value: updateParams[1] }, // open VCs
        { type: "bytes32", value: emptyRootHash }, // VC root hash
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyI }, // hub
        { type: "uint256", value: updateParams[2] }, // ethA
        { type: "uint256", value: updateParams[3] }, // ethI
        { type: "uint256", value: updateParams[4] }, // tokenA
        { type: "uint256", value: updateParams[5] } // tokenI
      ); 
      const badSigA = await web3latest.eth.sign(badStateHash, partyA);
      const badSigI = await web3latest.eth.sign(badStateHash, partyA);

      await lc
        .updateLCstate(
          lcId, 
          updateParams, 
          emptyRootHash, 
          badSigA, 
          badSigI
        ).should.be.rejectedWith(SolRevert);
    });

    it("4. Fail: Total token deposit is not equal to submitted Eth balances", async () => {
      const updateParams = [
        sequence,
        openVcs,
        finalBalances[0],
        finalBalances[1],
        initialDeposit[1],
        finalBalances[3],
      ];
      const badStateHash = web3latest.utils.soliditySha3(
        { type: "bytes32", value: lcId }, // ID
        { type: "bool", value: false }, // isclose
        { type: "uint256", value: updateParams[0] }, // sequence
        { type: "uint256", value: updateParams[1] }, // open VCs
        { type: "bytes32", value: emptyRootHash }, // VC root hash
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyI }, // hub
        { type: "uint256", value: updateParams[2] }, // ethA
        { type: "uint256", value: updateParams[3] }, // ethI
        { type: "uint256", value: updateParams[4] }, // tokenA
        { type: "uint256", value: updateParams[5] } // tokenI
      ); 
      const badSigA = await web3latest.eth.sign(badStateHash, partyA);
      const badSigI = await web3latest.eth.sign(badStateHash, partyI);

      await lc
        .updateLCstate(
          lcId, 
          updateParams, 
          emptyRootHash, 
          badSigA, 
          badSigI
        ).should.be.rejectedWith(SolRevert);
    });

    it("5. Fail: Incorrect sig for partyA", async () => {
      const updateParams = [
        sequence,
        openVcs,
        finalBalances[0],
        finalBalances[1],
        finalBalances[2],
        finalBalances[3],
      ];
      await lc
        .updateLCstate(lcId, updateParams, emptyRootHash, fakeSig, sigI)
        .should.be.rejectedWith(SolRevert);
    });

    it("6. Fail: Incorrect sig for partyI", async () => {
      const updateParams = [
        sequence,
        openVcs,
        finalBalances[0],
        finalBalances[1],
        finalBalances[2],
        finalBalances[3],
      ];
      await lc
        .updateLCstate(lcId, updateParams, emptyRootHash, sigA, fakeSig)
        .should.be.rejectedWith(SolRevert);
    });

    it("7. Success 1: updateLCstate called first time and timeout started", async () => {
      const updateParams = [
        sequence,
        openVcs,
        finalBalances[0],
        finalBalances[1],
        finalBalances[2],
        finalBalances[3],
      ];
      await lc.updateLCstate(lcId, updateParams, emptyRootHash, sigA, sigI);

      const channel = await lc.getChannel(lcId);
      expect(channel[10]).to.be.equal(true); // isSettling
    });

    it("8. Error: State nonce below onchain latest sequence", async () => {
      const badSequence = sequence - 1;
      const finalStateHash2 = web3latest.utils.soliditySha3(
        { type: "bytes32", value: lcId },
        { type: "bool", value: false }, // isclose
        { type: "uint256", value: badSequence }, // sequence
        { type: "uint256", value: openVcs }, // open VCs
        { type: "bytes32", value: emptyRootHash }, // VC root hash
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyI }, // hub
        { type: "uint256", value: finalBalances2[0] }, // ethA
        { type: "uint256", value: finalBalances2[1] }, // ethI
        { type: "uint256", value: finalBalances2[2] }, // tokenA
        { type: "uint256", value: finalBalances2[3] } // tokenI
      );

      const badSigA = await web3latest.eth.sign(finalStateHash2, partyA);
      const badSigI = await web3latest.eth.sign(finalStateHash2, partyI);
  
      const updateParams = [
        badSequence,
        openVcs,
        finalBalances2[0],
        finalBalances2[1],
        finalBalances2[2],
        finalBalances2[3],
      ];

      await lc
        .updateLCstate(lcId, updateParams, emptyRootHash, badSigA, badSigI)
        .should.be.rejectedWith(SolRevert);
    });

    it("9. Success 2: new state submitted to updateLC", async () => {
      const finalSequence = sequence + 1;
      const updateParams = [
        finalSequence,
        openVcs,
        finalBalances2[0],
        finalBalances2[1],
        finalBalances2[2],
        finalBalances2[3],
      ];

      await lc
        .updateLCstate(lcId, updateParams, emptyRootHash, sigA2, sigI2)

      const channel = await lc.getChannel(lcId);
      expect(Number(channel[4])).to.be.equal(finalSequence); //new state updated successfully!
    });

    it("10. Error: UpdateLC timed out", async () => {    
      const finalSequence = sequence + 2;  
      const updateParams = [
        finalSequence,
        openVcs,
        finalBalances[0],
        finalBalances[1],
        finalBalances[2],
        finalBalances[3],
      ];

      const hash = web3latest.utils.soliditySha3(
        { type: "bytes32", value: lcId },
        { type: "bool", value: false }, // isclose
        { type: "uint256", value: finalSequence }, // sequence
        { type: "uint256", value: openVcs }, // open VCs
        { type: "bytes32", value: emptyRootHash }, // VC root hash
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyI }, // hub
        { type: "uint256", value: finalBalances2[0] }, // ethA
        { type: "uint256", value: finalBalances2[1] }, // ethI
        { type: "uint256", value: finalBalances2[2] }, // tokenA
        { type: "uint256", value: finalBalances2[3] } // tokenI
      );

      const finalSigA = await web3latest.eth.sign(hash, partyA);
      const finalSigI = await web3latest.eth.sign(hash, partyI);

      // wait 1s after challenge
      wait(1000*(1+challenge))
      await lc
        .updateLCstate(lcId, updateParams, emptyRootHash, finalSigA, finalSigI)
        .should.be.rejectedWith(SolRevert);
    });
  });
});

contract("LedgerChannel :: initVCstate()", function(accounts) {
  before(async () => {
    partyA = accounts[0];
    partyB = accounts[1];
    partyI = accounts[2];
    partyN = accounts[3];

    ec = await EC.new();
    token = await Token.new(web3latest.utils.toWei("1000"), "Test", 1, "TST");
    Ledger.link("HumanStandardToken", token.address);
    Ledger.link("ECTools", ec.address);
    lc = await Ledger.new();

    await token.transfer(partyB, web3latest.utils.toWei("100"));
    await token.transfer(partyI, web3latest.utils.toWei("100"));

    let sentBalance = [
      web3latest.utils.toWei("10"),
      web3latest.utils.toWei("10")
    ];
    await token.approve(lc.address, sentBalance[1]);
    await token.approve(lc.address, sentBalance[1], { from: partyI });
    let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
    await lc.createChannel(lc_id, partyI, "1", token.address, sentBalance, {
      from: partyA,
      value: sentBalance[0]
    });
    await lc.joinChannel(lc_id, sentBalance, {
      from: partyI,
      value: sentBalance[0]
    });

    initialVCstate = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id }, // VC ID
      { type: "uint256", value: 0 }, // sequence
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyB }, // partyB
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
      { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("0") }, // token
      { type: "uint256", value: web3latest.utils.toWei("1") } // token
    );

    payload = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id },
      { type: "bool", value: false }, // isclose
      { type: "uint256", value: "1" }, // sequence
      { type: "uint256", value: "1" }, // open VCs
      { type: "bytes32", value: initialVCstate }, // VC root hash
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyI }, // hub
      { type: "uint256", value: web3latest.utils.toWei("5") },
      { type: "uint256", value: web3latest.utils.toWei("15") },
      { type: "uint256", value: web3latest.utils.toWei("5") }, // token
      { type: "uint256", value: web3latest.utils.toWei("15") } // token
    );

    fakeSig = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id }, // ID
      { type: "bool", value: false }, // isclose
      { type: "uint256", value: "1" }, // sequence
      { type: "uint256", value: "0" }, // open VCs
      { type: "string", value: "0x0" }, // VC root hash
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyI }, // hub
      { type: "uint256", value: web3latest.utils.toWei("15") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("15") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("15") }, // token
      { type: "uint256", value: web3latest.utils.toWei("15") } // token
    );

    sigA = await web3latest.eth.sign(payload, partyA);
    sigI = await web3latest.eth.sign(payload, partyI);
    fakeSig = await web3latest.eth.sign(fakeSig, partyA);

    vcRootHash = initialVCstate;
    bond = [web3latest.utils.toWei("1"), web3latest.utils.toWei("1")];
    let updateParams = [
      "1",
      "1",
      web3latest.utils.toWei("5"),
      web3latest.utils.toWei("15"),
      web3latest.utils.toWei("5"),
      web3latest.utils.toWei("15")
    ];
    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI);

    let lc_id_fail = web3latest.utils.sha3("fail", { encoding: "hex" });
    await token.approve(lc.address, sentBalance[1]);
    await lc.createChannel(
      lc_id_fail,
      partyI,
      "0",
      token.address,
      sentBalance,
      { from: partyA, value: sentBalance[0] }
    );
  });

  describe("initVCstate() has 8 possible cases:", () => {
    it("1. Fail: Channel with that ID does not exist", async () => {
      let lc_id = web3latest.utils.sha3("nochannel", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);
      let verificationA = await web3latest.eth.sign(initialVCstate, partyA);
      sigA = await web3latest.eth.sign(initialVCstate, partyA);

      expect(channel[0][0]).to.be.equal(
        "0x0000000000000000000000000000000000000000"
      ); //fail
      expect(channel[9]).to.not.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass (inverted because channel[8] is 0 for nonexistent channel)
      expect(vc[4].toString()).to.be.equal("0"); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      expect(vcRootHash).to.be.equal(initialVCstate); //pass (this is a way of checking isContained() if there is only one VC open)

      await lc
        .initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      // try {
      // await lc.initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
      // } catch (e) {
      // expect(e.message).to.equal(SolRevert(e.tx))
      // expect(e.name).to.equal('StatusError')
      // }
    });
    it("2. Fail: Channel with that ID is not open", async () => {
      let lc_id = web3latest.utils.sha3("fail", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);
      let verificationA = await web3latest.eth.sign(initialVCstate, partyA);
      sigA = await web3latest.eth.sign(initialVCstate, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.not.be.equal(true); //fail
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass (inverted because channel[8] is 0 for non open channel)
      expect(vc[4].toString()).to.be.equal("0"); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      expect(vcRootHash).to.be.equal(initialVCstate); //pass (this is a way of checking isContained() if there is only one VC open)

      await lc
        .initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      // try {
      // await lc.initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
      // } catch (e) {
      // expect(e.message).to.equal(SolRevert(e.tx))
      // expect(e.name).to.equal('StatusError')
      // }
    });
    it("TODO Fail: 3. Fail: VC with that ID is closed already", async () => {
      let lc_id = web3latest.utils.sha3("closed", { encoding: "hex" });
      let sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("10")
      ];
      await token.approve(lc.address, sentBalance[1]);
      await token.approve(lc.address, sentBalance[1], { from: partyI });
      await lc.createChannel(lc_id, partyI, 0, token.address, sentBalance, {
        from: partyA,
        value: sentBalance[0]
      });
      await lc.joinChannel(lc_id, sentBalance, {
        from: partyI,
        value: sentBalance[0]
      });

      let vcRootHash_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id }, // VC ID
        { type: "uint256", value: 0 }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // token
        { type: "uint256", value: web3latest.utils.toWei("0") } // token
      );

      let payload_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id },
        { type: "bool", value: false }, // isclose
        { type: "uint256", value: 1 }, // sequence
        { type: "uint256", value: 1 }, // open VCs
        { type: "bytes32", value: vcRootHash_temp }, // VC root hash
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyI }, // hub
        { type: "uint256", value: web3latest.utils.toWei("5") },
        { type: "uint256", value: web3latest.utils.toWei("15") },
        { type: "uint256", value: web3latest.utils.toWei("5") }, // token
        { type: "uint256", value: web3latest.utils.toWei("15") } // token
      );

      sigA = await web3latest.eth.sign(payload_temp, partyA);
      sigI = await web3latest.eth.sign(payload_temp, partyI);
      let updateParams = [
        1,
        1,
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15"),
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15")
      ];
      await lc.updateLCstate(lc_id, updateParams, vcRootHash_temp, sigA, sigI);

      let balances = [
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0")
      ];
      sigA = await web3latest.eth.sign(vcRootHash_temp, partyA);
      await lc.initVCstate(
        lc_id,
        lc_id,
        0,
        partyA,
        partyB,
        bond,
        balances,
        sigA
      );
      // wait
      wait(1000);
      await lc.closeVirtualChannel(lc_id, lc_id);

      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);
      let verificationA = await web3latest.eth.sign(vcRootHash_temp, partyA);
      sigA = await web3latest.eth.sign(vcRootHash_temp, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.be.equal(true); //fail
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(vc[4].toString()).to.not.be.equal("0"); //pass (inverted because vc was already closed)
      expect(sigA).to.be.equal(verificationA); //pass
      expect(vcRootHash_temp).to.be.equal(vcRootHash_temp); //pass (this is a way of checking isContained() if there is only one VC open)

      await lc
        .initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      // try {
      // await lc.initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
      // } catch (e) {
      // expect(e.message).to.equal(SolRevert(e.tx))
      // expect(e.name).to.equal('StatusError')
      // }
    });
    it("4. Fail: LC update timer has not yet expired", async () => {
      let sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("10")
      ];
      await token.approve(lc.address, sentBalance[1]);
      await token.approve(lc.address, sentBalance[1], { from: partyI });
      let lc_id = web3latest.utils.sha3("2222", { encoding: "hex" });
      await lc.createChannel(
        lc_id,
        partyI,
        "100000000",
        token.address,
        sentBalance,
        { from: partyA, value: sentBalance[0] }
      );
      await lc.joinChannel(lc_id, sentBalance, {
        from: partyI,
        value: sentBalance[0]
      });

      let vcRootHash_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id }, // VC ID
        { type: "uint256", value: 0 }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // token
        { type: "uint256", value: web3latest.utils.toWei("1") } // token
      );

      let payload_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id },
        { type: "bool", value: false }, // isclose
        { type: "uint256", value: "1" }, // sequence
        { type: "uint256", value: "1" }, // open VCs
        { type: "bytes32", value: vcRootHash_temp }, // VC root hash
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyI }, // hub
        { type: "uint256", value: web3latest.utils.toWei("5") },
        { type: "uint256", value: web3latest.utils.toWei("15") },
        { type: "uint256", value: web3latest.utils.toWei("5") }, // token
        { type: "uint256", value: web3latest.utils.toWei("15") } // token
      );
      let channel = await lc.getChannel(lc_id);

      let sigA_temp = await web3latest.eth.sign(payload_temp, partyA);
      let sigI_temp = await web3latest.eth.sign(payload_temp, partyI);
      let updateParams = [
        "1",
        "1",
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15"),
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15")
      ];
      await lc.updateLCstate(
        lc_id,
        updateParams,
        vcRootHash_temp,
        sigA_temp,
        sigI_temp
      );

      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);
      let verificationA = await web3latest.eth.sign(vcRootHash_temp, partyA);
      sigA = await web3latest.eth.sign(vcRootHash_temp, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(channel[8] * 1000).to.not.be.below(Date.now()); //fail
      expect(vc[4].toString()).to.be.equal("0"); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      expect(vcRootHash_temp).to.be.equal(vcRootHash_temp); //pass (this is a way of checking isContained() if there is only one VC open)

      await lc
        .initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      // try {
      // await lc.initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
      // } catch (e) {
      // expect(e.message).to.equal(SolRevert(e.tx))
      // expect(e.name).to.equal('StatusError')
      // }
    });
    it("5. Fail: Alice has not signed initial state (or wrong state)", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let channel = await lc.getChannel(lc_id);
      let verificationA = await web3latest.eth.sign(initialVCstate, partyA);
      sigA = await web3latest.eth.sign(initialVCstate, partyA);
      let vc = await lc.getVirtualChannel(lc_id);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass (inverted because channel[8] is 0 for non open channel)
      expect(vc[4].toString()).to.be.equal("0"); //pass
      expect(fakeSig).to.not.be.equal(verificationA); //fail
      expect(vcRootHash).to.be.equal(initialVCstate); //pass (this is a way of checking isContained() if there is only one VC open)

      await lc
        .initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, fakeSig)
        .should.be.rejectedWith(SolRevert);

      // try {
      // await lc.initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, fakeSig)
      // } catch (e) {
      // expect(e.message).to.equal(SolRevert(e.tx))
      // expect(e.name).to.equal('StatusError')
      // }
    });
    it("6. Fail: Old state not contained in root hash", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0")
      ];
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      let vcRootHash_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id }, // VC ID
        { type: "uint256", value: 0 }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // token
        { type: "uint256", value: web3latest.utils.toWei("0") } // token
      );

      let verificationA = await web3latest.eth.sign(vcRootHash_temp, partyA);
      sigA = verificationA;

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass (inverted because channel[8] is 0 for non open channel)
      expect(vc[4].toString()).to.be.equal("0"); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      expect(vcRootHash_temp).to.not.be.equal(initialVCstate); //fail (this is a way of checking isContained() if there is only one VC open)

      await lc
        .initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      // try {
      // await lc.initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
      // } catch (e) {
      // expect(e.message).to.equal(SolRevert(e.tx))
      // expect(e.name).to.equal('StatusError')
      // }
    });
    it("7. Success: VC inited successfully", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let channel = await lc.getChannel(lc_id);
      let verificationA = await web3latest.eth.sign(initialVCstate, partyA);
      sigA = await web3latest.eth.sign(initialVCstate, partyA);
      let vc = await lc.getVirtualChannel(lc_id);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass (inverted because channel[8] is 0 for non open channel)
      expect(vc[4].toString()).to.be.equal("0"); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      expect(vcRootHash).to.be.equal(initialVCstate); //pass (this is a way of checking isContained() if there is only one VC open)

      const tx = await lc.initVCstate(
        lc_id,
        lc_id,
        0,
        partyA,
        partyB,
        bond,
        balances,
        sigA
      );
      expect(tx.logs[0].event).to.equal("DidVCInit");
    });
    it("8. Fail: Update VC timer is not 0 (initVCstate has already been called before)", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let channel = await lc.getChannel(lc_id);
      let verificationA = await web3latest.eth.sign(initialVCstate, partyA);
      sigA = await web3latest.eth.sign(initialVCstate, partyA);
      let vc = await lc.getVirtualChannel(lc_id);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass (inverted because channel[8] is 0 for non open channel)
      expect(vc[4].toString()).to.not.be.equal("0"); //fail
      expect(sigA).to.be.equal(verificationA); //pass
      expect(vcRootHash).to.be.equal(initialVCstate); //pass (this is a way of checking isContained() if there is only one VC open)

      await lc
        .initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      // try {
      // await lc.initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA)
      // } catch (e) {
      // expect(e.message).to.equal(SolRevert(e.tx))
      // expect(e.name).to.equal('StatusError')
      // }
    });
  });
});

contract("LedgerChannel :: settleVC()", function(accounts) {
  before(async () => {
    partyA = accounts[0];
    partyB = accounts[1];
    partyI = accounts[2];
    partyN = accounts[3];

    ec = await EC.new();
    token = await Token.new(web3latest.utils.toWei("1000"), "Test", 1, "TST");
    Ledger.link("HumanStandardToken", token.address);
    Ledger.link("ECTools", ec.address);
    lc = await Ledger.new();

    await token.transfer(partyB, web3latest.utils.toWei("100"));
    await token.transfer(partyI, web3latest.utils.toWei("100"));

    let sentBalance = [
      web3latest.utils.toWei("10"),
      web3latest.utils.toWei("10")
    ];
    await token.approve(lc.address, sentBalance[1]);
    await token.approve(lc.address, sentBalance[1], { from: partyI });
    let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
    await lc.createChannel(lc_id, partyI, 0, token.address, sentBalance, {
      from: partyA,
      value: sentBalance[0]
    });
    await lc.joinChannel(lc_id, sentBalance, {
      from: partyI,
      value: sentBalance[0]
    });

    initialVCstate = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id }, // VC ID
      { type: "uint256", value: 0 }, // sequence
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyB }, // partyB
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
      { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // token
      { type: "uint256", value: web3latest.utils.toWei("0") } // token
    );

    payload = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id },
      { type: "bool", value: false }, // isclose
      { type: "uint256", value: 1 }, // sequence
      { type: "uint256", value: 1 }, // open VCs
      { type: "bytes32", value: initialVCstate }, // VC root hash
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyI }, // hub
      { type: "uint256", value: web3latest.utils.toWei("5") },
      { type: "uint256", value: web3latest.utils.toWei("15") },
      { type: "uint256", value: web3latest.utils.toWei("5") }, // token
      { type: "uint256", value: web3latest.utils.toWei("15") } // token
    );

    fakeSig = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id }, // ID
      { type: "bool", value: false }, // isclose
      { type: "uint256", value: 1 }, // sequence
      { type: "uint256", value: 0 }, // open VCs
      { type: "string", value: "0x0" }, // VC root hash
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyI }, // hub
      { type: "uint256", value: web3latest.utils.toWei("15") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("15") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("15") }, // token
      { type: "uint256", value: web3latest.utils.toWei("15") } // token
    );

    sigA = await web3latest.eth.sign(payload, partyA);
    sigI = await web3latest.eth.sign(payload, partyI);
    fakeSig = await web3latest.eth.sign(fakeSig, partyA);

    vcRootHash = initialVCstate;
    bond = [web3latest.utils.toWei("1"), web3latest.utils.toWei("1")];
    let updateParams = [
      "1",
      "1",
      web3latest.utils.toWei("5"),
      web3latest.utils.toWei("15"),
      web3latest.utils.toWei("5"),
      web3latest.utils.toWei("15")
    ];
    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI);

    let balances = [
      web3latest.utils.toWei("1"),
      web3latest.utils.toWei("0"),
      web3latest.utils.toWei("1"),
      web3latest.utils.toWei("0")
    ];
    sigA = await web3latest.eth.sign(initialVCstate, partyA);
    await lc.initVCstate(lc_id, lc_id, 0, partyA, partyB, bond, balances, sigA);

    let lc_id_fail = web3latest.utils.sha3("fail", { encoding: "hex" });
    await token.approve(lc.address, sentBalance[1]);
    await lc.createChannel(
      lc_id_fail,
      partyI,
      "0",
      token.address,
      sentBalance,
      { from: partyA, value: sentBalance[0] }
    );

    payload = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id }, // VC ID
      { type: "uint256", value: 1 }, // sequence
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyB }, // partyB
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
      { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("0") }, // token
      { type: "uint256", value: web3latest.utils.toWei("1") } // token
    );
  });

  describe("settleVC() has 14 possible cases:", () => {
    it("1. Fail: Channel with that ID does not exist", async () => {
      let lc_id = web3latest.utils.sha3("nochannel", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let sequence = 1;
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);
      let verificationA = await web3latest.eth.sign(payload, partyA);
      sigA = await web3latest.eth.sign(payload, partyA);

      expect(channel[0][0]).to.be.equal(
        "0x0000000000000000000000000000000000000000"
      ); //fail
      expect(channel[9]).to.not.be.equal(true); //pass (inverted for nonexistent channel)
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(Number(vc[2])).to.be.below(sequence); //pass
      expect(Number(vc[8][1])).to.be.below(Number(balances[1])); //pass
      expect(Number(vc[9][1])).to.be.below(Number(balances[3])); //pass
      expect(vc[10][0].toString()).to.not.be.equal(web3latest.utils.toWei("1")); //pass (inverted because vc state not inited yet)
      expect(vc[10][1].toString()).to.not.be.equal(web3latest.utils.toWei("1")); //pass (inverted because vc state not inited yet)
      expect(vc[4].toString()).to.be.equal("0"); //pass (inverted because vc state not inited yet)
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      //expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc
        .settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("2. Fail: Channel with that ID is not open", async () => {
      let lc_id = web3latest.utils.sha3("fail", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let sequence = 1;
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);
      let verificationA = await web3latest.eth.sign(payload, partyA);
      sigA = await web3latest.eth.sign(payload, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.not.be.equal(true); //fail
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(Number(vc[2])).to.be.below(sequence); //pass
      expect(Number(vc[8][1])).to.be.below(Number(balances[1])); //pass
      expect(Number(vc[9][1])).to.be.below(Number(balances[3])); //pass
      expect(vc[10][0].toString()).to.not.be.equal(web3latest.utils.toWei("1")); //pass (inverted because vc state not inited yet)
      expect(vc[10][1].toString()).to.not.be.equal(web3latest.utils.toWei("1")); //pass (inverted because vc state not inited yet)
      expect(vc[4].toString()).to.be.equal("0"); //pass (inverted because vc state not inited yet)
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      //expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc
        .settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });

    it("3. Fail: VC with that ID is already closed", async () => {
      //Sometimes reverts on initial close, unclear why. :(

      let lc_id = web3latest.utils.sha3("affectedLC", { encoding: "hex" });
      let vc_id = web3latest.utils.sha3("closedVC", { encoding: "hex" });
      let sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("10")
      ];
      await token.approve(lc.address, sentBalance[1]);
      await token.approve(lc.address, sentBalance[1], { from: partyI });
      await lc.createChannel(lc_id, partyI, 0, token.address, sentBalance, {
        from: partyA,
        value: sentBalance[0]
      });
      await lc.joinChannel(lc_id, sentBalance, {
        from: partyI,
        value: sentBalance[0]
      });

      let sequence = 0;
      initialVCstate = web3latest.utils.soliditySha3(
        { type: "uint256", value: vc_id }, // VC ID
        { type: "uint256", value: sequence }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // token
        { type: "uint256", value: web3latest.utils.toWei("0") } // token
      );

      sequence = 1;
      let openVcs = 1;
      let payload_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id },
        { type: "bool", value: false }, // isclose
        { type: "uint256", value: sequence }, // sequence
        { type: "uint256", value: openVcs }, // open VCs
        { type: "bytes32", value: initialVCstate }, // VC root hash
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyI }, // hub
        { type: "uint256", value: web3latest.utils.toWei("5") },
        { type: "uint256", value: web3latest.utils.toWei("15") },
        { type: "uint256", value: web3latest.utils.toWei("5") }, // token
        { type: "uint256", value: web3latest.utils.toWei("15") } // token
      );

      sigA = await web3latest.eth.sign(payload_temp, partyA);
      sigI = await web3latest.eth.sign(payload_temp, partyI);
      let updateParams = [
        sequence,
        openVcs,
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15"),
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15")
      ];
      await lc.updateLCstate(lc_id, updateParams, initialVCstate, sigA, sigI);

      let balances = [
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0")
      ];
      sigA = await web3latest.eth.sign(initialVCstate, partyA);
      await lc.initVCstate(
        lc_id,
        vc_id,
        0,
        partyA,
        partyB,
        bond,
        balances,
        sigA
      );

      await lc.closeVirtualChannel(lc_id, vc_id);

      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(vc_id);

      balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];

      sequence = 2;
      payload_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: vc_id }, // VC ID
        { type: "uint256", value: sequence }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // token
        { type: "uint256", value: web3latest.utils.toWei("1") } // token
      );
      sigA = await web3latest.eth.sign(payload_temp, partyA);
      let verificationA = sigA;

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.be.equal(true); //fail
      expect(Number(vc[2])).to.be.below(sequence); //pass
      expect(Number(vc[8][1])).to.be.below(Number(balances[1])); //pass
      expect(Number(vc[9][1])).to.be.below(Number(balances[3])); //pass
      expect(vc[10][0].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[10][1].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[4].toString()).to.not.be.equal("0"); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      // expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc
        .settleVC(lc_id, vc_id, sequence, partyA, partyB, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.settleVC(lc_id, lc_id, 2, partyA, partyB, balances, sigA)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("4. Fail: Onchain VC sequence is higher than submitted sequence", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let sequence = 0;
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);
      let verificationA = await web3latest.eth.sign(payload, partyA);
      sigA = await web3latest.eth.sign(payload, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(Number(vc[2])).to.not.be.below(sequence); //fail
      expect(Number(vc[8][1])).to.be.below(Number(balances[1])); //pass
      expect(Number(vc[9][1])).to.be.below(Number(balances[3])); //pass
      expect(vc[10][0].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[10][1].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[4].toString()).to.not.be.equal("0"); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      //expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc
        .settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("5. Fail: State update decreases recipient balance", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let sequence = 1;
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      let payload_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id }, // VC ID
        { type: "uint256", value: sequence }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // token
        { type: "uint256", value: web3latest.utils.toWei("1") } // token
      );

      let verificationA = await web3latest.eth.sign(payload_temp, partyA);
      sigA = await web3latest.eth.sign(payload_temp, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(Number(vc[2])).to.be.below(sequence); //pass
      expect(Number(vc[8][1])).to.not.be.below(Number(balances[1])); //fail
      expect(Number(vc[9][1])).to.be.below(Number(balances[3])); //pass
      expect(vc[10][0].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[10][1].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[4].toString()).to.not.be.equal("0"); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      //expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc
        .settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("6. Fail: State update decreases recipient balance", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0")
      ];
      let sequence = 1;
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      let payload_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id }, // VC ID
        { type: "uint256", value: sequence }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // token
        { type: "uint256", value: web3latest.utils.toWei("0") } // token
      );

      let verificationA = await web3latest.eth.sign(payload_temp, partyA);
      sigA = await web3latest.eth.sign(payload_temp, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(Number(vc[2])).to.be.below(sequence); //pass
      expect(Number(vc[8][1])).to.be.below(Number(balances[1])); //pass
      expect(Number(vc[9][1])).to.not.be.below(Number(balances[3])); //fail
      expect(vc[10][0].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[10][1].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[4].toString()).to.not.be.equal("0"); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      //expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc
        .settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("7. Fail: Eth balances do not match bonded amount", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let sequence = 1;
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      let payload_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id }, // VC ID
        { type: "uint256", value: sequence }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // token
        { type: "uint256", value: web3latest.utils.toWei("1") } // token
      );

      let verificationA = await web3latest.eth.sign(payload_temp, partyA);
      sigA = await web3latest.eth.sign(payload_temp, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(Number(vc[2])).to.be.below(sequence); //pass
      expect(Number(vc[8][1])).to.be.below(Number(balances[1])); //pass
      expect(Number(vc[9][1])).to.be.below(Number(balances[3])); //pass
      expect(vc[10][0].toString()).to.not.be.equal(web3latest.utils.toWei("2")); //fail
      expect(vc[10][1].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[4].toString()).to.not.be.equal("0"); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      //expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc
        .settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("8. Fail: Eth balances do not match bonded amount", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("1")
      ];
      let sequence = 1;
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      let payload_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id }, // VC ID
        { type: "uint256", value: sequence }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // token
        { type: "uint256", value: web3latest.utils.toWei("1") } // token
      );

      let verificationA = await web3latest.eth.sign(payload_temp, partyA);
      sigA = await web3latest.eth.sign(payload_temp, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(Number(vc[2])).to.be.below(sequence); //pass
      expect(Number(vc[8][1])).to.be.below(Number(balances[1])); //pass
      expect(Number(vc[9][1])).to.be.below(Number(balances[3])); //pass
      expect(vc[10][0].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[10][1].toString()).to.not.be.equal(web3latest.utils.toWei("2")); //fail
      expect(vc[4].toString()).to.not.be.equal("0"); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      //expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc
        .settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("9. Fail: InitVC was not called first", async () => {
      let lc_id = web3latest.utils.sha3("2222", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let sequence = 0;

      let initial_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id }, // VC ID
        { type: "uint256", value: sequence }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // token
        { type: "uint256", value: web3latest.utils.toWei("1") } // token
      );

      sequence = 1;
      let openVcs = 1;
      let payload_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id },
        { type: "bool", value: false }, // isclose
        { type: "uint256", value: sequence }, // sequence
        { type: "uint256", value: openVcs }, // open VCs
        { type: "bytes32", value: initial_temp }, // VC root hash
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyI }, // hub
        { type: "uint256", value: web3latest.utils.toWei("5") },
        { type: "uint256", value: web3latest.utils.toWei("15") },
        { type: "uint256", value: web3latest.utils.toWei("5") }, // token
        { type: "uint256", value: web3latest.utils.toWei("15") } // token
      );

      let sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("10")
      ];
      await token.approve(lc.address, sentBalance[1]);
      await token.approve(lc.address, sentBalance[1], { from: partyI });
      await lc.createChannel(lc_id, partyI, "1", token.address, sentBalance, {
        from: partyA,
        value: sentBalance[0]
      });
      await lc.joinChannel(lc_id, sentBalance, {
        from: partyI,
        value: sentBalance[0]
      });

      sigA = await web3latest.eth.sign(payload_temp, partyA);
      sigI = await web3latest.eth.sign(payload_temp, partyI);

      let updateParams = [
        sequence,
        openVcs,
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15"),
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15")
      ];
      await lc.updateLCstate(lc_id, updateParams, initial_temp, sigA, sigI);

      let verificationA = await web3latest.eth.sign(initial_temp, partyA);
      sigA = await web3latest.eth.sign(initial_temp, partyA);

      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(Number(vc[2])).to.be.below(sequence); //pass
      expect(Number(vc[8][1])).to.be.below(Number(balances[1])); //pass
      expect(Number(vc[9][1])).to.be.below(Number(balances[3])); //pass
      expect(vc[10][0].toString()).to.not.be.equal(web3latest.utils.toWei("1")); //pass (inverted because initVC not called)
      expect(vc[10][1].toString()).to.not.be.equal(web3latest.utils.toWei("1")); //pass (inverted because initVC not called)
      expect(vc[4].toString()).to.be.equal("0"); //fail
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      //expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc
        .settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("TODO 10. Fail: updateLC timeout has not expired", async () => {
      //Not sure how to test this since InitVC can only be called after timeout expires.
    });
    it("11. Fail: Incorrect partyA signature or payload", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let sequence = 1;
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      let verificationA = await web3latest.eth.sign(payload, partyA);
      sigA = await web3latest.eth.sign(payload, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(Number(vc[2])).to.be.below(sequence); //pass
      expect(Number(vc[8][1])).to.be.below(Number(balances[1])); //pass
      expect(Number(vc[9][1])).to.be.below(Number(balances[3])); //pass
      expect(vc[10][0].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[10][1].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[4].toString()).to.not.be.equal("0"); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(fakeSig).to.not.be.equal(verificationA); //fail
      //expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc
        .settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, fakeSig)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, fakeSig)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("TODO 12. Fail: UpdateVC timer has expired", async () => {
      //also unclear how best to unit test
    });
    it("13. Success 1: First state added!", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0.5"),
        web3latest.utils.toWei("0.5"),
        web3latest.utils.toWei("0.5"),
        web3latest.utils.toWei("0.5")
      ];
      let sequence = 1;
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      let payload_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id }, // VC ID
        { type: "uint256", value: sequence }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("0.5") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0.5") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0.5") }, // token
        { type: "uint256", value: web3latest.utils.toWei("0.5") } // token
      );

      let verificationA = await web3latest.eth.sign(payload_temp, partyA);
      sigA = await web3latest.eth.sign(payload_temp, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(Number(vc[2])).to.be.below(sequence); //pass
      expect(Number(vc[8][1])).to.be.below(Number(balances[1])); //pass
      expect(Number(vc[9][1])).to.be.below(Number(balances[3])); //pass
      expect(vc[10][0].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[10][1].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[4].toString()).to.not.be.equal("0"); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      //expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc.settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA);

      vc = await lc.getVirtualChannel(lc_id);
      expect(vc[1]).to.be.equal(true); //pass
    });
    it("14. Success 2: Disputed with higher sequence state!", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];
      let sequence = 2;
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      let payload_temp = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id }, // VC ID
        { type: "uint256", value: sequence }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // token
        { type: "uint256", value: web3latest.utils.toWei("1") } // token
      );

      let verificationA = await web3latest.eth.sign(payload_temp, partyA);
      sigA = await web3latest.eth.sign(payload_temp, partyA);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(Number(vc[2])).to.be.below(sequence); //pass
      expect(Number(vc[8][1])).to.be.below(Number(balances[1])); //pass
      expect(Number(vc[9][1])).to.be.below(Number(balances[3])); //pass
      expect(vc[10][0].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[10][1].toString()).to.be.equal(web3latest.utils.toWei("1")); //pass
      expect(vc[4].toString()).to.not.be.equal("0"); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(sigA).to.be.equal(verificationA); //pass
      //expect(vc[4]*1000).to.be.above(Date.now()) //pass

      await lc.settleVC(lc_id, lc_id, sequence, partyA, partyB, balances, sigA);

      vc = await lc.getVirtualChannel(lc_id);
      expect(parseInt(vc[2])).to.be.equal(sequence); //pass
    });
  });
});

contract("LedgerChannel :: closeVirtualChannel()", function(accounts) {
  let lc_id, vc_id;
  before(async () => {
    partyA = accounts[0];
    partyB = accounts[1];
    partyI = accounts[2];
    partyN = accounts[3];

    ec = await EC.new();
    token = await Token.new(web3latest.utils.toWei("1000"), "Test", 1, "TST");
    Ledger.link("HumanStandardToken", token.address);
    Ledger.link("ECTools", ec.address);
    lc = await Ledger.new();

    await token.transfer(partyB, web3latest.utils.toWei("100"));
    await token.transfer(partyI, web3latest.utils.toWei("100"));

    let sentBalance = [
      web3latest.utils.toWei("10"),
      web3latest.utils.toWei("10")
    ];
    await token.approve(lc.address, sentBalance[1]);
    await token.approve(lc.address, sentBalance[1], { from: partyI });
    lc_id = web3latest.utils.sha3("dkdkdkd", { encoding: "hex" });
    await lc.createChannel(lc_id, partyI, 0, token.address, sentBalance, {
      from: partyA,
      value: sentBalance[0]
    });
    await lc.joinChannel(lc_id, sentBalance, {
      from: partyI,
      value: sentBalance[0]
    });

    vc_id = web3latest.utils.sha3("wreqwerq", { encoding: "hex" });
    let sequence = 0;
    const initialVCstate = web3latest.utils.soliditySha3(
      { type: "uint256", value: vc_id }, // VC ID
      { type: "uint256", value: sequence }, // sequence
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyB }, // partyB
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
      { type: "uint256", value: web3latest.utils.toWei("1") }, // ethA
      { type: "uint256", value: web3latest.utils.toWei("0") }, // ethB
      { type: "uint256", value: web3latest.utils.toWei("1") }, // tokenA
      { type: "uint256", value: web3latest.utils.toWei("0") } // tokenB
    );

    sequence = 1;
    let openVcs = 1;
    const channelState1Hash = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id },
      { type: "bool", value: false }, // isclose
      { type: "uint256", value: sequence }, // sequence
      { type: "uint256", value: openVcs }, // open VCs
      { type: "bytes32", value: initialVCstate }, // VC root hash
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyI }, // hub
      { type: "uint256", value: web3latest.utils.toWei("9") },
      { type: "uint256", value: web3latest.utils.toWei("9") },
      { type: "uint256", value: web3latest.utils.toWei("9") }, // token
      { type: "uint256", value: web3latest.utils.toWei("9") } // token
    );

    const sigALc1 = await web3latest.eth.sign(channelState1Hash, partyA);
    const sigILc1 = await web3latest.eth.sign(channelState1Hash, partyI);

    bond = [web3latest.utils.toWei("1"), web3latest.utils.toWei("1")];
    let updateParams = [
      sequence,
      openVcs,
      web3latest.utils.toWei("9"),
      web3latest.utils.toWei("9"),
      web3latest.utils.toWei("9"),
      web3latest.utils.toWei("9")
    ];

    await lc.updateLCstate(
      lc_id,
      updateParams,
      initialVCstate,
      sigALc1,
      sigILc1
    );

    let balances = [
      web3latest.utils.toWei("1"),
      web3latest.utils.toWei("0"),
      web3latest.utils.toWei("1"),
      web3latest.utils.toWei("0")
    ];

    const sigAVc0 = await web3latest.eth.sign(initialVCstate, partyA);
    await lc.initVCstate(
      lc_id,
      vc_id,
      0,
      partyA,
      partyB,
      bond,
      balances,
      sigAVc0
    );

    sequence = 1;
    payload = web3latest.utils.soliditySha3(
      { type: "uint256", value: vc_id }, // VC ID
      { type: "uint256", value: sequence }, // sequence
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyB }, // partyB
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
      { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("0") }, // token
      { type: "uint256", value: web3latest.utils.toWei("1") } // token
    );

    balances = [
      web3latest.utils.toWei("0"),
      web3latest.utils.toWei("1"),
      web3latest.utils.toWei("0"),
      web3latest.utils.toWei("1")
    ];
    sigA = await web3latest.eth.sign(payload, partyA);
    await lc.settleVC(lc_id, vc_id, 1, partyA, partyB, balances, sigA);
  });

  describe("closeVirtualChannel() has 6 possible cases:", () => {
    it("1. Fail: Channel with that ID does not exist", async () => {
      let nonexistent_id = web3latest.utils.sha3("nochannel", {
        encoding: "hex"
      });
      let channel = await lc.getChannel(nonexistent_id);
      let vc = await lc.getVirtualChannel(nonexistent_id);

      expect(channel[0][0]).to.be.equal(
        "0x0000000000000000000000000000000000000000"
      ); //fail
      expect(channel[9]).to.not.be.equal(true); //pass (inverted for nonexistent channel)
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(vc[1]).to.not.be.equal(true); //pass (inverted for nonexistent VC)
      expect(vc[4] * 1000).to.be.below(Date.now()); //pass

      await lc
        .closeVirtualChannel(nonexistent_id, nonexistent_id)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.closeVirtualChannel(lc_id, lc_id)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("2. Fail: Channel with that ID is not open", async () => {
      let unopened_lc_id = web3latest.utils.sha3("adsfa8", { encoding: "hex" });
      let channel = await lc.getChannel(unopened_lc_id);
      let vc = await lc.getVirtualChannel(vc_id);

      expect(channel[0][0]).to.be.equal(
        "0x0000000000000000000000000000000000000000"
      ); //pass
      expect(channel[9]).to.not.be.equal(true); //fail
      expect(vc[0]).to.not.be.equal(true); //pass
      expect(vc[1]).to.be.equal(true); //pass (inverted for nonexistent VC)
      expect(vc[4] * 1000).to.be.below(Date.now()); //pass

      await lc
        .closeVirtualChannel(unopened_lc_id, vc_id)
        .should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.closeVirtualChannel(lc_id, lc_id)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("3. Fail: VC with that ID already closed", async () => {
      let subchan_id = web3latest.utils.sha3("yguf66", { encoding: "hex" });
      let closed_vc_id = web3latest.utils.sha3("w8ennvd", { encoding: "hex" });
      let sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("10")
      ];
      await token.approve(lc.address, sentBalance[1]);
      await token.approve(lc.address, sentBalance[1], { from: partyI });
      await lc.createChannel(
        subchan_id,
        partyI,
        0,
        token.address,
        sentBalance,
        {
          from: partyA,
          value: sentBalance[0]
        }
      );
      await lc.joinChannel(subchan_id, sentBalance, {
        from: partyI,
        value: sentBalance[0]
      });

      let sequence = 0;
      initialVCstate = web3latest.utils.soliditySha3(
        { type: "uint256", value: closed_vc_id }, // VC ID
        { type: "uint256", value: sequence }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // token
        { type: "uint256", value: web3latest.utils.toWei("0") } // token
      );

      sequence = 1;
      let openVcs = 1;
      let subchan1 = web3latest.utils.soliditySha3(
        { type: "uint256", value: subchan_id },
        { type: "bool", value: false }, // isclose
        { type: "uint256", value: sequence }, // sequence
        { type: "uint256", value: openVcs }, // open VCs
        { type: "bytes32", value: initialVCstate }, // VC root hash
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyI }, // hub
        { type: "uint256", value: web3latest.utils.toWei("9") },
        { type: "uint256", value: web3latest.utils.toWei("9") },
        { type: "uint256", value: web3latest.utils.toWei("9") }, // token
        { type: "uint256", value: web3latest.utils.toWei("9") } // token
      );

      const sigA1 = await web3latest.eth.sign(subchan1, partyA);
      const sigI1 = await web3latest.eth.sign(subchan1, partyI);

      let updateParams = [
        sequence,
        openVcs,
        web3latest.utils.toWei("9"),
        web3latest.utils.toWei("9"),
        web3latest.utils.toWei("9"),
        web3latest.utils.toWei("9")
      ];
      await lc.updateLCstate(
        subchan_id,
        updateParams,
        initialVCstate,
        sigA1,
        sigI1
      );

      let balances = [
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0")
      ];
      const bond = [web3latest.utils.toWei("1"), web3latest.utils.toWei("1")];
      const sigAVC0 = await web3latest.eth.sign(initialVCstate, partyA);
      await lc.initVCstate(
        subchan_id,
        closed_vc_id,
        0,
        partyA,
        partyB,
        bond,
        balances,
        sigAVC0
      );

      balances = [
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1"),
        web3latest.utils.toWei("0"),
        web3latest.utils.toWei("1")
      ];

      sequence = 1;
      const finalVcState = web3latest.utils.soliditySha3(
        { type: "uint256", value: closed_vc_id }, // VC ID
        { type: "uint256", value: sequence }, // sequence
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyB }, // partyB
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
        { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
        { type: "uint256", value: web3latest.utils.toWei("0") }, // token
        { type: "uint256", value: web3latest.utils.toWei("1") } // token
      );
      const sigAVC1 = await web3latest.eth.sign(finalVcState, partyA);

      await lc.settleVC(
        subchan_id,
        closed_vc_id,
        sequence,
        partyA,
        partyB,
        balances,
        sigAVC1
      );

      // explicitly wait 1 sec
      wait(1000);
      await lc.closeVirtualChannel(subchan_id, closed_vc_id);

      await lc
        .closeVirtualChannel(subchan_id, closed_vc_id)
        .should.be.rejectedWith(SolRevert);
    });
    it("4. Fail: VC is not in settlement state", async () => {
      // no point testing this since VCs cannot exist unless they're in settlement state. We probably don't need this flag too, since its
      // only checked in closeVC()
    });
    it("TO DO 5. Fail: updateVCtimeout has not expired", async () => {
      // figure out how to test this (need to wait for time to pass)
    });
    it("6. Fail: VC with that ID is not open", async () => {
      let vc_id = web3latest.utils.sha3("aoif2n", { encoding: "hex" });
      let vc = await lc.getVirtualChannel(vc_id);
      let channel = await lc.getChannel(lc_id);

      // vc should be empty
      expect(vc[5]).to.be.equal("0x0000000000000000000000000000000000000000"); //pass
      expect(vc[6]).to.be.equal("0x0000000000000000000000000000000000000000"); //pass
      expect(vc[7]).to.be.equal("0x0000000000000000000000000000000000000000"); //pass

      // channel should exist
      expect(channel[0][0]).to.be.equal(partyA);
      expect(channel[0][1]).to.be.equal(partyI);
      expect(channel[9]).to.be.equal(true); // isOpen

      await lc
        .closeVirtualChannel(lc_id, vc_id)
        .should.be.rejectedWith(SolRevert);
    });
  });
});

contract("LedgerChannel :: byzantineCloseChannel()", function(accounts) {
  before(async () => {
    partyA = accounts[0];
    partyB = accounts[1];
    partyI = accounts[2];
    partyN = accounts[3];

    ec = await EC.new();
    token = await Token.new(web3latest.utils.toWei("1000"), "Test", 1, "TST");
    Ledger.link("HumanStandardToken", token.address);
    Ledger.link("ECTools", ec.address);
    lc = await Ledger.new();

    await token.transfer(partyB, web3latest.utils.toWei("100"));
    await token.transfer(partyI, web3latest.utils.toWei("100"));

    let sentBalance = [
      web3latest.utils.toWei("10"),
      web3latest.utils.toWei("10")
    ];
    await token.approve(lc.address, sentBalance[1]);
    await token.approve(lc.address, sentBalance[1], { from: partyI });
    let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
    await lc.createChannel(lc_id, partyI, "0", token.address, sentBalance, {
      from: partyA,
      value: sentBalance[0]
    });
    await lc.joinChannel(lc_id, sentBalance, {
      from: partyI,
      value: sentBalance[0]
    });

    initialVCstate = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id }, // VC ID
      { type: "uint256", value: "0" }, // sequence
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyB }, // partyB
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
      { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // token
      { type: "uint256", value: web3latest.utils.toWei("0") } // token
    );

    payload = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id },
      { type: "bool", value: false }, // isclose
      { type: "uint256", value: "1" }, // sequence
      { type: "uint256", value: "1" }, // open VCs
      { type: "bytes32", value: initialVCstate }, // VC root hash
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyI }, // hub
      { type: "uint256", value: web3latest.utils.toWei("4") },
      { type: "uint256", value: web3latest.utils.toWei("15") },
      { type: "uint256", value: web3latest.utils.toWei("4") }, // token
      { type: "uint256", value: web3latest.utils.toWei("15") } // token
    );

    fakeSig = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id }, // ID
      { type: "bool", value: false }, // isclose
      { type: "uint256", value: "1" }, // sequence
      { type: "uint256", value: "0" }, // open VCs
      { type: "string", value: "0x0" }, // VC root hash
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyI }, // hub
      { type: "uint256", value: web3latest.utils.toWei("15") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("15") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("15") }, // token
      { type: "uint256", value: web3latest.utils.toWei("15") } // token
    );

    sigA = await web3latest.eth.sign(payload, partyA);
    sigI = await web3latest.eth.sign(payload, partyI);
    fakeSig = await web3latest.eth.sign(fakeSig, partyA);

    vcRootHash = initialVCstate;
    bond = [web3latest.utils.toWei("1"), web3latest.utils.toWei("1")];
    let updateParams = [
      "1",
      "1",
      web3latest.utils.toWei("4"),
      web3latest.utils.toWei("15"),
      web3latest.utils.toWei("4"),
      web3latest.utils.toWei("15")
    ];
    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI);

    let balances = [
      web3latest.utils.toWei("1"),
      web3latest.utils.toWei("0"),
      web3latest.utils.toWei("1"),
      web3latest.utils.toWei("0")
    ];
    sigA = await web3latest.eth.sign(initialVCstate, partyA);
    await lc.initVCstate(
      lc_id,
      lc_id,
      "0",
      partyA,
      partyB,
      bond,
      balances,
      sigA
    );

    let lc_id_fail = web3latest.utils.sha3("fail", { encoding: "hex" });
    await token.approve(lc.address, sentBalance[1]);
    await lc.createChannel(
      lc_id_fail,
      partyI,
      "100",
      token.address,
      sentBalance,
      { from: partyA, value: sentBalance[0] }
    );

    payload = web3latest.utils.soliditySha3(
      { type: "uint256", value: lc_id }, // VC ID
      { type: "uint256", value: 1 }, // sequence
      { type: "address", value: partyA }, // partyA
      { type: "address", value: partyB }, // partyB
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // bond token
      { type: "uint256", value: web3latest.utils.toWei("0") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("1") }, // eth
      { type: "uint256", value: web3latest.utils.toWei("0") }, // token
      { type: "uint256", value: web3latest.utils.toWei("1") } // token
    );

    balances = [
      web3latest.utils.toWei("0"),
      web3latest.utils.toWei("1"),
      web3latest.utils.toWei("0"),
      web3latest.utils.toWei("1")
    ];
    sigA = await web3latest.eth.sign(payload, partyA);
  });

  describe("byzantineCloseChannel() has 6 possible cases:", () => {
    it("1. Fail: Channel with that ID does not exist", async () => {
      let lc_id = web3latest.utils.sha3("nochannel", { encoding: "hex" });
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      expect(channel[0][0]).to.be.equal(
        "0x0000000000000000000000000000000000000000"
      ); //fail
      expect(channel[9]).to.not.be.equal(true); //pass (inverted for nonexistent channel)
      expect(channel[10]).to.not.be.equal(true); //pass (inverted for nonexistent channel)
      expect(channel[8] * 1000).to.not.be.above(Date.now()); //pass (inverted for nonexistent VC)
      expect(parseInt(channel[11])).to.be.equal(0); //pass
      expect(parseInt(channel[3][0])).to.be.at.least(
        parseInt(channel[1][0]) + parseInt(channel[1][1])
      ); //pass
      expect(parseInt(channel[3][1])).to.be.at.least(
        parseInt(channel[2][0]) + parseInt(channel[2][1])
      ); //pass

      await lc.byzantineCloseChannel(lc_id).should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.byzantineCloseChannel(lc_id)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("2. Fail: Channel with that ID is not open", async () => {
      let lc_id = web3latest.utils.sha3("fail", { encoding: "hex" });
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.not.be.equal(true); //fail
      expect(channel[10]).to.not.be.equal(true); //pass (inverted for nonexistent channel)
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(parseInt(channel[11])).to.be.equal(0); //pass
      expect(parseInt(channel[3][0])).to.be.at.least(
        parseInt(channel[1][0]) + parseInt(channel[1][1])
      ); //pass
      expect(parseInt(channel[3][1])).to.be.at.least(
        parseInt(channel[2][0]) + parseInt(channel[2][1])
      ); //pass

      await lc.byzantineCloseChannel(lc_id).should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.byzantineCloseChannel(lc_id)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("3. Fail: Channel is not in dispute", async () => {
      let lc_id = web3latest.utils.sha3("fail", { encoding: "hex" });

      let sentBalance = [
        web3latest.utils.toWei("10"),
        web3latest.utils.toWei("10")
      ];
      await token.approve(lc.address, sentBalance[1], { from: partyI });
      await lc.joinChannel(lc_id, sentBalance, {
        from: partyI,
        value: sentBalance[0]
      });

      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(channel[10]).to.be.equal(false); //fail
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(parseInt(channel[11])).to.be.equal(0); //pass
      expect(parseInt(channel[3][0])).to.be.at.least(
        parseInt(channel[1][0]) + parseInt(channel[1][1])
      ); //pass
      expect(parseInt(channel[3][1])).to.be.at.least(
        parseInt(channel[2][0]) + parseInt(channel[2][1])
      ); //pass

      await lc.byzantineCloseChannel(lc_id).should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.byzantineCloseChannel(lc_id)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("4. Fail: UpdateLCTimeout has not yet expired", async () => {
      let lc_id = web3latest.utils.sha3("fail", { encoding: "hex" });

      payload = web3latest.utils.soliditySha3(
        { type: "uint256", value: lc_id },
        { type: "bool", value: false }, // isclose
        { type: "uint256", value: "1" }, // sequence
        { type: "uint256", value: "0" }, // open VCs
        { type: "bytes32", value: "0x0" }, // VC root hash
        { type: "address", value: partyA }, // partyA
        { type: "address", value: partyI }, // hub
        { type: "uint256", value: web3latest.utils.toWei("5") },
        { type: "uint256", value: web3latest.utils.toWei("15") },
        { type: "uint256", value: web3latest.utils.toWei("5") }, // token
        { type: "uint256", value: web3latest.utils.toWei("15") } // token
      );
      let sigA_temp = await web3latest.eth.sign(payload, partyA);
      let sigI_temp = await web3latest.eth.sign(payload, partyI);

      let updateParams = [
        "1",
        "0",
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15"),
        web3latest.utils.toWei("5"),
        web3latest.utils.toWei("15")
      ];
      await lc.updateLCstate(lc_id, updateParams, "0x0", sigA_temp, sigI_temp);

      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(channel[10]).to.be.equal(true); //pass
      expect(channel[8] * 1000).to.be.above(Date.now()); //fail
      expect(parseInt(channel[11])).to.be.equal(0); //pass
      expect(parseInt(channel[3][0])).to.be.at.least(
        parseInt(channel[1][0]) + parseInt(channel[1][1])
      ); //pass
      expect(parseInt(channel[3][1])).to.be.at.least(
        parseInt(channel[2][0]) + parseInt(channel[2][1])
      ); //pass

      await lc.byzantineCloseChannel(lc_id).should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.byzantineCloseChannel(lc_id)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("5. Fail: VCs are still open", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(channel[10]).to.be.equal(true); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(parseInt(channel[11])).to.be.equal(1); //fail
      expect(parseInt(channel[3][0])).to.be.at.least(
        parseInt(channel[1][0]) + parseInt(channel[1][1])
      ); //pass
      expect(parseInt(channel[3][1])).to.be.at.least(
        parseInt(channel[2][0]) + parseInt(channel[2][1])
      ); //pass

      await lc.byzantineCloseChannel(lc_id).should.be.rejectedWith(SolRevert);

      //  try {
      // 	await lc.byzantineCloseChannel(lc_id)
      //   } catch (e) {
      // 	expect(e.message).to.equal(SolRevert(e.tx))
      // 	expect(e.name).to.equal('StatusError')
      //   }
    });
    it("6. Fail: Onchain Eth balances are greater than deposit", async () => {
      // can't test this until deposits are complete
    });
    it("7. Fail: Onchain token balances are greater than deposit", async () => {
      // can't test this until deposits are complete
    });
    it("8. Success: Channel byzantine closed!", async () => {
      let lc_id = web3latest.utils.sha3("1111", { encoding: "hex" });
      await lc.closeVirtualChannel(lc_id, lc_id);

      let channel = await lc.getChannel(lc_id);
      let vc = await lc.getVirtualChannel(lc_id);

      expect(channel[0][0]).to.be.equal(partyA); //pass
      expect(channel[9]).to.be.equal(true); //pass
      expect(channel[10]).to.be.equal(true); //pass
      expect(channel[8] * 1000).to.be.below(Date.now()); //pass
      expect(parseInt(channel[11])).to.be.equal(0); //pass
      expect(parseInt(channel[3][0])).to.be.at.least(
        parseInt(channel[1][0]) + parseInt(channel[1][1])
      ); //pass
      expect(parseInt(channel[3][1])).to.be.at.least(
        parseInt(channel[2][0]) + parseInt(channel[2][1])
      ); //pass

      await lc.byzantineCloseChannel(lc_id);

      channel = await lc.getChannel(lc_id);
      expect(channel[9]).to.be.equal(false);
    });
  });
});
