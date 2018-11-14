import { isSameToken } from '@melonproject/token-math/token';
import { isEqual, greaterThan } from '@melonproject/token-math/quantity';
import { Address } from '~/utils/types';
import { getContract, transactionFactory } from '~/utils/solidity';
import { getToken, allowance } from '~/contracts/dependencies/token';
import { ensure } from '~/utils/guards';
import { Contracts } from '~/Contracts';

const guard = async ({ quantity }, contractAddress: Address, environment) => {
  const engine = getContract(Contracts.Engine, contractAddress);
  const mlnAddress = await engine.methods.mlnToken().call();
  const mlnToken = await getToken(mlnAddress);
  ensure(
    isSameToken(quantity.token, mlnToken),
    'It is only possible to burn MLN',
  );
  const allowedMln = await allowance(mlnAddress, {
    owner: environment.wallet.address,
    spender: contractAddress.toString(),
  });

  ensure(
    isEqual(allowedMln, quantity) || greaterThan(allowedMln, quantity),
    `Amount must be approved prior to calling this function.`,
  );
};

const prepareArgs = async ({ quantity }) => [String(quantity.quantity)];

const postProcess = async receipt => receipt;

const options = { gas: '8000000' };

export const sellAndBurnMln = transactionFactory(
  'sellAndBurnMln',
  Contracts.Engine,
  guard,
  prepareArgs,
  postProcess,
  options,
);
