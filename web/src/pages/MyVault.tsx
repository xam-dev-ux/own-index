import { useAccount, useReadContract } from "wagmi";
import type { Addresses } from "../config";
import { vaultAbi } from "../abi";
import { factoryAbi } from "../abiWrite";
import { Actions, CreateVault, Setup } from "../Actions";
import { Vault } from "../Vault";
import { Card, Empty } from "../ui";

/** The connected wallet's vault: create one, choose components, then deposit / rebalance / withdraw. */
export function MyVault({ addr }: { addr: Addresses }) {
  const { address } = useAccount();
  const vaults = useReadContract({ address: addr.factory, abi: factoryAbi, functionName: "vaultsOf", args: [address!], query: { enabled: !!address, refetchInterval: 5000 } }).data;
  const vault = vaults && vaults.length > 0 ? vaults[vaults.length - 1] : undefined;
  const comps = useReadContract({ address: vault, abi: vaultAbi, functionName: "components", query: { enabled: !!vault, refetchInterval: 5000 } }).data;
  if (!address) return <Card title="Your vault"><Empty>Connect a wallet to create or view your vault.</Empty></Card>;
  if (!vaults) return <Card title="Your vault"><Empty>Looking for your vaults…</Empty></Card>;
  if (!vault) return <CreateVault addr={addr} />;
  if (!comps) return <Card title="Your vault"><Empty>Reading the vault…</Empty></Card>;
  if (comps.length === 0) return <Setup addr={addr} vault={vault} />;
  return (
    <>
      <div className="intro"><h1>Your vault</h1><p>Owned by your wallet. Only you can trade with it or withdraw from it.</p></div>
      <Vault addr={addr} vault={vault} />
      <Actions addr={addr} vault={vault} />
    </>
  );
}
