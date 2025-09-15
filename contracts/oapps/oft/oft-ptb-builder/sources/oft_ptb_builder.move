/// OFT Programmable Transaction Block (PTB) Builder
///
/// This module provides utilities for building programmable transaction blocks (PTBs)
/// that handle OFT cross-chain message reception and compose operations. It bridges
/// LayerZero's messaging infrastructure with Sui's PTB execution model.
module oft_ptb_builder::oft_ptb_builder;

use call::{call::{Call, Void}, call_cap::{Self, CallCap}};
use endpoint_v2::{endpoint_v2::EndpointV2, lz_receive::LzReceiveParam};
use oapp::ptb_builder_helper;
use oft::{oft::OFT, oft_msg_codec};
use oft_composer_common::oft_composer_registry::OFTComposerRegistry;
use ptb_move_call::{argument, move_call::{Self, MoveCall}, move_calls_builder::{Self, MoveCallsBuilder}};
use std::type_name;
use sui::{bcs, clock::Clock};
use utils::{buffer_writer, package};

/// Version identifier for lz_receive_info format - version 1 includes 2-byte version header plus serialized MoveCall
/// vector
const LZ_RECEIVE_INFO_VERSION_1: u16 = 1;

public struct OFT_PTB_BUILDER has drop {}

public struct OFTPtbBuilder has key {
    id: UID,
    call_cap: CallCap,
}

fun init(witness: OFT_PTB_BUILDER, ctx: &mut TxContext) {
    transfer::share_object(OFTPtbBuilder {
        id: object::new(ctx),
        call_cap: call_cap::new_package_cap(&witness, ctx),
    });
}

/// Generates execution metadata for OFT registration with LayerZero endpoint.
///
/// **Parameters**:
/// - `oft`: OFT instance that will be registered with the endpoint
/// - `endpoint`: LayerZero V2 endpoint for message processing infrastructure
/// - `composer_registry`: Registry for routing compose transfers to composers
///
/// **Returns**: Serialized execution metadata for endpoint registration
public fun lz_receive_info<T>(
    self: &OFTPtbBuilder,
    oft: &OFT<T>,
    endpoint: &EndpointV2,
    composer_registry: &OFTComposerRegistry,
    clock: &Clock,
): vector<u8> {
    let lz_receive_move_calls = vector[
        move_call::create(
            self.call_cap.id(),
            b"oft_ptb_builder".to_ascii_string(),
            b"build_lz_receive_ptb".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(oft)),
                argument::create_object(object::id_address(endpoint)),
                argument::create_object(object::id_address(composer_registry)),
                argument::create_id(ptb_builder_helper::lz_receive_call_id()),
                argument::create_object(object::id_address(clock)),
            ],
            vector[type_name::get_with_original_ids<T>()],
            true,
            vector[],
        ),
    ];
    let move_calls_bytes = bcs::to_bytes(&lz_receive_move_calls);
    let mut writer = buffer_writer::new();
    writer.write_u16(LZ_RECEIVE_INFO_VERSION_1).write_bytes(move_calls_bytes);
    writer.to_bytes()
}

/// Dynamically builds a PTB for processing incoming LayerZero messages based on message content.
///
/// **Parameters**:
/// - `oft`: Target OFT instance that will process the message
/// - `endpoint`: LayerZero endpoint managing message processing
/// - `composer_registry`: Registry for routing compose transfers (used if compose detected)
/// - `call`: LayerZero receive call containing the cross-chain message
///
/// **Returns**: Vector of Move calls forming a complete PTB for message execution
public fun build_lz_receive_ptb<T>(
    oft: &OFT<T>,
    endpoint: &EndpointV2,
    composer_registry: &OFTComposerRegistry,
    call: &Call<LzReceiveParam, Void>,
    clock: &Clock,
): vector<MoveCall> {
    let message = call.param().message();
    let oft_msg = oft_msg_codec::decode(*message);
    let mut builder = move_calls_builder::new();

    if (oft_msg.is_composed()) {
        let composer = oft_msg.send_to();
        add_lz_receive_compose_call(
            &mut builder,
            oft,
            endpoint,
            object::id_address(composer_registry),
            composer,
            clock,
        );
    } else {
        add_lz_receive_call(&mut builder, oft, clock);
    };
    builder.build()
}

/// Adds a standard lz_receive call to the PTB builder for simple token transfers.
///
/// **Parameters**:
/// - `builder`: PTB builder to add the call to
/// - `oft`: Target OFT instance that will process the token transfer
public fun add_lz_receive_call<T>(builder: &mut MoveCallsBuilder, oft: &OFT<T>, clock: &Clock) {
    let oft_package = package::original_package_of_type<OFT<T>>();
    builder.add(
        move_call::create(
            oft_package,
            b"oft".to_ascii_string(),
            b"lz_receive".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(oft)),
                argument::create_id(ptb_builder_helper::lz_receive_call_id()),
                argument::create_object(object::id_address(clock)),
            ],
            vector[type_name::get_with_original_ids<T>()],
            false,
            vector[],
        ),
    );
}

/// Adds a compose-enabled lz_receive call to the PTB builder for complex cross-chain workflows.
///
/// **Parameters**:
/// - `builder`: PTB builder to add the compose call to
/// - `oft`: Target OFT instance that will process the compose transfer
/// - `endpoint`: LayerZero endpoint managing compose message queuing
/// - `composer_registry`: Address of the composer registry for token routing
/// - `composer`: Target composer address that will execute the compose logic
public fun add_lz_receive_compose_call<T>(
    builder: &mut MoveCallsBuilder,
    oft: &OFT<T>,
    endpoint: &EndpointV2,
    composer_registry: address,
    composer: address,
    clock: &Clock,
) {
    let oft_package = package::original_package_of_type<OFT<T>>();
    let compose_queue = endpoint.get_compose_queue(composer);
    builder.add(
        move_call::create(
            oft_package,
            b"oft".to_ascii_string(),
            b"lz_receive_with_compose".to_ascii_string(),
            vector[
                argument::create_object(object::id_address(oft)),
                argument::create_object(compose_queue),
                argument::create_object(composer_registry),
                argument::create_id(ptb_builder_helper::lz_receive_call_id()),
                argument::create_object(object::id_address(clock)),
            ],
            vector[type_name::get_with_original_ids<T>()],
            false,
            vector[],
        ),
    );
}
