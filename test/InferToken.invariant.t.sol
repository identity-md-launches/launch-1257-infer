// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {InferToken} from "../src/InferToken.sol";

/// @dev Mixes successful and rejected operations against an independent accounting model.
/// Expected reverts are checked explicitly, so fail_on_revert catches harness errors too.
contract InferTokenHandler is Test {
    InferToken internal immutable token;
    address[4] internal actors;
    mapping(address actor => uint256 balance) public expectedBalance;
    mapping(address owner => mapping(address spender => uint256 amount)) public expectedAllowance;

    constructor(InferToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = 250_000_000 * 10 ** 18;
        }
    }

    function transfer(uint256 senderSeed, uint256 recipientSeed, uint256 amountSeed) external {
        address from = actors[senderSeed % actors.length];
        address to = actors[recipientSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[recipientSeed % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, 0, allowance < balance ? allowance : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 edgeSeed) external {
        uint256[4] memory amounts = [uint256(0), 1, type(uint256).max - 1, type(uint256).max];
        approve(ownerSeed, spenderSeed, amounts[edgeSeed % amounts.length]);
    }

    function rejectTransferOverdraft(uint256 senderSeed, uint256 recipientSeed, uint256 amountSeed) external {
        address from = actors[senderSeed % actors.length];
        address to = actors[recipientSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No model update: the invariant checks every balance and allowance remains intact.
    }

    function revokeAndRejectSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[recipientSeed % actors.length];
        approve(ownerSeed, spenderSeed, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function rejectAllowanceOverdraft(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 allowanceSeed
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[recipientSeed % actors.length];
        uint256 allowance = bound(allowanceSeed, 0, type(uint256).max - 1);
        approve(ownerSeed, spenderSeed, allowance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, allowance + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, allowance + 1);
    }

    function rejectTransferFromOverdraft(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 amountSeed,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[recipientSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        approve(ownerSeed, spenderSeed, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        // In particular, a finite allowance spent before the balance check must roll back.
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 limit = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < limit) limit = expectedAllowance[owner][spender];
        uint256 amount = bound(amountSeed, 0, limit);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract InferTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    InferToken internal token;
    InferTokenHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        token = new InferToken();
        actors = [makeAddr("holder 0"), makeAddr("holder 1"), makeAddr("holder 2"), makeAddr("holder 3")];
        for (uint256 i; i < actors.length; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / actors.length));
        }
        handler = new InferTokenHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.approveBoundary.selector;
        selectors[4] = handler.rejectTransferOverdraft.selector;
        selectors[5] = handler.revokeAndRejectSpend.selector;
        selectors[6] = handler.rejectAllowanceOverdraft.selector;
        selectors[7] = handler.rejectTransferFromOverdraft.selector;
        selectors[8] = handler.rejectZeroRecipient.selector;
        selectors[9] = handler.rejectZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.name(), "Infer");
        assertEq(token.symbol(), "INFER");
        assertEq(token.decimals(), 18);
    }

    /// @dev After every random sequence, each holder can empty its account with exact delivery.
    /// This is independent of its grants and of any earlier rejected transfers.
    function afterInvariant() public {
        // Sweep around the ring so even the final recipient first proves it can send.
        for (uint256 i; i < actors.length; ++i) {
            handler.transfer(i, (i + 1) % actors.length, handler.expectedBalance(actors[i]));
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        invariant_SupplyBalancesAndAllowancesMatchModel();
    }
}
