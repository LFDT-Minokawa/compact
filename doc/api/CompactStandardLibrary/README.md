**CompactStandardLibrary** ∙ [README](README.md) ∙ [API](exports.md)

***

# Compact standard library

This API provides standard types and `circuit`s for use in Compact programs.
Key parts of the API are:

- Common data types:
  - [`Maybe`](exports.md#maybe)
  - [`Either`](exports.md#either)
  - [`CurvePoint`](exports.md#curvepoint)
  - [`MerkleTreeDigest`](exports.md#merkletreedigest)
  - [`MerkleTreePathEntry`](exports.md#merkletreepathentry)
  - [`MerkleTreePath`](exports.md#merkletreepath)
  - [`ContractAddress`](exports.md#contractaddress)
  - [`ZswapCoinPublicKey`](exports.md#zswapcoinpublickey)
  - [`UserAddress`](exports.md#useraddress)
- Coin management data types:
  - [`ShieldedCoinInfo`](exports.md#shieldedcoininfo)
  - [`QualifiedShieldedCoinInfo`](exports.md#qualifiedshieldedcoininfo)
  - [`ShieldedSendResult`](exports.md#shieldedsendresult)
  - [`UnshieldedCoinInfo`](exports.md#unshieldedcoininfo)
- Common functions:
  - [`some`](exports.md#some)
  - [`none`](exports.md#none)
  - [`left`](exports.md#left)
  - [`right`](exports.md#right)
- Hashing functions:
  - [`transientHash`](exports.md#transientHash)
  - [`transientCommit`](exports.md#transientCommit)
  - [`persistentHash`](exports.md#persistentHash)
  - [`persistentCommit`](exports.md#persistentCommit)
  - [`degradeToTransient`](exports.md#degradeToTransient)
- Elliptic curve functions:
  - [`ecAdd`](exports.md#ecAdd)
  - [`ecMul`](exports.md#ecMul)
  - [`ecMulGenerator`](exports.md#ecMulGenerator)
  - [`hashToCurve`](exports.md#hashToCurve)
  - [`upgradeFromTransient`](exports.md#upgradeFromTransient)
- Merkle tree functions:
  - [`merkleTreePathRoot`](exports.md#merkleTreePathRoot)
  - [`merkleTreePathRootNoLeafHash`](exports.md#merkleTreePathRootNoLeafHash)
- Coin management functions
  - [`tokenType`](exports.md#tokenType)
  - [`nativeToken`](exports.md#nativeToken)
  - [`ownPublicKey`](exports.md#ownPublicKey)
  - [`createZswapInput`](exports.md#createZswapInput)
  - [`createZswapOutput`](exports.md#createZswapOutput)
  - [`mintShieldedToken`](exports.md#mintShieldedToken)
  - [`evolveNonce`](exports.md#evolveNonce)
  - [`receiveShielded`](exports.md#receiveShielded)
  - [`sendShielded`](exports.md#sendshielded)
  - [`sendImmediateShielded`](exports.md#sendimmediateshielded)
  - [`mergeCoin`](exports.md#mergeCoin)
  - [`mergeCoinImmediate`](exports.md#mergeCoinImmediate)
  - [`shieldedBurnAddress`](exports.md#shieldedBurnAddress)
  - [`mintUnshieldedToken`](exports.md#mintUnshieldedToken)
  - [`sendUnshielded`](exports.md#sendUnshielded)
  - [`receiveUnshielded`](exports.md#receiveUnshielded)
  - [`unshieldedBalance`](exports.md#unshieldedBalance)
  - [`unshieldedBalanceLt`](exports.md#unshieldedBalanceLt)
  - [`unshieldedBalanceGte`](exports.md#unshieldedBalanceGte)
  - [`unshieldedBalanceGt`](exports.md#unshieldedBalanceGt)
  - [`unshieldedBalanceLte`](exports.md#unshieldedBalanceLte)
