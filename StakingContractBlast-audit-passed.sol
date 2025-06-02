// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./blast/IBlastPoints.sol";
import "./blast/IBlast.sol";
import "./blast/IERC20Rebasing.sol";

import "./staking/Misc.sol";

contract StakingContractBlast is Ownable, ReentrancyGuard, Pausable {
   constructor(ConstructorParams memory params) Ownable(params.superOwner) {
      _token = IERC20(params.tokenAddress);
      _tokenSymbol = params.tokenSymbol;
      _tokenDecimals = params.tokenDecimals;

      _period0Duration = params.period0Duration;
      _period1Duration = params.period1Duration;
      _period2Duration = params.period2Duration;

      _period0Price = params.period0Price;
      _period1Price = params.period1Price;
      _period2Price = params.period2Price;

      _period0MaxAmount = params.period0MaxAmount;
      _period1MaxAmount = params.period1MaxAmount;
      _period2MaxAmount = params.period2MaxAmount;

      _period0MaxAmountPerAccount = params.period0MaxAmountPerAccount;
      _period1MaxAmountPerAccount = params.period1MaxAmountPerAccount;
      _period2MaxAmountPerAccount = params.period2MaxAmountPerAccount;
   }

   using EnumerableSet for EnumerableSet.AddressSet;
   using EnumerableSet for EnumerableSet.Bytes32Set;

   // members ------------------------------------------------------

   IERC20 public immutable _token;
   string public _tokenSymbol;
   uint8 public immutable _tokenDecimals;

   uint64 public _period0Duration;
   uint64 public _period1Duration;
   uint64 public _period2Duration;
   uint256 public immutable _period0Price;
   uint256 public immutable _period1Price;
   uint256 public immutable _period2Price;
   uint256 public immutable _period0MaxAmount;
   uint256 public immutable _period1MaxAmount;
   uint256 public immutable _period2MaxAmount;
   uint256 public immutable _period0MaxAmountPerAccount;
   uint256 public immutable _period1MaxAmountPerAccount;
   uint256 public immutable _period2MaxAmountPerAccount;

   uint256 public _period0AmountsCounter;
   uint256 public _period1AmountsCounter;
   uint256 public _period2AmountsCounter;

   uint64 public _depositsCounter;

   EnumerableSet.AddressSet private _accounts;
   EnumerableSet.Bytes32Set private _depositIds;

   mapping(address => uint256) public _period0AccountAmountCounters;
   mapping(address => uint256) public _period1AccountAmountCounters;
   mapping(address => uint256) public _period2AccountAmountCounters;

   mapping(bytes32 => DepositInfo) public _deposits;
   mapping(address => EnumerableSet.Bytes32Set) private _accountDepositIds;

   IBlast public constant _BLAST = IBlast(0x4300000000000000000000000000000000000002);
   IERC20Rebasing public _USDB;
   IERC20Rebasing public _WETHB;
   address public _blastPointsAddress;
   address public _blastPointsOperator;

   // events -------------------------------------------------------

   event ConfigureBlastPoints(uint256 usdbBalance, uint256 wethbBalance);
   event ClaimYieldAll(
      address indexed recipient,
      uint256 amountWETH,
      uint256 amountUSDB,
      uint256 amountGas
   );
   event ClaimGas(address indexed recipient, uint256 amount);
   event Deposit(
      address indexed account,
      bytes32 depositId,
      uint256 amount,
      uint64 createdAt,
      uint64 availableFrom
   );
   event Withdraw(address indexed account, bytes32 depositId, uint256 amount, uint64 createdAt);
   event UpdateDepositDuration(bytes32 depositId, uint64 availableFrom);
   event SetPeriodDuration(uint8 periodType, uint64 newDuration);

   // functions ----------------------------------------------------

   function getCurrentTime() internal view returns (uint64) {
      return uint64(block.timestamp);
   }

   function getAccountsCount() public view returns (uint256) {
      return _accounts.length();
   }

   function getAccountByIndex(uint256 idx) public view returns (address) {
      return _accounts.at(idx);
   }

   function getDepositsCount() public view returns (uint256) {
      return _depositIds.length();
   }

   function getDepositIdByIndex(uint256 idx) public view returns (bytes32) {
      return _depositIds.at(idx);
   }

   /**
    * Get basic statistics of amounts and counters
    */
   function getBasicStat() external view returns (BasicStat memory) {
      BasicStat memory res;
      res.period0MaxAmount = _period0MaxAmount;
      res.period0AmountsCounter = _period0AmountsCounter;
      res.period1MaxAmount = _period1MaxAmount;
      res.period1AmountsCounter = _period1AmountsCounter;
      res.period2MaxAmount = _period2MaxAmount;
      res.period2AmountsCounter = _period2AmountsCounter;

      return res;
   }

   /**
    * Get all Account's Deposits.
    *
    * @param account Account for which information is needed
    */
   function getAccountDeposits(address account) public view returns (DepositInfo[] memory) {
      EnumerableSet.Bytes32Set storage deposits = _accountDepositIds[account];
      if (deposits.length() == 0) {
         DepositInfo[] memory resNull;
         return resNull;
      }

      DepositInfo[] memory res = new DepositInfo[](deposits.length());
      for (uint i = 0; i < deposits.length(); ++i) {
         res[i] = _deposits[deposits.at(i)];
      }

      return res;
   }

   /**
    * Called by User when it makes Deposit.
    *
    * @param periodType The type of the Period (0 - 2) which will be used by Deposit
    */
   function deposit(uint8 periodType) external whenNotPaused nonReentrant {
      address sender = _msgSender();
      uint256 amount = 0;

      require(periodType < 3, "periodType must be less than 3");

      if (periodType == 0) {
         amount = _period0Price;
         if (_period0MaxAmount > 0) {
            require(
               (_period0AmountsCounter + amount) <= _period0MaxAmount,
               "The limit of the Period-0 has been reached"
            );
         }
         if (_period0MaxAmountPerAccount > 0) {
            require(
               (_period0AccountAmountCounters[sender] + amount) <= _period0MaxAmountPerAccount,
               "You have reached the limit per account (Period-0)"
            );
         }
      } else if (periodType == 1) {
         amount = _period1Price;
         if (_period1MaxAmount > 0) {
            require(
               (_period1AmountsCounter + amount) <= _period1MaxAmount,
               "The limit of the Period-1 has been reached"
            );
         }
         if (_period1MaxAmountPerAccount > 0) {
            require(
               (_period1AccountAmountCounters[sender] + amount) <= _period1MaxAmountPerAccount,
               "You have reached the limit per account (Period-1)"
            );
         }
      } else {
         amount = _period2Price;
         if (_period2MaxAmount > 0) {
            require(
               (_period2AmountsCounter + amount) <= _period2MaxAmount,
               "The limit of the Period-2 has been reached"
            );
         }
         if (_period2MaxAmountPerAccount > 0) {
            require(
               (_period2AccountAmountCounters[sender] + amount) <= _period2MaxAmountPerAccount,
               "You have reached the limit per account (Period-2)"
            );
         }
      }

      require(
         _token.allowance(sender, address(this)) >= amount,
         "You must allow to use of funds by the Contract"
      );
      require(_token.balanceOf(sender) >= amount, "You don't have enough funds");

      if (!_accounts.contains(sender)) {
         _accounts.add(sender);
      }

      bytes32 depositId = bytes32(
         keccak256(abi.encode(address(this), block.number + _depositsCounter))
      );
      // regenerate ID if collision
      if (_deposits[depositId]._id != 0) {
         depositId = bytes32(keccak256(abi.encode(depositId)));
      }

      uint64 currentTime = getCurrentTime();
      DepositInfo memory dep = DepositInfo(
         depositId,
         sender,
         amount,
         periodType,
         currentTime,
         0,
         false
      );

      if (periodType == 0) {
         _period0AmountsCounter = _period0AmountsCounter + amount;
         _period0AccountAmountCounters[sender] = _period0AccountAmountCounters[sender] + amount;
         dep._availableFrom = currentTime + _period0Duration;
      } else if (periodType == 1) {
         _period1AmountsCounter = _period1AmountsCounter + amount;
         _period1AccountAmountCounters[sender] = _period1AccountAmountCounters[sender] + amount;
         dep._availableFrom = currentTime + _period1Duration;
      } else {
         _period2AmountsCounter = _period2AmountsCounter + amount;
         _period2AccountAmountCounters[sender] = _period2AccountAmountCounters[sender] + amount;
         dep._availableFrom = currentTime + _period2Duration;
      }

      _deposits[depositId] = dep;
      _depositIds.add(depositId);
      _accountDepositIds[sender].add(depositId);
      _depositsCounter += 1;

      _token.transferFrom(sender, address(this), amount);

      emit Deposit(sender, depositId, amount, currentTime, dep._availableFrom);
   }

   /**
    * Called by User when it makes the Withdrawal.
    *
    * @param depositId the ID of the Deposit in the User's own
    */
   function withdraw(bytes32 depositId) external nonReentrant {
      address sender = _msgSender();

      DepositInfo memory dep = _deposits[depositId];
      uint256 amount = dep._amount;

      require(dep._withdrawn == false, "The Deposit has already been withdrawn");
      require(dep._owner == sender, "You're not the Owner of the Deposit");
      require(dep._availableFrom < getCurrentTime(), "you can't withdraw your Deposit yet");

      if (dep._periodType == 0) {
         _period0AccountAmountCounters[sender] = _period0AccountAmountCounters[sender] - amount;
         _period0AmountsCounter = _period0AmountsCounter - amount;
      } else if (dep._periodType == 1) {
         _period1AccountAmountCounters[sender] = _period1AccountAmountCounters[sender] - amount;
         _period1AmountsCounter = _period1AmountsCounter - amount;
      } else {
         _period2AccountAmountCounters[sender] = _period2AccountAmountCounters[sender] - amount;
         _period2AmountsCounter = _period2AmountsCounter - amount;
      }

      _deposits[dep._id]._withdrawn = true;

      _token.transfer(sender, amount);

      emit Withdraw(sender, depositId, amount, getCurrentTime());
   }

   /**
    * Called by user when he wants to update the Deposit's duration time.
    *
    * @param depositId the ID of the Deposit in the User's own
    */
   function updateDepositDuration(bytes32 depositId) external {
      address sender = _msgSender();

      DepositInfo memory dep = _deposits[depositId];
      require(dep._owner == sender, "You're not the Owner of the Deposit");

      uint64 duration = 0;
      if (dep._periodType == 0) {
         duration = _period0Duration;
      } else if (dep._periodType == 1) {
         duration = _period1Duration;
      } else {
         duration = _period2Duration;
      }

      _deposits[dep._id]._availableFrom = _deposits[dep._id]._createTime + duration;

      emit UpdateDepositDuration(depositId, _deposits[dep._id]._availableFrom);
   }

   /**
    * Called by the Contract's Owner to update the duration of the specific Period.
    *
    * @param periodType type of the period (0 - 2)
    * @param newDuration the duration in seconds of the period
    */
   function setPeriodDuration(uint8 periodType, uint64 newDuration) external onlyOwner {
      if (periodType == 0) {
         require(
            newDuration < _period0Duration,
            "newDuration must be less than current _period0Duration"
         );
         _period0Duration = newDuration;
      } else if (periodType == 1) {
         require(
            newDuration < _period1Duration,
            "newDuration must be less than current _period1Duration"
         );
         _period1Duration = newDuration;
      } else {
         require(
            newDuration < _period2Duration,
            "newDuration must be less than current _period2Duration"
         );
         _period2Duration = newDuration;
      }

      emit SetPeriodDuration(periodType, newDuration);
   }

   /**
    * Called by the Contract's Owner to pause the creation of Deposits
    */
   function pause() external onlyOwner {
      Pausable._pause();
   }

   /**
    * Called by the Contract's Owner to unpause the creation of Deposits
    */
   function unpause() external onlyOwner {
      Pausable._unpause();
   }

   // BLAST --------------------------------------------------------

   function configureBlastPoints(
      address blastUsdbYieldAddress,
      address blastWethbYieldAddress,
      address blastPointsAddress,
      address blastPointsOperator
   ) external onlyOwner {
      _BLAST.configureClaimableGas();
      _USDB = IERC20Rebasing(blastUsdbYieldAddress);
      uint256 usdbBalance = _USDB.configure(IERC20Rebasing.YieldMode.CLAIMABLE);
      _WETHB = IERC20Rebasing(blastWethbYieldAddress);
      uint256 wethbBalance = _WETHB.configure(IERC20Rebasing.YieldMode.CLAIMABLE);

      _blastPointsAddress = blastPointsAddress;
      _blastPointsOperator = blastPointsOperator;
      IBlastPoints(_blastPointsAddress).configurePointsOperator(_blastPointsOperator);

      emit ConfigureBlastPoints(usdbBalance, wethbBalance);
   }

   function configureBlastPointsOperatorOnBehalf(address blastPointsOperator) external onlyOwner {
      IBlastPoints(_blastPointsAddress).configurePointsOperatorOnBehalf(
         address(this),
         blastPointsOperator
      );
   }

   function configureGovernor(address gov) external onlyOwner {
      IBlast(_BLAST).configureGovernor(gov);
   }

   function configureBlastYieldModes(uint8 usdbYieldMode, uint8 wethbYieldMode) external onlyOwner {
      _USDB.configure(IERC20Rebasing.YieldMode(usdbYieldMode));
      _WETHB.configure(IERC20Rebasing.YieldMode(wethbYieldMode));
   }

   function claimYieldAll(
      address _recipient,
      uint256 _amountWETH,
      uint256 _amountUSDB
   ) external onlyOwner returns (uint256 amountWETH, uint256 amountUSDB, uint256 amountGas) {
      amountWETH = IERC20Rebasing(_WETHB).claim(_recipient, _amountWETH);
      amountUSDB = IERC20Rebasing(_USDB).claim(_recipient, _amountUSDB);
      amountGas = IBlast(_BLAST).claimMaxGas(address(this), _recipient);

      emit ClaimYieldAll(_recipient, amountWETH, amountUSDB, amountGas);
   }

   function claimGas(
      address _recipient,
      uint256 _minClaimRateBips
   ) external onlyOwner returns (uint256 amount) {
      if (_minClaimRateBips == 0) {
         amount = _BLAST.claimMaxGas(address(this), _recipient);
      } else {
         amount = _BLAST.claimGasAtMinClaimRate(address(this), _recipient, _minClaimRateBips);
      }

      emit ClaimGas(_recipient, amount);
   }
}
