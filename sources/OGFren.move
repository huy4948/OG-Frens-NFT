module OGFensNFT::OGFren {

    use std::signer;
    use std::vector;
    use std::string;

    use aptos_framework::account;
    use aptos_framework::aptos_account;
    use aptos_framework::managed_coin;
    use aptos_framework::coin;

    use aptos_token::token;

    const ECOLLECTION_NOT_CREATED: u64 = 0;
    const EINVALID_COLLECTION_OWNER: u64 = 1;
    const EINVALID_VECTOR_LENGTH: u64 = 2;
    const EFREN_NOT_FOUND: u64 = 3;
    const EFRENS_NOT_AVAILABLE: u64 = 4;
    const EINVALID_BALANCE: u64 = 5;

    struct OGFen has store {
        name: vector<u8>,
        description: vector<u8>, 
        max_quantity: u64,
        price: u64,
        available: u64,
        token_data: token::TokenDataId
    }

    struct FrenCollection<phantom CoinType> has key {
        name: vector<u8>,
        description: vector<u8>,
        frens: vector<OGFen>,
        owner: address,
        resource_signer_cap: account::SignerCapability
    }

    public entry fun create_collection<CoinType>(collection_owner: &signer, name: vector<u8>, description: vector<u8>, uri: vector<u8>) {
        let frens = vector::empty<OGFen>();
        let collection_owner_addr = signer::address_of(collection_owner);

        // creating a resource account which would create collection and mint tokens
        let (resource, resource_signer_cap) = account::create_resource_account(collection_owner, name);
        move_to<FrenCollection<CoinType>>(&resource, FrenCollection {name, description, frens, owner: collection_owner_addr,resource_signer_cap});

        // create a collection with the venue name and resource account as the creator
        token::create_collection(
            &resource, // signer
            string::utf8(name), // Name
            string::utf8(description), // Description
            string::utf8(uri), // URI
            3333, // Maximum NFTs
            vector<bool>[false, false, false] // Mutable Config
        )
    }

    public entry fun create_fren<CoinType>(collection_owner: &signer, venue_resource: address, name: vector<u8>, description: vector<u8>, uri: vector<u8>, max_quantity: u64, price: u64) acquires FrenCollection {
        assert!(exists<FrenCollection<CoinType>>(venue_resource), ECOLLECTION_NOT_CREATED);
       
        let collection_owner_addr = signer::address_of(collection_owner); 
        let collection_info = borrow_global_mut<FrenCollection<CoinType>>(venue_resource);
        assert!(collection_info.owner == collection_owner_addr, EINVALID_COLLECTION_OWNER);

        let collection_resource_signer = account::create_signer_with_capability(&collection_info.resource_signer_cap);

        // Creating a token data for this particular type of fren which would be used to mint NFTs
        let token_mutability = token::create_token_mutability_config(&vector<bool>[false, false, false, false, false]);

        let token_data = token::create_tokendata(
            &collection_resource_signer,
            string::utf8(collection_info.name), // Collection Name
            string::utf8(name), // Token Name
            string::utf8(description), // Token description
            max_quantity,
            string::utf8(uri), 
            collection_info.owner, // royalty payee address
            100,
            5,
            token_mutability,
            vector<string::String>[],
            vector<vector<u8>>[],
            vector<string::String>[]
        );

        let fren = OGFen {
            name,
            description,
            max_quantity,
            price,
            available: max_quantity, // At the point of creation, max quantity of frens would be equal to available frens
            token_data
        };

        vector::push_back(&mut collection_info.frens, fren);

    }

    public entry fun mint_fren<CoinType>(buyer: &signer, venue_resource: address, name: vector<u8>, quantity: u64) acquires FrenCollection {
        assert!(exists<FrenCollection<CoinType>>(venue_resource), ECOLLECTION_NOT_CREATED);

        let collection_info = borrow_global_mut<FrenCollection<CoinType>>(venue_resource);
        let fren_count = vector::length(&collection_info.frens);

        let i = 0;
        while (i < fren_count) {
            let current = vector::borrow<OGFen>(&collection_info.frens, i);
            if (current.name == name) {
                break
            };
            i = i +1;
        };
        assert!(i != fren_count, EFREN_NOT_FOUND);

        let fren = vector::borrow_mut<OGFen>(&mut collection_info.frens, i);
        assert!(fren.available >= quantity, EFRENS_NOT_AVAILABLE); 

        let total_price = fren.price * quantity;
        coin::transfer<CoinType>(buyer, collection_info.owner, total_price);
        fren.available = fren.available - quantity;

        let collection_resource_signer = account::create_signer_with_capability(&collection_info.resource_signer_cap);

        let buyer_addr = signer::address_of(buyer);

        // the buyer should opt in direct transfer for the NFT to be minted
        token::opt_in_direct_transfer(buyer, true);

        // Mint the NFT to the buyer account
        token::mint_token_to(&collection_resource_signer, buyer_addr, fren.token_data, quantity);
    }

    #[test_only]
    public fun get_resource_account(source: address, seed: vector<u8>)  : address {
        use std::hash;
        use aptos_std::from_bcs;
        use std::bcs;
        let bytes = bcs::to_bytes(&source);
        vector::append(&mut bytes, seed);
        from_bcs::to_address(hash::sha3_256(bytes))
    }

    #[test_only]
    struct FakeCoin {}

    #[test_only]
    public fun initialize_coin_and_mint(admin: &signer, user: &signer, mint_amount: u64) {
        let user_addr = signer::address_of(user);
        managed_coin::initialize<FakeCoin>(admin, b"fake", b"F", 9, false);
        aptos_account::create_account(user_addr);
        managed_coin::register<FakeCoin>(user);
        managed_coin::mint<FakeCoin>(admin, user_addr, mint_amount); 
    }

    
    #[test(collection_owner = @0x4, buyer = @0x5, module_owner = @OGFensNFT)]
    public fun can_create_collection(collection_owner: signer, buyer: signer, module_owner: signer) acquires FrenCollection {
        let venue_name = b"Eminem Concert";
        let venue_description = b"This concert would be lit";
        let venue_uri = b"https://dummy.com";
        let collection_owner_addr = signer::address_of(&collection_owner);
        let buyer_addr = signer::address_of(&buyer);

        let initial_mint_amount: u64 = 10000;
        initialize_coin_and_mint(&module_owner, &buyer, initial_mint_amount);
        aptos_account::create_account(collection_owner_addr);
        managed_coin::register<FakeCoin>(&collection_owner);

        create_collection<FakeCoin>(&collection_owner, venue_name, venue_description, venue_uri);
        let venue_resource = get_resource_account(collection_owner_addr, venue_name);
        assert!(exists<FrenCollection<FakeCoin>>(venue_resource), ECOLLECTION_NOT_CREATED);


        let ticket_name = b"Front row";
        let ticket_description = b"You can see a lot of people";
        let ticket_uri = b"https://dummyticket.com";
        let ticket_price = 100;
        let max_tickets = 50; 
        create_fren<FakeCoin>(&collection_owner, venue_resource, ticket_name, ticket_description, ticket_uri, max_tickets ,ticket_price);

        let collection_info = borrow_global_mut<FrenCollection<FakeCoin>>(venue_resource);
        assert!(vector::length(&collection_info.frens) == 1, EINVALID_VECTOR_LENGTH);

        mint_fren<FakeCoin>(&buyer, venue_resource, ticket_name, 1);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (initial_mint_amount - ticket_price), EINVALID_BALANCE);
        assert!(coin::balance<FakeCoin>(collection_owner_addr) == (ticket_price), EINVALID_BALANCE);
        
    }

}