'use strict'

import MerkleTree from '../helpers/MerkleTree'
const Utils = require('../helpers/utils')
const Ledger = artifacts.require('./LedgerChannel.sol')
const EC = artifacts.require('./ECTools.sol')
const Token = artifacts.require('./token/HumanStandardToken.sol')

const Web3latest = require('web3')
const web3latest = new Web3latest(new Web3latest.providers.HttpProvider("http://localhost:8545")) //ganache port
const BigNumber = web3.BigNumber

const should = require('chai').use(require('chai-as-promised')).use(require('chai-bignumber')(BigNumber)).should()
const SolRevert = 'VM Exception while processing transaction: revert'

let lc
let ec
let token

// state
let partyA 
let partyB 
let partyI 
let partyN

let vcRootHash

let payload
let sigA
let sigI
let sigB
let fakeSig

is close flag, lc state sequence, number open vc, vc root hash, partyA/B, partyI, balA/B, balI

contract('LedgerChannel :: createChannel()', function(accounts) {

  before(async () => {
  	partyA = accounts[0]
	partyB = accounts[1]
	partyI = accounts[2]
	partyN = accounts[3]

    ec = await EC.new()
    token = await Token.new(web3latest.utils.toWei('1000'), 'Test', 1, 'TST')
    Ledger.link('HumanStandardToken', token.address)
    Ledger.link('ECTools', ec.address)
    lc = await Ledger.new()

    await token.transfer(partyB, web3latest.utils.toWei('100'))
    await token.transfer(partyI, web3latest.utils.toWei('100'))

    let lc_id_fail = web3latest.utils.sha3('fail', {encoding: 'hex'})
    await lc.createChannel(lc_id_fail, partyI, '1000000000000000000', token.address, [0, 0], {from:partyA, value: 0})
  })

	describe('Creating a channel has 6 possible cases:', () => {
	  it("1. Fail: Channel with that ID has already been created", async () => {
	  	let lc_id = web3latest.utils.sha3('fail', {encoding: 'hex'})
    	let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
    	let approval = await token.approve(lc.address, sentBalance[1])
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[0][0]).to.not.be.equal('0x0000000000000000000000000000000000000000') //fail
  	    expect(partyI).to.not.be.equal('0x0000000000000000000000000000000000000000') //pass
  	    expect(sentBalance[0]).to.be.above(0) //pass
  	    expect(sentBalance[1]).to.be.above(0) //pass
  	    expect(sentBalance[0]).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sentBalance[1]).to.be.equal(web3latest.utils.toWei('10')) //pass

  	    await lc.createChannel(lc_id, partyI, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]}).should.be.rejectedWith(SolRevert)
	  })
	  it("2. Fail: No Hub address was provided.", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    	let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
    	let approval = await token.approve(lc.address, sentBalance[1])
    	let channel = await lc.getChannel(lc_id)
    	let partyI_fail = ('0x0000000000000000000000000000000000000000')
  	    expect(channel[0][0]).to.be.equal('0x0000000000000000000000000000000000000000') //pass
  	    expect(partyI_fail).to.be.equal('0x0000000000000000000000000000000000000000') //fail
  	    expect(sentBalance[0]).to.be.above(0) //pass
  	    expect(sentBalance[1]).to.be.above(0) //pass
  	    expect(sentBalance[0]).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sentBalance[1]).to.be.equal(web3latest.utils.toWei('10')) //pass

  	    await lc.createChannel(lc_id, partyI_fail, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]}).should.be.rejectedWith(SolRevert)
	  })
	  it("3. Fail: Token balance input is negative.", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    	let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('-10')]
    	let approval = await token.approve(lc.address, sentBalance[1])
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[0][0]).to.be.equal('0x0000000000000000000000000000000000000000') //pass
  	    expect(partyI).to.not.be.equal('0x0000000000000000000000000000000000000000') //pass
  	    expect(sentBalance[0]).to.be.above(0) //fail
  	    expect(sentBalance[1]).to.not.be.above(0) //pass
  	    expect(sentBalance[0]).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sentBalance[1]).to.be.equal(web3latest.utils.toWei('-10')) //pass

  	    await lc.createChannel(lc_id, partyI, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]}).should.be.rejectedWith(SolRevert)
	  })
	  it("4. Fail: Eth balance doesn't match paid value.", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    	let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
    	let approval = await token.approve(lc.address, sentBalance[1])
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[0][0]).to.be.equal('0x0000000000000000000000000000000000000000') //pass
  	    expect(partyI).to.not.be.equal('0x0000000000000000000000000000000000000000') //pass
  	    expect(sentBalance[0]).to.be.above(0) //pass
  	    expect(sentBalance[1]).to.be.above(0) //pass
  	    expect(sentBalance[0]).to.not.be.equal(web3latest.utils.toWei('1')) //fail
  	    expect(sentBalance[1]).to.be.equal(web3latest.utils.toWei('10')) //pass

  	    await lc.createChannel(lc_id, partyI, '0', token.address, sentBalance, {from:partyA, value: web3latest.utils.toWei('1')}).should.be.rejectedWith(SolRevert)
	  })
	  it("5. Fail: Token transferFrom failed.", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    	let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
    	let approval = await token.approve(lc.address, web3latest.utils.toWei('1'))
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[0][0]).to.be.equal('0x0000000000000000000000000000000000000000') //pass
  	    expect(partyI).to.not.be.equal('0x0000000000000000000000000000000000000000') //pass
  	    expect(sentBalance[0]).to.be.above(0) //pass
  	    expect(sentBalance[1]).to.be.above(0) //pass
  	    expect(sentBalance[0]).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sentBalance[1]).to.not.be.equal(web3latest.utils.toWei('1')) //fail

  	    await lc.createChannel(lc_id, partyI, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]}).should.be.rejectedWith(SolRevert)
	  })
	  it("6. Success: Channel created!", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    	let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
    	let approval = await token.approve(lc.address, web3latest.utils.toWei('10'))
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[0][0]).to.be.equal('0x0000000000000000000000000000000000000000') //pass
  	    expect(partyI).to.not.be.equal('0x0000000000000000000000000000000000000000') //pass
  	    expect(sentBalance[0]).to.be.above(0) //pass
  	    expect(sentBalance[1]).to.be.above(0) //pass
  	    expect(sentBalance[0]).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sentBalance[1]).to.be.equal(web3latest.utils.toWei('10')) //pass

  	    await lc.createChannel(lc_id, partyI, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]})
	  })
	})
})

contract('LedgerChannel :: LCOpenTimeout()', function(accounts) {

  before(async () => {
  	partyA = accounts[0]
	partyB = accounts[1]
	partyI = accounts[2]
	partyN = accounts[3]

    ec = await EC.new()
    token = await Token.new(web3latest.utils.toWei('1000'), 'Test', 1, 'TST')
    Ledger.link('HumanStandardToken', token.address)
    Ledger.link('ECTools', ec.address)
    lc = await Ledger.new()

    await token.transfer(partyB, web3latest.utils.toWei('100'))
    await token.transfer(partyI, web3latest.utils.toWei('100'))

	let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
	let approval = await token.approve(lc.address, sentBalance[1])
    let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    await lc.createChannel(lc_id, partyI, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]})

    let lc_id_fail = web3latest.utils.sha3('fail', {encoding: 'hex'})
    await lc.createChannel(lc_id_fail, partyI, '1000000000000000000', token.address, [0, 0], {from:partyA, value: 0})
  })


	describe('LCopenTimeout() has 5 possible cases:', () => {
	  it("1. Fail: Sender is not PartyA of channel", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[0][0]).to.not.be.equal(partyB) //fail
  	    expect(channel[0][0]).to.not.be.equal(null) //pass
  	    expect(channel[9]).to.be.equal(false) //pass
  	    expect(channel[7]).to.be.below(Date.now()) //pass

  	    await lc.LCOpenTimeout(lc_id, {from:partyB}).should.be.rejectedWith(SolRevert)
	  })
	  it("2. Fail: Channel does not exist", async () => {
	  	let lc_id = web3latest.utils.sha3('0000', {encoding: 'hex'})
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[0][0]).to.not.be.equal(partyB) //pass
  	    expect(channel[0][0]).to.be.equal(null || '0x0000000000000000000000000000000000000000') //fail
  	    expect(channel[9]).to.be.equal(false) //pass
  	    expect(channel[7]).to.be.below(Date.now()) //pass

  	    await lc.LCOpenTimeout(lc_id, {from:partyA}).should.be.rejectedWith(SolRevert)
	  })
	  it("3. Fail: Channel is already open", async () => {
	  	let lc_id = web3latest.utils.sha3('0000', {encoding: 'hex'})
  	    await lc.createChannel(lc_id, partyI, '0', token.address, ['0', '0'], {from:partyA})
	  	await lc.joinChannel(lc_id, ['0', '0'], {from: partyI})
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[0][0]).to.not.be.equal(null) //pass
  	    expect(channel[9]).to.be.equal(true) //fail
  	    expect(channel[7]).to.be.below(Date.now()) //pass

  	    await lc.LCOpenTimeout(lc_id, {from:partyA}).should.be.rejectedWith(SolRevert)
	  })
	  it("4. Fail: LCopenTimeout has not expired", async () => {
	  	let lc_id = web3latest.utils.sha3('fail', {encoding: 'hex'})
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[0][0]).to.not.be.equal(null) //pass
  	    expect(channel[9]).to.be.equal(false) //pass
  	    expect(channel[7]).to.be.above(Date.now()) //fail

  	    await lc.LCOpenTimeout(lc_id, {from:partyA}).should.be.rejectedWith(SolRevert)
	  })	 
	  //******
	  //NOTE: there's one more require in the contract for a failed token transfer. Unfortunately we can't recreate that here.
	  //******
	  it("5. Success!", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[0][0]).to.not.be.equal(null) //pass
  	    expect(channel[9]).to.be.equal(false) //pass
  	    expect(channel[7]).to.be.below(Date.now()) //pass

  	    let oldBalanceEth = await web3latest.eth.getBalance(partyA)
  	    let oldBalanceToken = await token.balanceOf(partyA)

  	    await lc.LCOpenTimeout(lc_id, {from:partyA})

  	    let newBalanceEth = await web3latest.eth.getBalance(partyA)
  	    let newBalanceToken = await token.balanceOf(partyA)
  	    newBalanceToken = newBalanceToken - oldBalanceToken
  	    let balanceToken = await (newBalanceToken).toString()
  	    //TODO gas estimate for this test
  	    // expect(newBalanceEth - oldBalanceEth).to.be.equal(web3latest.utils.toWei('10'))
  	    expect(balanceToken).to.be.equal(web3latest.utils.toWei('10'))
	  })
	})
})

contract('LedgerChannel :: joinChannel()', function(accounts) {

  before(async () => {
  	partyA = accounts[0]
	partyB = accounts[1]
	partyI = accounts[2]
	partyN = accounts[3]

    ec = await EC.new()
    token = await Token.new(web3latest.utils.toWei('1000'), 'Test', 1, 'TST')
    Ledger.link('HumanStandardToken', token.address)
    Ledger.link('ECTools', ec.address)
    lc = await Ledger.new()

    await token.transfer(partyB, web3latest.utils.toWei('100'))
    await token.transfer(partyI, web3latest.utils.toWei('100'))

	let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
	let approval = await token.approve(lc.address, sentBalance[1])
    let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    await lc.createChannel(lc_id, partyI, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]})

    let lc_id_fail = web3latest.utils.sha3('fail', {encoding: 'hex'})
    await lc.createChannel(lc_id_fail, partyI, '0', token.address, [0, 0], {from:partyA, value: 0})
    await lc.joinChannel(lc_id_fail, [0,0], {from: partyI, value: 0})
  })


	describe('joinChannel() has 6 possible cases:', () => {
	  it("1. Fail: Channel with that ID has already been opened", async () => {
	  	let lc_id = web3latest.utils.sha3('fail', {encoding: 'hex'})
		let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
		let approval = await token.approve(lc.address, sentBalance[1], {from: partyI})
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[9]).to.be.equal(true) //fail
  	    expect(channel[0][1]).to.be.equal(partyI) //pass
  	    expect(sentBalance[1]).to.be.at.least(0) //pass
  	    expect(sentBalance[0]).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sentBalance[1]).to.be.equal(web3latest.utils.toWei('10')) //pass

  	    await lc.joinChannel(lc_id, sentBalance, {from: partyI, value: sentBalance[0]}).should.be.rejectedWith(SolRevert)
	  })
	  it("2. Fail: Msg.sender is not PartyI of this channel", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
		let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
		let approval = await token.approve(lc.address, sentBalance[1], {from: partyI})
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[9]).to.be.equal(false) //pass
  	    expect(channel[0][1]).to.not.be.equal(partyB) //fail
  	    expect(sentBalance[1]).to.be.at.least(0) //pass
  	    expect(sentBalance[0]).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sentBalance[1]).to.be.equal(web3latest.utils.toWei('10')) //pass

  	    await lc.joinChannel(lc_id, sentBalance, {from: partyB, value: sentBalance[0]}).should.be.rejectedWith(SolRevert)
	  })
	  it("3. Fail: Token balance is negative", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
		let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('-10')]
		let approval = await token.approve(lc.address, sentBalance[1], {from: partyI})
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[9]).to.be.equal(false) //pass
  	    expect(channel[0][1]).to.be.equal(partyI) //pass
  	    expect(sentBalance[1]).to.be.below(0) //fail
  	    expect(sentBalance[0]).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sentBalance[1]).to.be.equal(web3latest.utils.toWei('-10')) //pass

  	    await lc.joinChannel(lc_id, sentBalance, {from: partyI, value: sentBalance[0]}).should.be.rejectedWith(SolRevert)
	  })
	  it("4. Fail: Eth balance does not match paid value", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
		let sentBalance = [web3latest.utils.toWei('1'), web3latest.utils.toWei('10')]
		let approval = await token.approve(lc.address, sentBalance[1], {from: partyI})
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[9]).to.be.equal(false) //pass
  	    expect(channel[0][1]).to.be.equal(partyI) //pass
  	    expect(sentBalance[1]).to.be.at.least(0) //pass
  	    expect(sentBalance[0]).to.not.be.equal(web3latest.utils.toWei('10')) //fail
  	    expect(sentBalance[1]).to.be.equal(web3latest.utils.toWei('10')) //pass

  	    await lc.joinChannel(lc_id, sentBalance, {from: partyI, value: web3latest.utils.toWei('10')}).should.be.rejectedWith(SolRevert)
	  })
	  it("5. Fail: Token transferFrom failed", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
		let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('1')]
		let approval = await token.approve(lc.address, sentBalance[1], {from: partyI})
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[9]).to.be.equal(false) //pass
  	    expect(channel[0][1]).to.be.equal(partyI) //pass
  	    expect(sentBalance[1]).to.be.at.least(0) //pass
  	    expect(sentBalance[0]).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sentBalance[1]).to.not.be.equal(web3latest.utils.toWei('10')) //fail

  	    await lc.joinChannel(lc_id, [sentBalance[0], web3latest.utils.toWei('10')], {from: partyI, value: sentBalance[0]}).should.be.rejectedWith(SolRevert)
	  })
	  it("6. Success: LC Joined!", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
		let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
		let approval = await token.approve(lc.address, sentBalance[1], {from: partyI})
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[9]).to.be.equal(false) //pass
  	    expect(channel[0][1]).to.be.equal(partyI) //pass
  	    expect(sentBalance[1]).to.be.at.least(0) //pass
  	    expect(sentBalance[0]).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sentBalance[1]).to.be.equal(web3latest.utils.toWei('10')) //pass

  	    await lc.joinChannel(lc_id, sentBalance, {from: partyI, value: sentBalance[0]})

	  })
	})
})

// //TODO deposit unit tests

contract('LedgerChannel :: consensusCloseChannel()', function(accounts) {

  before(async () => {
  	partyA = accounts[0]
	partyB = accounts[1]
	partyI = accounts[2]
	partyN = accounts[3]

    ec = await EC.new()
    token = await Token.new(web3latest.utils.toWei('1000'), 'Test', 1, 'TST')
    Ledger.link('HumanStandardToken', token.address)
    Ledger.link('ECTools', ec.address)
    lc = await Ledger.new()

    await token.transfer(partyB, web3latest.utils.toWei('100'))
    await token.transfer(partyI, web3latest.utils.toWei('100'))

	let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
	await token.approve(lc.address, sentBalance[1])
	await token.approve(lc.address, sentBalance[1], {from: partyI})
    let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    await lc.createChannel(lc_id, partyI, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]})
    await lc.joinChannel(lc_id, sentBalance, {from: partyI, value: sentBalance[0]})

    payload = web3latest.utils.soliditySha3(
      { type: 'uint256', value: lc_id },
      { type: 'bool', value: true }, // isclose
      { type: 'uint256', value: '1' }, // sequence
      { type: 'uint256', value: '0' }, // open VCs
      { type: 'bytes32', value: '0x0' }, // VC root hash
      { type: 'address', value: partyA }, // partyA
      { type: 'address', value: partyI }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('5') },
      { type: 'uint256', value: web3latest.utils.toWei('15') },
      { type: 'uint256', value: web3latest.utils.toWei('5') }, // token
      { type: 'uint256', value: web3latest.utils.toWei('15') }  // token
    ) 

    fakeSig = web3latest.utils.soliditySha3(
      { type: 'uint256', value: lc_id }, // ID
      { type: 'bool', value: true }, // isclose
      { type: 'uint256', value: '1' }, // sequence
      { type: 'uint256', value: '0' }, // open VCs
      { type: 'string', value: '0x0' }, // VC root hash
      { type: 'address', value: partyA }, // partyA
      { type: 'address', value: partyI }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('15') }, // eth
      { type: 'uint256', value: web3latest.utils.toWei('15') }, // eth
      { type: 'uint256', value: web3latest.utils.toWei('15') }, // token
      { type: 'uint256', value: web3latest.utils.toWei('15') }  // token
    )

    sigA = await web3latest.eth.sign(payload, partyA)
    sigI = await web3latest.eth.sign(payload, partyI)
    fakeSig = await web3latest.eth.sign(fakeSig, partyA)

    let lc_id_fail = web3latest.utils.sha3('fail', {encoding: 'hex'})
    await token.approve(lc.address, sentBalance[1])
    await lc.createChannel(lc_id_fail, partyI, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]})
  })


	describe('consensusCloseChannel() has 7 possible cases:', () => {
	  it("1. Fail: Channel with that ID does not exist", async () => {
	  	let lc_id = web3latest.utils.sha3('2222', {encoding: 'hex'})
		let balances = [web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal('0x0000000000000000000000000000000000000000') //fail
  	    expect(channel[9]).to.not.be.equal(true) //pass
  	    expect(totalEthDeposit).to.not.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.not.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass

  	    await lc.consensusCloseChannel(lc_id, '1', balances, sigA, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("2. Fail: Channel with that ID is not open", async () => {
	  	let lc_id = web3latest.utils.sha3('fail', {encoding: 'hex'})
		let balances = [web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(false) //fail
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass

  	    await lc.consensusCloseChannel(lc_id, '1', balances, sigA, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("3. Fail: Total Eth deposit is not equal to submitted Eth balances", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
		let balances = [web3latest.utils.toWei('5'), web3latest.utils.toWei('5'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.not.be.equal(web3latest.utils.toWei('10')) //fail
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass

  	    await lc.consensusCloseChannel(lc_id, '1', balances, sigA, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("4. Fail: Total token deposit is not equal to submitted token balances", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
		let balances = [web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('5')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.not.be.equal(web3latest.utils.toWei('10')) //fail
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass

  	    await lc.consensusCloseChannel(lc_id, '1', balances, sigA, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("5. Fail: Incorrect sig for partyA", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
		let balances = [web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(fakeSig).to.not.be.equal(verificationA) //fail
  	    expect(sigI).to.be.equal(verificationI) //pass

  	    await lc.consensusCloseChannel(lc_id, '1', balances, fakeSig, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("6. Fail: Incorrect sig for partyI", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
		let balances = [web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(fakeSig).to.not.be.equal(verificationI) //fail

  	    await lc.consensusCloseChannel(lc_id, '1', balances, sigA, fakeSig).should.be.rejectedWith(SolRevert)
	  })
	  it("7. Success: Channel Closed", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
		let balances = [web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let openChansInit = await lc.numChannels();
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass

  	    await lc.consensusCloseChannel(lc_id, '1', balances, sigA, sigI)
  	    let openChansFinal = await lc.numChannels();
  	    expect(openChansInit - openChansFinal).to.be.equal(1);
	  })
	})
})

contract('LedgerChannel :: updateLCstate()', function(accounts) {

  before(async () => {
  	partyA = accounts[0]
	partyB = accounts[1]
	partyI = accounts[2]
	partyN = accounts[3]

    ec = await EC.new()
    token = await Token.new(web3latest.utils.toWei('1000'), 'Test', 1, 'TST')
    Ledger.link('HumanStandardToken', token.address)
    Ledger.link('ECTools', ec.address)
    lc = await Ledger.new()

    await token.transfer(partyB, web3latest.utils.toWei('100'))
    await token.transfer(partyI, web3latest.utils.toWei('100'))

	let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
	await token.approve(lc.address, sentBalance[1])
	await token.approve(lc.address, sentBalance[1], {from: partyI})

    let lc_id_1 = web3latest.utils.sha3('1111', {encoding: 'hex'})
    await lc.createChannel(lc_id_1, partyI, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]})
    await lc.joinChannel(lc_id_1, sentBalance, {from: partyI, value: sentBalance[0]})

    await token.approve(lc.address, sentBalance[1])
	await token.approve(lc.address, sentBalance[1], {from: partyI})
    let lc_id_2 = web3latest.utils.sha3('2222', {encoding: 'hex'})
    await lc.createChannel(lc_id_2, partyI, '100000', token.address, sentBalance, {from:partyA, value: sentBalance[0]})
    await lc.joinChannel(lc_id_2, sentBalance, {from: partyI, value: sentBalance[0]})

    vcRootHash = web3latest.utils.soliditySha3({type: 'bytes32', value: '0x1'})
    payload = web3latest.utils.soliditySha3(
      { type: 'bytes32', value: lc_id_1 },
      { type: 'bool', value: false }, // isclose
      { type: 'uint256', value: '2' }, // sequence
      { type: 'uint256', value: '1' }, // open VCs
      { type: 'bytes32', value: vcRootHash }, // VC root hash
      { type: 'address', value: partyA }, // partyA
      { type: 'address', value: partyI }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('5') },
      { type: 'uint256', value: web3latest.utils.toWei('15') },
      { type: 'uint256', value: web3latest.utils.toWei('5') }, // token
      { type: 'uint256', value: web3latest.utils.toWei('15') }  // token
    ) 

    fakeSig = web3latest.utils.soliditySha3(
      { type: 'uint256', value: lc_id_1 }, // ID
      { type: 'bool', value: false }, // isclose
      { type: 'uint256', value: '2' }, // sequence
      { type: 'uint256', value: '1' }, // open VCs
      { type: 'bytes32', value: '0x1' }, // VC root hash
      { type: 'address', value: partyA }, // partyA
      { type: 'address', value: partyI }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('15') }, // eth
      { type: 'uint256', value: web3latest.utils.toWei('15') }, // eth
      { type: 'uint256', value: web3latest.utils.toWei('15') }, // token
      { type: 'uint256', value: web3latest.utils.toWei('15') }  // token
    )

    sigA = await web3latest.eth.sign(payload, partyA)
    sigI = await web3latest.eth.sign(payload, partyI)
    fakeSig = await web3latest.eth.sign(fakeSig, partyA)

    let lc_id_fail = web3latest.utils.sha3('fail', {encoding: 'hex'})
    await token.approve(lc.address, sentBalance[1])
    await lc.createChannel(lc_id_fail, partyI, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]})
  })


	describe('updateLCstate() has 10 possible cases:', () => {
	  it("1. Fail: Channel with that ID does not exist", async () => {
	  	let lc_id = web3latest.utils.sha3('nochannel', {encoding: 'hex'})
	  	let sequence = '2';
	  	let vcRootHash = web3latest.utils.soliditySha3({type: 'bytes32', value: '0x1'})
		let updateParams = [sequence, '1', web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal('0x0000000000000000000000000000000000000000') //fail
  	    expect(channel[9]).to.not.be.equal(true) //pass
  	    expect(totalEthDeposit).to.not.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.not.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass
  	    expect(channel[4]).to.be.below(sequence) //pass
  	    if(channel[10] == true) expect(channel[8]).to.be.above(Date.now()) //pass

  	    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("2. Fail: Channel with that ID is not open", async () => {
	  	let lc_id = web3latest.utils.sha3('fail', {encoding: 'hex'})
	  	let sequence = '2';
	  	let vcRootHash = web3latest.utils.soliditySha3({type: 'bytes32', value: '0x1'})
		let updateParams = [sequence, '1', web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(false) //fail
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass
  	    expect(channel[4]).to.be.below(sequence) //pass
  	    if(channel[10] == true) expect(channel[8]).to.be.above(Date.now()) //pass

  	    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("3. Fail: Total Eth deposit is not equal to submitted Eth balances", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
	  	let sequence = '2';
	  	let vcRootHash = web3latest.utils.soliditySha3({type: 'bytes32', value: '0x1'})
		let updateParams = [sequence, '1', web3latest.utils.toWei('5'), web3latest.utils.toWei('5'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.not.be.equal(web3latest.utils.toWei('10')) //fail
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass
  	    expect(channel[4]).to.be.below(sequence) //pass
  	    if(channel[10] == true) expect(channel[8]).to.be.above(Date.now()) //pass

  	    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("4. Fail: Total token deposit is not equal to submitted Eth balances", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
	  	let sequence = '2';
	  	let vcRootHash = web3latest.utils.soliditySha3({type: 'bytes32', value: '0x1'})
		let updateParams = [sequence, '1', web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('5')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.not.be.equal(web3latest.utils.toWei('10')) //fail
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass
  	    expect(channel[4]).to.be.below(sequence) //pass
  	    if(channel[10] == true) expect(channel[8]).to.be.above(Date.now()) //pass

  	    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("5. Fail: Incorrect sig for partyA", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
	  	let sequence = '2';
	  	let vcRootHash = web3latest.utils.soliditySha3({type: 'bytes32', value: '0x1'})
		let updateParams = [sequence, '1', web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('5')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(fakeSig).to.not.be.equal(verificationA) //fail
  	    expect(sigI).to.be.equal(verificationI) //pass
  	    expect(channel[4]).to.be.below(sequence) //pass
  	    if(channel[10] == true) expect(channel[8]).to.be.above(Date.now()) //pass

  	    await lc.updateLCstate(lc_id, updateParams, vcRootHash, fakeSig, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("6. Fail: Incorrect sig for partyI", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
	  	let sequence = '2';
	  	let vcRootHash = web3latest.utils.soliditySha3({type: 'bytes32', value: '0x1'})
		let updateParams = [sequence, '1', web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('5')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(fakeSig).to.not.be.equal(verificationI) //fail
  	    expect(channel[4]).to.be.below(sequence) //pass
  	    if(channel[10] == true) expect(channel[8]).to.be.above(Date.now()) //pass

  	    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, fakeSig).should.be.rejectedWith(SolRevert)
	  })
	  it("7. Success 1: updateLCstate called first time and timeout started", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
	  	let sequence = '2';
	  	// let vcRootHash = web3latest.utils.soliditySha3({type: 'bytes32', value: '0x1'})
		let updateParams = [sequence, '1', web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();
    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass
  	    expect(channel[4]).to.be.below(sequence) //pass
  	    if(channel[10] == true) expect(channel[8]).to.be.above(Date.now()) //pass

  	    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI)

  	    channel = await lc.getChannel(lc_id)
  	    expect(channel[10]).to.be.equal(true)
	  })
	  it("8. Error: State none below onchain latest sequence", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
	  	let sequence = '1';
	  	// let vcRootHash = web3latest.utils.soliditySha3({type: 'bytes32', value: '0x1'})
		let updateParams = [sequence, '1', web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();

  		payload = web3latest.utils.soliditySha3(
	      { type: 'bytes32', value: lc_id },
	      { type: 'bool', value: false }, // isclose
	      { type: 'uint256', value: '1' }, // sequence
	      { type: 'uint256', value: '1' }, // open VCs
	      { type: 'bytes32', value: vcRootHash }, // VC root hash
	      { type: 'address', value: partyA }, // partyA
	      { type: 'address', value: partyI }, // hub
	      { type: 'uint256', value: web3latest.utils.toWei('5') },
	      { type: 'uint256', value: web3latest.utils.toWei('15') },
	      { type: 'uint256', value: web3latest.utils.toWei('5') }, // token
	      { type: 'uint256', value: web3latest.utils.toWei('15') }  // token
	    ) 

  		let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

	    sigA = await web3latest.eth.sign(payload, partyA)
	    sigI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass
  	    expect(channel[4]).to.not.be.below(sequence) //fail
  	    if(channel[10] == true) expect(channel[8].toString()).to.not.be.above(Date.now()) //pass ==== Technically this is a fail right now, but sequence is checked earlier. Needs to be fixed later

  	    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("9. Error: UpdateLC timed out", async () => {
	  	let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
	  	let sequence = '3';
	  	// let vcRootHash = web3latest.utils.soliditySha3({type: 'bytes32', value: '0x1'})
		let updateParams = [sequence, '1', web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();

  		payload = web3latest.utils.soliditySha3(
	      { type: 'bytes32', value: lc_id },
	      { type: 'bool', value: false }, // isclose
	      { type: 'uint256', value: '3' }, // sequence
	      { type: 'uint256', value: '1' }, // open VCs
	      { type: 'bytes32', value: vcRootHash }, // VC root hash
	      { type: 'address', value: partyA }, // partyA
	      { type: 'address', value: partyI }, // hub
	      { type: 'uint256', value: web3latest.utils.toWei('5') },
	      { type: 'uint256', value: web3latest.utils.toWei('15') },
	      { type: 'uint256', value: web3latest.utils.toWei('5') }, // token
	      { type: 'uint256', value: web3latest.utils.toWei('15') }  // token
	    )

	    let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI) 

	    sigA = await web3latest.eth.sign(payload, partyA)
	    sigI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass
  	    expect(channel[4]).to.be.below(sequence) //pass
  	    if(channel[10] == true) expect(channel[8].toString()).to.not.be.above(Date.now()) //fail

  	    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI).should.be.rejectedWith(SolRevert)
	  })
	  it("10. Success 2: new state submitted to updateLC", async () => {
	  	let lc_id = web3latest.utils.sha3('2222', {encoding: 'hex'})
	  	let sequence = '3';
	  	// let vcRootHash = web3latest.utils.soliditySha3({type: 'bytes32', value: '0x1'})
		let updateParams = [sequence, '1', web3latest.utils.toWei('5'), web3latest.utils.toWei('15'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]
    	let channel = await lc.getChannel(lc_id)
    	let totalEthDeposit = channel[3][0].add(channel[1][2]).add(channel[1][3]).toString();
    	let totalTokenDeposit = channel[3][1].add(channel[2][2]).add(channel[2][3]).toString();

  		payload = web3latest.utils.soliditySha3(
	      { type: 'bytes32', value: lc_id },
	      { type: 'bool', value: false }, // isclose
	      { type: 'uint256', value: '3' }, // sequence
	      { type: 'uint256', value: '1' }, // open VCs
	      { type: 'bytes32', value: vcRootHash }, // VC root hash
	      { type: 'address', value: partyA }, // partyA
	      { type: 'address', value: partyI }, // hub
	      { type: 'uint256', value: web3latest.utils.toWei('5') },
	      { type: 'uint256', value: web3latest.utils.toWei('15') },
	      { type: 'uint256', value: web3latest.utils.toWei('5') }, // token
	      { type: 'uint256', value: web3latest.utils.toWei('15') }  // token
	    ) 

    	let verificationA = await web3latest.eth.sign(payload, partyA)
    	let verificationI = await web3latest.eth.sign(payload, partyI)

	    sigA = await web3latest.eth.sign(payload, partyA)
	    sigI = await web3latest.eth.sign(payload, partyI)

  	    expect(channel[0][0]).to.be.equal(partyA) //pass
  	    expect(channel[9]).to.be.equal(true) //pass
  	    expect(totalEthDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(totalTokenDeposit).to.be.equal(web3latest.utils.toWei('20')) //pass
  	    expect(sigA).to.be.equal(verificationA) //pass
  	    expect(sigI).to.be.equal(verificationI) //pass
  	    expect(channel[4]).to.be.below(sequence) //pass
  	    if(channel[10] == true) expect(channel[8].toString()).to.not.be.above(Date.now()) //pass

  	    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI)

  	    sequence = '4';
  	    updateParams = [sequence, '1', web3latest.utils.toWei('10'), web3latest.utils.toWei('10'), web3latest.utils.toWei('5'), web3latest.utils.toWei('15')]

  	    payload = web3latest.utils.soliditySha3(
	      { type: 'bytes32', value: lc_id },
	      { type: 'bool', value: false }, // isclose
	      { type: 'uint256', value: '4' }, // sequence
	      { type: 'uint256', value: '1' }, // open VCs
	      { type: 'bytes32', value: vcRootHash }, // VC root hash
	      { type: 'address', value: partyA }, // partyA
	      { type: 'address', value: partyI }, // hub
	      { type: 'uint256', value: web3latest.utils.toWei('10') },
	      { type: 'uint256', value: web3latest.utils.toWei('10') },
	      { type: 'uint256', value: web3latest.utils.toWei('5') }, // token
	      { type: 'uint256', value: web3latest.utils.toWei('15') }  // token
	    ) 

	    sigA = await web3latest.eth.sign(payload, partyA)
	    sigI = await web3latest.eth.sign(payload, partyI)

	    await lc.updateLCstate(lc_id, updateParams, vcRootHash, sigA, sigI)

	    channel = await lc.getChannel(lc_id)
	    expect(channel[4].toString()).to.be.equal(sequence); //new state updated successfully!
	  })
	})

	//TODO test sequence and timeout (can only be done after first success case)
})
  // it("Alice signs initial lcS0 state", async () => {
  //   AI_lcS0_sigA = await web3latest.eth.sign(AI_lcS0, partyA)
  // })

  //       // address[2] partyAdresses; // 0: partyA 1: partyI
  //       // uint256[2] ethBalances; // 0: balanceA 1:balanceI
  //       // uint256[2] erc20Balances; // 0: balanceA 1:balanceI
  //       // uint256[2] deposited;
  //       // uint256 initialDeposit;
  //       // uint256 sequence;
  //       // uint256 confirmTime;
  //       // bytes32 VCrootHash;
  //       // uint256 LCopenTimeout;
  //       // uint256 updateLCtimeout; // when update LC times out
  //       // bool isOpen; // true when both parties have joined
  //       // bool isUpdateLCSettling;
  //       // uint256 numOpenVC;


  // it("Alice initiates ledger channel with lcS0", async () => {
  //   let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
  //   let approval = await token.approve(lc.address, web3latest.utils.toWei('10'))
  //   let res = await lc.createChannel(lc_id, partyI, '0', token.address, [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')], {from:partyA, value: web3latest.utils.toWei('10')})
  //   var gasUsed = res.receipt.gasUsed
  //   //console.log('createChan: '+ gasUsed)
  //   let openChans = await lc.numChannels()
  //   let chan = await lc.getChannel(lc_id)
  //   assert.equal(chan[0].toString(), [partyA,partyI]) //check partyAddresses
  //   assert.equal(chan[1].toString(), [web3latest.utils.toWei('10'), '0', '0', '0']) //check ethBalances
  //   assert.equal(chan[2].toString(), [web3latest.utils.toWei('10'), '0', '0', '0']) //check erc20Balances
  //   assert.equal(chan[3].toString(), [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]) //check initalDeposit
  //   assert.equal(chan[4].toString(), '0') //check sequence
  //   assert.equal(chan[5].toString(), '0') //check confirmTime
  //   assert.equal(chan[6], '0x0000000000000000000000000000000000000000000000000000000000000000') //check VCrootHash
  //   //check if chan[7] is equal to now + confirmtime
  //   assert.equal(chan[8].toString(), '0') //check updateLCTimeout
  //   assert.equal(chan[9], false) //check isOpen
  //   assert.equal(chan[10], false) //check isUpdateLCSettling
  //   assert.equal(chan[11], '0') //check numOpenVC
  // })

  // it("Hub signs initial lcS0 state", async () => {
  //   AI_lcS0_sigI = await web3latest.eth.sign(AI_lcS0, partyI)
  // })

