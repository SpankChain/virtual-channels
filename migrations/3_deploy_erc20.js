const HumanStandardToken = artifacts.require(
  "./lib/token/HumanStandardToken.sol"
);

module.exports = async function(deployer, network, accounts) {
  const supply = 10000000;
  if (network !== "mainnet") {
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
