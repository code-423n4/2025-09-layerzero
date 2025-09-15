/// Unit tests for the SendFee extension module.
///
/// This test module covers:
/// - SendFee creation and initialization
/// - Fee calculation and application logic
/// - Setter and getter functionality
/// - Fee validation (valid/invalid fee_bps)
/// - Edge cases and precision testing
/// - Error conditions
#[test_only]
module oft::fee_tests;

use oft::oft_fee::{Self, OFTFee};
use sui::test_utils;

// === Test Constants ===

const ALICE: address = @0xa11ce;
const BOB: address = @0xb0b;
const OFT_ADDRESS: address = @0x123;

// Send Fee test constants
const VALID_FEE_BPS: u64 = 250; // 2.5%
const MAX_FEE_BPS: u64 = 10_000; // 100%
const INVALID_FEE_BPS: u64 = 10_001; // > 100%

// === Error Codes ===

const E_INVALID_FEE_BPS: u64 = 0;
const E_INVALID_FEE_AMOUNT: u64 = 1;
const E_INVALID_FEE_DEPOSIT_ADDRESS: u64 = 2;

// === Send Fee Creation Tests ===

#[test]
fun test_create_send_fee_valid() {
    let fee_bps = VALID_FEE_BPS;
    let fee_deposit_address = BOB;

    let fee = create_fee(fee_bps, fee_deposit_address);

    assert!(oft_fee::fee_bps(&fee) == fee_bps, E_INVALID_FEE_BPS);
    assert!(oft_fee::fee_deposit_address(&fee) == fee_deposit_address, E_INVALID_FEE_DEPOSIT_ADDRESS);

    test_utils::destroy(fee);
}

#[test]
fun test_create_send_fee_max_fee() {
    let fee_bps = MAX_FEE_BPS;
    let fee_deposit_address = BOB;

    let fee = create_fee(fee_bps, fee_deposit_address);

    assert!(oft_fee::fee_bps(&fee) == MAX_FEE_BPS, E_INVALID_FEE_BPS);
    assert!(oft_fee::fee_deposit_address(&fee) == fee_deposit_address, E_INVALID_FEE_DEPOSIT_ADDRESS);

    test_utils::destroy(fee);
}

#[test]
#[expected_failure(abort_code = oft_fee::EInvalidFeeBps)]
fun test_create_send_fee_invalid_fee_bps() {
    let fee_bps = INVALID_FEE_BPS;
    let fee_deposit_address = BOB;

    let fee = create_fee(fee_bps, fee_deposit_address);

    test_utils::destroy(fee);
}

// === Fee Calculation Tests ===

#[test]
fun test_apply_fee_basic() {
    let fee_bps = VALID_FEE_BPS; // 2.5%
    let fee = create_fee(fee_bps, BOB);

    // Test with 1000 units
    let amount_ld = 1000u64;
    let expected_after_fee = 975u64; // 1000 - (1000 * 250 / 10000) = 1000 - 25 = 975

    let actual_after_fee = oft_fee::apply_fee(&fee, amount_ld);
    assert!(actual_after_fee == expected_after_fee, E_INVALID_FEE_AMOUNT);

    test_utils::destroy(fee);
}

#[test]
fun test_apply_fee_zero_amount() {
    let fee_bps = VALID_FEE_BPS;
    let fee = create_fee(fee_bps, BOB);

    let amount_ld = 0u64;
    let expected_after_fee = 0u64;

    let actual_after_fee = oft_fee::apply_fee(&fee, amount_ld);
    assert!(actual_after_fee == expected_after_fee, E_INVALID_FEE_AMOUNT);

    test_utils::destroy(fee);
}

#[test]
fun test_apply_fee_max_fee_rate() {
    let fee_bps = MAX_FEE_BPS; // 100%
    let fee = create_fee(fee_bps, BOB);

    let amount_ld = 1000u64;
    let expected_after_fee = 0u64; // 100% fee means nothing left

    let actual_after_fee = oft_fee::apply_fee(&fee, amount_ld);
    assert!(actual_after_fee == expected_after_fee, E_INVALID_FEE_AMOUNT);

    test_utils::destroy(fee);
}

#[test]
fun test_apply_fee_large_amounts() {
    let fee_bps = VALID_FEE_BPS; // 2.5%
    let fee = create_fee(fee_bps, BOB);

    // Test with large amount
    let amount_ld = 1000000000u64; // 1 billion
    let fee_amount = (((amount_ld as u128) * (fee_bps as u128)) / 10_000) as u64;
    let expected_after_fee = amount_ld - fee_amount;

    let actual_after_fee = oft_fee::apply_fee(&fee, amount_ld);
    assert!(actual_after_fee == expected_after_fee, E_INVALID_FEE_AMOUNT);

    test_utils::destroy(fee);
}

// === Setter and Getter Tests ===

#[test]
fun test_set_fee_bps_valid() {
    let mut fee = create_fee(VALID_FEE_BPS, BOB);
    let new_fee_bps = 500u64; // 5%

    oft_fee::set_fee_bps(&mut fee, OFT_ADDRESS, new_fee_bps);

    assert!(oft_fee::fee_bps(&fee) == new_fee_bps, E_INVALID_FEE_BPS);

    test_utils::destroy(fee);
}

#[test]
fun test_set_fee_bps_zero() {
    let mut fee = create_fee(VALID_FEE_BPS, BOB);
    let new_fee_bps = 0u64;

    oft_fee::set_fee_bps(&mut fee, OFT_ADDRESS, new_fee_bps);

    assert!(oft_fee::fee_bps(&fee) == new_fee_bps, E_INVALID_FEE_BPS);

    test_utils::destroy(fee);
}

#[test]
fun test_set_fee_bps_max() {
    let mut fee = create_fee(VALID_FEE_BPS, BOB);
    let new_fee_bps = MAX_FEE_BPS;

    oft_fee::set_fee_bps(&mut fee, OFT_ADDRESS, new_fee_bps);

    assert!(oft_fee::fee_bps(&fee) == new_fee_bps, E_INVALID_FEE_BPS);

    test_utils::destroy(fee);
}

#[test]
#[expected_failure(abort_code = oft_fee::EInvalidFeeBps)]
fun test_set_fee_bps_invalid() {
    let mut fee = create_fee(VALID_FEE_BPS, BOB);

    // This should fail because fee_bps > MAX_FEE_BPS
    oft_fee::set_fee_bps(&mut fee, OFT_ADDRESS, INVALID_FEE_BPS);

    test_utils::destroy(fee);
}

#[test]
fun test_set_fee_deposit_address() {
    let mut fee = create_fee(VALID_FEE_BPS, BOB);
    let new_address = ALICE;

    oft_fee::set_fee_deposit_address(&mut fee, OFT_ADDRESS, new_address);

    assert!(oft_fee::fee_deposit_address(&fee) == new_address, E_INVALID_FEE_DEPOSIT_ADDRESS);

    test_utils::destroy(fee);
}

#[test]
fun test_getter_functions() {
    let fee_bps = 1500u64; // 15%
    let fee_deposit_address = ALICE;
    let fee = create_fee(fee_bps, fee_deposit_address);

    // Test getter functions
    assert!(oft_fee::fee_bps(&fee) == fee_bps, E_INVALID_FEE_BPS);
    assert!(oft_fee::fee_deposit_address(&fee) == fee_deposit_address, E_INVALID_FEE_DEPOSIT_ADDRESS);

    test_utils::destroy(fee);
}

// === Edge Cases and Precision Tests ===

#[test]
fun test_fee_calculations_precision() {
    // Test various fee rates for precision
    let test_amounts = vector[1u64, 10u64, 100u64, 999u64, 1000u64, 10000u64];
    let test_fee_rates = vector[1u64, 10u64, 100u64, 1000u64, 5000u64]; // 0.01%, 0.1%, 1%, 10%, 50%

    let mut i = 0;
    while (i < test_amounts.length()) {
        let amount = *test_amounts.borrow(i);

        let mut j = 0;
        while (j < test_fee_rates.length()) {
            let fee_bps = *test_fee_rates.borrow(j);
            let fee = create_fee(fee_bps, BOB);

            let result = oft_fee::apply_fee(&fee, amount);
            let expected_fee = (((amount as u128) * (fee_bps as u128)) / 10_000) as u64;
            let expected_result = amount - expected_fee;

            assert!(result == expected_result, E_INVALID_FEE_AMOUNT);

            test_utils::destroy(fee);
            j = j + 1;
        };

        i = i + 1;
    };
}

#[test]
fun test_fee_calculations_edge_values() {
    // Test edge case values for fee calculations
    let fee_1bp = create_fee(1u64, BOB); // 0.01%
    let fee_9999bp = create_fee(9999u64, BOB); // 99.99%

    // Test with minimum non-zero amount
    let min_amount = 1u64;
    let result_1bp = oft_fee::apply_fee(&fee_1bp, min_amount);
    let result_9999bp = oft_fee::apply_fee(&fee_9999bp, min_amount);

    // For 1 unit with 0.01% fee: fee = 0 (rounded down), so result = 1
    assert!(result_1bp == 1, E_INVALID_FEE_AMOUNT);
    // For 1 unit with 99.99% fee: fee = 0 (rounded down), so result = 1
    assert!(result_9999bp == 1, E_INVALID_FEE_AMOUNT);

    // Test with larger amounts where rounding matters
    let large_amount = 10000u64;
    let result_1bp_large = oft_fee::apply_fee(&fee_1bp, large_amount);
    let result_9999bp_large = oft_fee::apply_fee(&fee_9999bp, large_amount);

    // For 10000 units with 0.01% fee: fee = 1, so result = 9999
    assert!(result_1bp_large == 9999, E_INVALID_FEE_AMOUNT);
    // For 10000 units with 99.99% fee: fee = 9999, so result = 1
    assert!(result_9999bp_large == 1, E_INVALID_FEE_AMOUNT);

    test_utils::destroy(fee_1bp);
    test_utils::destroy(fee_9999bp);
}

// === Helper ===

fun create_fee(fee_bps: u64, fee_deposit_address: address): OFTFee {
    let mut fee = oft_fee::new();
    oft_fee::set_fee_bps(&mut fee, OFT_ADDRESS, fee_bps);
    oft_fee::set_fee_deposit_address(&mut fee, OFT_ADDRESS, fee_deposit_address);
    fee
}
