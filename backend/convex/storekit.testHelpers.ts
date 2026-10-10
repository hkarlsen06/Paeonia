// Shared fixtures for the StoreKit and access tests. The extra dot in the file
// name keeps Convex from bundling it.
import { readFileSync } from "node:fs";
import type { TestConvex } from "./test.setup";
import { omitNulls } from "./lib/db";

/** Loads the three subscription products from the seed file. */
export async function seedProducts(t: TestConvex): Promise<void> {
  const products = JSON.parse(readFileSync(new URL("../seed/subscription_products.json", import.meta.url), "utf8"));
  await t.run(async (ctx) => {
    for (const product of products) {
      await ctx.db.insert("subscription_products", omitNulls(product));
    }
  });
}

/** Arguments for `record_verified_storekit_transaction` with sensible defaults. */
export function storekitArgs(options: {
  userId: string | null;
  token: string | null;
  productId?: string;
  transactionId?: string;
  originalTransactionId?: string;
  status?: string;
  expiresAt?: string;
  environment?: string;
}) {
  const transactionId = options.transactionId ?? "tx-1";
  return {
    p_user_id: options.userId,
    p_app_account_token: options.token,
    p_apple_product_id: options.productId ?? "no.paeonia.couple",
    p_environment: options.environment ?? "sandbox",
    p_original_transaction_id: options.originalTransactionId ?? transactionId,
    p_transaction_id: transactionId,
    p_web_order_line_item_id: null,
    p_status: options.status ?? "active",
    p_purchased_at: new Date(Date.now() - 86_400_000).toISOString(),
    p_expires_at: options.expiresAt ?? new Date(Date.now() + 30 * 86_400_000).toISOString(),
    p_revoked_at: null,
    p_revocation_reason: null,
    p_signed_payload: "signed-transaction",
    p_payload_json: { transactionInfo: { productId: options.productId ?? "no.paeonia.couple" } },
  };
}
