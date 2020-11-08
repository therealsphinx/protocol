import { BigNumber } from 'ethers';

export enum FeeHook {
  Continuous,
  PreBuyShares,
  PostBuyShares,
  PreRedeemShares,
}

export enum FeeManagerActionId {
  InvokeContinuousHookForFees,
  PayoutSharesOutstandingForFees,
}

export enum FeeSettlementType {
  None,
  Direct,
  Mint,
  Burn,
  MintSharesOutstanding,
  BurnSharesOutstanding,
}

export interface FeeSharesDueInfo {
  sharesDue: BigNumber;
  nextAggregateValueDue: BigNumber;
  nextSharePrice: BigNumber;
}
