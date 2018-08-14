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

// is close flag, lc state sequence, number open vc, vc root hash, partyA/B, partyI, balA/B, balI

contract('LedgerChannel', function(accounts) {

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
    await lc.createChannel(lc_id_fail, partyI, '0', token.address, [0, 0], {from:partyA, value: 0})
  })

	describe('createChannel() has 6 possible cases:', () => {
	  it("1. Fail: Channel with that ID has already been created", async () => {
	  	let lc_id = web3latest.utils.sha3('fail', {encoding: 'hex'})
    	let sentBalance = [web3latest.utils.toWei('10'), web3latest.utils.toWei('10')]
    	let approval = await token.approve(lc.address, sentBalance[1])
    	let channel = await lc.getChannel(lc_id)
  	    expect(channel[0]).to.not.be.equal(null) //fail
  	    expect(partyI).to.not.be.equal('0x0000000000000000000000000000000000000000000000000000000000000000') //pass
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
    	let partyI_fail = ('0x0000000000000000000000000000000000000000000000000000000000000000')
  	    expect(channel[0]).to.not.be.equal(null) //pass
  	    expect(partyI_fail).to.be.equal('0x0000000000000000000000000000000000000000000000000000000000000000') //fail
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
  	    expect(channel[0]).to.not.be.equal(null) //pass
  	    expect(partyI).to.not.be.equal('0x0000000000000000000000000000000000000000000000000000000000000000') //pass
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
  	    expect(channel[0]).to.not.be.equal(null) //pass
  	    expect(partyI).to.not.be.equal('0x0000000000000000000000000000000000000000000000000000000000000000') //pass
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
  	    expect(channel[0]).to.not.be.equal(null) //pass
  	    expect(partyI).to.not.be.equal('0x0000000000000000000000000000000000000000000000000000000000000000') //pass
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
  	    expect(channel[0]).to.not.be.equal(null) //pass
  	    expect(partyI).to.not.be.equal('0x0000000000000000000000000000000000000000000000000000000000000000') //pass
  	    expect(sentBalance[0]).to.be.above(0) //pass
  	    expect(sentBalance[1]).to.be.above(0) //pass
  	    expect(sentBalance[0]).to.be.equal(web3latest.utils.toWei('10')) //pass
  	    expect(sentBalance[1]).to.be.equal(web3latest.utils.toWei('10')) //pass

  	    await lc.createChannel(lc_id, partyI, '0', token.address, sentBalance, {from:partyA, value: sentBalance[0]})
	  })
	  	
	})
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

