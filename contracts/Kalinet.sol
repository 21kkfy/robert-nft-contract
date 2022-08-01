// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// Azuki-labs ERC721A
import "https://github.com/chiru-labs/ERC721A/blob/main/contracts/ERC721A.sol";
// Open-Zeppelin Ownable - modified under the MIT license.
import "./OwnableNR.sol";
// Open-Zeppelin Reentrancy Guard
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// ERC2981 NFT Royalty Standard
import "@openzeppelin/contracts/token/common/ERC2981.sol";
// ERC20 Token Standard
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// Open-Zeppelin Strings Library
import "@openzeppelin/contracts/utils/Strings.sol";
// Open-Zeppelin Merkle Proof
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/*


  _  __     _ _            _   
 | |/ /    | (_)          | |  
 | ' / __ _| |_ _ __   ___| |_ 
 |  < / _` | | | '_ \ / _ \ __|
 | . \ (_| | | | | | |  __/ |_ 
 |_|\_\__,_|_|_|_| |_|\___|\__|
                               
                               

 */
/// @title Kalinet ERC721A, Royalty NFT contract.
/// @author Kalinet - Developer Team
/// @notice This contract provides a team mint, a whitelist mint and a public mint.

contract Kalinet is ERC721A, OwnableNR, ReentrancyGuard, ERC2981 {
    using Strings for uint256;
    uint256 public constant MAX_SUPPLY = 8500;
    uint256 public constant TEAM_MINT_AMOUNT = 25;
    /// @dev MAX_SUPPLY_WHITELIST must be declared AFTER TEAM_MINT_AMOUNT to avoid
    /// it being summed up as non-assigned (0).
    uint256 public constant MAX_SUPPLY_WHITELIST = 4000;
    uint256 public constant MAX_WHITELIST_MINT = 10;
    uint256 public constant MAX_PUBLIC_MINT = 20;
    uint256 public constant MAX_WHITELIST_WALLETS = 1000;
    uint256 public constant WHITELIST_SALE_PRICE = 0.5 ether;
    uint256 public constant PUBLIC_SALE_PRICE = 0.6 ether;
    uint96 public royaltyDividend = 1000;
    string private baseTokenUri;
    string public placeholderTokenUri;

    /***********************
     * OTTER WALLETS *
     ***********************/
    address payable ownerWallet = payable(msg.sender);
    address payable adminWallet = payable(msg.sender);
    //deploy smart contract, toggle WL, toggle WL when done, toggle publicSale
    //2 days later toggle reveal
    // Start the contract in stopped state.
    bool public isRevealed = true;
    bool public publicSale = false;
    bool public whiteListSale = false;
    bool public pause = true;
    bool public teamMinted = false;

    mapping(address => uint256) public totalPublicMint;
    mapping(address => uint256) public totalWhitelistMint;

    /*************
     * MODIFIERS *
     *************/

    /*
     * msg.sender can NOT be a contract.
     */
    modifier callerIsUser() {
        require(
            tx.origin == msg.sender,
            "Kalinet :: Cannot be called by a contract"
        );
        _;
    }
    /// @notice As an end-user, when the pause is set to 'false'
    /// you are allowed to access whitelist mint and public mint.
    modifier notPaused() {
        require(!pause, "Kalinet :: Contract is paused.");
        _;
    }

    // Mainnet JSON: QmRzBmU2ggazKXvDQqHq4kyQtjizsnQiEYU8PATzvo14eT
    constructor() ERC721A("Kalinet", "$DSN") {}

    /*********************
     * MINTING FUNCTIONS *
     *********************/

    /// @notice This is where the public minting process happens.
    /// @dev 1. This is the mint function available for the non-whitelisted(public) & whitelisted wallets.
    /// @dev 2. Require functions are important especially for this function.
    /// First of all, a modifier checks if the wallet address connecting to this function is a real user
    /// Secondly, There are multiple require functions inside the function that can be understood easily.
    /// @notice Note If you prefer to mint from snowtrace.io you must include the PUBLIC_SALE_PRICE as a parameter given.
    function mint(uint256 _quantity)
        external
        payable
        nonReentrant
        callerIsUser
        notPaused
    {
        require(publicSale, "Kalinet :: Not Yet Active.");
        require(
            (totalSupply() + _quantity) <= MAX_SUPPLY,
            "Kalinet :: Beyond Max Supply"
        );
        require(
            (totalPublicMint[msg.sender] + _quantity) <= MAX_PUBLIC_MINT,
            "Kalinet :: Minted maximum amount."
        );
        require(
            msg.value >= (PUBLIC_SALE_PRICE * _quantity),
            "Kalinet :: Not enough AVAX. "
        );
        totalPublicMint[msg.sender] += _quantity;

        _safeMint(msg.sender, _quantity);
    }

    /// @notice This is where the whitelist minting process happens.
    /// @dev 1. This is the mint function available for the whitelisted wallets.
    /// @dev 2. Require functions are important especially for this function.
    /// First of all, a modifier checks if the wallet address connecting to this function is a real user
    /// Secondly, There is also a modifier that checks to make sure the calling address is whitelisted.
    /// Lastly, There are multiple require functions inside the function that can be understood easily.
    /// @notice IMPORTANT If you prefer to mint from snowtrace.io you must include the WHITELIST_SALE_PRICE as a parameter given.
    function whitelistMint(uint256 _quantity)
        external
        payable
        nonReentrant
        callerIsUser
        notPaused
    {
        require(whiteListSale, "Kalinet :: White-list minting is on pause");
        require(
            (totalSupply() + _quantity) <= MAX_SUPPLY_WHITELIST,
            "Kalinet :: Cannot mint beyond max supply"
        );
        require(
            (totalWhitelistMint[msg.sender] + _quantity) <= MAX_WHITELIST_MINT,
            "Kalinet :: Cannot mint beyond whitelist max mint!"
        );
        require(
            msg.value >= (WHITELIST_SALE_PRICE * _quantity),
            "Kalinet :: Payment is below the price"
        );
        totalWhitelistMint[msg.sender] += _quantity;
        _safeMint(msg.sender, _quantity);
    }

    /*****************
     * URI FUNCTIONS *
     *****************/

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenUri;
    }

    /// @notice This is the function contract uses to access the metadata, JSON files, for the created images.
    /// This contract uses the gas-saver approach of storing images and JSON files to the IPFS.
    /// The actual images are not stored on the blockchain platform, Avalanche, and stored on the IPFS.
    /// IPFS is a service that is used by most of the smart contracts to reduce the gas fee, it uses decentralized approach.
    /// @param tokenId, tokenId is the UID for an NFT's JSON file from this collection.
    /// @return String this function returns a URI address. Example: "ipfs://cid-for-json-directory/1.json"
    /// IMPORTANT: ipfs://cid-for-json-directory/ there must be a "/" to indicate it's a directory.
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        uint256 trueId = tokenId + 1;

        if (!isRevealed) {
            return placeholderTokenUri;
        }
        //string memory baseURI = _baseURI();
        return
            bytes(baseTokenUri).length > 0
                ? string(
                    abi.encodePacked(baseTokenUri, trueId.toString(), ".json")
                )
                : "";
    }

    /// @notice setTokenUri & setPlaceHolderUri
    /// @dev This is used to set the IPFS URI that will be provided to the
    /// @param _baseTokenUri param is set to baseTokenUri, this is the uri file that contains the IPFS directory.
    function setTokenUri(string memory _baseTokenUri) external onlyOwner {
        baseTokenUri = _baseTokenUri;
    }

    function setPlaceHolderUri(string memory _placeholderTokenUri)
        external
        onlyOwner
    {
        placeholderTokenUri = _placeholderTokenUri;
    }

    /********************
     * TOGGLE FUNCTIONS *
     ********************/

    /// @notice togglePause, toggleWhiteListSale, togglePublicSale, toggleReveal
    /// functions are only accesses by the owner of this contract. Allows the owner wallet to access
    /// @dev Explain to a developer any extra details
    function togglePause() external onlyOwnerAdmin {
        pause = !pause;
    }

    function toggleWhiteListSale() external onlyOwnerAdmin {
        whiteListSale = !whiteListSale;
    }

    function togglePublicSale() external onlyOwnerAdmin {
        publicSale = !publicSale;
    }

    function toggleReveal() external onlyOwnerAdmin {
        isRevealed = !isRevealed;
    }

    /*********************
     * ROYALTY FUNCTIONS *
     *********************/
    // 1. Before sold-out royalty 10%
    // 2. After sold-out royalty 5%
    // 3. Contract only allows royalty fee to be 10% up-most.
    // Note "feeDenominator" is a constant value: 10000
    // -> 1000/10000 = %10

    /**
    @notice Sets the contract-wide royalty info.
     */
    function setRoyaltyInfo(address receiver, uint96 feeBasisPoints)
        external
        onlyOwnerAdmin
    {
        require(
            feeBasisPoints <= 1000,
            "Kalinet-Royalty: Royalty fee can't exceed %10"
        );
        _setDefaultRoyalty(receiver, feeBasisPoints);
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        public
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        //suppress error
        _tokenId;
        return (adminWallet, (_salePrice * royaltyDividend) / 10000);
    }

    /// @inheritdoc	ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC2981, ERC721A)
        returns (bool)
    {
        return
            ERC721A.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    /**********************
     * WITHDRAW FUNCTIONS *
     **********************/

    function withdraw() external payable onlyOwner {
        uint256 fullBalance = address(this).balance;
        require(owner() != address(0));
        _withdraw(owner(), (fullBalance * 100) / 100);
    }

    /**
     * @notice This is an internal function called to withdraw AVAX.
     * @dev This is a private function called via withdraw.
     */
    function _withdraw(address wallet, uint256 amount) private {
        (bool success, ) = wallet.call{value: amount}("");
        require(success, "Kalinet: Transfer failed.");
    }

    /// @notice This function is used to avoid having stuck ERC20 tokens inside the contract.
    /// @dev Withdraw a token
    /// @param _token Withdraw stuck tokens from the contract to keep it clean.
    function withdrawStuckTokens(address payable _token) public onlyOwner {
        uint256 tokenAmount = IERC20(_token).balanceOf(address(this));

        IERC20(_token).transfer(owner(), tokenAmount);
    }

    /***********************
     * WHITELIST FUNCTIONS *
     ***********************/
    bytes32 private merkleRoot;

    // Kalao
    function isEarlyMinter(
        address _whitelistedAddress,
        bytes32[] calldata _proof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(_whitelistedAddress));
        return MerkleProof.verify(_proof, merkleRoot, leaf);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function getMerkleRoot() external view returns (bytes32) {
        return merkleRoot;
    }

    function prepareContract() external onlyOwnerAdmin {
        transferAdmin(adminWallet);
        _setDefaultRoyalty(msg.sender, uint96(royaltyDividend));
        baseTokenUri = "ipfs://QmY9eD6n4NwgRY67vwMva7RJ4NrcVknvUZYYswxiAdhRv7/";
    }
}
