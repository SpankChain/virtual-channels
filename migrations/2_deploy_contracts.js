var EC = artifacts.require("./ECTools.sol");
var LC = artifacts.require("./LedgerChannel.sol");
const Vulnerable = artifacts.require("./VulnerableLedgerChannel.sol");

module.exports = async function(deployer, network) {
  deployer.deploy(EC);
  deployer.link(EC, LC);
  deployer.deploy(LC);

  if (network !== "mainnet") {
    deployer.link(EC, Vulnerable);
    deployer.deploy(Vulnerable);
  }
};
