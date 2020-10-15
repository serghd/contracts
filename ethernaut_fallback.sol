pragma solidity ^0.4.18;

import 'github.com/aragon/zeppelin-solidity/blob/master/contracts/ownership/Ownable.sol';
import 'github.com/ConsenSysMesh/openzeppelin-solidity/blob/master/contracts/math/SafeMath.sol';

contract Fallback is Ownable {
  
  using SafeMath for uint256;
  mapping(address => uint) public contributions;

  function Fallback() public {
    contributions[msg.sender] = 1000 * (1 ether);
  }

  function contribute() public payable {
    require(msg.value < 0.001 ether);
    contributions[msg.sender] = contributions[msg.sender].add(msg.value);
    if(contributions[msg.sender] > contributions[owner]) {
      owner = msg.sender;
    }
  }

  function getContribution() public view returns (uint) {
    return contributions[msg.sender];
  }

  function withdraw() public onlyOwner {
    owner.transfer(this.balance);
  }

  function() payable public {
    require(msg.value > 0 && contributions[msg.sender] > 0);
    owner = msg.sender;
  }
}