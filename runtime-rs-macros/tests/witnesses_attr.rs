// Integration test for #[witnesses] — exercised via cargo test.
// Validates that the macro generates a trait impl that satisfies a
// hand-written trait of the same shape rust-passes.ss would emit.

use compact_runtime::WitnessContext;
use compact_runtime_macros::witnesses;

#[allow(unused)]
struct MyState;

// Stand-in for the per-contract Ledger<'a, D> rust-passes emits — the
// macro should generate code referencing the in-test Ledger, so
// we expose that here for the test.
mod contract {
    pub struct Ledger<'a> {
        _phantom: std::marker::PhantomData<&'a ()>,
    }
}

// Stand-in for the per-contract Witnesses<PS> trait rust-passes emits.
// The macro must produce an impl that satisfies THIS trait.
pub trait Witnesses<PS> {
    fn secret_key(&self, ctx: &WitnessContext<contract::Ledger<'_>, PS>) -> (PS, [u8; 32]);
}

struct MyWitnesses;

#[witnesses(MyWitnesses, PS = MyState)]
impl MyWitnesses {
    fn secret_key(
        &self,
        ctx: &WitnessContext<contract::Ledger<'_>, MyState>,
    ) -> (MyState, [u8; 32]) {
        let _ = ctx;
        (MyState, [0u8; 32])
    }
}

#[test]
fn macro_generates_trait_impl_callable_via_trait_object() {
    fn call_as_trait_object<W: Witnesses<MyState>>(_w: &W) {}
    let w = MyWitnesses;
    call_as_trait_object(&w);
}
