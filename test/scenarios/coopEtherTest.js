'use strict'

import MerkleTree from '../helpers/MerkleTree'
const Utils = require('../helpers/utils')
const Ledger = artifacts.require('./LedgerChannel.sol')
const EC = artifacts.require('./ECTools.sol')

const Web3latest = require('web3')
const web3latest = new Web3latest(new Web3latest.providers.HttpProvider("http://localhost:7545")) //ganache port


let lc

// state

let partyA
let partyB
let partyI

let vcRootHash

// is close flag, lc state sequence, number open vc, vc root hash, partyA/B, partyI, balA/B, balI

let AI_lcS0
let AI_lcS1
let AI_lcS2
let AI_lcS3

let BI_lcS0
let BI_lcS1
let BI_lcS2

let AB_vcS0
let AB_vcS1

let AB_vc2_S0
let AB_vc2_S1

// signature storage
let AI_lcS0_sigA
let AI_lcS1_sigA
let AI_lcS2_sigA
let AI_lcS3_sigA

let AI_lcS0_sigI
let AI_lcS1_sigI
let AI_lcS2_sigI
let AI_lcS3_sigI

let BI_lcS0_sigB
let BI_lcS1_sigB
let BI_lcS2_sigB

let BI_lcS0_sigI
let BI_lcS1_sigI
let BI_lcS2_sigI

let AB_vcS0_sigA
let AB_vcS1_sigA

let AB_vcS0_sigB
let AB_vcS1_sigB

contract('Test Cooperative Ether Payments', function(accounts) {

  before(async () => {
    partyA = accounts[0]
    partyB = accounts[1]
    partyI = accounts[2]

    let ec = await EC.new()
    Ledger.link('ECTools', ec.address)
    lc = await Ledger.new()
  })

  it("Create initial ledger channel state lcS0 for AI channel", async () => {
    AI_lcS0 = web3latest.utils.soliditySha3(
      { type: 'bool', value: false }, // isclose
      //{ type: 'bytes32', value: web3.sha3('lc2', {encoding: 'hex'}) }, // lcid
      { type: 'uint256', value: 0 }, // sequence
      { type: 'uint256', value: 0 }, // open VCs
      { type: 'string', value: '0x0' }, // VC root hash
      { type: 'address', value: partyA }, // partyA
      { type: 'address', value: partyI }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('10') },
      { type: 'uint256', value: web3latest.utils.toWei('20') }
    ) 
  })

  it("Alice signs initial lcS0 state", async () => {
    AI_lcS0_sigA = await web3latest.eth.sign(AI_lcS0, partyA)
  })


  it("Alice initiates ledger channel with lcS0", async () => {
    let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    await lc.createChannel(lc_id, partyI, '0', {from:partyA, value: web3latest.utils.toWei('10')})
    let openChans = await lc.numChannels()
    let chan = await lc.Channels(lc_id)
    assert.equal(openChans.toString(), '0')
    assert.equal(chan[0], partyA)
    assert.equal(chan[1], partyI)
    assert.equal(chan[2].toString(), web3latest.utils.toWei('10'))
    assert.equal(chan[3].toString(), '0')
    assert.equal(chan[4].toString(), '0')
    assert.equal(chan[5].toString(), '0')
    assert.equal(chan[6], '0x0000000000000000000000000000000000000000000000000000000000000000')
    assert.equal(chan[8].toString(), '0')
    assert.equal(chan[9], false)
    assert.equal(chan[10], false)
    assert.equal(chan[11].toString(), '0')
  })

  it("Hub signs initial lcS0 state", async () => {
    AI_lcS0_sigI = await web3latest.eth.sign(AI_lcS0, partyI)
  })

  it("Ingrid joins ledger channel", async () => {
    let lc_id = web3latest.utils.sha3('1111', {encoding: 'hex'})
    await lc.joinChannel(lc_id, {from: partyI, value: web3latest.utils.toWei('20')})
    let openChans = await lc.numChannels()
    let chan = await lc.Channels(lc_id)
    assert.equal(openChans.toString(), '1')
    assert.equal(chan[0], partyA)
    assert.equal(chan[1], partyI)
    assert.equal(chan[2].toString(), web3latest.utils.toWei('10'))
    assert.equal(chan[3].toString(), web3latest.utils.toWei('20'))
    assert.equal(chan[4].toString(), '0')
    assert.equal(chan[5].toString(), '0')
    assert.equal(chan[6], '0x0000000000000000000000000000000000000000000000000000000000000000')
    assert.equal(chan[8].toString(), '0')
    assert.equal(chan[9], true)
    assert.equal(chan[10], false)
    assert.equal(chan[11].toString(), '0')
  })

  // Bob creates ledger channel
  it("Create Bob's ledger channel state lcS0 for BI channel", async () => {
    BI_lcS0 = web3latest.utils.soliditySha3(
      { type: 'bool', value: false }, // isclose
      //{ type: 'bytes32', value: web3.sha3('lc4', {encoding: 'hex'}) }, // lcid
      { type: 'uint256', value: 0 }, // sequence
      { type: 'uint256', value: 0 }, // open VCs
      { type: 'string', value: '0x0' }, // VC root hash
      { type: 'address', value: partyB }, // partyA
      { type: 'address', value: partyI }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('10') },
      { type: 'uint256', value: web3latest.utils.toWei('20') }
    ) 
  })

  it("Bob signs initial lcS0 state", async () => {
    BI_lcS0_sigB = await web3latest.eth.sign(BI_lcS0, partyB)
  })


  it("Bob initiates ledger channel with lcS0", async () => {
    let lc_id = web3latest.utils.sha3('2222', {encoding: 'hex'})
    await lc.createChannel(lc_id, partyI, '0', {from:partyB, value: web3latest.utils.toWei('10')})
    let openChans = await lc.numChannels()
    let chan = await lc.Channels(lc_id)
    assert.equal(openChans.toString(), '1')
    assert.equal(chan[0], partyB)
    assert.equal(chan[1], partyI)
    assert.equal(chan[2].toString(), web3latest.utils.toWei('10'))
    assert.equal(chan[3].toString(), '0')
    assert.equal(chan[4].toString(), '0')
    assert.equal(chan[5].toString(), '0')
    assert.equal(chan[6], '0x0000000000000000000000000000000000000000000000000000000000000000')
    assert.equal(chan[8].toString(), '0')
    assert.equal(chan[9], false)
    assert.equal(chan[10], false)
    assert.equal(chan[11].toString(), '0')
  })

  it("Hub signs initial lcS0 state", async () => {
    BI_lcS0_sigI = await web3latest.eth.sign(BI_lcS0, partyI)
  })

  it("Ingrid joins ledger channel", async () => {
    let lc_id = web3latest.utils.sha3('2222', {encoding: 'hex'})
    await lc.joinChannel(lc_id, {from: partyI, value: web3latest.utils.toWei('20')})
    let openChans = await lc.numChannels()
    let chan = await lc.Channels(lc_id)
    assert.equal(openChans.toString(), '2')
    assert.equal(chan[0], partyB)
    assert.equal(chan[1], partyI)
    assert.equal(chan[2].toString(), web3latest.utils.toWei('10'))
    assert.equal(chan[3].toString(), web3latest.utils.toWei('20'))
    assert.equal(chan[4].toString(), '0')
    assert.equal(chan[5].toString(), '0')
    assert.equal(chan[6], '0x0000000000000000000000000000000000000000000000000000000000000000')
    assert.equal(chan[8].toString(), '0')
    assert.equal(chan[9], true)
    assert.equal(chan[10], false)
    assert.equal(chan[11].toString(), '0')
  })


  it("Alice creates vc state vcSO with Bob", async () => {
    AB_vcS0 = web3latest.utils.soliditySha3(
      { type: 'bytes32', value: web3latest.utils.sha3('1337', {encoding: 'hex'}) }, // vc id
      { type: 'uint256', value: 0 }, // sequence
      { type: 'address', value: partyB }, // partyA
      { type: 'address', value: partyB }, // hub,
      { type: 'uint256', value: web3latest.utils.toWei('12') }, // hub bond
      { type: 'uint256', value: web3latest.utils.toWei('5') },
      { type: 'uint256', value: web3latest.utils.toWei('7') }
    )

  })

  it("Alice and Bob sign vcSO", async () => {
    AB_vcS0_sigA = await web3latest.eth.sign(AB_vcS0, partyA)
    AB_vcS0_sigB = await web3latest.eth.sign(AB_vcS0, partyB)
  })

  it("Alice creates lc state lcS1 containing vcSO with Ingrid", async () => {
    var hash = web3latest.utils.sha3(AB_vcS0, {encoding: 'hex'})
    var buf = Utils.hexToBuffer(hash)
    var elems = []
    elems.push(buf)
    elems.push(Utils.hexToBuffer('0x0000000000000000000000000000000000000000000000000000000000000000'))
    var merkle = new MerkleTree(elems)

    vcRootHash = Utils.bufferToHex(merkle.getRoot())

    AI_lcS1 = web3latest.utils.soliditySha3(
      { type: 'bool', value: false }, // isclose
      //{ type: 'bytes32', value: web3.sha3('lc2', {encoding: 'hex'}) }, // lcid
      { type: 'uint256', value: 1 }, // sequence
      { type: 'uint256', value: 1 }, // open VCs
      { type: 'string', value: vcRootHash }, // VC root hash
      { type: 'address', value: partyA }, // partyA
      { type: 'address', value: partyI }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('5') },
      { type: 'uint256', value: web3latest.utils.toWei('13') }
    ) 
  })

  it("Alice signs lcS1 state and sends to Hub", async () => {
    AI_lcS1_sigA = await web3latest.eth.sign(AI_lcS1, partyA)
  })

  it("Bob creates lc state lcS1 containing vcSO with Ingrid", async () => {
    var hash = web3latest.utils.sha3(AB_vcS0, {encoding: 'hex'})
    var buf = Utils.hexToBuffer(hash)
    var elems = []
    elems.push(buf)
    elems.push(Utils.hexToBuffer('0x0000000000000000000000000000000000000000000000000000000000000000'))
    var merkle = new MerkleTree(elems)

    vcRootHash = Utils.bufferToHex(merkle.getRoot())

    BI_lcS1 = web3latest.utils.soliditySha3(
      { type: 'bool', value: false }, // isclose
      //{ type: 'bytes32', value: web3.sha3('lc4', {encoding: 'hex'}) }, // lcid
      { type: 'uint256', value: 1 }, // sequence
      { type: 'uint256', value: 1 }, // open VCs
      { type: 'string', value: vcRootHash }, // VC root hash
      { type: 'address', value: partyB }, // partyA
      { type: 'address', value: partyI }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('3') },
      { type: 'uint256', value: web3latest.utils.toWei('15') }
    ) 
  })

  it("Bob signs lcS1 state and sends to hub", async () => {
    BI_lcS1_sigB = await web3latest.eth.sign(BI_lcS1, partyB)
  })

  it("Hub signs both Alice and Bob's lcS1 state to open VC", async () => {
    AI_lcS1_sigI = await web3latest.eth.sign(AI_lcS1, partyI)
    BI_lcS1_sigI = await web3latest.eth.sign(BI_lcS1, partyI)
  })

  it("Alice generates virtual channel payment with Bob", async () => {
    AB_vcS1 = web3latest.utils.soliditySha3(
      { type: 'bytes32', value: web3latest.utils.sha3('1337', {encoding: 'hex'}) }, // vc id
      { type: 'uint256', value: 0 }, // sequence
      { type: 'address', value: partyB }, // partyA
      { type: 'address', value: partyB }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('12') }, // hub bond
      { type: 'uint256', value: web3latest.utils.toWei('5') },
      { type: 'uint256', value: web3latest.utils.toWei('7') }
    )

  })

  it("Alice and Bob sign vcS1", async () => {
    AB_vcS1_sigA = await web3latest.eth.sign(AB_vcS1, partyA)
    AB_vcS1_sigB = await web3latest.eth.sign(AB_vcS1, partyB)
  })

  it("Alice generates lc state to close vc", async () => {
    AI_lcS2 = web3latest.utils.soliditySha3(
      { type: 'bool', value: false }, // isclose
      //{ type: 'bytes32', value: web3.sha3('lc2', {encoding: 'hex'}) }, // lcid
      { type: 'uint256', value: 2 }, // sequence
      { type: 'uint256', value: 0 }, // open VCs
      { type: 'string', value: '0x0' }, // VC root hash
      { type: 'address', value: partyA }, // partyA
      { type: 'address', value: partyI }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('8') },
      { type: 'uint256', value: web3latest.utils.toWei('22') }
    ) 

  })

  it("Bob generates lc state to close vc", async () => {
    BI_lcS2 = web3latest.utils.soliditySha3(
      { type: 'bool', value: false }, // isclose
      //{ type: 'bytes32', value: web3.sha3('lc4', {encoding: 'hex'}) }, // lcid
      { type: 'uint256', value: 2 }, // sequence
      { type: 'uint256', value: 0 }, // open VCs
      { type: 'string', value: '0x0' }, // VC root hash
      { type: 'address', value: partyB }, // partyA
      { type: 'address', value: partyI }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('12') },
      { type: 'uint256', value: web3latest.utils.toWei('18') }
    )   
  })

  it("Alice signs lcS2 state and sends to Hub", async () => {
    AI_lcS2_sigA = await web3latest.eth.sign(AI_lcS2, partyA)
  })

  it("Bob signs lcS2 state and sends to hub", async () => {
    BI_lcS2_sigB = await web3latest.eth.sign(BI_lcS2, partyB)
  })

  it("Hub signs both Alice and Bob's lcS2 state to open VC", async () => {
    AI_lcS2_sigI = await web3latest.eth.sign(AI_lcS2, partyI)
    BI_lcS2_sigI = await web3latest.eth.sign(BI_lcS2, partyI)
  })

  it("Alice creates lc update to close lc", async () => {
    AI_lcS3 = web3latest.utils.soliditySha3(
      { type: 'bool', value: true }, // isclose
      //{ type: 'bytes32', value: web3.sha3('lc2', {encoding: 'hex'}) }, // lcid
      { type: 'uint256', value: '3' }, // sequence
      { type: 'uint256', value: '0' }, // open VCs
      { type: 'bytes32', value: '0x0' }, // VC root hash
      { type: 'address', value: partyA }, // partyA
      { type: 'address', value: partyI }, // hub
      { type: 'uint256', value: web3latest.utils.toWei('8') },
      { type: 'uint256', value: web3latest.utils.toWei('22') }
    ) 
  })

  it("Alice signs lcS3 state and sends to Hub", async () => {
    AI_lcS3_sigA = await web3latest.eth.sign(AI_lcS3, partyA)
  })

  it("Hub signs closing lcS3 state", async () => {
    AI_lcS3_sigI = await web3latest.eth.sign(AI_lcS3, partyI)
  })

  it("Close ledger channel", async () => {
    // var balA = await web3latest.eth.getBalance(partyA)
    // var balB = await web3latest.eth.getBalance(partyI)
    // console.log('Balance A before close: ' + balA)
    // console.log('Balance I before close: ' + balB)
    let receipt = await lc.consensusCloseChannel(web3latest.utils.sha3('1111', {encoding: 'hex'}), '3', web3latest.utils.toWei('8'), web3latest.utils.toWei('22'), AI_lcS3_sigA, AI_lcS3_sigI)
    var gasUsed = receipt.receipt.gasUsed
    //console.log('Gas Used: ' + gasUsed)
    // balA = await web3latest.eth.getBalance(partyA)
    // balB = await web3latest.eth.getBalance(partyI)
    // console.log('Balance A after close: ' + balA)
    // console.log('Balance I after close: ' + balB)
  })

})