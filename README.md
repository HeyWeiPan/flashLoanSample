# flashLoanSample

Please check out flashLoanSample.sol. This code is intended to perform a flash loan operation with interactions with other protocols within it. Steps within one transcation:  
  
      1. Borrow DAI from AAVE v2 flash loan  
      2. Swap DAI for wETH on Uniswap  
      3. Swap wETH for KNC on Kyber network  
      4. Swap KNC for DAI on sushiswapRouter  
      5. return DAO + fee to AAVE v2 flash loan
     
