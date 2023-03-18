// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract BlockPearlDapp is ERC1155, Ownable, ReentrancyGuard {
    using Strings for uint256;
    using SafeMath for uint256;

    // Define data structures to store entrepreneur and investor details
    struct Entrepreneur {
        address wallet;
        bool hasViableIdea;
        uint256 tokenId;
    }

    struct Investment {
        address investor;
        address entrepreneur;
        uint256 amount;
    }

    uint256 private _currentTokenId;
    address private _feeRecipient;
    uint256 private constant FEE_PERCENTAGE = 250; // 2.5% as basis points (10000 = 100%)
    uint256 private constant MAX_INVESTMENT = 5 ether;

    mapping(address => Entrepreneur) public entrepreneurs;
    Investment[] public investments;
    mapping(address => bool) public investors;

    string private _baseURI;

    event EntrepreneurRegistered(address indexed entrepreneur);
    event IdeaVetted(address indexed entrepreneur, uint256 tokenId);
    event InvestmentMade(
        address indexed investor,
        address indexed entrepreneur,
        uint256 tokenId,
        uint256 amount
    );
    event FeeRecipientChanged(address indexed newFeeRecipient);
    event BaseURIChanged(string newBaseURI);

    modifier validEntrepreneur(address entrepreneurAddress) {
        require(
            entrepreneurs[entrepreneurAddress].wallet != address(0),
            "Entrepreneur not registered"
        );
        _;
    }

    modifier onlyInvestor() {
        require(investors[msg.sender], "Caller is not a registered investor");
        _;
    }

    constructor(address feeRecipient, string memory baseURI) ERC1155("") {
        _currentTokenId = 1;
        setFeeRecipient(feeRecipient);
        setBaseURI(baseURI);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return
            string(
                abi.encodePacked(_baseURI, Strings.toString(tokenId), ".json")
            );
    }

    // Register an entrepreneur
    function registerEntrepreneur(address entrepreneurAddress) public {
        require(
            entrepreneurAddress != address(0),
            "Entrepreneur cannot be the zero address"
        );
        require(
            entrepreneurs[entrepreneurAddress].wallet == address(0),
            "Entrepreneur already registered"
        );

        entrepreneurs[entrepreneurAddress] = Entrepreneur(
            entrepreneurAddress,
            false,
            0
        );

        emit EntrepreneurRegistered(entrepreneurAddress);
    }

    // Vet an entrepreneur's idea and issue an NFT
    function vetIdea(address entrepreneurAddress)
        public
        onlyOwner
        validEntrepreneur(entrepreneurAddress)
    {
        require(
            !entrepreneurs[entrepreneurAddress].hasViableIdea,
            "Entrepreneur already has a viable idea"
        );

        entrepreneurs[entrepreneurAddress].hasViableIdea = true;
        entrepreneurs[entrepreneurAddress].tokenId = _currentTokenId;
        _mint(entrepreneurAddress, _currentTokenId, 1, "");
        _currentTokenId = _currentTokenId.add(1);

        emit IdeaVetted(
            entrepreneurAddress,
            entrepreneurs[entrepreneurAddress].tokenId
        );
    }

    // Register an investor
    function registerInvestor(address investorAddress) public {
        require(
            investorAddress != address(0),
            "Investor cannot be the zero address"
        );
        require(!investors[investorAddress], "Investor already registered");

        investors[investorAddress] = true;
    }

    // Invest in an entrepreneur's idea
    function investInIdea(address entrepreneurAddress, uint256 amount)
        public
        payable
        nonReentrant
        validEntrepreneur(entrepreneurAddress)
        onlyInvestor
    {
        require(amount > 0, "Investment amount must be greater than 0");
        require(
            amount <= MAX_INVESTMENT,
            "Investment amount exceeds maximum limit"
        );
        require(
            entrepreneurs[entrepreneurAddress].hasViableIdea,
            "Entrepreneur does not have a viable idea"
        );

        // Calculate fee amount and net investment
        uint256 feeAmount = (amount * FEE_PERCENTAGE) / 10000;
        uint256 netInvestment = amount.sub(feeAmount);

        // Transfer the investment amount and the fee
        (bool success, ) = _feeRecipient.call{value: feeAmount}("");
        require(success, "Fee transfer failed");

        (bool success2, ) = entrepreneurAddress.call{value: netInvestment}("");
        require(success2, "Investment transfer failed");

        // Record the investment
        investments.push(
            Investment(msg.sender, entrepreneurAddress, netInvestment)
        );

        emit InvestmentMade(
            msg.sender,
            entrepreneurAddress,
            entrepreneurs[entrepreneurAddress].tokenId,
            netInvestment
        );
    }

    // Set the fee recipient
    function setFeeRecipient(address newFeeRecipient) public onlyOwner {
        require(
            newFeeRecipient != address(0),
            "Fee recipient cannot be the zero address"
        );
        _feeRecipient = newFeeRecipient;

        emit FeeRecipientChanged(newFeeRecipient);
    }

    // Set the base URI for metadata
    function setBaseURI(string memory newBaseURI) public onlyOwner {
        _baseURI = newBaseURI;

        emit BaseURIChanged(newBaseURI);
    }

    // Withdraw any accidentally sent ETH to the contract
    function withdraw() public payable onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }

    // Fallback function to receive ETH
    receive() external payable {}
}
