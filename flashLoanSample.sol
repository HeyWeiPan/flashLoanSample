// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.6;

import { FlashLoanReceiverBase } from "./FlashLoanReceiverBase.sol";
import { ILendingPool, ILendingPoolAddressesProvider } from "./MyInterfaces.sol";

import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
import "https://github.com/KyberNetwork/smart-contracts/contracts/sol6/KyberNetworkProxy.sol";

/**
 * @author Warren Pan 02-22-2021
 * @title This is a demo flash loan operation on Kovan Testnet with following interations:
 *      1. Borrow DAI from AAVE v2 flash loan
 *      2. Swap DAI for wETH on Uniswap
 *      3. Swap wETH for KNC on Kyber network
 *      4. Swap KNC for DAI on sushiswapRouter
 *      5. return DAO + fee to AAVE v2
 * 
 * notice: this steps take place in ONE transaction, the transaction will be reverted if any of the step failed
 * 
 */
contract FlashLoanDemo is FlashLoanReceiverBase {
    address constant KOVAN_DAI = address(0xFf795577d9AC8bD7D90Ee22b6C1703490b6512FD);
    address constant KOVAN_KNC = address(0xad67cB4d63C9da94AcA37fDF2761AaDF780ff4a2);
    address constant KOVAN_UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant KOVAN_SUSHISWAP_ROUTER_ADDRESS = 0x027Bb5f9205360aC628C33508c3f182320A44525;
    address constant KOVAN_KYBER_PROXY_ADDRESS = 0x692f391bCc85cefCe8C237C01e1f636BbD70EA4D;
    address constant KOVAN_KYBER_NETWORK_ADDRESS = 0xB5034418f6Cc1fd494535F2D38F770C9827f88A1;
    
    ERC20 constant internal KOVAN_WETH_TOKEN_ERC20 = ERC20(0xd0A1E359811322d97991E03f863a0C30C2cF029C);
    ERC20 constant internal KOVAN_KNC_TOKEN_ERC20 = ERC20(0xad67cB4d63C9da94AcA37fDF2761AaDF780ff4a2);
    
    KyberNetworkProxy public kyberProxy;
    IUniswapV2Router02 private uniswapRouter;
    IUniswapV2Router02 private sushiswapRouter;
    IERC20 private DAI;
    IERC20 private KNC;
    
    using SafeMath for uint256;
    
    constructor(ILendingPoolAddressesProvider _addressProvider) FlashLoanReceiverBase(_addressProvider) public {
        uniswapRouter = IUniswapV2Router02(KOVAN_UNISWAP_ROUTER_ADDRESS);
        sushiswapRouter = IUniswapV2Router02(KOVAN_SUSHISWAP_ROUTER_ADDRESS);
        DAI = IERC20(KOVAN_DAI);
        KNC = IERC20(KOVAN_KNC);
        kyberProxy = KyberNetworkProxy(KOVAN_KYBER_PROXY_ADDRESS);
    }
    
    /**
     * This function is called after your contract has received the flash loaned amount
     * overriding executeOperation() in IFlashLoanReceiver 
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    )
        external
        override
        returns (bool)
    {   
        // swap DAI for wETH
        uint256 loanAmount = amounts[0];
        uint256 wETHAmount = uniswapSwap(loanAmount);
        
        // swap wETH for KNC
        uint256 kncAmount = kyberSwap(wETHAmount);
        
        // swap KNC for DAI
        sushiswapSwap(kncAmount);
        
        // Approve the LendingPool contract allowance to *pull* the owed amount
        for (uint i = 0; i < assets.length; i++) {
            uint amountOwing = amounts[i] + (premiums[i]);
            IERC20(assets[i]).approve(address(LENDING_POOL), amountOwing);
        }

        return true;
    }
    
    
    function myFlashLoanCall(uint256 loanAmount) public {
        address receiverAddress = address(this);

        address[] memory assets = new address[](1);
        assets[0] = KOVAN_DAI;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;
        amounts[0] = amounts[0] * loanAmount;

        // 0 means revert the transaction if not validated
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        address onBehalfOf = address(this);
        bytes memory params = "";
        uint16 referralCode = 0;

        LENDING_POOL.flashLoan(
            receiverAddress,
            assets,
            amounts,
            modes,
            onBehalfOf,
            params,
            referralCode
        );
    }
    
    /**
     * Swap from DAI to wETH on uniswap
     */
    function uniswapSwap(uint256 srcAmount) internal returns (uint256) {
        uint256 amountIn = srcAmount;

        require(DAI.approve(address(uniswapRouter), amountIn), 'approve failed.');
        
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = uniswapRouter.WETH();
        uint deadline = block.timestamp + 15;
        uint[] memory amounts = uniswapRouter.swapExactTokensForETH(srcAmount, 0, path, address(this), deadline);

        return amounts[1];
    }
    
    /**
     * swap from wETH to KNC on kyber network
     */
    function kyberSwap(uint256 srcAmount) public payable returns (uint256) {
        uint minConversionRate;

        // Get the minimum conversion rate
        (minConversionRate,) = kyberProxy.getExpectedRate(KOVAN_WETH_TOKEN_ERC20, KOVAN_KNC_TOKEN_ERC20, srcAmount);
        
        require(KOVAN_WETH_TOKEN_ERC20.approve(address(kyberProxy), srcAmount), 'approve failed.');
    
        // swap
        uint destAmount = kyberProxy.swapTokenToToken(KOVAN_WETH_TOKEN_ERC20, srcAmount, KOVAN_KNC_TOKEN_ERC20, minConversionRate);
        
        // Send the swapped tokens to the destination address
        require(KOVAN_KNC_TOKEN_ERC20.transfer(address(this), destAmount));
        
        return destAmount;
    }
    
    /**
     * Swap from KNC to DAI on sushiswap
     */
    function sushiswapSwap(uint256 srcAmount) internal returns (uint256) {
        uint256 amountIn = srcAmount;

        require(KNC.approve(address(sushiswapRouter), amountIn), 'approve failed.');
        
        address[] memory path = new address[](2);
        path[0] = address(KNC);
        path[1] = address(DAI);
        uint deadline = block.timestamp + 15;
        uint[] memory amounts = uniswapRouter.swapExactTokensForTokens(srcAmount, 0, path, address(this), deadline);

        return amounts[1];
    }
}
