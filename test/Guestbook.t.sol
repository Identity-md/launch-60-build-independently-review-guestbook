// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Guest} from "../src/Guest.sol";
import {Guestbook} from "../src/Guestbook.sol";

interface Vm {
    function prank(address) external;
    function warp(uint256) external;
    function expectRevert(bytes4) external;
    function expectRevert() external;
    function expectEmit(bool, bool, bool, bool) external;
}

contract MaliciousToken {
    Guestbook public book;
    bool public propagate;
    bool public returnFalse;
    bool public callbackRejected;
    uint256 public observedCount;

    function configure(Guestbook book_, bool propagate_, bool returnFalse_) external {
        book = book_;
        propagate = propagate_;
        returnFalse = returnFalse_;
    }

    function transferFrom(address, address, uint256) external returns (bool) {
        observedCount = book.entryCount();
        (bool ok, bytes memory result) = address(book).call(abi.encodeCall(book.post, ("callback")));
        callbackRejected = !ok && bytes4(result) == Guestbook.ReentrantCall.selector;
        if (propagate) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
        return !returnFalse;
    }
}

contract GuestbookTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    Guest token;
    Guestbook book;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event MessagePosted(uint256 indexed id, address indexed author, uint256 timestamp, string message);

    function setUp() public {
        token = new Guest();
        book = new Guestbook(address(token));
        token.transfer(ALICE, 10 ether);
        vm.prank(ALICE);
        token.approve(address(book), 10 ether);
    }

    function testDeployment() public view {
        require(keccak256(bytes(token.name())) == keccak256("Guest"));
        require(keccak256(bytes(token.symbol())) == keccak256("GUEST"));
        require(token.decimals() == 18 && token.totalSupply() == 1e27);
        require(token.balanceOf(address(this)) == 1e27 - 10 ether);
        require(address(book.token()) == address(token) && book.entryCount() == 0);
    }

    function testConstructorMintEventAndSupply() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), 1e27);
        Guest fresh = new Guest();
        require(fresh.balanceOf(address(this)) == fresh.totalSupply());
    }

    function testPostPaymentEventAndEnumeration() public {
        vm.warp(12345);
        vm.expectEmit(true, true, false, true);
        emit MessagePosted(0, ALICE, 12345, "hello");
        vm.prank(ALICE);
        require(book.post("hello") == 0);
        require(book.entryCount() == 1);
        (address author, uint256 timestamp, string memory message) = book.entries(0);
        require(author == ALICE && timestamp == 12345 && keccak256(bytes(message)) == keccak256("hello"));
        require(token.balanceOf(ALICE) == 9 ether && token.balanceOf(book.DEAD()) == 1 ether);
        require(token.balanceOf(address(book)) == 0 && token.totalSupply() == 1e27);
        require(token.allowance(ALICE, address(book)) == 9 ether);
        token.transfer(BOB, 1 ether);
        vm.prank(BOB);
        token.approve(address(book), 1 ether);
        vm.warp(12346);
        vm.prank(BOB);
        require(book.post("second") == 1);
        (author, timestamp, message) = book.entries(0);
        require(author == ALICE && timestamp == 12345 && keccak256(bytes(message)) == keccak256("hello"));
        (author, timestamp, message) = book.entries(1);
        require(author == BOB && timestamp == 12346 && keccak256(bytes(message)) == keccak256("second"));
        require(book.entryCount() == 2 && token.balanceOf(book.DEAD()) == 2 ether);
        vm.expectRevert();
        book.entries(2);
    }

    function testEmptyAndExactly140Bytes() public {
        vm.prank(ALICE);
        book.post("");
        vm.prank(ALICE);
        book.post(string(new bytes(140)));
        require(book.entryCount() == 2);
    }

    function testTooLongAndMultibyte() public {
        vm.expectRevert(Guestbook.MessageTooLong.selector);
        vm.prank(ALICE);
        book.post(string(new bytes(141)));
        bytes memory unicodeMessage;
        for (uint256 i; i < 71; i++) {
            unicodeMessage = abi.encodePacked(unicodeMessage, unicode"é");
        }
        vm.expectRevert(Guestbook.MessageTooLong.selector);
        vm.prank(ALICE);
        book.post(string(unicodeMessage));
        require(book.entryCount() == 0 && token.balanceOf(ALICE) == 10 ether);
    }

    function testMissingInsufficientAndRevokedPermissions() public {
        token.transfer(BOB, 1 ether);
        vm.expectRevert(Guest.InsufficientAllowance.selector);
        vm.prank(BOB);
        book.post("no permission");
        vm.prank(BOB);
        token.approve(address(book), 1 ether - 1);
        vm.expectRevert(Guest.InsufficientAllowance.selector);
        vm.prank(BOB);
        book.post("short permission");
        vm.prank(ALICE);
        token.approve(address(book), 0);
        vm.expectRevert(Guest.InsufficientAllowance.selector);
        vm.prank(ALICE);
        book.post("revoked");
        require(book.entryCount() == 0 && token.balanceOf(book.DEAD()) == 0);
        vm.prank(ALICE);
        token.approve(address(book), 1 ether);
        vm.prank(ALICE);
        book.post("recovered");
    }

    function testInsufficientBalanceRollsBackAllowanceAndEntries() public {
        vm.prank(BOB);
        token.approve(address(book), 1 ether);
        vm.expectRevert(Guest.InsufficientBalance.selector);
        vm.prank(BOB);
        book.post("unfunded");
        require(book.entryCount() == 0 && token.allowance(BOB, address(book)) == 1 ether);
        require(token.balanceOf(book.DEAD()) == 0);
    }

    function testInvalidTokenAddresses() public {
        vm.expectRevert(Guestbook.InvalidToken.selector);
        new Guestbook(address(0));
        vm.expectRevert(Guestbook.InvalidToken.selector);
        new Guestbook(ALICE);
    }

    function testReentrantTokenCannotAppendAndSeesEffects() public {
        MaliciousToken evil = new MaliciousToken();
        Guestbook target = new Guestbook(address(evil));
        evil.configure(target, false, false);
        target.post("outer");
        require(evil.callbackRejected() && evil.observedCount() == 1 && target.entryCount() == 1);
        target.post("next");
        require(target.entryCount() == 2);
    }

    function testReentrantRevertAndFalsePaymentAreAtomic() public {
        MaliciousToken evil = new MaliciousToken();
        Guestbook target = new Guestbook(address(evil));
        evil.configure(target, true, false);
        vm.expectRevert(Guestbook.ReentrantCall.selector);
        target.post("rolled back");
        require(target.entryCount() == 0 && evil.observedCount() == 0);
        evil.configure(target, false, true);
        vm.expectRevert(Guestbook.PaymentFailed.selector);
        target.post("false payment");
        require(target.entryCount() == 0 && evil.observedCount() == 0);
        evil.configure(target, false, false);
        target.post("guard recovered");
        require(target.entryCount() == 1);
    }

    function testTransferAndApprovalEventsInfiniteAllowanceAndSelfTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(ALICE, BOB, type(uint256).max);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.expectEmit(true, true, false, true);
        emit Transfer(ALICE, BOB, 1 ether);
        vm.prank(BOB);
        require(token.transferFrom(ALICE, BOB, 1 ether));
        require(token.allowance(ALICE, BOB) == type(uint256).max);
        vm.prank(ALICE);
        token.transfer(ALICE, 9 ether);
        require(token.balanceOf(ALICE) == 9 ether && token.balanceOf(BOB) == 1 ether);
        vm.prank(BOB);
        require(token.transfer(ALICE, 0));
    }

    function testZeroAddressesAndUnauthorizedTransfer() public {
        vm.expectRevert(Guest.ZeroAddress.selector);
        token.transfer(address(0), 0);
        vm.expectRevert(Guest.ZeroAddress.selector);
        token.approve(address(0), 1);
        vm.expectRevert(Guest.ZeroAddress.selector);
        token.transferFrom(address(0), BOB, 0);
        vm.expectRevert(Guest.InsufficientAllowance.selector);
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);
        vm.expectRevert(Guest.InsufficientBalance.selector);
        vm.prank(BOB);
        token.transfer(ALICE, 1);
    }

    function testNoMintAdminOrEditingSelectors() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", ALICE, 1));
        require(!ok && token.totalSupply() == 1e27);
        (ok,) = address(token).call(abi.encodeWithSignature("transferOwnership(address)", ALICE));
        require(!ok);
        vm.prank(ALICE);
        book.post("permanent");
        (ok,) = address(book).call(abi.encodeWithSignature("edit(uint256,string)", 0, "changed"));
        require(!ok);
        (ok,) = address(book).call(abi.encodeWithSignature("deleteEntry(uint256)", 0));
        require(!ok && book.entryCount() == 1);
    }

    function testFuzzMessageBoundaryAndAccounting(bytes memory message) public {
        if (message.length > 140) vm.expectRevert(Guestbook.MessageTooLong.selector);
        vm.prank(ALICE);
        book.post(string(message));
        bool accepted = message.length <= 140;
        require(book.entryCount() == (accepted ? 1 : 0));
        require(token.balanceOf(ALICE) == (accepted ? 9 ether : 10 ether));
        require(token.balanceOf(book.DEAD()) == (accepted ? 1 ether : 0));
        if (accepted) {
            (,, string memory stored) = book.entries(0);
            require(keccak256(bytes(stored)) == keccak256(message));
        }
    }

    function testFuzzTransfersConserveSupply(uint256 amount) public {
        amount %= 1e27 - 10 ether + 1;
        uint256 beforeBalance = token.balanceOf(address(this));
        token.transfer(BOB, amount);
        require(token.balanceOf(BOB) == amount && token.balanceOf(address(this)) == beforeBalance - amount);
        require(token.balanceOf(ALICE) + token.balanceOf(BOB) + token.balanceOf(address(this)) == token.totalSupply());
    }
}
