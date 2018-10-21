# Payment Channels v0


SpankBank
The SpankBank is an algorithmic central bank that powers the two-token SpankChain economic system.

SPANK is a staking token which can be deposited with the SpankBank to earn newly minted BOOTY.

BOOTY is low-volatility fee credit good for $1 worth of SpankChain services.

SpankChain will collect fees for using the camsite, payment hub, advertising network, and other services in BOOTY. The fees are sent to the SpankBank where they are counted and burned.

The SpankBank has a 30 day billing period. At the beginning of each new period, if the total BOOTY supply is under the target supply (20x the total fees collected in the previous period), new BOOTY is minted to reach the target supply and distributed proportionally to all SPANK stakers.

In the future, we plan to add features to incentivize decentralized moderation of the SpankChain platform, rewarding BOOTY to those who help maintain its integrity. We also plan to add mechanisms that will incentivize maintaining the $1 BOOTY peg.



# virtual-channels
This repo contains contract code related to Connext and Spankchain's payment channel hub implementation. 

How to use these docs: 
- An in-depth walkthrough of the spec (with diagrams) can be found in the `PROTOCOL.md` file. If you don't understand how our protocol works, we reccommend starting there.
- Test cases are outlined in `./tests`
- This readme contains an explanation of all of the contract functions along with code/state samples.

### //TODO
