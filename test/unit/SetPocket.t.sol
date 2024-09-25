// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { PSMTestBase } from "test/PSMTestBase.sol";

contract PSMSetPocketFailureTests is PSMTestBase {

    function test_setPocket_invalidOwner() public {
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)",
            address(this))
        );
        psm.setPocket(address(1));
    }

    function test_setPocket_invalidPocket() public {
        vm.prank(owner);
        vm.expectRevert("PSM3/invalid-pocket");
        psm.setPocket(address(0));
    }

    function test_setPocket_insufficientAllowanceBoundary() public {
        address pocket1 = makeAddr("pocket1");
        address pocket2 = makeAddr("pocket2");

        vm.prank(owner);
        psm.setPocket(pocket1);

        vm.prank(pocket1);
        usdc.approve(pocket2, 1_000_000e6);

        deal(address(usdc), pocket1, 1_000_000e6 + 1);

        vm.prank(owner);
        vm.expectRevert("SafeERC20/transfer-from-failed");
        psm.setPocket(pocket2);

        // deal(address(usdc), pocket1, 1_000_000e6);

        // psm.setPocket(pocket2);
    }

}
