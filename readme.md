TokenSwap
===============================
The intent of this contract is to facilitate the automated process of a variable rate claimable token swap.

What is a "variable rate claimable token swap"?  The variable rate simply refers to the fact that the rate at which tokens are swapped are converted is set to a dynamic configurable amount. The claimable part means that the swapper is able to make a claim against their allocated balance to upstream supported contracts.

There are 12 internal state variables, i'll explain each one below:

* **creator**
This is the address of the person who created the contract instance.  They have the ability to prematurely end the token swap and also initiate final token transfer once token swap is successful

* **beneficiary**
The address which will receive the raised ETH. It can only be set at the time of contract creation and cannot be changed.

* **upstream_claim_address**
The upstream contract that can process participant claims, must contain the Claim() function as shown in the interface contract.

* **amountRaisedInWei**
Internal accounting variable that keeps track of how much has been raised.

* **rewardTokensIssued**
Internal accounting variable that keeps track of how many reward tokens been issued.

* **tokenSwapClosed**
Flag to track status of tokenswap.

* **fundingGoalInWei**
How much ETH constitutes a successful token swap

* **fundingCapInWei**
How much ETH should we stop the token swap

* **standardRewardRate**
The pre-calculated standard amount reward tokens issued for every 1 ETH. Its basically just funding Cap / RewardTokens to be issued

* **startDate**
Set this to when you want the token swap to begin

* **endDate**
Automatically set to whatever enddate you want

* **trancheSize**
Pre-calculated amount of tokens to issue before checking for the next variable price adjustment. 


* **particpants**
Mapping of particpants addresses and these details
	* **weiReceived** (track how much particpant has swapped)
	* **claimTokens** (how much the user can claim)
	* **claimed** (has user claimed or not)

## TokenSwap statuses
### In progress
Users can call Swap() to execute their swaps.  Contract creator can also issue a CloseTokenSwap() at anytime to cancel the process.

### Cancelled
Users can call WithdrawWei() to withdraw all ETH they have sent if the token swap is cancelled or does not meet target

### Target not met
As above, users can call WithdrawWei() to get their ETH back

### Success
Users can call Claim() to make their claim to the upstream contract if the token swap is successful

Also on success the token swap creator can issue a call to TransitionAllTokens() to send all Ether raised to the beneficiary address.