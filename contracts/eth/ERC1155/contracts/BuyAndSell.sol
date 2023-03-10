
pragma solidity ^0.8.8;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./INFT.sol";
error NotOwner();
error PriceMustBeAboveZero();



contract PriceOFETHTOUSD{

    uint minimalValue = 50;
    
    function PriceFeed() public payable{
        msg.value > minimalValue;
    }

    function GetLastestPrice() public view returns (uint){
        AggregatorV3Interface Price = AggregatorV3Interface(0x8A753747A1Fa494EC906cE90E9f37563A8AF630e);
        (,int256 price,,,) = Price.latestRoundData();
        return uint (price * 1e18);
    }

    function GetValueInDOllar(uint _ethAmount) public view returns(uint){
        uint ValuePrice = GetLastestPrice();
        uint AmountinDollars =(ValuePrice * _ethAmount) /1e18;
        return AmountinDollars;
    }

}


contract BuyAndSell is ReentrancyGuard, PriceOFETHTOUSD {
    // -----------  VAR --------------
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;

    Counters.Counter private productId;
    address public NFTAddress;
    INFT getNFT;
    address public platFormAddress;
    uint256 private platformFee;
    mapping(uint256 => PRODUCT) private IdToProduct;
    mapping(address => uint256[]) private UserToSoldNFTs;
    EnumerableSet.UintSet private _tokensForPackSale; // all ids for pack sale
    mapping(uint256 => uint256) public tokensForPackSaleBalances; // id => balance (amount for single sale)
    uint256 public packPrice;
    // nft => tokenId => offerer address => offer struct
    mapping(address => mapping(uint256 => mapping(address => OfferNFT)))
        private offerNfts;


    struct OfferNFT {
        uint256 tokenId;
        address offerer;
        uint256 offerPrice;
        bool accepted;
    }

    struct NFT {
        uint256 id;
        address owner;
        bool onSell;
    }

    struct PRODUCT {
        uint256 id;
        uint256 itemId;
        uint256 price;
        bool isSold;
        address seller;
    }
    // ---------------  Events ------------
    event NFTIsOnSale(
        uint256 indexed productId,
        uint256 indexed nftId,
        uint256 price,
        address seller
    );
    event NFTsSold(
        uint256 indexed productId,
        uint256 indexed nftId,
        uint256 price,
        address buyer
    );

    event NFTCanceled(
        uint256 indexed productId,
        uint256 indexed itemId,
        address indexed seller
    );

    event OfferredNFT(
        uint256 indexed tokenId,
        uint256 offerPrice,
        address indexed offerer
    );
    event CanceledOfferredNFT(
        uint256 indexed tokenId,
        uint256 offerPrice,
        address indexed offerer
    );
    event AcceptedNFT(
        uint256 indexed tokenId,
        uint256 offerPrice,
        address offerer,
        address indexed nftOwner
    );

    constructor(address _NFTAddress,
                uint256 _platformFee,
                address _feeRecipient) {
        getNFT = INFT(_NFTAddress);
        platformFee = _platformFee;
        platFormAddress = _feeRecipient;
        NFTAddress = _NFTAddress;

    }

    // Offer listed NFT
    function offerNFT(
        uint256 _tokenId,
        uint256 _productId,
        uint256 _offerPrice,
        address _offerer
    ) external{
        require(_offerPrice > 0, "price can not 0");
        
        NFT nft = getNFT.getNFTDetails(_tokenId);
        PRODUCT memory product = IdToProduct[_productId];
        require(
            product.itemId == _tokenId,
            "nft is not listed"
        );
        require(
            product.seller != address(0) && !product.isSold,
            "nft is already sold out"
        );
                
                
        IERC20(NFTAddress).transferFrom(
            msg.sender,
            product.seller,
            _offerPrice
        );

        offerNfts[NFTAddress][_tokenId][msg.sender] = OfferNFT({
            tokenId: nft.tokenId,
            offerer: msg.sender,
            offerPrice: _offerPrice,
            accepted: false
        });


        emit OfferredNFT(
            _tokenId,
            _offerPrice,
            msg.sender
        );
    }

    // Offerer cancel offerring
    function cancelOfferNFT(uint256 _tokenId) external
    {   
        OfferNFT memory offer = offerNfts[NFTAddress][_tokenId][_offerer];
        require(
            offer.offerPrice > 0 && offer.offerer != address(0),
            "not offerred nft"
        );
        PRODUCT memory product = IdToProduct[_productId];
        require(
            product.itemId == _tokenId,
            "nft is not listed"
        );
        require(
            product.seller != address(0) && !product.isSold,
            "nft is already sold out"
        );

        OfferNFT memory offer = offerNfts[NFTAddress][_tokenId][msg.sender];
        require(offer.offerer == msg.sender, "not offerer");
        require(!offer.accepted, "offer already accepted");
        delete offerNfts[NFTAddress][_tokenId][msg.sender];
        IERC20(offer.payToken).transfer(offer.offerer, offer.offerPrice);
        emit CanceledOfferredNFT(
            offer.tokenId,
            offer.offerPrice,
            msg.sender
        );
    }

    // listed NFT owner accept offerring
    function acceptOfferNFT(
        uint256 _tokenId,
        address _offerer,
        address[] memory _Royaltyrecipients, uint256[] memory _Royaltyamounts
    ) external
    {
        

        OfferNFT memory offer = offerNfts[NFTAddress][_tokenId][_offerer];
        require(
            offer.offerPrice > 0 && offer.offerer != address(0),
            "not offerred nft"
        );

        NFT nft = getNFT.getNFTDetails(_tokenId);
        PRODUCT memory product = IdToProduct[_productId];
        require(
            product.itemId == _tokenId,
            "nft is not listed"
        );
        require(
            product.seller != address(0) && !product.isSold,
            "nft is already sold out"
        );

        require(
            product.seller == msg.sender,
            "seller is not the owner"
        );
        OfferNFT storage offer = offerNfts[NFTAddress][_tokenId][_offerer];
        require(!product.isSold, "already sold");
        require(!offer.accepted, "offer already accepted");

        product.sold = true;
        offer.accepted = true;

        uint256 offerPrice = offer.offerPrice;
        uint256 totalPrice = offerPrice;

        IERC20 payToken = IERC20(NFTAddress);
        NFT nft = getFreeNFT.getNFTDetails(itemId);
        uint royalties = _Royaltyrecipients.length;
        for (uint r = 0; r <= royalties; r++){
            address royaltyRecipient = _Royaltyrecipients[r];
            uint256 royaltyFee = _Royaltyamounts[r];
            if (royaltyFee > 0) {
                uint256 royaltyTotal = calculateRoyalty(royaltyFee, _price);
                // Transfer royalty fee to collection owner
                payToken.transfer(royaltyRecipient, royaltyTotal);
                totalPrice -= royaltyTotal;
            }

        }


        // Calculate & Transfer platfrom fee
        uint256 platformFeeTotal = calculatePlatformFee(offerPrice);
        payToken.transfer(feeRecipient, platformFeeTotal);

        // Transfer to seller
        payToken.transfer(product.seller, totalPrice - platformFeeTotal);

        // Transfer NFT to offerer
        IERC1155(NFTAddress).safeTransferFrom(
            address(this),
            offer.offerer,
            product.itemId,
            1,
            ""
        );

        emit AcceptedNFT(
            offer.tokenId,
            offer.offerPrice,
            offer.offerer,
            product.seller
        );
    }


    // -------------------- MARKETPLACE ----------------
    // put Product to sell = >
    // require price > 0
    
    function putProductToSell(uint256 _itemId, uint256 _price)
        external
        nonReentrant
    {
        require(_price > 0, "Price = 0");
        uint256 pricePlusFees = _price + (_price / 100) * 1;
        productId.increment();
        uint256 currentProductId = productId.current();
        getNFT.changeOwner(address(this), _itemId);
        getNFT.changeState(_itemId);

        IdToProduct[currentProductId].id = currentProductId;
        IdToProduct[currentProductId].price = pricePlusFees;
        IdToProduct[currentProductId].isSold = false;
        IdToProduct[currentProductId].seller = msg.sender;
        IdToProduct[currentProductId].itemId = _itemId;
        IERC1155(NFTAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _itemId,
            1,
            ""
        );
        emit NFTIsOnSale(currentProductId, _itemId, pricePlusFees, msg.sender);
    }

    // our contract can recieve ERC1155 tokens
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    // ------------ Normal Buy Method -----------
    // require msg.value => price
    // product still availaibe
    function purchaseProduct(uint256 _productId, address[] memory _Royaltyrecipients, uint256[] memory _Royaltyamounts) external payable nonReentrant {
        uint256 price = IdToProduct[_productId].price;
        bool isSold = IdToProduct[_productId].isSold;
        require(msg.value >= price, "amount < price");
        require(isSold == false, "Sold out");
        //------------------------
        // ANOTHER WAY OF ROYALTY
        //------------------------
        // uint256 seller_share = msg.value - ((msg.value * 1) / 100);
        // address seller = payable(IdToProduct[_productId].seller);
        // //paiment send eth to seller and owner
        // (bool sent, ) = seller.call{value: seller_share}("");
        // require(sent, "failed");
        // (bool sent2, ) = platFormAddress.call{
        //     value: (msg.value - seller_share)
        // }("");
        // require(sent2, "failed");
        // -------
        uint256 itemId = IdToProduct[_productId].itemId;
        
        
        //--------------------
        // royalty calculation
        //--------------------
        uint256 totalPrice = price;
        uint royalties = _Royaltyrecipients.length;
        // NFT nft = getNFT.getNFTDetails(itemId);
        for (r = 0; r <= royalties; r++){
            address royaltyRecipient = _Royaltyrecipients[r];
            uint256 royaltyFee = _Royaltyamounts[r];
            if (royaltyFee > 0) {
                uint256 royaltyTotal = calculateRoyalty(royaltyFee, price);
                // Transfer royalty fee to receivers
                IERC20(NFTAddress).transferFrom(
                    msg.sender,
                    royaltyRecipient,
                    royaltyTotal
                );
                totalPrice -= royaltyTotal;
            }
        }

        // Transfer to nft owner
            IERC20(NFTAddress).transferFrom(
                msg.sender,
                seller,
                totalPrice - platformFeeTotal
            );


        // Calculate & Transfer platfrom fee
        uint256 platformFeeTotal = calculatePlatformFee(price);
        IERC20(NFTAddress).transferFrom(
            msg.sender,
            feeRecipient,
            platformFeeTotal
        );
        //--------------------
        //--------------------

        getNFT.changeOwner(msg.sender, itemId);
        getNFT.changeState(itemId);
        
        UserToSoldNFTs[seller].push(itemId);
        IdToProduct[_productId].isSold = true;
        // transfer NFT to buyer
        IERC1155(NFTAddress).safeTransferFrom(
            address(this),
            msg.sender,
            itemId,
            1,
            ""
        );
        emit NFTsSold(_productId, itemId, seller_share, msg.sender);
    }

    // ----------- Cancel Sell --------------

    function cancelSell(uint256 _productId) external {
        PRODUCT memory product = IdToProduct[_productId];
        require(product.seller == msg.sender, "not S");
        require(product.isSold == false, "sold out");
        uint256 itemId = product.itemId;
        getNFT.changeOwner(msg.sender, itemId);
        getNFT.changeState(itemId);
        IdToProduct[_productId].isSold = true;
        IERC1155(NFTAddress).safeTransferFrom(
            address(this),
            msg.sender,
            itemId,
            1,
            ""
        );
        emit NFTCanceled(_productId, itemId, msg.sender);
    }

    // ----------- Pack functionalities ---------
    // usefull for launchpad feature
    // ------------------------------------------

    function setPackPrice(uint256 price) external onlyOwner {
        packPrice = price;
    }

    function setForPackSale(uint256 id, uint256 amount) external onlyOwner {
        require(amount > 0);
        require(packPrice != 0, "Pack price must be set");
        require(
            amount <= tokensHeldBalances[id],
            "Amount exceeds held amount available"
        );

        // Removing from tokensHeld
        tokensHeldBalances[id] -= amount;
        if (tokensHeldBalances[id] < 1) {
            _tokensHeld.remove(id);
        }

        // Adding to tokensForPackSale
        if (tokensForPackSaleBalances[id] == 0) {
            _tokensForPackSale.add(id);
        }
        tokensForPackSaleBalances[id] += amount;
    }

    function removeFromPackSale(uint256 id, uint256 amount) external onlyOwner {
        require(amount > 0);
        require(tokensForPackSaleBalances[id] > 0, "Not on sale");
        require(
            tokensForPackSaleBalances[id] >= amount,
            "Amount exceeds token set for sale"
        );

        // Removing from tokensForPackSale
        tokensForPackSaleBalances[id] -= amount;
        if (tokensForPackSaleBalances[id] == 0) {
            _tokensForPackSale.remove(id);
        }

        // Adding back to tokensHeld
        if (tokensHeldBalances[id] == 0) {
            // if new token
            _tokensHeld.add(id);
        }
        tokensHeldBalances[id] += amount;
    }

    function buyPack() public payable { // buy 4 random nfts
        uint256 totalNFTsAvailable; // sums together each id's balance
        for (uint256 i = 0; i < _tokensForPackSale.length(); i++) {
            totalNFTsAvailable += tokensForPackSaleBalances[
                _tokensForPackSale.at(i)
            ];
        }
        require(msg.value == packPrice, "Ether sent does not match price");
        require(totalNFTsAvailable >= 4, "At least 4 nfts must be available");
        uint256 preHash = (block.number * block.difficulty) / block.timestamp;
        uint256[] memory selectedIds = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            // Equal chance of unique tokens, can be duplicate
            uint256 selectedId =
                _tokensForPackSale.at(
                    uint256(keccak256(abi.encode(preHash + i))) %
                        _tokensForPackSale.length()
                );

            tokensForPackSaleBalances[selectedId] -= 1;
            uint256 fromBalance = _balances[selectedId][address(this)];
            require(fromBalance >= 1, "Insufficient balance for transfer");
            if (tokensForPackSaleBalances[selectedId] == 0) {
                _tokensForPackSale.remove(selectedId);
            }
            // Transfer
            _balances[selectedId][address(this)] = fromBalance - 1;
            _balances[selectedId][msg.sender] += 1;

            selectedIds[i] = selectedId;
        }
        uint256[] memory counts = new uint256[](4);
        counts[0] = 1;
        counts[1] = 1;
        counts[2] = 1;
        counts[3] = 1;
        emit TransferBatch(
            msg.sender,
            address(this),
            msg.sender,
            selectedIds,
            counts
        );
    }

    modifier isOwner(
        address _nft,
        uint256 _tokenId,
        address spender
    ) {
        IERC721 nft = IERC1155(_nft);
        address owner = nft.ownerOf(_tokenId);
        if (spender != owner) {
            revert NotOwner();
        }
        _;
    }

    function updateListing(
        address _nft,
        uint256 _tokenId,
        uint256 newPrice,
        uint256 _productId
    )
        external nonReentrant isOwner(_nft, _tokenId, msg.sender)
    {
        if (newPrice == 0) {
            revert PriceMustBeAboveZero();
        }

        NFT nft = getNFT.getNFTDetails(_tokenId);
        PRODUCT memory product = IdToProduct[_productId];
        require(
            product.itemId == _tokenId,
            "nft is not listed"
        );

        product.price = newPrice;
        emit NFTIsOnSale(_productId, product.itemId, newPrice, msg.sender);
    }

    function purchaseBatchProduct(uint256[] memory productIds, address[] memory _Royaltyrecipients, uint256[] memory _Royaltyamounts) public payable {
        
        for (p = 0; p <= productIds.length; p++){
            uint256 price = IdToProduct[_productId[p]].price;
            bool isSold = IdToProduct[_productId[p]].isSold;
            require(msg.value >= price, "amount < price");
            require(isSold == false, "Sold out");
            //------------------------
            // ANOTHER WAY OF ROYALTY
            //------------------------
            // uint256 seller_share = msg.value - ((msg.value * 1) / 100);
            // address seller = payable(IdToProduct[_productId[p]].seller);
            // //paiment send eth to seller and owner
            // (bool sent, ) = seller.call{value: seller_share}("");
            // require(sent, "failed");
            // (bool sent2, ) = platFormAddress.call{
            //     value: (msg.value - seller_share)
            // }("");
            // require(sent2, "failed");
            // -------
            uint256 itemId = IdToProduct[_productId[p]].itemId;
            
            
            //--------------------
            // royalty calculation
            //--------------------
            uint256 totalPrice = price;
            uint royalties = _Royaltyrecipients.length;
            // NFT nft = getNFT.getNFTDetails(itemId);
            for (r = 0; r <= royalties; r++){
                address royaltyRecipient = _Royaltyrecipients[r];
                uint256 royaltyFee = _Royaltyamounts[r];
                if (royaltyFee > 0) {
                    uint256 royaltyTotal = calculateRoyalty(royaltyFee, price);
                    // Transfer royalty fee to receivers
                    IERC20(NFTAddress).transferFrom(
                        msg.sender,
                        royaltyRecipient,
                        royaltyTotal
                    );
                    totalPrice -= royaltyTotal;
                }
            }

            // Transfer to nft owner
            IERC20(NFTAddress).transferFrom(
                msg.sender,
                seller,
                totalPrice - platformFeeTotal
            );


            // Calculate & Transfer platfrom fee
            uint256 platformFeeTotal = calculatePlatformFee(price);
            IERC20(NFTAddress).transferFrom(
                msg.sender,
                feeRecipient,
                platformFeeTotal
            );

            //--------------------
            
            getNFT.changeOwner(msg.sender, itemId);
            getNFT.changeState(itemId);
            UserToSoldNFTs[seller].push(itemId);
            IdToProduct[_productId[p]].isSold = true;
            emit NFTsSold(_productId[p], itemId, seller_share, msg.sender);
        }


        uint256[] product_amounts = nft.gettokensHeldBalances(productIds);

        IERC1155(NFTAddress).safeBatchTransferFrom(
            address(this),
            msg.sender,
            productIds,
            product_amounts,
            ""
        );

        emit TransferBatch(
            msg.sender,
            address(this),
            msg.sender,
            productIds,
            product_amounts
        );
    }

    // Withdraw ether from contract.
    function withdraw() external onlyOwner {
        require(address(this).balance > 0, "Balance must be positive");
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success == true);
    }

    // ----------- VIEWS---------

    // Enumeration of held tokens

    function getTokenForPackSaleByIndex(uint256 index)
        public
        view
        returns (uint256)
    {
        return _tokensForPackSale.at(index);
    }

    function getTokensForPackSaleSize() public view returns (uint256) {
        return _tokensForPackSale.length();
    }


    // get user Sold Product

    function getUserSoldProducts(address _user)
        external
        view
        returns (uint256[] memory)
    {
        return UserToSoldNFTs[_user];
    }

    // get detail of a product

    function getProductDetail(uint256 _productId)
        external
        view
        returns (PRODUCT memory)
    {
        return IdToProduct[_productId];
    }

    function getUserOnSellNFTs(address _user) external view returns(PRODUCT[] memory){
        uint totalProducts = productId.current();
        uint userProductCounter  = 0 ;
        uint256 currentIndex = 0;
        // get length
        for (uint256 i = 1; i <= totalProducts; i++) {
            if (IdToProduct[i].seller == _user && IdToProduct[i].isSold == false) {
                userProductCounter += 1;
            }
        }
        PRODUCT[] memory products = new PRODUCT[](userProductCounter);

        for (uint256 i = 1; i <= totalProducts; i++) {
            if (IdToProduct[i].seller == _user && IdToProduct[i].isSold == false) {
                PRODUCT storage currentProduct = IdToProduct[i];
                products[currentIndex] = currentProduct;
                currentIndex += 1;
            }
        }
        return products;
    }

    // get sold product

    function getUserSoldProduct(address _user) external view returns(PRODUCT[] memory){
        uint totalProducts = productId.current();
        uint userProductCounter  = 0 ;
        uint256 currentIndex = 0;
        // get length
        for (uint256 i = 1; i <= totalProducts; i++) {
            if (IdToProduct[i].seller == _user && IdToProduct[i].isSold == true) {
                userProductCounter += 1;
            }
        }
        PRODUCT[] memory products = new PRODUCT[](userProductCounter);

        for (uint256 i = 1; i <= totalProducts; i++) {
            if (IdToProduct[i].seller == _user && IdToProduct[i].isSold == true) {
                PRODUCT storage currentProduct = IdToProduct[i];
                products[currentIndex] = currentProduct;
                currentIndex += 1;
            }
        }
        return products;
    }

    function getTotalProductCreated() external view returns (uint256) {
        return productId.current();
    }

    function calculateRoyalty(uint256 _royalty, uint256 _price)
        public
        pure
        returns (uint256)
    {
        return (_price * _royalty) / 10000;
    }

    function calculatePlatformFee(uint256 _price)
        public
        view
        returns (uint256)
    {
        return (_price * platformFee) / 10000;
    }
}
