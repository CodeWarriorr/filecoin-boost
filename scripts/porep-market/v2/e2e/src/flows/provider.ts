import { Wallet } from "ethers";
import { assertEqual } from "../assertions.js";
import type { ScenarioContext } from "../runtime.js";
import { envBigInt, envValue } from "../runtime.js";
import { artifactAbis } from "../contracts/abi.js";
import { Evm, lower } from "../contracts/evm.js";
import { contracts } from "../contracts/views.js";
import { requireDevnet } from "../devnet/docker.js";

export type ProviderOffer = {
  provider: bigint;
  providerPayee: string;
  offerId: bigint;
  paymentToken: string;
  pricePer32GiBPerMonth: bigint;
};

export async function registerDevnetProviderAndOffer(context: ScenarioContext): Promise<ProviderOffer> {
  requireDevnet(context);
  const evm = new Evm(context);
  const view = contracts(context);
  const abi = artifactAbis(context);
  const provider = envBigInt(context, "MINER_ACTOR_ID", 1000n);
  const providerPayee = envValue(context, "V2_PROVIDER_PAYEE") || new Wallet(context.config.privateKeySp).address;
  const paymentToken = envValue(context, "V2_PAYMENT_TOKEN", context.config.addresses.usdcToken);
  const price = envBigInt(context, "V2_PRICE_PER_32GIB_MONTH", 86_400_000_000n);
  const availableBytes = envBigInt(context, "V2_AVAILABLE_BYTES", 1_073_741_824n);
  const minPrice = envBigInt(context, "V2_MIN_PRICE_PER_32GIB_MONTH", 1n);

  if (lower(providerPayee) === lower(evm.signerAddress)) {
    throw new Error("V2 provider payee must differ from client/deployer for payout assertions");
  }

  console.log("=== Register V2 provider in SPRegistry ===");
  console.log("Current PoRep Market V2 uses provider registration plus offer-based matching.");

  if (await view.providerRegistered(provider)) {
    console.log(`Provider ${provider} already registered, refreshing V2 smoke-test capacity and payee`);
    await evm.send(context.config.addresses.spRegistry, "updateAvailableSpace(uint64,uint256)", [provider, availableBytes]);
    await evm.send(context.config.addresses.spRegistry, "setPayee(uint64,address)", [provider, providerPayee]);
  } else {
    await evm.send(context.config.addresses.spRegistry, "registerProviderFor(uint64,address,uint256,address)", [
      provider,
      evm.signerAddress,
      availableBytes,
      providerPayee
    ]);
  }

  assertEqual(await view.providerRegistered(provider), true, `provider ${provider} registered`);
  await evm.send(context.config.addresses.spRegistry, "setPaymentToken(address,bool,uint256)", [paymentToken, true, minPrice]);

  const existingOffer = (await view.providerOfferIds(provider)).find((id) => id > 0n);
  let offerId: bigint;
  if (existingOffer !== undefined) {
    offerId = existingOffer;
    console.log(`Provider ${provider} already has offer ${offerId}, refreshing payment row`);
    await evm.send(context.config.addresses.spRegistry, "setOfferPayment(uint256,address,bool,uint256)", [
      offerId,
      paymentToken,
      true,
      price
    ]);
  } else {
    const txHash = await evm.send(
      context.config.addresses.spRegistry,
      "createOffer(uint64,(uint256,uint256,uint64,uint64),(uint16,uint64,uint16,uint8),(address,bool,uint256)[])",
      [
        provider,
        offerTerms(context),
        offerSlis(context),
        `[(${paymentToken},true,${price})]`
      ]
    );
    const event = evm.parseEvent(evm.receipt(txHash), abi.spRegistry, "OfferCreated");
    offerId = BigInt(event.args[0].toString());
  }

  const offer = await view.offerView(offerId, paymentToken);
  assertEqual(BigInt(offer[1].toString()), provider, "offer provider");
  assertEqual(Boolean(offer[2]), true, "offer active");
  assertEqual(Boolean(offer[6]), true, "offer payment active");
  assertEqual(BigInt(offer[7].toString()), price, "offer price");

  context.state.set("PROVIDER", provider);
  context.state.set("PROVIDER_PAYEE", providerPayee);
  context.state.set("OFFER_ID", offerId);
  console.log(`Provider ${provider} registered with offer ${offerId} for token ${paymentToken} at price ${price} and payee ${providerPayee}.`);

  return { provider, providerPayee, offerId, paymentToken, pricePer32GiBPerMonth: price };
}

function offerTerms(context: ScenarioContext): string {
  const minSize = envBigInt(context, "V2_MIN_SIZE_BYTES", 1n);
  const maxSize = envBigInt(context, "V2_MAX_SIZE_BYTES", 0n);
  const minDuration = envBigInt(context, "V2_MIN_DURATION_EPOCHS", 518_400n);
  const maxDuration = envBigInt(context, "V2_MAX_DURATION_EPOCHS", 3_680_640n);
  return `(${minSize},${maxSize},${minDuration},${maxDuration})`;
}

function offerSlis(context: ScenarioContext): string {
  const retrievability = envBigInt(context, "V2_RETRIEVABILITY_BPS", 10_000n);
  const bandwidth = envBigInt(context, "V2_BANDWIDTH_BYTES_PER_SECOND", 1_048_576n);
  const latency = envBigInt(context, "V2_LATENCY_MS", 100n);
  const indexing = envBigInt(context, "V2_INDEXING_PCT", 100n);
  return `(${retrievability},${bandwidth},${latency},${indexing})`;
}
