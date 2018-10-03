const HumanStandardToken = artifacts.require(
  "./lib/token/HumanStandardToken.sol"
);

module.exports = async function(deployer, network, accounts) {
  if (network !== "mainnet") {
    const supply = 696969 * 1e18;
    await deployer.deploy(HumanStandardToken, supply, "Test Token", 18, "TST");
    const hst = await HumanStandardToken.deployed();
    await Promise.all(
      accounts.map(async (account, index) => {
        if (index === 0) {
          return;
        }
        return hst.transfer(account, supply / accounts.length);
      })
    );
  }
};
