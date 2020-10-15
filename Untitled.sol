// SPDX-License-Identifier: GPL-3.0

pragma solidity > 0.7.0;
//pragma solidity < 0.4.21;

contract simple_storage6
{
    uint m_stored_data;

    function set(uint x) public {
        m_stored_data = x;
    }
    
    function get() public view returns(uint) {
        return m_stored_data;
    }
    
}