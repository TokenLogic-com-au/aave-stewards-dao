// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AaveV3ArbitrumAssets} from "aave-address-book/AaveV3Arbitrum.sol";

import {IAggregatorInterface} from "src/finance/interfaces/IAggregatorInterface.sol";
import {OracleMathHarness} from "./OracleMath.t.sol";

interface IRoundDataFeed {
  function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

contract OracleMathForkTest is Test {
  uint256 internal constant FORK_BLOCK = 512244730;

  OracleMathHarness internal harness;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl("arbitrum"), FORK_BLOCK);
    harness = new OracleMathHarness();
  }

  function _expectedOut(address fromToken, address toToken, address fromOracle, address toOracle, uint256 amount)
    internal
    view
    returns (uint256)
  {
    uint256 pFrom = uint256(IAggregatorInterface(fromOracle).latestAnswer());
    uint256 pTo = uint256(IAggregatorInterface(toOracle).latestAnswer());
    uint256 fromScale = 10 ** IERC20Metadata(fromToken).decimals();
    uint256 toScale = 10 ** IERC20Metadata(toToken).decimals();

    return (amount * pFrom * toScale) / (pTo * fromScale);
  }

  function test_getExpectedOut_cappedAdapter() public {
    vm.expectRevert();
    IRoundDataFeed(AaveV3ArbitrumAssets.USDC_ORACLE).latestRoundData();

    uint256 amount = 1_000e6;
    uint256 out = harness.getExpectedOut(
      AaveV3ArbitrumAssets.USDC_UNDERLYING,
      AaveV3ArbitrumAssets.USDT_UNDERLYING,
      AaveV3ArbitrumAssets.USDC_ORACLE,
      AaveV3ArbitrumAssets.USDT_ORACLE,
      amount
    );

    assertEq(
      out,
      _expectedOut(
        AaveV3ArbitrumAssets.USDC_UNDERLYING,
        AaveV3ArbitrumAssets.USDT_UNDERLYING,
        AaveV3ArbitrumAssets.USDC_ORACLE,
        AaveV3ArbitrumAssets.USDT_ORACLE,
        amount
      )
    );
  }

  function test_getExpectedOut_aaveToUsdc() public view {
    uint256 amount = 10e18;
    uint256 out = harness.getExpectedOut(
      AaveV3ArbitrumAssets.AAVE_UNDERLYING,
      AaveV3ArbitrumAssets.USDC_UNDERLYING,
      AaveV3ArbitrumAssets.AAVE_ORACLE,
      AaveV3ArbitrumAssets.USDC_ORACLE,
      amount
    );

    assertEq(
      out,
      _expectedOut(
        AaveV3ArbitrumAssets.AAVE_UNDERLYING,
        AaveV3ArbitrumAssets.USDC_UNDERLYING,
        AaveV3ArbitrumAssets.AAVE_ORACLE,
        AaveV3ArbitrumAssets.USDC_ORACLE,
        amount
      )
    );
  }

  function test_getExpectedOut_wethToUsdc() public view {
    uint256 amount = 1e18;
    uint256 out = harness.getExpectedOut(
      AaveV3ArbitrumAssets.WETH_UNDERLYING,
      AaveV3ArbitrumAssets.USDC_UNDERLYING,
      AaveV3ArbitrumAssets.WETH_ORACLE,
      AaveV3ArbitrumAssets.USDC_ORACLE,
      amount
    );

    assertEq(
      out,
      _expectedOut(
        AaveV3ArbitrumAssets.WETH_UNDERLYING,
        AaveV3ArbitrumAssets.USDC_UNDERLYING,
        AaveV3ArbitrumAssets.WETH_ORACLE,
        AaveV3ArbitrumAssets.USDC_ORACLE,
        amount
      )
    );
  }
}
