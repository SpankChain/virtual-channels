require("babel-register");
require("babel-polyfill");
const HDWalletProvider = require("truffle-hdwallet-provider");

const mnemonic =
  "fetch local valve black attend double eye excite planet primary install allow";

var test = false;
var rinkeby = false;
var account;

if (test) {
  account = "0x01da6f5f5c89f3a83cc6bebb0eafc1f1e1c4a303";
  if (rinkeby) {
    account = "0x1e8524370b7caf8dc62e3effbca04ccc8e493ffe";
  }
}

module.exports = {
  networks: {
    coverage: {
      host: "localhost",
      network_id: "*",
      port: 9545, // <-- If you change this, also set the port option in .solcover.js.
      gas: 0xfffffffffff, // <-- Use this high gas value
      gasPrice: 0x01 // <-- Use this low gas price
    },
    rinkeby: {
      provider: () => {
        return new HDWalletProvider(
          mnemonic,
          "https://rinkeby.infura.io/nsUEX1RYRhRDJoN89CrK"
        );
      },
      network_id: 4,
      gas: 4612388 // Gas limit used for deploys
    },
    ropsten: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "3",
      from: account,
      gas: 4700000
    },
    mainnet: {
      host: "127.0.0.1",
      port: 8545,
      network_id: "1",
      gas: 4700000
    },
    ganache: {
      host: "127.0.0.1",
      port: 7545,
      network_id: "4447",
      gas: 4700000
    },
    truffledev: {
      host: "127.0.0.1",
      port: 9545,
      network_id: "4447",
      gas: 4700000
    },
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*"
    }
  },
  solc: {
    optimizer: {
      enabled: true,
      runs: 500
    }
  },
  mocha: {
    enableTimeouts: false
  }
};

/*
Available Accounts
==================
(0) 0x8ec75ef3adf6c953775d0738e0e7bd60e647e5ef
(1) 0x9a8d670c323e894dda9a045372a75d607a47cb9e
(2) 0xa76f1305f64daf03983781f248f09c719cda30bf
(3) 0xe4cbacbf76d1120dfe78b926fbcfa6e5bc9917a1
(4) 0x6fab42068c1eedbcbd3948b1cddef1eef1249825
(5) 0xacc361b5b7f3bbda23ea044b3142dcc6b76ec708
(6) 0xecd03eb3951705da1b434fcf0da914268b687e3d
(7) 0x1754e4007922865fb09349897524ee2dd63ac184
(8) 0x6fec9dda7a05f9e45601d77a0f1e733c821a02d8
(9) 0x778e55d7517b5278399d41f4a89f78418154297b
Private Keys
==================
(0) f0f18fd1df636821d2d6a04b4d4f4c76fc33eb66c253ae1e4028bf33c48622bc
(1) 1ee927be212d11c388af6f0a11e66ab2fb054193ed50b6c1b457e2b80ab45b67
(2) cf218d8691b038086126d98f91297e608f9e2aa1fdd5ba2cfce41eab2887ed76
(3) 33e495d9693e612f87b80e2d202e910e36a5e416a0368d93b9e756a2b5668836
(4) 53efc621d7b1b9386b7ca95067f3082de9d0e1024600363ae38465a2ce6af4e3
(5) 2b1f640a724e13ee80041636ff6acf4f980b63cc609bc5d9d94c80f1d45bab5c
(6) dbd5dd1198c75025a66982abcc8892f3abfb31db35e677005e93d383e615c2cf
(7) 874bc239731735873dd55edebc6e14764ce1e08ed45e1f52c80d53721c961152
(8) 48ab1dc0428e4cd7ad5a63987d3da4561d7f0599462ecddba82e382a60b249aa
(9) eef8d4482cf4bb3b6f70f7b91f19545a73f6e3bb27d54f6a78ad49a57ed70483
HD Wallet
==================
Mnemonic:      `fetch local valve black attend double eye excite planet primary install allow`
Base HD Path:  m/44'/60'/0'/0/{account_index}
*/
