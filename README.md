# ✨ So you want to run an audit

This `README.md` contains a set of checklists for our audit collaboration. This is your audit repo, which is used for scoping your audit and for providing information to wardens

Some of the checklists in this doc are for our scouts and some of them are for **you as the audit sponsor (⭐️)**.

---

# Repo setup

## ⭐️ Sponsor: Add code to this repo

- [ ] Create a PR to this repo with the below changes:
- [ ] Confirm that this repo is a self-contained repository with working commands that will build (at least) all in-scope contracts, and commands that will run tests producing gas reports for the relevant contracts.
- [ ] Please have final versions of contracts and documentation added/updated in this repo **no less than 48 business hours prior to audit start time.**
- [ ] Be prepared for a 🚨code freeze🚨 for the duration of the audit — important because it establishes a level playing field. We want to ensure everyone's looking at the same code, no matter when they look during the audit. (Note: this includes your own repo, since a PR can leak alpha to our wardens!)

## ⭐️ Sponsor: Repo checklist

- [ ] Modify the [Overview](#overview) section of this `README.md` file. Describe how your code is supposed to work with links to any relevant documentation and any other criteria/details that the auditors should keep in mind when reviewing. (Here are two well-constructed examples: [Ajna Protocol](https://github.com/code-423n4/2023-05-ajna) and [Maia DAO Ecosystem](https://github.com/code-423n4/2023-05-maia))
- [ ] Optional: pre-record a high-level overview of your protocol (not just specific smart contract functions). This saves wardens a lot of time wading through documentation.
- [ ] Review and confirm the details created by the Scout (technical reviewer) who was assigned to your contest. *Note: any files not listed as "in scope" will be considered out of scope for the purposes of judging, even if the file will be part of the deployed contracts.*  

---

# LayerZero audit details
- Total Prize Pool: $103000 in USDC
  - HM awards: up to XXX XXX USDC (Notion: HM (main) pool)
    - If no valid Highs or Mediums are found, the HM pool is $0 
  - QA awards: $4000 in USDC
  - Judge awards: $2500 in USDC
  - Scout awards: $500 in USDC
  - (this line can be removed if there is no mitigation) Mitigation Review: XXX XXX USDC
- [Read our guidelines for more details](https://docs.code4rena.com/competitions)
- Starts XXX XXX XX 20:00 UTC (ex. `Starts March 22, 2023 20:00 UTC`)
- Ends XXX XXX XX 20:00 UTC (ex. `Ends March 30, 2023 20:00 UTC`)

**❗ Important notes for wardens** 
## 🐺 C4 staff: delete the PoC requirement section if not applicable - i.e. for non-Solidity/EVM audits.
1. A coded, runnable PoC is required for all High/Medium submissions to this audit. 
  - This repo includes a basic template to run the test suite.
  - PoCs must use the test suite provided in this repo.
  - Your submission will be marked as Insufficient if the POC is not runnable and working with the provided test suite.
  - Exception: PoC is optional (though recommended) for wardens with signal ≥ 0.68.
1. Judging phase risk adjustments (upgrades/downgrades):
  - High- or Medium-risk submissions downgraded by the judge to Low-risk (QA) will be ineligible for awards.
  - Upgrading a Low-risk finding from a QA report to a Medium- or High-risk finding is not supported.
  - As such, wardens are encouraged to select the appropriate risk level carefully during the submission phase.

## Automated Findings / Publicly Known Issues

_Note for C4 wardens: Anything included in this `Automated Findings / Publicly Known Issues` section is considered a publicly known issue and is ineligible for awards._


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
- contracts/oapps/oapp/sources
- contracts/oapps/oft/oft/sources
- contracts/oapps/oft/oft-composer-common/sources


# Additional context

## Areas of concern (where to focus for bugs)

TBD

## Main invariants

TBD

## Miscellaneous
Employees of LayerZero and employees' family members are ineligible to participate in this audit.

Code4rena's rules cannot be overridden by the contents of this README. In case of doubt, please check with C4 staff.


