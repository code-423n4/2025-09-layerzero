module oft_example::oft_example;

use oapp::oapp;
use oft::oft;
use sui::coin;

public struct OFT_EXAMPLE has drop {}

#[allow(lint(share_owned))]
fun init(otw: OFT_EXAMPLE, ctx: &mut TxContext) {
    let (oft_cap, admin_cap, oapp) = oapp::new(&otw, ctx);
    let (treasury, metadata) = coin::create_currency(
        otw,
        6,
        b"OFT Example",
        b"",
        b"",
        option::none(),
        ctx,
    );

    let oft = oft::create_oft(oapp, oft_cap, treasury, &metadata, 6, ctx);

    transfer::public_transfer(admin_cap, ctx.sender());
    transfer::public_share_object(metadata);
    transfer::public_share_object(oft);
}
