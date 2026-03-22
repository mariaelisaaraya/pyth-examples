use aiken/collection/list
use aiken/math/rational
use cardano/assets.{PolicyId}
use cardano/transaction.{Transaction}
use pyth
use types/u32

/// On-chain configuration for the lazer-rwa minting policy.
/// Passed as a parameter at deployment time — each feed/threshold
/// combination produces a unique policy ID.
pub type LazerRwaConfig {
  /// Policy ID of the Pyth deployment on Cardano
  pyth_id: PolicyId,
  /// Pyth Lazer feed ID for the target RWA asset (e.g. 346 = XAU/USD)
  feed_id: Int,
  /// Minimum price (as integer, before exponent) to allow minting.
  /// For XAU/USD with exponent -3: 3000000 means $3,000.000
  min_price: Int,
}

/// Minting actions for the RWA token.
pub type MintAction {
  /// Mint new RWA tokens — only allowed if Pyth price >= min_price
  Mint
  /// Burn RWA tokens — always allowed
  Burn
}

/// Reads the price of a specific feed from a Pyth price update,
/// applying the exponent to return a proper Rational value.
/// Follows the pattern from Pyth Cardano documentation.
fn read_rwa_price(
  pyth_id: PolicyId,
  feed_id: Int,
  self: Transaction,
) -> (Int, rational.Rational) {
  // Verify and extract price data from the Pyth withdrawal redeemer
  let updates = pyth.get_updates(pyth_id, self)
  // Expect exactly one signed update in this transaction
  expect [update] = updates

  // Locate the feed matching our configured RWA asset
  expect Some(feed) =
    list.find(update.feeds, fn(f) { u32.as_int(f.feed_id) == feed_id })

  // Extract the raw price value
  expect Some(Some(price)) = feed.price

  // Apply exponent to get the real price as a Rational
  expect Some(exponent) = feed.exponent
  expect Some(multiplier) = rational.from_int(10) |> rational.pow(exponent)
  let real_price = rational.from_int(price) |> rational.mul(multiplier)

  (price, real_price)
}

/// Minting policy for RWA tokens backed by Pyth Lazer price feeds.
///
/// Uses `pyth.get_updates()` to read verified price data from the
/// transaction and enforces a configurable price threshold before
/// allowing token minting. The config parameter makes each deployment
/// specific to one RWA feed and threshold.
validator lazer_rwa_mint(config: LazerRwaConfig) {
  mint(redeemer: MintAction, _policy_id: PolicyId, self: Transaction) {
    when redeemer is {
      // Burn — always permitted (reduces supply)
      Burn -> True

      // Mint — requires on-chain price verification via Pyth
      Mint -> {
        let (raw_price, _real_price) =
          read_rwa_price(config.pyth_id, config.feed_id, self)

        // Threshold check: raw price must be at or above minimum to mint
        raw_price >= config.min_price
      }
    }
  }
}
