// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

struct SwapData {
    SwapType swapType;
    address extRouter;
    bytes extCalldata;
    bool needScale;
}

struct SwapDataExtra {
    address tokenIn;
    address tokenOut;
    uint minOut;
    SwapData swapData;
}

enum SwapType {
    NONE,
    KYBERSWAP,
    ODOS,
    // ETH_WETH not used in Aggregator
    ETH_WETH,
    OKX,
    ONE_INCH,
    RESERVE_1,
    RESERVE_2,
    RESERVE_3,
    RESERVE_4,
    RESERVE_5
}

interface IPSwapAggregator {
    event SwapSingle(SwapType indexed swapType, address indexed tokenIn, uint amountIn);

    function swap(address tokenIn, uint amountIn, SwapData calldata swapData) external payable;
}
