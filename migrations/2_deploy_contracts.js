var EC = artifacts.require("./ECTools.sol");
var LC = artifacts.require("./LedgerChannel.sol");
const Vulnerable = artifacts.require("./VulnerableLedgerChannel.sol");
const HumanStandardToken = artifacts.require(
  "./lib/token/HumanStandardToken.sol"
);

module.exports = async function(deployer, network, accounts) {
  const authorizedTokens = [];
  deployer.deploy(EC);

  if (network !== "mainnet" && network !== "rinkeby") {
    deployer.link(EC, Vulnerable);
    deployer.deploy(Vulnerable);

    const supply = web3.utils.toBN(web3.utils.toWei("696969", "ether"));
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
          supply.div(web3.utils.toBN(accounts.length))
        );
      })
    );

    authorizedTokens.push(hst.address);
  }

  deployer.link(EC, LC);
  deployer.deploy(LC, authorizedTokens);
};
