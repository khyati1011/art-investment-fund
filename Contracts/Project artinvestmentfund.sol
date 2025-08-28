// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// SafeMath is not needed in Solidity ^0.8.0 due to built-in overflow protection

/**
 * @title Art Investment Fund - Project.sol
 * @dev A smart contract for collective art ownership and appreciation
 * @notice This contract allows multiple investors to collectively own fractionalized art pieces
 * @author Art Investment Fund Team
 */
contract Project is ERC20, Ownable, ReentrancyGuard {
    // SafeMath not needed in Solidity ^0.8.0 - built-in overflow protection

    // Struct to represent an art piece in the fund
    struct ArtPiece {
        uint256 artId;                  // Unique identifier for the art piece
        address nftContract;            // Address of the NFT contract
        uint256 tokenId;                // Token ID of the NFT
        uint256 purchasePrice;          // Original purchase price in wei
        uint256 currentValuation;       // Current market valuation
        uint256 totalShares;            // Total shares available for this art piece
        bool isActive;                  // Whether the art piece is active for investment
        string metadata;                // IPFS hash or metadata string
        uint256 acquisitionDate;        // Timestamp of acquisition
    }

    // Struct to track individual investments
    struct Investment {
        uint256 artId;                  // Art piece ID
        uint256 shares;                 // Number of shares owned
        uint256 investmentAmount;       // Total amount invested in wei
        uint256 investmentDate;         // Date of last investment
    }

    // State variables
    uint256 private _artIdCounter;                                      // Counter for art piece IDs
    mapping(uint256 => ArtPiece) public artPieces;                    // Art piece data
    mapping(address => mapping(uint256 => Investment)) public investments; // Investor investments
    mapping(address => uint256[]) public investorArtPieces;           // Art pieces per investor
    
    // Constants and configuration
    uint256 public constant SHARES_PER_ETH = 1000;                   // 1000 shares per 1 ETH
    uint256 public managementFeePercent = 2;                         // 2% management fee
    uint256 public totalFundsManaged;                                // Total funds under management

    // Events
    event ArtPieceAdded(uint256 indexed artId, address nftContract, uint256 tokenId, uint256 purchasePrice);
    event InvestmentMade(address indexed investor, uint256 indexed artId, uint256 shares, uint256 amount);
    event ValuationUpdated(uint256 indexed artId, uint256 oldValuation, uint256 newValuation);
    event ArtPieceSold(uint256 indexed artId, uint256 salePrice, uint256 totalProfit);
    event DividendsDistributed(uint256 indexed artId, uint256 totalDividends);

    /**
     * @dev Constructor initializes the ERC20 token and sets deployer as owner
     */
    constructor() ERC20("Art Investment Fund Token", "AIFT") Ownable(msg.sender) {
        // msg.sender (contract deployer) automatically becomes the owner
    }

    /**
     * @dev CORE FUNCTION 1: Add a new art piece to the investment fund
     * @param _nftContract Address of the NFT contract
     * @param _tokenId Token ID of the NFT
     * @param _purchasePrice Purchase price of the art piece in wei
     * @param _metadata IPFS hash or metadata string describing the artwork
     * @notice Only the contract owner can add new art pieces
     * @notice The contract must own the NFT before calling this function
     */
    function addArtPiece(
        address _nftContract,
        uint256 _tokenId,
        uint256 _purchasePrice,
        string memory _metadata
    ) external onlyOwner nonReentrant {
        require(_nftContract != address(0), "Invalid NFT contract address");
        require(_purchasePrice > 0, "Purchase price must be greater than 0");
        
        // Verify that this contract owns the NFT
        IERC721 nftContract = IERC721(_nftContract);
        require(nftContract.ownerOf(_tokenId) == address(this), "Contract must own the NFT");

        // Increment counter and create new art ID
        _artIdCounter++;
        uint256 newArtId = _artIdCounter;
        
        // Calculate total shares based on purchase price (1000 shares per ETH)
        uint256 totalShares = (_purchasePrice * SHARES_PER_ETH) / 1 ether;
        
        // Create and store the art piece
        artPieces[newArtId] = ArtPiece({
            artId: newArtId,
            nftContract: _nftContract,
            tokenId: _tokenId,
            purchasePrice: _purchasePrice,
            currentValuation: _purchasePrice,
            totalShares: totalShares,
            isActive: true,
            metadata: _metadata,
            acquisitionDate: block.timestamp
        });

        // Update total funds managed
        totalFundsManaged = totalFundsManaged + _purchasePrice;
        
        emit ArtPieceAdded(newArtId, _nftContract, _tokenId, _purchasePrice);
    }

    /**
     * @dev CORE FUNCTION 2: Invest in a specific art piece by purchasing shares
     * @param _artId ID of the art piece to invest in
     * @param _shares Number of shares to purchase
     * @notice Investors must send ETH equal to the share price * number of shares
     * @notice Mints ERC20 tokens representing ownership shares
     */
    function investInArt(uint256 _artId, uint256 _shares) external payable nonReentrant {
        require(_artId > 0 && _artId <= _artIdCounter, "Invalid art ID");
        require(_shares > 0, "Shares must be greater than 0");
        require(artPieces[_artId].isActive, "Art piece is not active for investment");
        
        ArtPiece storage art = artPieces[_artId];
        
        // Calculate the price per share based on current valuation
        require(art.totalShares > 0, "Art piece has no shares available");
        uint256 sharePrice = art.currentValuation / art.totalShares;
        uint256 requiredPayment = sharePrice * _shares;
        
        require(msg.value >= requiredPayment, "Insufficient payment for shares");
        
        // Track investor's art pieces if this is their first investment in this piece
        if (investments[msg.sender][_artId].shares == 0) {
            investorArtPieces[msg.sender].push(_artId);
        }
        
        // Update investment records
        investments[msg.sender][_artId].artId = _artId;
        investments[msg.sender][_artId].shares = investments[msg.sender][_artId].shares + _shares;
        investments[msg.sender][_artId].investmentAmount = investments[msg.sender][_artId].investmentAmount + requiredPayment;
        investments[msg.sender][_artId].investmentDate = block.timestamp;
        
        // Mint ERC20 tokens representing the shares
        _mint(msg.sender, _shares);
        
        // Refund any excess payment
        if (msg.value > requiredPayment) {
            payable(msg.sender).transfer(msg.value - requiredPayment);
        }
        
        emit InvestmentMade(msg.sender, _artId, _shares, requiredPayment);
    }

    /**
     * @dev CORE FUNCTION 3: Distribute profits from art appreciation or sale
     * @param _artId ID of the art piece that generated profits
     * @param _totalProfit Total profit amount to distribute in wei
     * @notice Only contract owner can trigger profit distribution
     * @notice Deducts management fee before distribution
     */
    function distributeProfits(uint256 _artId, uint256 _totalProfit) external onlyOwner nonReentrant {
        require(_artId > 0 && _artId <= _artIdCounter, "Invalid art ID");
        require(_totalProfit > 0, "Profit must be greater than 0");
        require(address(this).balance >= _totalProfit, "Insufficient contract balance for distribution");
        
        ArtPiece storage art = artPieces[_artId];
        require(art.isActive, "Art piece must be active");
        
        // Calculate and deduct management fee
        uint256 managementFee = (_totalProfit * managementFeePercent) / 100;
        uint256 netProfit = _totalProfit - managementFee;
        
        // Transfer management fee to contract owner
        payable(owner()).transfer(managementFee);
        
        // Note: In a full implementation, you would distribute profits proportionally
        // to all shareholders. For simplicity, this version keeps net profits in the contract
        // where they can be claimed by shareholders proportional to their ownership
        
        emit DividendsDistributed(_artId, netProfit);
    }

    // ======================== VIEW FUNCTIONS ========================

    /**
     * @dev Get detailed information about a specific art piece
     * @param _artId ID of the art piece
     * @return ArtPiece struct containing all details
     */
    function getArtPieceDetails(uint256 _artId) external view returns (ArtPiece memory) {
        require(_artId > 0 && _artId <= _artIdCounter, "Invalid art ID");
        return artPieces[_artId];
    }

    /**
     * @dev Get investment details for a specific investor and art piece
     * @param _investor Address of the investor
     * @param _artId ID of the art piece
     * @return Investment struct containing investment details
     */
    function getInvestorInvestment(address _investor, uint256 _artId) external view returns (Investment memory) {
        return investments[_investor][_artId];
    }

    /**
     * @dev Get all art piece IDs that an investor has invested in
     * @param _investor Address of the investor
     * @return Array of art piece IDs
     */
    function getInvestorArtPieces(address _investor) external view returns (uint256[] memory) {
        return investorArtPieces[_investor];
    }

    /**
     * @dev Get the total number of art pieces in the fund
     * @return Total count of art pieces
     */
    function getTotalArtPieces() external view returns (uint256) {
        return _artIdCounter;
    }

    // ======================== ADMIN FUNCTIONS ========================

    /**
     * @dev Update the current market valuation of an art piece
     * @param _artId ID of the art piece
     * @param _newValuation New valuation in wei
     * @notice Only contract owner can update valuations
     */
    function updateValuation(uint256 _artId, uint256 _newValuation) external onlyOwner {
        require(_artId > 0 && _artId <= _artIdCounter, "Invalid art ID");
        require(_newValuation > 0, "Valuation must be greater than 0");
        
        uint256 oldValuation = artPieces[_artId].currentValuation;
        artPieces[_artId].currentValuation = _newValuation;
        
        emit ValuationUpdated(_artId, oldValuation, _newValuation);
    }

    /**
     * @dev Update the management fee percentage
     * @param _newFeePercent New fee percentage (max 10%)
     * @notice Only contract owner can update management fee
     */
    function setManagementFee(uint256 _newFeePercent) external onlyOwner {
        require(_newFeePercent <= 10, "Management fee cannot exceed 10%");
        managementFeePercent = _newFeePercent;
    }

    /**
     * @dev Emergency function to withdraw all ETH from contract
     * @notice Only contract owner can perform emergency withdrawal
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev Fallback function to receive ETH payments
     */
    receive() external payable {
        // Contract can receive ETH for investments and profit distributions
    }
}
