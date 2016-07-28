contract TokenSwapInterface {
    function Claim(address, uint);
}

contract TokenSwap {
	address creator;

    address beneficiary;
    address upstreamClaimAddress;

    uint amountRaisedWei;
    uint rewardTokensIssued;
    bool tokenswapClosed;

    uint fundingGoalInWei; 
    uint fundingCapInWei;
    uint standardRewardRate;

    uint startDate;
    uint endDate;

    uint trancheSize;

    mapping(address => TokenSwapStruct) participants;

    /* data structure to hold information about donators */
    struct TokenSwapStruct {
        uint weiRecieved;
        uint claimTokens;
        bool claimed;
    }

    function TokenSwap(address _beneficiary, uint _startDate, uint goalInEther, uint rewardPointsToIssue) {
        beneficiary = _beneficiary;
        creator = msg.sender;
        fundingGoalInWei = goalInEther * 1 ether;
        fundingCapInWei = fundingGoalInWei * 2;
        standardRewardRate = rewardPointsToIssue / (goalInEther * 2);

        if (_startDate == 0)
            startDate = now;
        else
            startDate = _startDate;

        endDate = startDate + 14 * 1 days;

        trancheSize = rewardPointsToIssue / 14;
    }

    //we dont know the address of the token at crowdfund time
    function SetRexTokenAddress(address _upstream_claim_address) {
        if (msg.sender == creator)
            upstreamClaimAddress = _upstream_claim_address;
    }

    function getRewardRate(uint tranche) constant returns (uint) {

        //50% bonus
        if (tranche == 1)
            return standardRewardRate * 15 / 10;

        //20% bonus
        if (tranche == 2)
            return standardRewardRate * 12 / 10;

        //5% deduction
        if (tranche > 10)
            return (standardRewardRate * 100) / 105;

        //standard Rate
        return standardRewardRate;

    }

    function getTrancheStats(uint rewardPointsSetAside) constant returns (uint tranche, uint remaining) {
        tranche = ((rewardTokensIssued + rewardPointsSetAside) / trancheSize) + 1;
        remaining = (tranche * trancheSize) - (rewardTokensIssued + rewardPointsSetAside); 
        return (tranche, remaining);
    }

    function Swap() {

        //no funding until it starts
        if (now < startDate) {
            msg.sender.send(msg.value);
            return;
        }

        //if crowdfund is over, return funds
        if (tokenswapClosed) {
            msg.sender.send(msg.value);
            return;
        }

        //if crowdfund is past duration, return funds 
        if (now > endDate) {
            msg.sender.send(msg.value);
            return;
        }

        uint adjAmount;

        //if funder sent more than the remaining amount then send them a refund of the difference
        if (msg.value > fundingCapInWei - amountRaisedWei) {
            adjAmount = fundingCapInWei - amountRaisedWei;
            if (!msg.sender.send(msg.value - adjAmount))
                throw;
        }
        else
            adjAmount = msg.value;

        //calculate bought tokens

        uint tranche;
        uint trancheRemaining;
        uint rate;
        uint claimTokensBought;
        uint fundsRemaining = adjAmount;

        while (fundsRemaining > 0) {
            (tranche, trancheRemaining) = getTrancheStats(claimTokensBought);
            rate = getRewardRate(tranche);
            if ((fundsRemaining * rate) / 1 ether > trancheRemaining) {
                claimTokensBought += trancheRemaining;
                fundsRemaining -= ((trancheRemaining * 1000) / rate) * 1 finney;   
            }
            else {
                claimTokensBought += (fundsRemaining * rate) / 1 ether;
                break;
            }
        }

        participants[msg.sender].weiRecieved += adjAmount;
        participants[msg.sender].claimTokens += claimTokensBought;
        amountRaisedWei += adjAmount;
        rewardTokensIssued += claimTokensBought;

        //if we reached our target then close the sale
        if (amountRaisedWei >= fundingCapInWei)
            tokenswapClosed = true;
    }   

    //this function is only allowed to be called from the token contract
    function Claim() {

        if (!tokenswapClosed) 
            return;

        //if we didn't meet the target then stop
        if (amountRaisedWei < fundingGoalInWei) 
            return;

        //check if claimant has not already claimed 
        if (participants[msg.sender].claimed)
            return;

        participants[msg.sender].claimed = true;
        TokenSwapInterface(upstreamClaimAddress).Claim(msg.sender, participants[msg.sender].claimTokens);
    }

    function rewardPointsBalance(address funder) returns (uint) {
        if (participants[funder].claimed)
            return 0;
        else
            return participants[funder].claimTokens;
    }

    function WithdrawWei() {
        //if crowdsale not closed then stop
        if (!tokenswapClosed) return;

        //if crowdsale was a success then stop
        if (amountRaisedWei >= fundingGoalInWei) return;

        //only allow them to claim once
        if (!participants[msg.sender].claimed) {

            //set funder amount to zero 
            participants[msg.sender].claimed = true;
            //if send fails, revert tx with a throw
            if (!msg.sender.send(participants[msg.sender].weiRecieved))
                throw;

        }
    }

    function TransitionAllTokens() {
        //only creator can execute
        if (msg.sender != creator)
            return;

        //dont allow if not closed
        if (!tokenswapClosed)
            return;

        //dont allow final transition unless success
        if (amountRaisedWei < fundingGoalInWei) return;

        beneficiary.send(this.balance);
    }

    function CloseTokenSwap() {
        //only creator can execute
        if (msg.sender != creator)
            return;

        tokenswapClosed = true;
    }

    /* Reject any Eth sent here with no function */
    function () {
        throw;
    }
}
