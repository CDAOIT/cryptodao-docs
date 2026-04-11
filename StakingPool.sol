// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IsOHM {
    function rebase( uint256 ohmProfit_, uint epoch_) external returns (uint256);

    function circulatingSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function gonsForBalance( uint amount ) external view returns ( uint );

    function balanceForGons( uint gons ) external view returns ( uint );
    
    function index() external view returns ( uint );
}

interface IRewardManager {
    function distribute() external returns ( bool );
}

contract StakingPool is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct Epoch {
        uint length;
        uint number;
        uint endBlock;
        uint distribute;
    }
    Epoch public epoch;

    mapping ( address => bool ) public stakeContracts;

    address public rewardManager;
    address public OHM;
    address public sOHM;

    event Staked(address indexed _staker, uint256 _amount);

    error ErrorNotAuthorized();
    error ErrorAmountExceedsBalance();
    error ErrorInvalidAddress();

    function initialize(address _OHM, address _sOHM, uint256 _epochLength, uint256 _firstEpochNumber, uint256  _firstEpochBlock) external initializer {
        require( _OHM != address(0));
        OHM = _OHM;
        require( _sOHM != address(0));
        sOHM = _sOHM;

        __Ownable_init(msg.sender);
        
        epoch = Epoch({
            length: _epochLength,
            number: _firstEpochNumber,
            endBlock: _firstEpochBlock,
            distribute: 0
        });
    }
 
    /**
        @notice stake OHM to enter warmup
        @param _amount uint256
        @param _recipient address
        @return bool
     */
    function stake (uint256 _amount, address _recipient) external returns (bool) {
        if (!stakeContracts[msg.sender]) {
            revert ErrorNotAuthorized();
        }

        _rebase();
        _stake(_amount, _recipient);

        return true;
    }

    function bondStake (uint256 _amount, address _recipient) external returns (bool) {
        if (!stakeContracts[msg.sender]) {
            revert ErrorNotAuthorized();
        }

        _rebase();
        _stake(_amount, _recipient);

        return true;
    }


    function presaleStake (uint256 _amount, address _recipient) external returns (bool) {
        if (!stakeContracts[msg.sender]) {
            revert ErrorNotAuthorized();
        }

        _stake(_amount, _recipient);
        return true;
    }


    function _stake(uint256 _amount, address _recipient) private {
        uint256 sOHMBalance = IsOHM( sOHM ).balanceOf( address(this) );
        if (sOHMBalance < _amount) {
            revert ErrorAmountExceedsBalance();
        }
        
        IERC20( OHM ).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20( sOHM ).safeTransfer(msg.sender, _amount);

        emit Staked(_recipient, _amount);
    }


    /**
        @notice redeem sOHM for OHM
        @param _amount uint
        @param _trigger bool
     */
    function unstake(uint256 _amount, bool _trigger) external {
        if ( _trigger ) {
            _rebase();
        }
        IERC20( sOHM ).safeTransferFrom( msg.sender, address(this), _amount );
        IERC20( OHM ).safeTransfer( msg.sender, _amount );
    }


    /**
        @notice trigger rebase if epoch over
    */
    function rebase() external {
        if ( epoch.endBlock > block.number) revert();
        _rebase();
    }

   
    function _rebase() private {
        if( epoch.endBlock <= block.number ) {
            IsOHM( sOHM ).rebase( epoch.distribute, epoch.number );

            epoch.endBlock = epoch.endBlock + epoch.length;
            epoch.number++;
            if (rewardManager != address(0)) {
                IRewardManager( rewardManager ).distribute();
            }

            uint256 balance = contractBalance();
            uint256 staked = IsOHM( sOHM ).circulatingSupply();
            if( balance <= staked ) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = balance - staked;
            }
        }
    }

    /**
        @notice returns the sOHM index, which tracks rebase growth
        @return uint
     */
    function index() external view returns ( uint ) {
        return IsOHM( sOHM ).index();
    }

   /**
        @notice returns contract OHM holdings, including bonuses provided
        @return uint
     */
    function contractBalance() public view returns ( uint256 ) {
        return IERC20( OHM ).balanceOf( address(this) );
    }

    
    function setRewardManager(address _address) external onlyOwner {
        if (_address == address(0)) revert ErrorInvalidAddress();
        rewardManager = _address;
    }


    function setStakeContracts(address _stakeContract, bool _isStakeContract) external onlyOwner {
        stakeContracts[_stakeContract] = _isStakeContract;
    }

    function resetRebaseParam(uint256 _len, uint256 _block) external onlyOwner {
        epoch.length = _len;
        epoch.endBlock = _block;
    }
    
}
