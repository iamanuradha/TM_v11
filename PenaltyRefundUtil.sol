// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import "./Flight.sol";

contract PenaltyRefundUtil {
    mapping(uint => uint) private cancelpenaltyMap;
    mapping(uint => uint) private delaypenaltyMap;

    constructor() {
        //Penalties for cancelling the ticket at different times before the scheduled flight time
        // Penalty for Cancelling between 2 to 12 hours is 80% of ticket price, between 12 to 24 hours is 60%, between 24 to 48 hours is 40%
        cancelpenaltyMap[2] = 80;
        cancelpenaltyMap[12] = 60;
        cancelpenaltyMap[24] = 40;

        //Different Penalties for different ranges of flight delay
        // Penalty for delaying the flight by 2 to 4 hours is 20% of ticket price, by 4 to 6 hours is 40%, by 6 to 8 hours is 60%
        delaypenaltyMap[2] = 20;
        delaypenaltyMap[4] = 40;
        delaypenaltyMap[6] = 60;
    }

    function computePenaltyRefundAmt(uint flightTime, uint ethAmount) public view returns(uint, uint) {
        uint penalty = 0; uint refundAmt = 0;
          if((block.timestamp < flightTime - 2 hours) && (block.timestamp > flightTime - 12 hours)){
            
            penalty = (cancelpenaltyMap[2] * ethAmount) / 100;
            refundAmt = ethAmount - penalty;
        
        //Customer triggers cancellation before 12 to 24 hours of flight departure
        } else if((block.timestamp < flightTime - 12 hours) && (block.timestamp > flightTime - 24 hours)){
            
            penalty = (cancelpenaltyMap[12] * ethAmount) / 100;
            refundAmt = ethAmount - penalty;
        
        //Customer triggers cancellation before 24 to 48 hours of flight departure
        } else if((block.timestamp < flightTime - 24 hours) && (block.timestamp > flightTime - 48 hours)){
            
            penalty = (cancelpenaltyMap[24] * ethAmount) / 100;
            refundAmt = ethAmount - penalty;

        //Customer triggers cancellation before 2 days of flight departure
        } else {
            //full refund
            refundAmt = ethAmount;
        }
        return (penalty, refundAmt);
    }

    function computePenaltyRefundAmtForClaimRefund(Flight.FlightState state, 
        uint flightTime, uint departureTime, uint ethAmount, bool flightStateUpdated) 
        public view returns(uint, uint) {

        uint penalty = 0; uint refundAmt = 0;

        if(state == Flight.FlightState.CANCELLED || !flightStateUpdated){
           //full refund to the customer
           refundAmt = ethAmount;
        } else if(state == Flight.FlightState.DELAYED){
           //Calculate the refund based on delay time and refund to customer
           //Flight is delayed by 2 to 4 hours
            if((departureTime - flightTime > 2 hours) && (departureTime - flightTime <= 4 hours)){
                penalty = (delaypenaltyMap[2] * ethAmount) / 100;
                refundAmt = ethAmount - penalty;
            //Flight is delayed by 4 to 6 hours
            } else if((departureTime - flightTime > 4 hours) && (departureTime - flightTime <= 6 hours)){
                penalty = (delaypenaltyMap[4] * ethAmount) / 100;
                refundAmt = ethAmount - penalty;
            //Flight is delayed by 6 to 8 hours
            } else if((departureTime - flightTime > 6 hours) && (departureTime - flightTime <= 8 hours)){
                penalty = (delaypenaltyMap[6] * ethAmount) / 100;
                refundAmt = ethAmount - penalty;
            //Flight is delayed by more than 8 hours
            } else if (departureTime - flightTime > 8 hours){
                //Full refund
                refundAmt = ethAmount;
            }
        }
        return (penalty, refundAmt);
    }

}