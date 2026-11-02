# VERIMETRIUM · public GLOBAL VERSION AUTHORITY

This repository contains **public metadata ONLY** (global version numbers, roles, work labels, cryptographic source-set digests). It intentionally contains **no** MT5/Pine source code, proprietary settings, trading logs, raw ticks, strategy secrets, passwords or private source manifests.

The frozen initial anchor is V1000.00–V1004.00, imported from the existing private GVA registry. First unissued candidate: **V1005.00**. Until the protective ruleset and dedicated GitHub App are ACTIVE and negative/positive checks have passed, this is a *staged* authority and the previous private ledger must remain the authoritative source.

## Required controls (GitHub Free, PUBLIC repository)

1. Create repository named `verimetrium-version-authority`, **Public**, with **no initial files**. Upload this package's `public/` tree. Inspect all content first because public commits cannot be made private retroactively.
2. Create a GitHub App `verimetrium-gva-issuer` with repository Contents RW and install it ONLY on this public repository. Configure Actions variable `GVA_APP_CLIENT_ID` and secret `GVA_APP_PRIVATE_KEY`; never commit private key.
3. Test one App-authenticated issuance while ruleset not yet ACTIVE. This writes `V1005.00` only if the request is unique and accepted; test must be nontrading audit or SYS DEV, NOT REL.
4. Configure public repo `Settings > Rules > Rulesets > New branch ruleset`, target `main`, select **Restrict updates**, **Restrict deletions**, **Block force pushes**, enforcement `Active`, bypass ONLY the new App with `Always allow`. Do not include admin user. Confirm through GitHub UI/API.
5. Test user direct non-force push to `main` is rejected; test App issuance still works; test duplicate hash is blocked. Only then switch old private GVA workflows to READ-ONLY and mark public ledger as sole authority in private docs.

GitHub App + branch rulesets give control against ordinary Git writers. Repository owners with authority to change rulesets remain administrators and can revoke/alter protection. This project does **not** claim to prevent that.

## Issue input (public! only hashes and nonsecret IDs)

Title exactly `GVA OFFICIAL VERSION REQUEST`. Body example:

```json
{"expected_next":"V1005.00","system":"SYS","role":"AUD","work":"GVA-K05-CERT","source_set_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
```

This workflow proves assignment and ledger integrity. It does **not** independently certify the private source-set hash or MT5 F7/RAW/VETO/economic parity. That requires separate independent CI evidence. `REL` is deliberately blocked.

`python gva/issuer.py verify` and `python -m unittest discover -s gva/tests -v` should succeed without credentials.
