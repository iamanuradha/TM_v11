// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import "./Flight.sol";
import "./BookingContract.sol";
import "./BookingSystem.sol";
import "./Customers.sol";
import "./Bookings.sol";
import "./PenaltyRefundUtil.sol";


/**
 * @title BookingServer
 * @dev This contract serves as an abtraction for two entities namely airlines and its passengers 
 * for performing various flight and its booking activities.
 *
 * For an Airline, flight activities comprises of updating flight status, view flight booking list
 * For a Passenger, flight activities comprises of booking flight ticket, cancel booking
 *
 * NOTE: This contract assumes that ETH to be used for tranfer of funds between entities. Also
 * exact value of the ticket in ethers is expected.
 */

contract BookingServer is BookingSystem{

    Flight private flight;
    address payable private airlines;
    bool private flightStateUpdated = false;

    event cancelTransferred(address from, address to, uint amountInEther, uint256 currentTime, string transferReason);
    event BookingComplete(address customer, string flightId);
    event FlightCancelled(address airlines, string flightId);

    Bookings private bookings;
    Customers private customers;
    PenaltyRefundUtil private penaltyrefundUtil;

	modifier onlyCustomer() {
        require(msg.sender != airlines, "Only customer can do this action");
        _;
    }

    modifier onlyAirlines() {
        require(msg.sender == airlines, "Only airlines can do this action");
        _;
    }

    modifier onlyValidAddress(address addr) {
        require(addr != address(0));
        _;
    }

    modifier onlyValidFlightNumberAndState(string memory _flightNumber) {
        Flight.FlightData memory flightData = flight.getFlightData(_flightNumber);
        require(bytes(flightData.flightNumber).length > 0, "Invalid flight number");
        require(flightData.state != Flight.FlightState.CANCELLED 
        && flightData.state != Flight.FlightState.DEPARTED, "Flight is Cancelled");
        _;
    }

    modifier validBookingAndState(address _customer, BookingContract.BookingState _state){
        BookingContract.BookingData memory bookingData = bookings.getBooking(_customer).getBookingData();
        require(bytes(bookingData.flightNumber).length > 0, "Booking not found for this customer");
        require(bookingData.state == _state, "Booking is not in a valid state");
        _;
    }

    modifier onlyExactTicketAmount(string memory _flightNumber) {
        Flight.FlightData memory flightData = flight.getFlightData(_flightNumber);
        require(msg.value == flightData.ethAmount *10**18, "Exact booking ethers needed");
        _;
    }

	modifier onlySufficientFunds() {
		require(msg.sender.balance > msg.value, "Insufficient funds to book the ticket");
		_;
	}

	constructor() {
        flight = new Flight();
        flight.populateFlights();
        airlines = payable(msg.sender);
        customers = new Customers();
        bookings = new Bookings();
        penaltyrefundUtil = new PenaltyRefundUtil();
    }

    function initiateBooking(string memory _flightNumber, Flight.SeatCategory _seatCategory)
        public
        payable
        onlyCustomer
        onlySufficientFunds
		onlyValidFlightNumberAndState(_flightNumber) returns(string memory){

        BookingContract booking = new BookingContract(msg.sender, airlines, msg.value);
        bookings.addBooking(msg.sender, booking);
        customers.addCustomer(msg.sender);

        Flight.FlightData memory flightData = flight.getFlightData(_flightNumber);
        payable(airlines).transfer(flightData.ethAmount*10**18);
        string memory bookingComment = booking.bookTicket(msg.sender, _seatCategory, _flightNumber);
        return bookingComment;
    }

	function getBookingData(address customer)
        public view
        onlyAirlines returns (BookingContract.BookingData memory) {
        return bookings.getBooking(customer).getBookingData();
    }

    function cancelBooking()
        public
        onlyCustomer
        validBookingAndState(msg.sender, BookingContract.BookingState.CONFIRMED){
        uint penalty;
        uint refundAmt;

         //Retrieve the booking based on either customer address
        BookingContract.BookingData memory bookingData = bookings.getBooking(msg.sender).getBookingData();
        Flight.FlightData memory flightData = flight.getFlightData(bookingData.flightNumber);

        require(flightData.state == Flight.FlightState.ON_TIME || flightData.state == Flight.FlightState.DELAYED);

        //Requires current time is 2 hours before the flight time
        require(block.timestamp < flightData.flightTime - 2 hours, "There is less than 2 hours for flight departure. Hence can't cancel the ticket");

        (penalty, refundAmt) = penaltyrefundUtil.computePenaltyRefundAmt(flightData.flightTime, flightData.ethAmount);

        payable(airlines).transfer(penalty*10**18);
        payable(msg.sender).transfer(refundAmt*10**18);
        bookings.getBooking(msg.sender).cancelBooking(penalty, refundAmt);
    }

    function claimRefund()
        public
        onlyCustomer
        validBookingAndState(msg.sender, BookingContract.BookingState.CONFIRMED){
        uint penalty;
        uint refundAmt;

        BookingContract.BookingData memory bookingData = bookings.getBooking(msg.sender).getBookingData();
        Flight.FlightData memory flightData = flight.getFlightData(bookingData.flightNumber);
        (penalty, refundAmt) = penaltyrefundUtil.computePenaltyRefundAmtForClaimRefund(flightData.state, 
        flightData.flightTime, flightData.departureTime, flightData.ethAmount, flightStateUpdated);
        bookings.getBooking(msg.sender).claimRefund(penalty, refundAmt);
        payable(airlines).transfer(penalty*10**18);
        payable(msg.sender).transfer(refundAmt*10**18);
    }

   function cancelFlight(string memory _flightNumber)
        public
		onlyAirlines
        onlyValidFlightNumberAndState(_flightNumber) {

        require(block.timestamp <= (flight.getFlightData(_flightNumber).flightTime - 24 hours), "Flight can only be cancelled, 24 hrours before flight start time");

        flight.setFlightState(_flightNumber, Flight.FlightState.CANCELLED, 0);
        emit FlightCancelled(msg.sender, _flightNumber);
        Flight.FlightData memory flightData = flight.getFlightData(_flightNumber);
        _processAllCustomers(Flight.FlightState.CANCELLED, flightData.ethAmount);
    }

    function updateFlightStatus(string memory _flightNumber, Flight.FlightState _state, uint _delayInHours)
		public
		onlyAirlines{
            Flight.FlightData memory flightData = flight.getFlightData(_flightNumber);
            require(bytes(flightData.flightNumber).length > 0, "Invalid flight number");
            require(_state != Flight.FlightState.CANCELLED, "Use cancelFlight api");
            require (block.timestamp > flightData.flightTime - 24 hours, "Updates permitted 24 hrs before flight departure time");
            if(_state == Flight.FlightState.DELAYED){
                require(_delayInHours > 0, "Update the delayed hours when the flight status is delayed");
            }
            flight.setFlightState(_flightNumber, _state, _delayInHours);
            flightStateUpdated = true;
            //on status set to departed passback customer locked money with contract
            if(_state == Flight.FlightState.DEPARTED) {
                _processAllCustomers(Flight.FlightState.DEPARTED, flightData.ethAmount);
            }
    }

    //Get Flight Information
    function getFlightData(string memory _flightNumber) public view returns (Flight.FlightData memory){
        Flight.FlightData memory flightData = flight.getFlightData(_flightNumber);
        require(bytes(flightData.flightNumber).length > 0, "Invalid flight number");
        return flight.getFlightData(_flightNumber);
    }

    function _processAllCustomers(Flight.FlightState state, uint ethAmount) private {
        for(uint i = 0; i < customers.getCustomersCount(); i++) {
            address customerAddr = customers.getCustomer(i);
            BookingContract.BookingData memory bookingData = bookings.getBooking(customerAddr).getBookingData();
            if (state == Flight.FlightState.CANCELLED) {
                if (bookingData.state == BookingContract.BookingState.CONFIRMED) {
                    payable(customerAddr).transfer(ethAmount*10**18);
                    bookings.getBooking(customerAddr).flightCancelled();
                } else if(bookingData.state == BookingContract.BookingState.CANCELLED) {
                    uint refund = bookingData.cancelPenalty;
                    payable(customerAddr).transfer(refund*10**18);
                    bookings.getBooking(customerAddr).flightCancelled();
                }
            } else if (state == Flight.FlightState.DEPARTED) {
                if (bookingData.state == BookingContract.BookingState.CONFIRMED) {
                    uint lockedAmt = bookings.getBooking(customerAddr).getValue() - ethAmount*10**18;
                    payable(customerAddr).transfer(lockedAmt);
                }
            }
        }
    }
}