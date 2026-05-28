// SPDX-License-Identifier: Apache-2.0
//
// Procedural macros for compact-runtime. The `#[witnesses]` attribute
// macro generates `impl Witnesses<PS> for <UserType>` blocks matching the
// trait that rust-passes.ss emits in the generated contract crate.
//
// The macro design intentionally keeps the trait as the source of truth:
// rust-passes emits it (so the contract crate is self-describing); the
// macro just removes per-witness boilerplate from user code.

use proc_macro::TokenStream;
use quote::quote;

/// `#[witnesses]` attribute macro — see crate docs.
///
/// **Skeleton in Task M2.** Real implementation lands in Task M3.
#[proc_macro_attribute]
pub fn witnesses(_attr: TokenStream, item: TokenStream) -> TokenStream {
    // M2 stub: pass the input through unchanged so the crate compiles
    // and downstream wiring can be tested. M3 replaces this with the
    // real expansion.
    let item = proc_macro2::TokenStream::from(item);
    let expanded = quote! { #item };
    expanded.into()
}
