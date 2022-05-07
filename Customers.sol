// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;


/// @author GreatLearningGroup3
/// @title BookingContract holding customer booking details
contract Customers {
    address[] private customers;

    function addCustomer(address customerAddress) public {
        customers.push(customerAddress);
    }

    function getCustomersCount() public view returns(uint) {
        return customers.length;
    }

    function getCustomer(uint index) public view returns(address) {
        return customers[index];
    }
}