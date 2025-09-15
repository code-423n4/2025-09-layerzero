module zro_oft_example::zro_oft_example;

use call::call_cap::CallCap;
use oapp::oapp::{Self, OApp};
use oft::oft;
use sui::coin::{CoinMetadata, TreasuryCap};
use utils::package;
use zro::zro::ZRO;

const EInvalidOFTCap: u64 = 1;

public struct ZRO_OFT_EXAMPLE has drop {}

fun init(otw: ZRO_OFT_EXAMPLE, ctx: &mut TxContext) {
    let (oft_cap, admin_cap, oapp) = oapp::new(&otw, ctx);
    transfer::public_transfer(admin_cap, ctx.sender());
    transfer::public_transfer(oft_cap, ctx.sender());
    transfer::public_transfer(oapp, ctx.sender());
}

#[allow(lint(share_owned))]
public fun init_zro_oft(
    oft_cap: CallCap,
    oapp: OApp,
    treasury_cap: TreasuryCap<ZRO>,
    metadata: CoinMetadata<ZRO>,
    ctx: &mut TxContext,
) {
    assert!(oft_cap.id() == package::original_package_of_type<ZRO_OFT_EXAMPLE>(), EInvalidOFTCap);
    let oft = oft::create_oft(oapp, oft_cap, treasury_cap, &metadata, 6, ctx);
    transfer::public_share_object(oft);
    transfer::public_freeze_object(metadata);
}
