/// OFT Fee Management Module
///
/// This module provides fee calculation and management functionality for OFT (Omnichain Fungible Token) transfers.
/// It implements a basis point (BPS) based fee system where fees are calculated as a percentage of the transfer amount.
module oft::oft_fee;

use sui::event;

// === Constants ===

/// Base fee in basis points (10,000 BPS = 100%)
/// Used as denominator in fee calculations
const BASE_FEE_BPS: u64 = 10_000;

// === Errors ===

const EInvalidFeeBps: u64 = 1;
const EInvalidFeeDepositAddress: u64 = 2;
const ESameValue: u64 = 3;

// === Structs ===

/// OFT fee configuration structure
public struct OFTFee has store {
    /// Fee rate in basis points (0-10,000, where 10,000 = 100%)
    fee_bps: u64,
    /// Address where collected fees will be deposited
    fee_deposit_address: address,
}

// === Events ===

public struct FeeBpsSetEvent has copy, drop {
    /// Address of the OFT package
    oft: address,
    /// New fee rate in basis points (0-10,000, where 10,000 = 100%)
    fee_bps: u64,
}

public struct FeeDepositAddressSetEvent has copy, drop {
    /// Address of the OFT package
    oft: address,
    /// Address where collected fees will be deposited
    fee_deposit_address: address,
}

// === Creation Functions ===

/// Creates a new OFTFee instance with zero fee rate and zero address
/// Initial state: no fees are charged and no deposit address is set
public(package) fun new(): OFTFee {
    OFTFee { fee_bps: 0, fee_deposit_address: @0x0 }
}

// === Core Functions ===

/// Applies the configured fee to the given amount and returns the amount after fee deduction
///
/// **Parameters**:
/// - `amount_ld`: The original amount in local decimals
///
/// **Returns**:
/// The amount after fee deduction (original amount - calculated fee)
public(package) fun apply_fee(self: &OFTFee, amount_ld: u64): u64 {
    assert!(self.fee_deposit_address != @0x0, EInvalidFeeDepositAddress);
    let preliminary_fee = ((((amount_ld as u128) * (self.fee_bps as u128)) / (BASE_FEE_BPS as u128)) as u64);
    amount_ld - preliminary_fee
}

// === Management Functions ===

/// Sets the fee deposit address where collected fees will be sent
///
/// **Parameters**:
/// - `oft`: Address of the OFT package
/// - `fee_deposit_address`: New address for fee deposits (cannot be zero address)
public(package) fun set_fee_deposit_address(self: &mut OFTFee, oft: address, fee_deposit_address: address) {
    assert!(fee_deposit_address != @0x0, EInvalidFeeDepositAddress);
    assert!(self.fee_deposit_address != fee_deposit_address, ESameValue);
    self.fee_deposit_address = fee_deposit_address;
    event::emit(FeeDepositAddressSetEvent { oft, fee_deposit_address });
}

/// Sets the fee rate in basis points
///
/// **Parameters**:
/// - `oft`: Address of the OFT package
/// - `fee_bps`: New fee rate in basis points (0-10,000, where 10,000 = 100%)
public(package) fun set_fee_bps(self: &mut OFTFee, oft: address, fee_bps: u64) {
    assert!(fee_bps <= BASE_FEE_BPS, EInvalidFeeBps);
    assert!(self.fee_bps != fee_bps, ESameValue);
    self.fee_bps = fee_bps;
    event::emit(FeeBpsSetEvent { oft, fee_bps });
}

// === View Functions ===

/// Returns true if the OFT has a fee rate greater than 0
public(package) fun has_oft_fee(self: &OFTFee): bool {
    self.fee_bps > 0
}

/// Returns the current fee rate in basis points
public(package) fun fee_bps(self: &OFTFee): u64 {
    self.fee_bps
}

/// Returns the current fee deposit address
public(package) fun fee_deposit_address(self: &OFTFee): address {
    self.fee_deposit_address
}
