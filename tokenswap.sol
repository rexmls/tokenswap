contract TokenClaimInterface {
    function addNewTokens(address, uint) returns (bool);
}

contract CoordinatorInterface {
    function setContractAddress(bytes32, address);
    function getAddress(bytes32) returns (address);
} 

contract TokenSwap {
	address creator;

    address coordinator;

    uint amountRaisedWei;
    uint rewardTokensIssued;
    bool tokenswapClosed;
    bool claimsActive;

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

    function TokenSwap(address _coordinator, uint _startDate, uint goalInEther, uint rewardPointsToIssue) {
        
        //register with coordinator if we get an address
        if (_coordinator != 0x0) {
            CoordinatorInterface(_coordinator).setContractAddress("tokenswap", this);
            coordinator = _coordinator;
        }

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

    function setCoordinator(address _newCoordinator) {
 
        //only allow the creator
        if (msg.sender != creator)
            return;

        //make sure we have a valid address
        if (_newCoordinator == 0x0)
            return;
        
        //only allow it to be set once
        //this is very important for continuity, we cant have the tokenswap contract change its upstream coordinator and therefore its sibling contracts without users being notified
        if (coordinator != 0x0)
            return;

        CoordinatorInterface(_newCoordinator).setContractAddress("tokenswap", this);
        coordinator = _newCoordinator;
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

    function activateClaims() {
        if (msg.sender == creator)
            claimsActive = true;
    }

    function getTrancheStats(uint rewardPointsSetAside) constant returns (uint tranche, uint remaining) {
        tranche = ((rewardTokensIssued + rewardPointsSetAside) / trancheSize) + 1;
        remaining = (tranche * trancheSize) - (rewardTokensIssued + rewardPointsSetAside); 
        return (tranche, remaining);
    }

    function Swap() {

        bool result;

        //no funding until it starts
        if (now < startDate) {
            result = msg.sender.send(msg.value);
            return;
        }

        //if crowdfund is over, return funds
        if (tokenswapClosed) {
            result = msg.sender.send(msg.value);
            return;
        }

        //if crowdfund is past duration, return funds 
        if (now > endDate) {
            result = msg.sender.send(msg.value);
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

    // call this to claim tokens
    function Claim() {

        if (!tokenswapClosed) 
            return;

        //if we didn't meet the target then stop
        if (amountRaisedWei < fundingGoalInWei) 
            return;

        //check if claimant has not already claimed 
        if (participants[msg.sender].claimed)
            return;

        if (!claimsActive)
            return;

        participants[msg.sender].claimed = true;
        address tokenAddress = CoordinatorInterface(coordinator).getAddress("token");
        TokenClaimInterface(tokenAddress).addNewTokens(msg.sender, participants[msg.sender].claimTokens * 10000);
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

            //set claimed flag
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

        address beneficiaryAddress = CoordinatorInterface(coordinator).getAddress("dao");
        bool result = beneficiaryAddress.send(this.balance);
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

    function returnEth(address _to) {
        if (msg.sender == creator && now > endDate + 4 weeks)
            bool result = _to.send(this.balance);
    }
}
