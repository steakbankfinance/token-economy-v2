pragma solidity 0.6.12;

import "./lib/BEP20.sol";
import "./interface/IMintBurnToken.sol";

contract aLBNB2BNBLP is BEP20, IMintBurnToken {

    constructor(address ownerAddr) public {
        super.initializeBEP20("Aged LBNB2BNB LP", "aLBNB2BNB", 18, 0, ownerAddr);
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (SteakBank).
    function mintTo(address _to, uint256 _amount) override external onlyOwner returns (bool) {
        _mint(_to, _amount);
        return true;
    }

    /**
   * @dev Burn `amount` tokens and decreasing the total supply.
   */
    function burn(uint256 amount) override external returns (bool) {
        _burn(_msgSender(), amount);
        return true;
    }
}