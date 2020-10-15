pragma solidity ^0.4.18;

import 'github.com/aragon/zeppelin-solidity/blob/master/contracts/ownership/Ownable.sol';
import 'github.com/ConsenSysMesh/openzeppelin-solidity/blob/master/contracts/math/SafeMath.sol';

contract Fallout is Ownable {
  
  using SafeMath for uint256;
  mapping (address => uint) allocations;

  /* constructor */
  function Fal1out() public payable {
    owner = msg.sender;
    allocations[owner] = msg.value;
  }

  function allocate() public payable {
    allocations[msg.sender] = allocations[msg.sender].add(msg.value);
  }

  function sendAllocation(address allocator) public {
    require(allocations[allocator] > 0);
    allocator.transfer(allocations[allocator]);
  }

  function collectAllocations() public onlyOwner {
    msg.sender.transfer(this.balance);
  }

  function allocatorBalance(address allocator) public view returns (uint) {
    return allocations[allocator];
  }
}