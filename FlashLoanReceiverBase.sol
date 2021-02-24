// SPDX-License-Identifier: agpl-3.0
pragma solidity >=0.6.6;

import {IFlashLoanReceiver, ILendingPoolAddressesProvider, ILendingPool, IERC20  } from "./MyInterfaces.sol";
import { SafeERC20, SafeMath } from "./MyLibraries.sol";

abstract contract FlashLoanReceiverBase is IFlashLoanReceiver {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  ILendingPoolAddressesProvider internal _addressesProvider;
  ILendingPool internal LENDING_POOL;

  constructor(ILendingPoolAddressesProvider provider) internal {
    _addressesProvider = provider;
    LENDING_POOL = ILendingPool(ILendingPoolAddressesProvider(provider).getLendingPool());
  }
  
  receive() external payable {}
}
