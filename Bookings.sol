// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import "./BookingContract.sol";

/// @author GreatLearningGroup3
/// @title BookingContract holding customer booking details
contract Bookings {
    mapping(address => BookingContract) private bookings;
    
    function addBooking(address addr, BookingContract booking) public {
        bookings[addr] = booking;
    }

    function getBooking(address addr) public view returns(BookingContract) {
        return bookings[addr];
    }
}

 