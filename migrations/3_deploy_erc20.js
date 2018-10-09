const HumanStandardToken = artifacts.require(
  "./lib/token/HumanStandardToken.sol"
);

const Web3 = require("web3");

module.exports = async function(deployer, network, accounts) {
  if (network !== "mainnet") {
    const supply = Web3.utils.toBN(Web3.utils.toWei("696969", "ether"));
    await deployer.deploy(
      HumanStandardToken,
      supply,
      "Test Token",
      "18",
      "TST"
    );
    const hst = await HumanStandardToken.deployed();
    await Promise.all(
      accounts.map(async (account, index) => {
        if (index === 0) {
          return;
        }
        return hst.transfer(
          account,
          supply.div(Web3.utils.toBN(accounts.length))
        );
      })
    );
  }
};
