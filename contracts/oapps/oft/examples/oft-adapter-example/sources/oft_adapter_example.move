module oft_adapter_example::oft_adapter_example;

use oapp::oapp;
use oft::oft;
use sui::coin;

public struct OFT_ADAPTER_EXAMPLE has drop {}

#[allow(lint(share_owned))]
fun init(otw: OFT_ADAPTER_EXAMPLE, ctx: &mut TxContext) {
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

    let oft = oft::create_oft_adapter(oapp, oft_cap, &metadata, 6, ctx);

    transfer::public_transfer(admin_cap, ctx.sender());
    // unlike in oft example, here we transfer the treasury back to the authority, in real world use case, the treasury
    // and metadata should already be held by some other authorities other than the owner
    // or the authority do not want to hand over the treasury_cap to the adapter
    transfer::public_transfer(treasury, ctx.sender());
    transfer::public_share_object(metadata);
    transfer::public_share_object(oft);
}
