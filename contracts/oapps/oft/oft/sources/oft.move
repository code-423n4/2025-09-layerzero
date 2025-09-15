/// Omnichain Fungible Token (OFT) Implementation
///
/// This module provides a comprehensive implementation of LayerZero's Omnichain Fungible Token (OFT)
/// standard, enabling seamless cross-chain token transfers with advanced composability features.
module oft::oft;

use call::{call::{Call, Void}, call_cap::CallCap};
use endpoint_v2::{
    endpoint_quote::QuoteParam as EndpointQuoteParam,
    endpoint_send::SendParam as EndpointSendParam,
    endpoint_v2::{Self, EndpointV2},
    lz_receive::LzReceiveParam,
    messaging_channel::MessagingChannel,
    messaging_composer::ComposeQueue,
    messaging_fee::MessagingFee,
    messaging_receipt::MessagingReceipt,
    utils
};
use oapp::oapp::{AdminCap, OApp};
use oft::{
    oft_compose_msg_codec,
    oft_fee::{Self, OFTFee},
    oft_fee_detail::{Self, OFTFeeDetail},
    oft_limit::{Self, OFTLimit},
    oft_msg_codec::{Self, OFTMessage},
    oft_receipt::{Self, OFTReceipt},
    oft_send_context::{Self, OFTSendContext},
    oft_sender::OFTSender,
    rate_limiter::{Self, RateLimiter},
    send_param::SendParam
};
use oft_composer_common::oft_composer_registry::OFTComposerRegistry;
use std::u64;
use sui::{balance::{Self, Balance}, clock::Clock, coin::{Self, Coin, CoinMetadata, TreasuryCap}, event, sui::SUI};
use utils::bytes32::{Self, Bytes32};
use zro::zro::ZRO;

// === Errors ===

const EComposeMsgNotAllowed: u64 = 1;
const EComposeMsgRequired: u64 = 2;
const EInsufficientBalance: u64 = 3;
const EInvalidSendContext: u64 = 4;
const EInvalidComposeQueue: u64 = 5;
const EInvalidLocalDecimals: u64 = 6;
const EPaused: u64 = 7;
const EPauseUnchanged: u64 = 8;
const ESlippageExceeded: u64 = 9;

// === Constants ===

/// Message type for basic token transfers without compose functionality
const SEND_TYPE: u16 = 1;
/// Message type for token transfers with compose functionality
const SEND_AND_CALL_TYPE: u16 = 2;

// === Structs ===

/// Omnichain Fungible Token (OFT) - Core contract enabling seamless cross-chain token transfers.
public struct OFT<phantom T> has key, store {
    /// Unique identifier for this OFT instance
    id: UID,
    /// Core omnichain application functionality - handles peer management, messaging, and configuration
    oapp: OApp,
    /// Capability granting this OFT authorization to make cross-chain calls via LayerZero
    oft_cap: CallCap,
    /// Token management strategy determining mint/burn vs escrow/release behavior
    treasury: OFTTreasury<T>,
    /// Address reference to the coin metadata object for this token type
    coin_metadata: address,
    /// Multiplier for converting between local decimals and shared decimals (10^(local-shared))
    decimal_conversion_rate: u64,
    /// Standardized decimal precision used for cross-chain transfers (≤ local decimals)
    shared_decimals: u8,
    /// Emergency pause state - when true, blocks all send/receive operations
    paused: bool,
    /// Manages fee configurations & fee application logic on sending
    fee: OFTFee,
    /// Manages ratelimit settings and inbound/outbound transfer flow control by token amount
    inbound_rate_limiter: RateLimiter,
    outbound_rate_limiter: RateLimiter,
}

/// Token management strategy defining how cross-chain transfers handle token supply.
public enum OFTTreasury<phantom T> has store {
    /// Standard OFT that mints/burns tokens using treasury capability.
    OFT {
        /// Treasury capability granting mint/burn privileges for the token type T
        treasury_cap: TreasuryCap<T>,
    },
    /// Adapter OFT that escrows/releases existing tokens from a balance pool.
    OFTAdapter {
        /// Token balance pool used for escrow (outbound) and release (inbound) operations
        escrow: Balance<T>,
    },
}

// === Events ===

public struct OFTCreatedEvent has copy, drop {
    /// Address of the OFT package
    oft: address,
    /// Address of the newly created OFT object instance
    oft_object: address,
    /// Address of the associated coin metadata object defining token properties
    coin_metadata: address,
    /// Whether the OFT is an adapter OFT
    is_adapter: bool,
}

public struct OFTSentEvent has copy, drop {
    /// Address of the OFT package
    oft: address,
    /// Unique identifier for this cross-chain message, used for tracking and correlation
    guid: Bytes32,
    /// Destination endpoint ID where tokens are being sent
    dst_eid: u32,
    /// Address that initiated the transfer (sender or capability holder)
    from_address: address,
    /// Actual amount debited from sender in local decimals (after dust removal)
    amount_sent_ld: u64,
    /// Amount that will be credited to recipient in local decimals (equals amount_sent_ld for standard transfers)
    amount_received_ld: u64,
}

public struct OFTReceivedEvent has copy, drop {
    /// Address of the OFT package
    oft: address,
    /// Unique identifier linking this receipt to the original send transaction
    guid: Bytes32,
    /// Source endpoint ID where tokens originated
    src_eid: u32,
    /// Address that will receive the credited tokens
    to_address: address,
    /// Amount credited to recipient in local decimals
    amount_received_ld: u64,
}

public struct PausedSetEvent has copy, drop {
    /// Address of the OFT package
    oft: address,
    /// New pause state - true indicates operations are suspended, false indicates normal operation
    paused: bool,
}

// === OFT Creation ===

/// Creates a standard OFT implementation using the mint/burn treasury model.
///
/// **Parameters**:
/// - `oapp`: Configured OApp instance for cross-chain messaging
/// - `oft_cap`: CallCap granting authorization for LayerZero operations
/// - `treasury_cap`: Treasury capability enabling mint/burn operations
/// - `coin_metadata`: Metadata object defining token properties and decimals
/// - `shared_decimals`: Standardized decimal precision for cross-chain transfers
///
/// **Returns**: Configured OFT instance ready for registration and operation
public fun create_oft<T>(
    oapp: OApp,
    oft_cap: CallCap,
    treasury_cap: TreasuryCap<T>,
    coin_metadata: &CoinMetadata<T>,
    shared_decimals: u8,
    ctx: &mut TxContext,
): OFT<T> {
    create_oft_internal(oapp, oft_cap, coin_metadata, shared_decimals, OFTTreasury::OFT { treasury_cap }, false, ctx)
}

/// Creates an adapter OFT implementation using the escrow/release treasury model.
///
/// **Parameters**:
/// - `oapp`: Configured OApp instance for cross-chain messaging
/// - `oft_cap`: CallCap granting authorization for LayerZero operations
/// - `coin_metadata`: Metadata object defining token properties and decimals
/// - `shared_decimals`: Standardized decimal precision for cross-chain transfers
///
/// **Returns**: Configured OFT adapter instance ready for registration and operation
public fun create_oft_adapter<T>(
    oapp: OApp,
    oft_cap: CallCap,
    coin_metadata: &CoinMetadata<T>,
    shared_decimals: u8,
    ctx: &mut TxContext,
): OFT<T> {
    create_oft_internal(
        oapp,
        oft_cap,
        coin_metadata,
        shared_decimals,
        OFTTreasury::OFTAdapter { escrow: balance::zero<T>() },
        true,
        ctx,
    )
}

// === OFT Core Functions ===

/// Provides a comprehensive quote for OFT transfers without executing the transaction.
///
/// **Parameters**:
/// - `send_param`: Complete transfer parameters including amounts and destination
///
/// **Returns**: Tuple of (transfer_limits, fee_details, amount_receipt)
/// - `OFTLimit`: Transfer restrictions and limits (currently unbounded)
/// - `vector<OFTFeeDetail>`: OFT-specific fees (currently empty)
/// - `OFTReceipt`: Final amounts after dust removal and validation
public fun quote_oft<T>(
    self: &OFT<T>,
    send_param: &SendParam,
    clock: &Clock,
): (OFTLimit, vector<OFTFeeDetail>, OFTReceipt) {
    self.assert_not_paused();

    // Rate limit capacity
    let max_amount_ld = self.outbound_rate_limiter.rate_limit_capacity(send_param.dst_eid(), clock);
    let oft_limit = oft_limit::create(0, max_amount_ld);

    // Fee details
    let (amount_sent_ld, amount_received_ld) = self.debit_view(send_param.amount_ld(), send_param.min_amount_ld());
    let oft_fee_details = if (amount_sent_ld > amount_received_ld) {
        vector[oft_fee_detail::create(amount_sent_ld - amount_received_ld, false, b"OFT Fee".to_ascii_string())]
    } else {
        vector[]
    };

    // Receipt
    let oft_receipt = oft_receipt::create(amount_sent_ld, amount_received_ld);

    (oft_limit, oft_fee_details, oft_receipt)
}

/// Quotes LayerZero messaging fees required for cross-chain token transfers.
///
/// **Parameters**:
/// - `sender`: Address that will send the transfer (for message attribution)
/// - `send_param`: Complete transfer parameters including destination and execution options
/// - `pay_in_zro`: Whether to use ZRO tokens for fee payment
///
/// **Returns**: Quote call to send to the endpoint to get the messaging fees
public fun quote_send<T>(
    self: &OFT<T>,
    sender: address,
    send_param: &SendParam,
    pay_in_zro: bool,
    ctx: &mut TxContext,
): Call<EndpointQuoteParam, MessagingFee> {
    self.assert_not_paused();
    let (_, amount_received_ld) = self.debit_view(send_param.amount_ld(), send_param.min_amount_ld());
    let (message, options) = self.build_msg_and_options(sender, send_param, amount_received_ld);
    self.oapp.quote(&self.oft_cap, send_param.dst_eid(), message, options, pay_in_zro, ctx)
}

/// Confirms and extracts results from a quote operation.
///
/// This function consumes a Call object returned by `quote_send()` to extract the
/// quote parameters and messaging fee, providing access to the quote results.
///
/// **Parameters**
/// - `call`: Completed Call object from `quote_send()` execution
///
/// **Returns**
/// - `MessagingFee`: Fee required for sending the message
public fun confirm_quote_send<T>(self: &OFT<T>, call: Call<EndpointQuoteParam, MessagingFee>): MessagingFee {
    let (_, fee) = self.oapp.confirm_quote(&self.oft_cap, call);
    fee
}

/// Initiates a cross-chain token transfer with flexible sender options.
///
/// **Parameters**:
/// - `sender`: Reference to OFTSender (Context or CallCap) specifying the sender address
/// - `send_param`: Transfer parameters (destination, amount, options, etc.)
/// - `coin_provided`: Coin to debit tokens from (must have sufficient balance)
/// - `native_coin_fee`: SUI tokens for paying messaging fees
/// - `zro_coin_fee`: Optional ZRO tokens for alternative fee payment
/// - `refund_address`: Optional address to receive unspent fee tokens. If provided, the excess
///   messagingfees will be refunded to this address in `confirm_send()`.
/// - `clock`: Clock object for rate limiting and timestamp-based operations
///
/// **Returns**:
/// - `Call<EndpointSendParam, MessagingReceipt>`: Endpoint call for message sending (execute this first)
/// - `OFTSendContext`: Send context containing the OFTReceipt and sender info required for `confirm_send()`
public fun send<T>(
    self: &mut OFT<T>,
    sender: &OFTSender,
    send_param: &SendParam,
    coin_provided: &mut Coin<T>,
    native_coin_fee: Coin<SUI>,
    zro_coin_fee: Option<Coin<ZRO>>,
    refund_address: Option<address>,
    clock: &Clock,
    ctx: &mut TxContext,
): (Call<EndpointSendParam, MessagingReceipt>, OFTSendContext) {
    self.assert_not_paused();

    let (amount_sent_ld, amount_received_ld) = self.debit(
        coin_provided,
        send_param.amount_ld(),
        send_param.min_amount_ld(),
        ctx,
    );
    let oft_receipt = oft_receipt::create(amount_sent_ld, amount_received_ld);

    // Release rate limit capacity for the pathway (net inflow), based on the amount received on the other side
    self.inbound_rate_limiter.release_rate_limit_capacity(send_param.dst_eid(), amount_received_ld, clock);
    // Consume rate limit capacity for the pathway (net outflow), based on the amount received on the other side
    self.outbound_rate_limiter.try_consume_rate_limit_capacity(send_param.dst_eid(), amount_received_ld, clock);

    let (message, options) = self.build_msg_and_options(sender.get_address(), send_param, amount_received_ld);
    let ep_call = self
        .oapp
        .lz_send(
            &self.oft_cap,
            send_param.dst_eid(),
            message,
            options,
            native_coin_fee,
            zro_coin_fee,
            refund_address,
            ctx,
        );

    let call_id = ep_call.id();
    (ep_call, oft_send_context::create(oft_receipt, sender.get_address(), call_id))
}

/// Confirms and finalizes a token send operation with flexible fee handling.
///
/// This function must be called after executing a `Call` returned by `send()`.
/// It performs final validation of the send operation, resets the OApp's sending state, and
/// either transfers unspent fees to a refund address (if provided) or returns them to the caller.
///
/// **Parameters:**
/// - `call`: The completed Call object returned from LayerZero endpoint execution
/// - `sender`: Reference to OFTSender used for authorization validation
/// - `send_context`: OFTSendContext created by the corresponding `send()` call
///
/// **Returns**
/// - `MessagingReceipt`: Receipt containing message details (nonce, fee, etc.)
/// - `OFTReceipt`: Receipt containing OFT-specific transfer details
/// - `Option<Coin<SUI>>`: Unspent native token fees (None if auto-refunded, Some if returned to caller)
/// - `Option<Coin<ZRO>>`: Unspent ZRO token fees (None if auto-refunded, Some if returned to caller)
public fun confirm_send<T>(
    self: &mut OFT<T>,
    sender: &OFTSender,
    call: Call<EndpointSendParam, MessagingReceipt>,
    send_context: OFTSendContext,
): (MessagingReceipt, OFTReceipt, Option<Coin<SUI>>, Option<Coin<ZRO>>) {
    let (oft_receipt, from_address, call_id) = send_context.destroy();
    assert!(sender.get_address() == from_address && call.id() == call_id, EInvalidSendContext);

    let (param, messaging_receipt) = self.oapp.confirm_lz_send(&self.oft_cap, call);
    event::emit(OFTSentEvent {
        oft: self.oft_address(),
        guid: messaging_receipt.guid(),
        dst_eid: param.dst_eid(),
        from_address,
        amount_sent_ld: oft_receipt.amount_sent_ld(),
        amount_received_ld: oft_receipt.amount_received_ld(),
    });

    // Refund the tokens to the refund address if provided.
    let (native_token, zro_token) = if (param.refund_address().is_some()) {
        let refund_address = param.refund_address().destroy_some();
        let (native_token, zro_token) = param.destroy();
        utils::transfer_coin(native_token, refund_address);
        utils::transfer_coin_option(zro_token, refund_address);
        (option::none(), option::none())
    } else {
        let (native_token, zro_token) = param.destroy();
        (option::some(native_token), zro_token)
    };
    (messaging_receipt, oft_receipt, native_token, zro_token)
}

/// Processes inbound cross-chain token transfers and delivers tokens directly to the recipient.
///
/// **Parameters**:
/// - `call`: LayerZero receive call containing the verified cross-chain message
/// - `clock`: Clock object for rate limiting and timestamp-based operations
///
/// **Note**: For transfers with compose functionality, use `lz_receive_with_compose` instead
public fun lz_receive<T>(self: &mut OFT<T>, call: Call<LzReceiveParam, Void>, clock: &Clock, ctx: &mut TxContext) {
    let (_src_eid, _nonce, _guid, coin_credited, oft_msg) = self.lz_receive_internal(call, clock, ctx);
    assert!(!oft_msg.is_composed(), EComposeMsgNotAllowed);
    utils::transfer_coin(coin_credited, oft_msg.send_to());
}

/// Processes inbound cross-chain token transfers with compose functionality for advanced workflows.
///
/// **Parameters**:
/// - `compose_queue`: The composer's message queue for sequencing operations
/// - `composer_registry`: Registry managing token deposits for composers
/// - `call`: LayerZero receive call containing the verified cross-chain message
/// - `clock`: Clock object for rate limiting and timestamp-based operations
///
/// **Note**: For simple transfers without compose, use `lz_receive` instead
public fun lz_receive_with_compose<T>(
    self: &mut OFT<T>,
    compose_queue: &mut ComposeQueue,
    composer_registry: &mut OFTComposerRegistry,
    call: Call<LzReceiveParam, Void>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (src_eid, nonce, guid, coin_credited, oft_msg) = self.lz_receive_internal(call, clock, ctx);
    assert!(oft_msg.is_composed(), EComposeMsgRequired);
    let composer = endpoint_v2::get_composer(compose_queue);
    assert!(oft_msg.send_to() == composer, EInvalidComposeQueue);
    let compose_msg = oft_compose_msg_codec::encode(
        nonce,
        src_eid,
        coin_credited.value(),
        oft_msg.compose_from().destroy_some(),
        *oft_msg.compose_msg().borrow(),
    );
    endpoint_v2::send_compose(&self.oft_cap, compose_queue, guid, 0, compose_msg);
    composer_registry.send_to_composer(&self.oft_cap, guid, composer, coin_credited, ctx);
}

// === Admin Functions ===

/// Registers this OFT with the LayerZero endpoint to enable cross-chain messaging.
///
/// **Parameters**:
/// - `admin`: Admin capability proving authorization to perform registration
/// - `endpoint`: LayerZero V2 endpoint to register with
/// - `lz_receive_info`: Execution metadata for message delivery
public fun register_oapp<T>(
    self: &OFT<T>,
    admin: &AdminCap,
    endpoint: &mut EndpointV2,
    lz_receive_info: vector<u8>,
    ctx: &mut TxContext,
) {
    self.oapp.assert_admin(admin);
    endpoint.register_oapp(&self.oft_cap, lz_receive_info, ctx);
}

/// Configures enforced execution options for a specific destination chain and message type.
///
/// **Parameters**:
/// - `admin`: Admin capability proving authorization
/// - `eid`: Destination endpoint ID to configure options for
/// - `msg_type`: Message type (SEND_TYPE or SEND_AND_CALL_TYPE)
/// - `options`: Encoded execution options to enforce
public fun set_enforced_options<T>(self: &mut OFT<T>, admin: &AdminCap, eid: u32, msg_type: u16, options: vector<u8>) {
    // Admin is asserted in oapp::set_enforced_options
    self.oapp.set_enforced_options(admin, eid, msg_type, options);
}

/// Configures a trusted peer OFT on another chain and initializes messaging if needed.
///
/// **Parameters**:
/// - `admin`: Admin capability proving authorization
/// - `endpoint`: LayerZero V2 endpoint for channel initialization
/// - `messaging_channel`: OFT's messaging channel for state management
/// - `eid`: Destination chain endpoint ID
/// - `peer`: Address of the trusted OFT on the destination chain
public fun set_peer<T>(
    self: &mut OFT<T>,
    admin: &AdminCap,
    endpoint: &EndpointV2,
    messaging_channel: &mut MessagingChannel,
    eid: u32,
    peer: Bytes32,
    ctx: &mut TxContext,
) {
    // Admin is asserted in oapp::set_peer
    self.oapp.set_peer(admin, eid, peer);
    if (!endpoint_v2::is_channel_inited(messaging_channel, eid, peer)) {
        endpoint.init_channel(&self.oft_cap, messaging_channel, eid, peer, ctx);
    };
}

/// Configures a delegate address that can perform certain operations on behalf of this OFT.
///
/// **Parameters**:
/// - `admin`: Admin capability proving authorization
/// - `endpoint`: LayerZero V2 endpoint to configure the delegate on
/// - `new_delegate`: Address that will receive delegate privileges
public fun set_delegate<T>(self: &OFT<T>, admin: &AdminCap, endpoint: &mut EndpointV2, new_delegate: address) {
    self.oapp.assert_admin(admin);
    endpoint.set_delegate(&self.oft_cap, new_delegate);
}

/// Controls the pause state of OFT operations for emergency situations.
///
/// **Parameters**:
/// - `admin`: Admin capability proving authorization
/// - `paused`: New pause state (true to pause, false to unpause)
public fun set_pause<T>(self: &mut OFT<T>, admin: &AdminCap, paused: bool) {
    self.oapp.assert_admin(admin);
    assert!(self.paused != paused, EPauseUnchanged);
    self.paused = paused;
    event::emit(PausedSetEvent { oft: self.oft_address(), paused });
}

// === Fee Management Admin Functions ===

/// Sets the OFT fee deposit address where collected fees will be sent
///
/// **Parameters**:
/// - `admin`: Admin capability proving authorization
/// - `fee_deposit_address`: New address for fee deposits (cannot be zero address)
public fun set_fee_deposit_address<T>(self: &mut OFT<T>, admin: &AdminCap, fee_deposit_address: address) {
    self.oapp.assert_admin(admin);
    let oft_address = self.oft_address();
    self.fee.set_fee_deposit_address(oft_address, fee_deposit_address);
}

/// Sets the fee rate in basis points
///
/// **Parameters**:
/// - `admin`: Admin capability proving authorization
/// - `fee_bps`: New OFT fee rate in basis points (0-10,000, where 10,000 = 100%)
public fun set_fee_bps<T>(self: &mut OFT<T>, admin: &AdminCap, fee_bps: u64) {
    self.oapp.assert_admin(admin);
    let oft_address = self.oft_address();
    self.fee.set_fee_bps(oft_address, fee_bps);
}

// === Rate Limiter Admin Functions ===

/// Sets the rate limit for a specific endpoint
///
/// **Parameters**:
/// - `admin`: Admin capability proving authorization
/// - `eid`: Remote endpoint ID to set the rate limit for
/// - `inbound`: Whether to set the inbound (true) or outbound (false) rate limit
/// - `rate_limit`: Maximum token amount allowed per window
/// - `window_seconds`: Duration of the rate limit window in seconds
/// - `clock`: Clock object for timestamp-based rate limit calculations
public fun set_rate_limit<T>(
    self: &mut OFT<T>,
    admin: &AdminCap,
    eid: u32,
    inbound: bool,
    rate_limit: u64,
    window_seconds: u64,
    clock: &Clock,
) {
    self.oapp.assert_admin(admin);
    let oft_address = self.oft_address();
    if (inbound) {
        self.inbound_rate_limiter.set_rate_limit(oft_address, eid, rate_limit, window_seconds, clock);
    } else {
        self.outbound_rate_limiter.set_rate_limit(oft_address, eid, rate_limit, window_seconds, clock);
    }
}

/// Unsets the rate limit for a specific endpoint
///
/// **Parameters**:
/// - `admin`: Admin capability proving authorization
/// - `eid`: Remote endpoint ID to unset the rate limit for
/// - `inbound`: Whether to unset the inbound (true) or outbound (false) rate limit
public fun unset_rate_limit<T>(self: &mut OFT<T>, admin: &AdminCap, eid: u32, inbound: bool) {
    self.oapp.assert_admin(admin);
    let oft_address = self.oft_address();
    if (inbound) {
        self.inbound_rate_limiter.unset_rate_limit(oft_address, eid);
    } else {
        self.outbound_rate_limiter.unset_rate_limit(oft_address, eid);
    }
}

// === OFT View Functions ===

/// Returns the OFT standard version (major, minor)
public fun oft_version<T>(_self: &OFT<T>): (u64, u64) {
    (1, 1)
}

/// Returns the address of the OFT (the call capability ID)
public fun oft_address<T>(self: &OFT<T>): address {
    self.oapp.oapp_address()
}

/// Returns the address of the coin metadata object
public fun coin_metadata<T>(self: &OFT<T>): address {
    self.coin_metadata
}

/// Returns the number of decimals used for cross-chain transfers
public fun shared_decimals<T>(self: &OFT<T>): u8 {
    self.shared_decimals
}

/// Returns whether the OFT is currently paused
public fun is_paused<T>(self: &OFT<T>): bool {
    self.paused
}

/// Returns true if this is an adapter OFT (escrow model), false if standard OFT (mint/burn model)
public fun is_adapter<T>(self: &OFT<T>): bool {
    match (&self.treasury) {
        OFTTreasury::OFTAdapter { escrow: _ } => true,
        OFTTreasury::OFT { treasury_cap: _ } => false,
    }
}

// === Fee Management View Functions ===

/// Returns true if the OFT has a fee rate greater than 0
public fun has_oft_fee<T>(self: &OFT<T>): bool {
    self.fee.has_oft_fee()
}

/// Returns the current fee rate in basis points
public fun fee_bps<T>(self: &OFT<T>): u64 {
    self.fee.fee_bps()
}

/// Returns the current fee deposit address
public fun fee_deposit_address<T>(self: &OFT<T>): address {
    self.fee.fee_deposit_address()
}

// === Rate Limiter View Functions ===

/// Returns the rate limit configuration for a specific endpoint
public fun rate_limit_config<T>(self: &OFT<T>, eid: u32, inbound: bool): (u64, u64) {
    if (inbound) {
        self.inbound_rate_limiter.rate_limit_config(eid)
    } else {
        self.outbound_rate_limiter.rate_limit_config(eid)
    }
}

/// Returns the number of messages in flight for a specific endpoint
public fun rate_limit_in_flight<T>(self: &OFT<T>, eid: u32, inbound: bool, clock: &Clock): u64 {
    if (inbound) {
        self.inbound_rate_limiter.in_flight(eid, clock)
    } else {
        self.outbound_rate_limiter.in_flight(eid, clock)
    }
}

/// Returns the rate limit capacity for a specific endpoint
public fun rate_limit_capacity<T>(self: &OFT<T>, eid: u32, inbound: bool, clock: &Clock): u64 {
    if (inbound) {
        self.inbound_rate_limiter.rate_limit_capacity(eid, clock)
    } else {
        self.outbound_rate_limiter.rate_limit_capacity(eid, clock)
    }
}

// === OApp View Functions ===

/// Returns the admin address for this OFT
public fun admin<T>(self: &OFT<T>): address {
    self.oapp.admin()
}

/// Combines enforced and extra options for a specific endpoint and message type
public fun combine_options<T>(self: &OFT<T>, eid: u32, msg_type: u16, extra_options: vector<u8>): vector<u8> {
    self.oapp.combine_options(eid, msg_type, extra_options)
}

/// Returns the enforced options for a specific endpoint and message type
public fun get_enforced_options<T>(self: &OFT<T>, eid: u32, msg_type: u16): &vector<u8> {
    self.oapp.get_enforced_options(eid, msg_type)
}

/// Returns whether a peer is configured for the given endpoint ID
public fun has_peer<T>(self: &OFT<T>, eid: u32): bool {
    self.oapp.has_peer(eid)
}

/// Returns the peer address for the given endpoint ID
public fun get_peer<T>(self: &OFT<T>, eid: u32): Bytes32 {
    self.oapp.get_peer(eid)
}

// === Internal Functions ===

/// Internal function to create OFT instances with common logic
#[allow(lint(share_owned))] // LSP detects the oapp returned by oapp::new as share_owned, but it is not
fun create_oft_internal<T>(
    oapp: OApp,
    oft_cap: CallCap,
    coin_metadata: &CoinMetadata<T>,
    shared_decimals: u8,
    treasury: OFTTreasury<T>,
    is_adapter: bool,
    ctx: &mut TxContext,
): OFT<T> {
    // SECURITY: Verify that the CallCap is authorized for this specific OApp instance
    // This prevents unauthorized cross-chain operations using mismatched capabilities
    oapp.assert_oapp_cap(&oft_cap);

    let local_decimals = coin_metadata.get_decimals();
    // CRITICAL: Shared decimals must not exceed local decimals to prevent precision overflow
    // This ensures conversion operations remain mathematically sound
    assert!(local_decimals >= shared_decimals, EInvalidLocalDecimals);

    // Calculate the conversion multiplier for decimal precision transformations
    // OPERATIONAL: This rate determines dust removal precision and cross-chain consistency
    let decimal_conversion_rate = u64::pow(10, (local_decimals - shared_decimals));

    let oft = OFT {
        id: object::new(ctx),
        oapp,
        oft_cap,
        treasury,
        coin_metadata: object::id_address(coin_metadata),
        decimal_conversion_rate,
        shared_decimals,
        paused: false, // OFT starts in active state - admin can pause if needed
        fee: oft_fee::new(), // Default fee is 0%
        inbound_rate_limiter: rate_limiter::create(true, ctx),
        outbound_rate_limiter: rate_limiter::create(false, ctx),
    };

    // Emit creation event for off-chain indexing and monitoring
    event::emit(OFTCreatedEvent {
        oft: oft.oapp.oapp_address(),
        oft_object: object::id_address(&oft),
        coin_metadata: object::id_address(coin_metadata),
        is_adapter,
    });

    oft
}

/// Internal implementation of cross-chain token receive logic.
fun lz_receive_internal<T>(
    self: &mut OFT<T>,
    call: Call<LzReceiveParam, Void>,
    clock: &Clock,
    ctx: &mut TxContext,
): (u32, u64, Bytes32, Coin<T>, OFTMessage) {
    self.assert_not_paused();

    // SECURITY: Delegate to OApp for LayerZero message validation and peer verification
    // This ensures the message comes from a trusted source and passes all security checks
    let lz_receive_param = self.oapp.lz_receive(&self.oft_cap, call);
    let (src_eid, _, nonce, guid, message, _, _, value) = lz_receive_param.destroy();

    // Decode OFT-specific payload and convert amounts to local precision
    let oft_msg = oft_msg_codec::decode(message);
    let amount_received_ld = self.to_ld(oft_msg.amount_sd());

    // Release rate limit capacity for the pathway (net outflow)
    self.outbound_rate_limiter.release_rate_limit_capacity(src_eid, amount_received_ld, clock);
    // Consume rate limit capacity for the pathway (net inflow)
    self.inbound_rate_limiter.try_consume_rate_limit_capacity(src_eid, amount_received_ld, clock);

    // CRITICAL: Credit tokens according to treasury model (mint or release from escrow)
    let coin_credited = self.credit(amount_received_ld, ctx);

    event::emit(OFTReceivedEvent {
        oft: self.oft_address(),
        guid,
        src_eid,
        to_address: oft_msg.send_to(),
        amount_received_ld,
    });

    // CLEANUP: Return any unintended native tokens to the executor
    // This handles cases where the executor mistakenly sent native tokens with the message
    utils::transfer_coin_option(value, ctx.sender());

    (src_eid, nonce, guid, coin_credited, oft_msg)
}

/// Calculates final transfer amounts without executing the debit operation.
fun debit_view<T>(self: &OFT<T>, amount_ld: u64, min_amount_ld: u64): (u64, u64) {
    if (self.has_oft_fee()) {
        debit_view_with_fee(self, amount_ld, min_amount_ld)
    } else {
        no_fee_debit_view(self, amount_ld, min_amount_ld)
    }
}

/// Calculates final transfer amounts with fee deduction.
fun debit_view_with_fee<T>(self: &OFT<T>, amount_ld: u64, min_amount_ld: u64): (u64, u64) {
    let amount_ld_after_fee = self.fee.apply_fee(amount_ld);
    let amount_received_ld = self.remove_dust(amount_ld_after_fee);
    assert!(amount_received_ld >= min_amount_ld, ESlippageExceeded);
    (amount_ld, amount_received_ld)
}

/// Calculates final transfer amounts without fee deduction.
fun no_fee_debit_view<T>(self: &OFT<T>, amount_ld: u64, min_amount_ld: u64): (u64, u64) {
    let amount_sent_ld = self.remove_dust(amount_ld);
    let amount_received_ld = amount_sent_ld;
    assert!(amount_received_ld >= min_amount_ld, ESlippageExceeded);
    (amount_sent_ld, amount_received_ld)
}

/// Executes token debit operation based on OFT model (burn vs. escrow).
fun debit<T>(
    self: &mut OFT<T>,
    coin: &mut Coin<T>,
    amount_ld: u64,
    min_amount_ld: u64,
    ctx: &mut TxContext,
): (u64, u64) {
    let (amount_sent_ld, amount_received_ld) = self.debit_view(amount_ld, min_amount_ld);
    let coin_to_debit = coin.split(amount_received_ld, ctx);
    if (amount_sent_ld > amount_received_ld) {
        let fee_coin = coin.split(amount_sent_ld - amount_received_ld, ctx);
        utils::transfer_coin(fee_coin, self.fee.fee_deposit_address());
    };

    // Execute treasury-model-specific debit operation
    // SECURITY: This is the critical point where tokens leave circulation (burn) or availability (escrow)
    match (&mut self.treasury) {
        OFTTreasury::OFT { treasury_cap } => {
            // Standard OFT: Burn tokens to reduce total supply across all chains
            // This approach is suitable for tokens where the protocol controls total supply
            treasury_cap.burn(coin_to_debit);
        },
        OFTTreasury::OFTAdapter { escrow } => {
            // Adapter OFT: Escrow tokens to maintain fixed total supply
            // Tokens remain in existence but are locked until released on message receipt
            let escrowed_balance = coin_to_debit.into_balance();
            escrow.join(escrowed_balance);
        },
    };

    (amount_sent_ld, amount_received_ld)
}

/// Executes token credit operation based on OFT model (mint vs. release from escrow).
fun credit<T>(self: &mut OFT<T>, amount_ld: u64, ctx: &mut TxContext): Coin<T> {
    // Execute treasury-model-specific credit operation
    // SECURITY: This is where tokens enter circulation (mint) or availability (release from escrow)
    match (&mut self.treasury) {
        OFTTreasury::OFT { treasury_cap } => {
            // Standard OFT: Mint new tokens, increasing total supply
            // Only possible if this OFT instance holds the treasury capability
            treasury_cap.mint(amount_ld, ctx)
        },
        OFTTreasury::OFTAdapter { escrow } => {
            // Adapter OFT: Release tokens from escrow balance
            // CRITICAL: Must have sufficient escrowed tokens from previous inbound transfers
            assert!(escrow.value() >= amount_ld, EInsufficientBalance);
            let released_balance = escrow.split(amount_ld);
            coin::from_balance(released_balance, ctx)
        },
    }
}

/// Constructs the LayerZero message payload and execution options for cross-chain transmission.
fun build_msg_and_options<T>(
    self: &OFT<T>,
    sender: address,
    send_param: &SendParam,
    amount_ld: u64,
): (vector<u8>, vector<u8>) {
    // Prepare compose parameters
    let (compose_from, compose_msg, msg_type) = if (send_param.compose_msg().length() > 0) {
        (option::some(bytes32::from_address(sender)), option::some(*send_param.compose_msg()), SEND_AND_CALL_TYPE)
    } else {
        (option::none(), option::none(), SEND_TYPE)
    };

    // Encode message and combine options
    let message = oft_msg_codec::encode(send_param.to(), self.to_sd(amount_ld), compose_from, compose_msg);
    let options = self.oapp.combine_options(send_param.dst_eid(), msg_type, *send_param.extra_options());
    (message, options)
}

/// Removes precision dust by rounding down to the nearest representable amount in shared decimals.
fun remove_dust<T>(self: &OFT<T>, amount_ld: u64): u64 {
    (amount_ld / self.decimal_conversion_rate) * self.decimal_conversion_rate
}

/// Converts an amount from standardized shared decimals to local chain decimal precision.
fun to_ld<T>(self: &OFT<T>, amount_sd: u64): u64 {
    amount_sd * self.decimal_conversion_rate
}

/// Converts an amount from local chain decimal precision to standardized shared decimals.
fun to_sd<T>(self: &OFT<T>, amount_ld: u64): u64 {
    amount_ld / self.decimal_conversion_rate
}

/// Validates that the OFT is in an operational state and not paused.
fun assert_not_paused<T>(self: &OFT<T>) {
    assert!(!self.paused, EPaused);
}

// === Test Functions ===

#[test_only]
public(package) fun debit_for_test<T>(
    self: &mut OFT<T>,
    coin: &mut Coin<T>,
    amount_ld: u64,
    min_amount_ld: u64,
    ctx: &mut TxContext,
): (u64, u64) {
    self.debit(coin, amount_ld, min_amount_ld, ctx)
}

#[test_only]
public(package) fun mint_for_testing<T>(self: &mut OFT<T>, amount_ld: u64, ctx: &mut TxContext): Coin<T> {
    self.credit(amount_ld, ctx)
}

#[test_only]
public(package) fun cap_for_test<T>(self: &OFT<T>): &CallCap {
    &self.oft_cap
}

#[test_only]
public(package) fun cap_id_for_test<T>(self: &OFT<T>): address {
    self.oft_cap.id()
}

#[test_only]
public(package) fun destruct_oft_sent_event(event: OFTSentEvent): (Bytes32, u32, address, u64, u64) {
    let OFTSentEvent { oft: _, guid, dst_eid, from_address, amount_sent_ld, amount_received_ld } = event;
    (guid, dst_eid, from_address, amount_sent_ld, amount_received_ld)
}

#[test_only]
public(package) fun remove_dust_for_test<T>(self: &OFT<T>, amount_ld: u64): u64 {
    self.remove_dust(amount_ld)
}

#[test_only]
public(package) fun register_oapp_for_test<T>(
    self: &OFT<T>,
    endpoint: &mut EndpointV2,
    lz_receive_info: vector<u8>,
    ctx: &mut TxContext,
) {
    endpoint.register_oapp(&self.oft_cap, lz_receive_info, ctx);
}

#[test_only]
public(package) fun to_ld_for_test<T>(self: &OFT<T>, amount_sd: u64): u64 {
    self.to_ld(amount_sd)
}

#[test_only]
public(package) fun to_sd_for_test<T>(self: &OFT<T>, amount_ld: u64): u64 {
    self.to_sd(amount_ld)
}

#[test_only]
public(package) fun debit_view_for_test<T>(self: &OFT<T>, amount_ld: u64, min_amount_ld: u64): (u64, u64) {
    self.debit_view(amount_ld, min_amount_ld)
}
