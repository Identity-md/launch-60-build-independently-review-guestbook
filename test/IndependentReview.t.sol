// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Guest} from "../src/Guest.sol";
import {Guestbook} from "../src/Guestbook.sol";

interface ReviewVm {
    function expectRevert() external;
}

contract ReviewFactory {
    function launch() external returns (Guest token, Guestbook book) {
        token = new Guest();
        book = new Guestbook(address(token));
    }
}

contract EmptyReturnToken {
    fallback() external {}
}

contract IndependentReviewTest {
    ReviewVm constant vm = ReviewVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testFactorySupplyAndRuntimeFloor() public {
        ReviewFactory factory = new ReviewFactory();
        (Guest token, Guestbook book) = factory.launch();
        require(token.balanceOf(address(factory)) == 1e27);
        require(address(book.token()) == address(token));
        checkRuntime(address(token));
        checkRuntime(address(book));
    }

    function checkRuntime(address target) internal view {
        bytes memory code = target.code;
        require(code.length > 0 && code.length <= 24_576);
        for (uint256 i; i < code.length; i++) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            require(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }

    function testMissingReturnDataFailsAtomically() public {
        Guestbook book = new Guestbook(address(new EmptyReturnToken()));
        vm.expectRevert();
        book.post("must fail");
        require(book.entryCount() == 0);
        vm.expectRevert();
        book.post("guard must not stick");
        require(book.entryCount() == 0);
    }

    function testFiniteAllowanceAndFailureConservation() public {
        Guest token = new Guest();
        Guestbook book = new Guestbook(address(token));
        token.approve(address(book), 1 ether);
        book.post("one");
        require(token.allowance(address(this), address(book)) == 0);
        vm.expectRevert();
        book.post("two");
        require(book.entryCount() == 1);
        require(token.balanceOf(book.DEAD()) == 1 ether);
        require(token.balanceOf(address(this)) == token.totalSupply() - 1 ether);
    }
}
