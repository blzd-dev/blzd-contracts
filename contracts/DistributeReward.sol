pragma solidity 0.6.12;

import "./libs/IBEP20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract DistributeReward {
    using SafeMath for uint256;
    
    address public constant marketing = 0x10346e91429E0676dCC13d67C0e3F6E9A028207F;
    address public constant owner = 0xCe059E8af96a654d4afe630Fa325FBF70043Ab11;
    address public constant mods = 0xb1155a0f8C7F34632dA1D516AF6591dE75c0eCFd;
    address public constant dev = 0xbA828b976bFf1467E23Cb59bf2FFF6B81d8829C0;
    IBEP20 public blzd;

    constructor(address _blzd) public {
        blzd = IBEP20(_blzd);
    }

    function distribute() external {
        uint256 balance = IBEP20(blzd).balanceOf(address(this));
        uint256 devReward = balance.mul(400).div(888);
        uint256 marKetingReward = balance.mul(200).div(888);
        uint256 modsReward =  balance.mul(100).div(888);
        uint256 ownerReward =  ((balance.sub(marKetingReward)).sub(devReward)).sub(modsReward);
        blzd.transfer(marketing, marKetingReward);
        blzd.transfer(owner, ownerReward);
        blzd.transfer(mods, modsReward);
        blzd.transfer(dev, devReward);
    }   
}
