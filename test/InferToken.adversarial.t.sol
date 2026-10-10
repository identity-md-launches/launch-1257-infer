// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {InferToken} from "src/InferToken.sol";

/// @dev An ordinary contract caller used to distinguish msg.sender from tx.origin.
contract InferCallerRelay {
    function move(InferToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    function grant(InferToken token, address spender, uint256 amount) external returns (bool) {
        return token.approve(spender, amount);
    }

    function pull(InferToken token, address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}

/// forge-config: default.fuzz.runs = 1000
contract InferTokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    InferToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;
    address internal otherSpender;

    function setUp() public {
        token = new InferToken();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
        otherSpender = makeAddr("adversarial other spender");
    }

    function test_OneBaseUnitCanMoveAndReturnThroughAllowance() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxUintDirectTransferRevertsWithoutMovingValue() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxUintDelegatedTransferCannotSpendBeyondBalance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxUintMinusOneIsFiniteAndDecreasesOnEverySpend() public {
        uint256 grant = type(uint256).max - 1;
        assertTrue(token.approve(spender, grant));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), grant - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UsedInfiniteApprovalCanBeReplacedAndRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 1);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_ZeroValueSpendPreservesExistingFiniteApproval() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RelayUsesItsOwnBalanceAndApprovalDespiteHolderOrigin() public {
        InferCallerRelay relay = new InferCallerRelay();
        assertTrue(token.transfer(alice, 100));
        assertTrue(token.transfer(address(relay), 7));
        vm.prank(alice, alice);
        assertTrue(relay.move(token, bob, 1));
        assertEq(token.balanceOf(address(relay)), 6);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 1);

        vm.prank(alice, alice);
        assertTrue(relay.grant(token, spender, type(uint256).max));
        assertEq(token.allowance(address(relay), spender), type(uint256).max);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_RelayCannotUseAnOriginOrCallersAllowance() public {
        InferCallerRelay relay = new InferCallerRelay();
        assertTrue(token.transfer(alice, 100));
        vm.prank(alice);
        assertTrue(token.approve(spender, 100));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(relay), 0, 1));
        vm.prank(spender, alice);
        relay.pull(token, alice, bob, 1);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 100);

        vm.prank(alice);
        assertTrue(token.approve(address(relay), 1));
        vm.prank(spender, alice);
        assertTrue(relay.pull(token, alice, bob, 1));
        assertEq(token.balanceOf(alice), 99);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, address(relay)), 0);
        assertEq(token.allowance(alice, spender), 100);
    }

    function testFuzz_FailedSpendCanBeRetriedAfterFunding(uint256 balanceSeed, uint256 amountSeed, bool infinite)
        public
    {
        uint256 balance = bound(balanceSeed, 0, SUPPLY - 1);
        uint256 amount = bound(amountSeed, balance + 1, SUPPLY);
        assertTrue(token.transfer(alice, balance));
        uint256 grant = infinite ? type(uint256).max : amount;
        vm.prank(alice);
        assertTrue(token.approve(spender, grant));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), grant);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        // Reuse the original grant: rollback must preserve a permission the holder can still use.
        assertTrue(token.transfer(alice, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), infinite ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_GrantsAreIsolatedByOwnerAndSpender(uint256 firstGrant, uint256 otherGrant, uint256 amountSeed)
        public
    {
        assertTrue(token.transfer(alice, SUPPLY / 2));
        assertTrue(token.transfer(bob, SUPPLY / 2));
        vm.startPrank(alice);
        assertTrue(token.approve(spender, firstGrant));
        assertTrue(token.approve(otherSpender, otherGrant));
        assertTrue(token.approve(alice, otherGrant));
        vm.stopPrank();
        vm.prank(bob);
        assertTrue(token.approve(spender, otherGrant));

        uint256 amount = bound(amountSeed, 0, firstGrant < SUPPLY / 2 ? firstGrant : SUPPLY / 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), firstGrant == type(uint256).max ? firstGrant : firstGrant - amount);
        assertEq(token.allowance(alice, otherSpender), otherGrant);
        assertEq(token.allowance(alice, alice), otherGrant);
        assertEq(token.allowance(bob, spender), otherGrant);
        assertEq(token.balanceOf(alice), SUPPLY / 2 - amount);
        assertEq(token.balanceOf(bob), SUPPLY / 2 + amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_MixedTransferRoundTripHasNoFeeOrUnitLoss(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(bob), amount);
        vm.prank(bob);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
