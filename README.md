# LayerZero audit details
- Total Prize Pool: $103,000 in USDC
  - HM awards: up to $96,000 in USDC
    - If no valid Highs or Mediums are found, the HM pool is $0 
  - QA awards: $4,000 in USDC
  - Judge awards: $3,000 in USDC
- [Read our guidelines for more details](https://docs.code4rena.com/competitions)
- Starts September 16, 2025 20:00 UTC
- Ends September 30, 2025 20:00 UTC


# Overview

LayerZero is an omnichain interoperability protocol that enables smart contracts to read from and write state to different blockchains. Developers can build omnichain applications (OApps) that can send state transitions, value transfers, and call smart contracts on other networks as if they were on a single blockchain.

LayerZero's design ensures that the core protocol contracts are immutable and non-upgradeable, ensuring your application continues to operate as expected indefinitely, while your contracts stay easily configurable and flexible to define each part of the protocol's message passing rails.

## Links

- **Previous audits:**  https://github.com/LayerZero-Labs/Audits
- **Documentation:** https://docs.layerzero.network/v2
- **Website:** [LayerZero.network](https://layerzero.network/)
- **X/Twitter:** [@layerzero_core](https://x.com/layerzero_core)


## Automated Findings / Publicly Known Issues

_Note for C4 wardens: Anything included in this `Automated Findings / Publicly Known Issues` section is considered a publicly known issue and is ineligible for awards._

n/a


# Scope

## Files in Scope:

- contracts/call/sources
- contracts/endpoint-v2/sources
- contracts/utils/sources
- contracts/zro/sources
- contracts/message-libs/blocked-message-lib/sources
- contracts/message-libs/message-lib-common/sources
- contracts/message-libs/treasury/sources
- contracts/message-libs/uln-302/sources
- contracts/ptb-builders/ptb-move-call/sources
- contracts/ptb-builders/endpoint-ptb-builder/sources
- contracts/ptb-builders/msglib-ptb-builders/msglib-ptb-builder-call-types/sources
- contracts/ptb-builders/msglib-ptb-builders/uln-302-ptb-builder/sources
- contracts/workers/worker-common/sources
- contracts/workers/dvns/dvn/sources
- contracts/workers/dvns/dvn-call-type/sources
- contracts/workers/dvns/dvn-layerzero/sources
- contracts/workers/executors/executor-call-type/sources
- contracts/workers/executors/executor-fee-lib/sources
- contracts/workers/executors/executor-layerzero/sources
- contracts/workers/executors/executor/sources
- contracts/oapps/oapp/sources
- contracts/oapps/oft/oft/sources
- contracts/oapps/oft/oft-composer-common/sources

# Additional context

## Areas of concern (where to focus for bugs)

- Make sure a message cannot be executed until all messages before it (in terms of nonces) have been delivered. Make sure a message can only be executed once.
- Is the fee calculation in the msglib sound? If it differs between implementations, it may be unintended.

## Main invariants

- LayerZero should never have the ability to override user-set configuration.
- In general, LayerZero should not be able to DOS in any way, in the case that protocols are not using default configuration.

## Miscellaneous
Employees of LayerZero and employees' family members are ineligible to participate in this audit.

Code4rena's rules cannot be overridden by the contents of this README. In case of doubt, please check with C4 staff.


